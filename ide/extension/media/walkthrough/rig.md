# Point Symposium at your rig

Your **rig** is the machine that actually runs training — usually a gaming PC with a GPU.
Start the Symposium trainer on it:

```bash
pip install -r trainer/requirements.txt
uvicorn trainer.server:app --host 0.0.0.0 --port 8765
```

Then set **`symposium.rig.url`** to that machine's address (e.g. `http://192.168.1.20:8765`).
On the same PC, the default `http://127.0.0.1:8765` just works.

The Engine Tracker and the **Symposium Rig** output channel both read from this one URL.
