# DGX Spark — long harness run rules

Phase 2 and Phase 3 harness runs use `local_harness.py` with real LLM
backends. Full-budget runs (`--budget 9000`) can take **2–4 hours** depending
on model latency. Follow these rules to avoid losing run output to SSH drops
or background pipe failures.

---

> **STOP — before any long harness run on the DGX Spark:**
> Tell the user the command to run. Do NOT execute it yourself via Bash tool.
> This applies to:
> - Any `local_harness.py --llm` run with `--budget` ≥ 300
> - Any `vllm-serve.sh` invocation
> - Any `make run-spark` or `make spark` invocation on the DGX

---

## Always use tmux — never run_in_background

Do NOT invoke `local_harness.py` with `run_in_background: true` in the Bash
tool for long runs. The background task runner holds the stdout pipe; when it
closes, log output stops even though the harness keeps running.

**Tell the user to run it themselves inside tmux:**

```zsh
# On DGX Spark — start vLLM server (one-time, keep running)
tmux new -s vllm
bash jed-redteam-attack/vllm-serve.sh
# Ctrl+B then D to detach

# Run the harness in a separate session
tmux new -s harness
source ~/LosusAI/Projects/Kaggle/.venv/bin/activate
cd jed-redteam-attack
python local_harness.py \
  --budget 9000 \
  --llm
# Ctrl+B then D to detach — session survives SSH drops
# tmux attach -t harness to reattach
```

## Never kill a running harness without asking

A full 9000s harness run takes hours. Always confirm with the user before
stopping it. Check status first:

```zsh
tmux list-sessions
ps aux | grep local_harness
```

## Diagnosing a silent run

Do NOT assume the harness crashed if output stops. Check in order:

1. **tmux session still alive?**
   ```zsh
   tmux attach -t harness
   ```

2. **Process still running?**
   ```zsh
   ps aux | grep local_harness
   ```

3. **vLLM endpoint still responding?**
   ```zsh
   curl http://localhost:8000/v1/models
   ```

If the process is alive but output stopped, the tmux pipe broke — reattach to
resume watching. Do not restart.

## Logging

Pipe harness output to a log file so it survives detachment:

```zsh
python local_harness.py \
  --budget 9000 \
  --llm \
  2>&1 | tee logs/harness_$(date +%Y%m%d_%H%M%S).log
```

After completion, the log contains the full score report and per-phase output
needed to update `docs/plans/leaderboard.md`.
