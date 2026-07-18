"""A tiny GPT, written to be read.

This is the same architecture as GPT-2/LLaMA at 1/10000th the size: a stack
of transformer blocks doing next-token prediction. Every model Symposium
chats with — Qwen on your PC, a friend's Llama over the LAN — is this exact
shape with bigger numbers. If you understand this file, you understand what
the weights you download actually *are*.

Reading order: `CausalSelfAttention` → `Block` → `TinyGPT.forward` →
`TinyGPT.generate`.
"""

from __future__ import annotations

import math

import torch
import torch.nn as nn
import torch.nn.functional as F

from .common import ByteTokenizer, ModelPreset


class CausalSelfAttention(nn.Module):
    """The layer that lets tokens look at earlier tokens.

    Each token emits a *query* ("what am I looking for?"), a *key* ("what do
    I contain?") and a *value* ("what do I pass along if attended to").
    A token's output is a weighted average of all earlier tokens' values,
    weighted by how well its query matches their keys. "Causal" = a token may
    only attend backwards — you can't peek at the future you're predicting.
    """

    def __init__(self, preset: ModelPreset):
        super().__init__()
        assert preset.n_embd % preset.n_head == 0
        self.n_head = preset.n_head
        # One matrix computes q, k and v for every head at once — three
        # separate Linears would give identical math, just slower.
        self.qkv = nn.Linear(preset.n_embd, 3 * preset.n_embd)
        self.proj = nn.Linear(preset.n_embd, preset.n_embd)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        B, T, C = x.shape  # batch, sequence length, embedding width
        q, k, v = self.qkv(x).split(C, dim=2)
        # Reshape so each head attends independently in its own subspace —
        # "multi-head" means several smaller attentions in parallel, letting
        # one head track syntax while another tracks, say, who's speaking.
        q = q.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
        k = k.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
        v = v.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
        # Fused attention kernel; is_causal applies the "no peeking" mask.
        y = F.scaled_dot_product_attention(q, k, v, is_causal=True)
        y = y.transpose(1, 2).contiguous().view(B, T, C)  # merge heads back
        return self.proj(y)


class Block(nn.Module):
    """One transformer layer: attention (mix between tokens) then an MLP
    (think per-token). The `x + ...` residual connections are what make deep
    stacks trainable — each layer only learns a *correction* to the stream,
    and gradients can flow straight through the additions.
    """

    def __init__(self, preset: ModelPreset):
        super().__init__()
        self.ln1 = nn.LayerNorm(preset.n_embd)
        self.attn = CausalSelfAttention(preset)
        self.ln2 = nn.LayerNorm(preset.n_embd)
        # The classic 4x expansion: project wide, nonlinearity, project back.
        self.mlp = nn.Sequential(
            nn.Linear(preset.n_embd, 4 * preset.n_embd),
            nn.GELU(),
            nn.Linear(4 * preset.n_embd, preset.n_embd),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x + self.attn(self.ln1(x))
        x = x + self.mlp(self.ln2(x))
        return x


class TinyGPT(nn.Module):
    def __init__(self, preset: ModelPreset):
        super().__init__()
        self.preset = preset
        vocab = ByteTokenizer.vocab_size
        # Two lookup tables turn "byte 72 at position 5" into a vector:
        # what the token is + where it sits. Their sum enters the stack.
        self.tok_emb = nn.Embedding(vocab, preset.n_embd)
        self.pos_emb = nn.Embedding(preset.block_size, preset.n_embd)
        self.blocks = nn.ModuleList(Block(preset) for _ in range(preset.n_layer))
        self.ln_f = nn.LayerNorm(preset.n_embd)
        self.head = nn.Linear(preset.n_embd, vocab, bias=False)
        # Weight tying: the table that maps token→vector is reused to map
        # vector→token scores. Saves a third of our parameters and is what
        # GPT-2 does too.
        self.head.weight = self.tok_emb.weight
        self.apply(self._init)

    def _init(self, m: nn.Module) -> None:
        # Small-std normal init keeps early logits near zero, so the first
        # loss is ≈ ln(256) ≈ 5.55 — "uniformly clueless". If your step-1
        # loss is far from that, something is wired wrong.
        if isinstance(m, nn.Linear):
            nn.init.normal_(m.weight, std=0.02)
            if m.bias is not None:
                nn.init.zeros_(m.bias)
        elif isinstance(m, nn.Embedding):
            nn.init.normal_(m.weight, std=0.02)

    def num_params(self) -> int:
        # parameters() deduplicates shared tensors, so the tied
        # tok_emb/head table is counted once.
        return sum(p.numel() for p in self.parameters())

    def forward(
        self, idx: torch.Tensor, targets: torch.Tensor | None = None
    ) -> tuple[torch.Tensor, torch.Tensor | None]:
        B, T = idx.shape
        assert T <= self.preset.block_size, "sequence longer than context window"
        pos = torch.arange(T, device=idx.device)
        x = self.tok_emb(idx) + self.pos_emb(pos)
        for block in self.blocks:
            x = block(x)
        x = self.ln_f(x)
        logits = self.head(x)  # (B, T, vocab): next-byte scores at every position
        loss = None
        if targets is not None:
            # Cross-entropy between predicted distributions and the actual
            # next bytes. This single number is the whole training signal.
            loss = F.cross_entropy(logits.view(-1, logits.size(-1)), targets.view(-1))
        return logits, loss

    @torch.no_grad()
    def generate(
        self,
        idx: torch.Tensor,
        max_new_tokens: int,
        temperature: float = 0.8,
        top_k: int = 50,
    ) -> torch.Tensor:
        """Sample tokens one at a time — the same loop every chat app runs.

        temperature <1 sharpens the distribution (safer, blander); top_k
        throws away all but the k most likely bytes before sampling, which
        stops rare-garbage bytes from derailing a tiny model.
        """
        self.eval()
        for _ in range(max_new_tokens):
            # Crop context to the window — positions beyond block_size have
            # no learned embedding.
            ctx = idx[:, -self.preset.block_size:]
            logits, _ = self(ctx)
            logits = logits[:, -1, :] / max(temperature, 1e-6)
            if top_k > 0:
                kth = torch.topk(logits, min(top_k, logits.size(-1))).values[:, -1:]
                logits[logits < kth] = -float("inf")
            probs = F.softmax(logits, dim=-1)
            nxt = torch.multinomial(probs, num_samples=1)
            idx = torch.cat([idx, nxt], dim=1)
        return idx
