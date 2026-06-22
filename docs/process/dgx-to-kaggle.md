# DGX Spark → Kaggle Submission Process

Tune attack algorithms against Gemma 4 26B on DGX Spark, then push to Kaggle
for official scoring against both models.

---

## 1. Serve Gemma on DGX (one-time per session)

```zsh
tmux new -s llama
MODEL=gemma bash jed-redteam-attack/scripts/llama-serve.sh
# Ctrl+B D to detach — keeps running
```

Verify it's up:

```zsh
curl -s http://localhost:8082/v1/models | python3 -m json.tool
```

---

## 2. Run the harness against Gemma

```zsh
tmux new -s harness
source ~/LosusAI/Projects/Kaggle/.venv/bin/activate
cd jed-redteam-attack
MODEL=gemma bash scripts/harness-run.sh            # 300s (default)
MODEL=gemma BUDGET=900 bash scripts/harness-run.sh # full budget
# Ctrl+B D to detach
```

Log is written to `logs/harness_YYYYMMDD_HHMMSS.log`.

---

## 3. Tune based on results

Inspect the log:
- Which seeds produced tool calls? → keep and expand in `payloads/library.py`
- Which predicates fired? → target the missing ones in algorithm params
- Which seeds got 0 tool calls? → rephrase or drop

Iterate: edit → re-run harness → compare scores → repeat.

---

## 4. Push to Kaggle

From `jed-redteam-attack/`:

```zsh
# Dataset + notebook (most common after payload/algorithm changes):
bash scripts/push-kaggle.sh "v0.X: describe what changed"

# Notebook only (if only kaggle_notebook.ipynb changed):
bash scripts/push-kaggle.sh --notebook

# Dataset only (if code/payloads changed but notebook is fine):
bash scripts/push-kaggle.sh --dataset "v0.X: describe what changed"
```

Or via Make:

```zsh
make push MSG="v0.X: describe what changed"
make push-notebook
make push-dataset MSG="v0.X: describe what changed"
```

`push-kaggle.sh` handles: wheel rebuild → zip `algorithms/` + `payloads/` →
stage files → `kaggle datasets version` → `kaggle kernels push`.

---

## 5. Kaggle UI — GPU selection and run

After `kaggle kernels push`, Kaggle auto-starts a committed run on T4 (default).
If a different GPU tier is needed:

1. Open the notebook in the Kaggle editor
2. Stop the auto-run
3. Right panel → **Accelerator → desired GPU** (P100 or T4 x2)
4. **Save Version → Save & Run All**

Cells 6 (GPT-OSS 20B) and 7 (Gemma 4 26B) each run at 9000s budget.

---

## 6. Record scores

After both cells complete, record results in `docs/plans/leaderboard.md`
(Competition section). See `.claude/rules/leaderboard.md` for row format.

---

## Model notes

| Model | DGX | Kaggle |
|---|---|---|
| Gemma 4 26B | llama-server on port 8082 (`MODEL=gemma`) | `llkh0a/gemma-4-26b-a4b-it-ud-q4-k-m-gguf` |
| GPT-OSS 20B | **Non-functional on DGX** (Bug 8 WNT — unsloth GGUF ≠ competition GGUF) | `llkh0a/gpt-oss-20b-gguf` |

DGX and Kaggle scores are not directly comparable (different model quantizations,
budget, and environment). Use DGX for fast iteration; Kaggle for official scores.
See `docs/investigate/2026-06-22-predicates-scoring-gpt-oss-dgx.md` for Bug 8 detail.
