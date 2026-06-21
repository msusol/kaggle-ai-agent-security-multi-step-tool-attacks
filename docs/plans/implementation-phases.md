# JED Red-Team Attack — Implementation Phases

## Goal

Evolve the vibe-planned `jed-redteam-attack/` codebase from a stub-validated
prototype into a competition-ready submission, progressing through three execution
environments in order of increasing fidelity. Each phase has a clear exit criterion
before proceeding to the next.

**Competition deadline:** 2026-09-01  
**Target:** Score > starter baseline (0.24); competitive range is 5–50+.

---

## Shared Virtual Environment

All Kaggle competition projects share a single root-level `.venv`:

```
~/LosusAI/Projects/Kaggle/
├── .venv/                  ← shared venv (Python 3.14.0)
├── kaggle-ai-agent-security-multi-step-tool-attacks/
├── kaggle-nemotron-model-reasoning-challenge/
└── ...
```

Activate before any work in this project:

```bash
source ~/LosusAI/Projects/Kaggle/.venv/bin/activate
```

The project `.gitignore` already ignores `venv/` and `.venv/` so no accidental commits of the env.

---

## Context

The attack system (`attack.py` + five algorithms A–E) is already scaffolded from the
vibe-planning session. The stub SDK (`aicomp_sdk/`) uses keyword matching — it does
not call a real LLM. Score against the stub saturates at ~0.3 due to fixed tool
signatures.

Real score growth comes from:
1. Diverse LLM-produced tool-call argument sets (`2 × unique_cell_count` dominates)
2. Genuine multi-step taint chains (`UNTRUSTED_TO_ACTION` — most robust against private guardrail)
3. Model-specific payload tuning (GPT-OSS-20B vs Gemma 4 26B behave differently)

The three phases match the `docker-compose.yml` profiles (`dev`, `spark`) and
`vllm-serve.sh` already present in the repo.

---

## Phase 1 — MacBook: Stub Env + Local Scoring

**Goal:** Validate the full algorithm pipeline end-to-end with zero LLM dependency.
All logic bugs must be caught here before spending GPU time.

### Setup

```bash
source ~/LosusAI/Projects/Kaggle/.venv/bin/activate
cd jed-redteam-attack
pip install -e .
pytest tests/ -v                          # must pass all 14 tests
```

### Run targets

```bash
# Fast smoke test — algorithms load and return candidates
python attack.py

# Full harness with replay scoring
python local_harness.py \
  --budget 300

# Docker equivalent
make build-dev && make run-stub
```

### Tasks

- [ ] Confirm `pytest tests/ -v` — all 14 tests green
- [ ] Run `python attack.py` — no import errors, >0 candidates returned
- [ ] Run `python local_harness.py --budget 300` — all 5 phases complete within budget
- [ ] Verify stub score ≥ 0.3 and 8 unique cells covered
- [ ] Verify replay phase succeeds (no candidates fail on fresh env)
- [ ] Review `probe_results` from Algorithm A — confirm all 4 predicates fire
- [ ] Review Algorithm B beam output — mutation operators producing diverse candidates
- [ ] Review Algorithm C taint chains — `UNTRUSTED_TO_ACTION` confirmed hits
- [ ] Review Algorithm D diversity targets — all 14 explicit targets attempted
- [ ] Review Algorithm E depth sweep — priming depths 3/5/8/12 all run

### Exit criteria

- All 14 pytest tests pass
- Stub harness score ≥ 0.3 with all 4 predicates represented
- Replay phase completes with ≥ 1 confirmed candidate per predicate
- No unhandled exceptions across any algorithm within a 300s run

---

## Phase 2 — DGX Spark: Real LLM + Local Scoring

**Goal:** Run the full harness against a real LLM served locally on the DGX Spark.
Measure actual attack surface — stub score is irrelevant here. This is the first
signal on what payloads actually work against transformer models.

### Setup

On the DGX Spark (one-time):

```bash
# Start vLLM serving a local model
bash jed-redteam-attack/vllm-serve.sh

# Verify endpoint is up
curl http://localhost:8000/v1/models
```

On the DGX Spark (run harness locally):

```bash
source ~/LosusAI/Projects/Kaggle/.venv/bin/activate
cd jed-redteam-attack
pip install -r requirements-llm.txt
pip install -e .

# Run against local vLLM endpoint
python local_harness.py \
  --budget 300 \
  --llm
```

Or via Docker (spark profile):

```bash
# On DGX: serve the model
bash vllm-serve.sh

# On DGX: run harness container pointing at localhost
make run-spark   # uses SPARK_IP=localhost by default for local DGX run
```

