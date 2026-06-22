# Leaderboard

> **DGX vs Kaggle scores are not comparable.**
> DGX runs use Llama 3.1 8B or competition GGUFs (GPT-OSS 20B, Gemma 4 26B) at 300–900s budget and are for algorithm development.
> Kaggle runs use GPT-OSS 20B and Gemma 4 26B at 9000s and produce competition scores.

## Development (stub + DGX Spark)

Scores here track algorithm correctness and improvement across iterations,
not competition ranking.

| Version | Env | Model | Score (norm) | Score (raw) | Cells | Findings | Budget | Notes |
|---|---|---|---|---|---|---|---|---|
| v0.1 | stub | stub | 0.30 | 60.0 | 8 | 299 | 300s | Phase 1 baseline — all 5 algorithm phases complete |
| v0.4 | dgx-local | llama-3.1-8b | 0.15 | 30.0 | 3 | 5 | 300s | First real-LLM run; parser fix (nested JSON); direct/authority prompts fire; taint chain visible but not scoring |
| v0.5 | dgx-local | llama-3.1-8b | 0.24 | 48.0 | 4 | 6 | 300s | Taint chain fix (_messages sync); UNTRUSTED_TO_ACTION now fires; 3-predicate coverage |
| v0.6 | dgx-local | llama-3.1-8b | 0.10 | 20.0 | 2 | 4 | 300s | ⚠ REGRESSION: email.read added to TOOL_SCHEMA broke system prompt determinism; reverted |
| v0.7 | dgx-local | gemma | 0.28 | 56.0 | 6 | 8 | 300s | First Gemma run with tools-API mode (Bug 8/9 fix); all 4 predicates fire; email.send + CONFUSED_DEPUTY work; zero PEG errors |
| v0.8 | dgx-local | gemma | 0.25 | 50.0 | 5 | 6 | 300s | Bug 8 WNT close + max_tokens fix; slight regression vs v0.7 — finished in 173s (budget not exhausted); need more payload diversity |
| v0.9 | dgx-local | gemma | 0.25 | 50.0 | 5 | 7 | 300s | +13 Gemma seeds (library.py), Phase C expanded to 192 combos; article #1 still returned for all web queries — +1 finding but no new cells |
| v0.10 | dgx-local | gemma | 0.27 | 54.0 | 5 | 4 | 300s | Phase C BREAKTHROUGH: article #5 exclusively matched, UNTRUSTED_TO_ACTION+CONFUSED_DEPUTY confirmed; Phase D killed by hardcoded -150s margin bug (only 16.2s) |

## Competition (Kaggle)

Scores here are official or validation runs against GPT-OSS 20B and Gemma 4 26B.

| Version | Env | Model | Score (norm) | Score (raw) | Cells | Findings | Budget | Notes |
|---|---|---|---|---|---|---|---|---|
| v0.2 | kaggle | gpt_oss | 22.35 | ~4,470 | unknown | unknown | 9000s | Validation only (v22); Phase B likely broken — Phase A+C only |
| v0.2 | kaggle | gemma | 14.48 | ~2,896 | unknown | unknown | 9000s | Validation only (v22); well below baseline (~240/1000) |
| v0.3 | kaggle | both | 4.960 | TBD | TBD | TBD | 9000s | First official submission (v33); lower than broken v22 validation — likely missing algorithms/ on scoring path |
| v0.4 | kaggle | both | 5.660 | TBD | TBD | TBD | 9000s | v34 — Phase B fix (triggered_predicates handles list[dict]); DGX payloads |
