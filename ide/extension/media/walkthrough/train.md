# Start your first training run

Press **`Ctrl+Shift+T`** (or run **Symposium: Start Training Run on Rig** from the Command
Palette).

Pick a model size and how many steps, and Symposium starts a real run on your rig:

- **nano** — ~0.85M params, trains visibly in minutes even on CPU.
- **micro** — ~2.7M params, more coherent, happier on a GPU.

Then watch it learn in the **Engine Tracker** — the loss curve falling, and the "watch it
learn to talk" samples going from gibberish → letters → words in the **Symposium Rig** log.

That's the whole loop: *your editor → your rig → your model.*
