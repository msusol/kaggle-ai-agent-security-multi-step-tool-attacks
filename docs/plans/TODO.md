# TODO — JED Red-Team Attack

<!-- Last updated: 2026-06-20 -->

---

## Phase 1 — MacBook: Stub Env + Local Scoring

- [x] Activate shared venv: `source ~/LosusAI/Projects/Kaggle/.venv/bin/activate`
- [x] Confirm `pytest tests/ -v` — all 14 tests green
- [x] Run `python attack.py` — no import errors, >0 candidates returned
- [x] Run `python local_harness.py --budget 300` — all 5 phases complete within budget
- [x] Verify stub score ≥ 0.3 and 8 unique cells covered
- [x] Verify replay phase succeeds (no candidates fail on fresh env)
- [x] Review `probe_results` from Algorithm A — confirm all 4 predicates fire
- [x] Review Algorithm B beam output — mutation operators producing diverse candidates
- [x] Review Algorithm C taint chains — `UNTRUSTED_TO_ACTION` confirmed hits
- [x] Review Algorithm D diversity targets — all 14 explicit targets attempted
- [x] Review Algorithm E depth sweep — priming depths 3/5/8/12 all run

## Phase 2 — DGX Spark: Real LLM + Local Scoring

- [ ] Install `requirements-llm.txt` on DGX Spark
- [ ] Run `vllm-serve.sh` — confirm model loads and endpoint responds at port 8000
- [ ] Run `local_harness.py --budget 300 --llm` against local vLLM
- [ ] Record baseline real-LLM score and unique cell count
- [ ] Inspect `probe_results` from A — which seed payloads fire on real LLM?
- [ ] Identify zero-hit seeds (no tool calls) — candidates for rephrasing
- [ ] Identify partial-hit seeds (read fires, exfil does not) — tune repair logic in A
- [ ] Add model-specific seeds to `payloads/library.py` based on transcript output
- [ ] Tune beam parameters in B for real-LLM latency (`beam_width`, `branch_factor`)
- [ ] Validate Algorithm C taint chains fire on real LLM (highest-value predicate)
- [ ] Run at `--budget 900` once tuned — measure score improvement

## Phase 3 — MacBook: Remote Attack via DGX Spark vLLM

- [ ] Confirm DGX Spark IP is reachable from MacBook on port 8000
- [ ] Run `SPARK_IP=<dgx-ip> python local_harness.py --budget 60 --llm` from Mac
- [ ] Confirm transcript logs capture real LLM reasoning (not stub output)
- [ ] Tune `payloads/library.py` — add GPT-OSS-20B specific seeds
- [ ] Tune `payloads/library.py` — add Gemma 4 26B seeds
- [ ] Expand `DIVERSITY_TARGETS` in `algorithms/algo_d.py` using real observed arg sets
- [ ] Run `--budget 900` from MacBook against DGX vLLM — record score and cell count
- [ ] Achieve score materially above stub baseline on at least one model
- [ ] Publish updated wheel to Kaggle dataset (`make publish-update`)
- [ ] Run `kaggle_notebook.ipynb` smoke test (Cell 3) — confirm wheel imports correctly

## Phase 4 — Kaggle Submission

- [x] Fix `dataset-metadata.json` (username `gdataranger`, title ≤50 chars)
- [x] Build wheel: `python -m build --wheel --outdir .`
- [x] Publish dataset v1 to `gdataranger/jed-aicomp-sdk`
- [x] Create `kernel-metadata.json` for `gdataranger/jed-attack-agent-security`
- [x] Fix dataset — publish v3 via staging dir (wheel + attack.py + local_harness.py only)
- [ ] Push notebook: `kaggle kernels push -p /tmp/jed-kernel`
- [ ] Run smoke test (Cell 3) — confirm wheel installs correctly on Kaggle
- [ ] Run full `kaggle_notebook.ipynb` against GPT-OSS 20B (Cell 6)
- [ ] Run full `kaggle_notebook.ipynb` against Gemma 4 26B (Cell 7)
- [ ] Record public scores from both models
- [ ] Submit via Kaggle notebook "Submit" button
- [ ] Monitor leaderboard; compare public vs private score gap

---

## Next steps

### Phase 1 — MacBook stub validation
1. `source ~/LosusAI/Projects/Kaggle/.venv/bin/activate`
2. `pip install -e . && pytest tests/ -v` — baseline green
2. `python local_harness.py --budget 300` — full algorithm pipeline smoke test
3. Review per-algorithm output and fix any logic errors before moving to real LLM

### Phase 2 — DGX Spark real LLM
1. SSH to DGX Spark, run `bash vllm-serve.sh`
2. `pip install -r requirements-llm.txt && python local_harness.py --budget 300 --llm`
3. Capture transcript logs; identify which seeds fire and which don't

### Phase 3 — MacBook → DGX remote
1. Note DGX Spark LAN IP; confirm port 8000 reachable from MacBook
2. `SPARK_IP=<ip> python local_harness.py --budget 60 --llm` — first remote run
3. Iterate: edit payloads on Mac → score remotely → repeat