### Tasks

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

### Exit criteria

- Real-LLM harness run completes without budget exhaustion errors
- At least 2 of 4 predicates triggered on real model
- Algorithm A repair phase converts ≥ 1 partial hit to a confirmed candidate
- Beam parameters tuned so Algorithm B finishes within its 40% budget window

---

## Phase 3 — MacBook: Remote Attack via DGX Spark vLLM

**Goal:** Edit and iterate on the MacBook while the DGX Spark serves the real model
via vLLM over the local network. This is the primary iteration loop for payload
tuning — fast edit-on-Mac, score-against-real-LLM cycle.

### Setup

On the DGX Spark (persistent):

```bash
bash jed-redteam-attack/vllm-serve.sh   # keep running; port 8000 open on LAN
```

On the MacBook:

```bash
source ~/LosusAI/Projects/Kaggle/.venv/bin/activate
cd jed-redteam-attack
pip install -r requirements-llm.txt
pip install -e .

# Run harness pointing at DGX Spark IP
SPARK_IP=<dgx-ip> python local_harness.py \
  --budget 300 \
  --llm

# Or via Make
SPARK_IP=<dgx-ip> make run-spark
```

Or via Docker + spark profile:

```bash
SPARK_IP=<dgx-ip> make run-spark
```

### Iteration loop

```
1. Edit payloads/library.py on MacBook    (add/tune seeds)
2. python local_harness.py --budget 60 --llm   (quick validation)
3. Inspect transcript output             (why did the LLM refuse or comply?)
4. Tune algorithms or payloads           (model-specific fixes)
5. Run --budget 300 --llm for full score
6. Repeat until score plateaus
```

### Tasks

- [ ] Confirm DGX Spark IP is reachable from MacBook on port 8000
- [ ] Run `SPARK_IP=<dgx-ip> python local_harness.py --budget 60 --llm` from Mac
- [ ] Confirm transcript logs capture real LLM reasoning (not stub output)
- [ ] Tune `payloads/library.py` — add GPT-OSS-20B specific seeds (contextual inertia,
      reasoning mirage, compound role-play framings per README)
- [ ] Tune `payloads/library.py` — add Gemma 4 26B seeds (softer framing, research context)
- [ ] Expand `DIVERSITY_TARGETS` in `algorithms/algo_d.py` using real observed arg sets
- [ ] Run `--budget 900` from MacBook against DGX vLLM — record score and cell count
- [ ] Achieve score materially above stub baseline on at least one model
- [ ] Publish updated wheel to Kaggle dataset (`make publish-update`)
- [ ] Run `kaggle_notebook.ipynb` smoke test (Cell 3) to confirm wheel imports correctly

### Exit criteria

- MacBook → DGX Spark vLLM pipeline stable for ≥ 30-minute runs without dropout
- Score on GPT-OSS proxy model > 1.0 (normalized)
- `UNTRUSTED_TO_ACTION` taint chains confirmed on real LLM (most robust for private guardrail)
- Kaggle dataset published and notebook smoke test passes

---

## Phase 4 — Kaggle Submission (Future)

After Phase 3 produces a validated `attack.py`:

- [ ] Publish final wheel version to `marksusol/jed-aicomp-sdk` dataset
- [ ] Run full `kaggle_notebook.ipynb` against GPT-OSS 20B (Cell 6)
- [ ] Run full `kaggle_notebook.ipynb` against Gemma 4 26B (Cell 7)
- [ ] Record public scores from both models
- [ ] Submit via Kaggle notebook "Submit" button
- [ ] Monitor leaderboard; compare public vs private score gap

See `jed-redteam-attack/docs/03-kaggle-notebook.md` for full notebook walkthrough.

---

## Notes

- **Stub vs real LLM:** The stub saturates at 0.3 due to fixed 8 tool signatures.
  Against real LLMs, unique cell counts of 50+ are achievable — that's where the
  real score lives.
- **Private guardrail sensitivity:** Focus payload tuning on Algorithm C taint chains
  (`UNTRUSTED_TO_ACTION`) — these require genuine multi-step agent reasoning and are
  hardest for the private guardrail to block.
- **Budget allocation reminder:** A=10%, C=20%, B=40%, D=20%, E=10%. Reduce
  `beam_width`/`branch_factor` in B when real-LLM latency is 2–10s per interact().
- **vllm-serve.sh:** Already scripted in `jed-redteam-attack/vllm-serve.sh` — no
  additional DGX setup needed beyond running the script.
