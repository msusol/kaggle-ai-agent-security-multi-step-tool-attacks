# Leaderboard synchronization

Track every meaningful harness run and Kaggle submission in
`docs/plans/leaderboard.md`. This is the primary record of score progress
across algorithm iterations, payload tuning, and model evaluations.

## Triggers — when to add a row

| Trigger | Action |
|---|---|
| `local_harness.py --llm` completes on DGX Spark (Phase 2) | Add row with real-LLM scores |
| `local_harness.py --llm` completes from MacBook → DGX (Phase 3) | Add row with remote-LLM scores |
| Kaggle notebook Cell 6 completes (GPT-OSS 20B) | Add/update row with public score |
| Kaggle notebook Cell 7 completes (Gemma 4 26B) | Add/update row with public score |
| Official Kaggle submission scored | Add row with both public scores and leaderboard rank |
| A run errors out or is abandoned | Do NOT add a row |

## Row fields

| Field | Source |
|---|---|
| `version` | Increment patch (v0.1 → v0.2) for payload/param tweaks; bump minor (v0.1 → v1.0) for new algorithm phases or major structural changes |
| `env` | `stub` / `dgx-local` / `dgx-remote` / `kaggle` |
| `model` | `stub` / `gpt_oss` / `gemma` / `both` |
| `score_normalized` | From harness `score_normalized_0_to_1000` or Kaggle public score |
| `score_raw` | From harness `score_raw` |
| `unique_cells` | From harness `unique_cells` |
| `findings_count` | From harness `findings_count` |
| `budget_s` | Budget passed to harness or Kaggle 9000s |
| `notes` | One sentence — what changed vs previous row |

## leaderboard.md format

```markdown
# Leaderboard

| Version | Env | Model | Score (norm) | Score (raw) | Cells | Findings | Budget | Notes |
|---|---|---|---|---|---|---|---|---|
| v0.1 | stub | stub | 0.3 | 60.0 | 8 | 299 | 300s | Phase 1 baseline |
```

## What not to add

- Do not add stub harness runs after Phase 1 — stub scores are fixed at 0.3.
- Do not update historical rows unless correcting a factual error.
- Do not add rows for `python attack.py` smoke tests (no replay scoring).

## File location

`docs/plans/leaderboard.md` — create it on the first real-LLM run if it
does not already exist. Seed it with the Phase 1 stub baseline row.
