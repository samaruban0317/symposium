"""Symposium Lab — a tiny, runnable RAG pipeline.

Ingest PDFs / Markdown / text -> chunk -> embed (CPU) -> Qdrant -> retrieve.

No GPU and no torch: `fastembed` runs an ONNX model on the CPU, so this works
fine on the 16GB no-GPU box. This is the "R" and the retrieval half of RAG; wire
the top chunks into any chat model's prompt for the "G".

Setup (see lab/README.md):
    pip install "qdrant-client[fastembed]" pypdf python-dotenv

Usage:
    python rag_pipeline.py ingest ./some_docs      # a file OR a folder
    python rag_pipeline.py ask "what is a closure?"
"""
from __future__ import annotations

import hashlib
import pathlib
import sys

from qdrant_client import QdrantClient

COLLECTION = "symposium_lab"
STORE = pathlib.Path(__file__).parent / ".qdrant"        # on-disk, persists between runs
EMBED_MODEL = "BAAI/bge-small-en-v1.5"                    # 384-dim, fast, CPU-only
EXTS = {".pdf", ".md", ".txt"}


def _client() -> QdrantClient:
    c = QdrantClient(path=str(STORE))                    # local mode — no server to run
    c.set_model(EMBED_MODEL)                             # fastembed picks it up automatically
    return c


def _read(p: pathlib.Path) -> str:
    if p.suffix.lower() == ".pdf":
        from pypdf import PdfReader
        return "\n".join((pg.extract_text() or "") for pg in PdfReader(str(p)).pages)
    return p.read_text(encoding="utf-8", errors="ignore")


def _chunk(text: str, size: int = 800, overlap: int = 120) -> list[str]:
    text = " ".join(text.split())                        # normalise whitespace
    out, i = [], 0
    while i < len(text):
        out.append(text[i:i + size])
        i += size - overlap
    return [c for c in out if c.strip()]


def ingest(path: str) -> None:
    root = pathlib.Path(path)
    files = [root] if root.is_file() else [p for p in root.rglob("*") if p.suffix.lower() in EXTS]
    if not files:
        sys.exit(f"nothing to ingest: no {sorted(EXTS)} under {path}")

    docs, ids, metas = [], [], []
    for f in files:
        for j, ch in enumerate(_chunk(_read(f))):
            docs.append(ch)
            ids.append(int(hashlib.md5(f"{f}:{j}".encode()).hexdigest()[:15], 16))
            metas.append({"source": str(f), "chunk": j})

    _client().add(collection_name=COLLECTION, documents=docs, ids=ids, metadata=metas)
    print(f"ingested {len(docs)} chunks from {len(files)} file(s) -> {STORE}")


def ask(question: str, k: int = 4) -> None:
    hits = _client().query(collection_name=COLLECTION, query_text=question, limit=k)
    if not hits:
        print("no matches — ingest something first.")
        return
    for h in hits:
        src = h.metadata.get("source") if h.metadata else "?"
        chk = h.metadata.get("chunk") if h.metadata else "?"
        print(f"\n[{h.score:.3f}] {src}#{chk}\n{h.document[:400]}")


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in {"ingest", "ask"}:
        sys.exit(__doc__)
    {"ingest": ingest, "ask": ask}[sys.argv[1]](sys.argv[2])
