# Kaggle Competition Notebook Guide
## AI Agent Security — JED Red-Team Attack

This document covers publishing the project as a Kaggle dataset, importing
it into the competition notebook, and running the full evaluation pipeline
against the real models.

---

## Overview

```
Step 1: Publish jed-aicomp-sdk dataset to Kaggle
         ↓
Step 2: Attach dataset to competition notebook
         ↓
Step 3: pip install wheel from dataset
         ↓
Step 4: Smoke test against stub env (no GPU)
         ↓
Step 5: Run evaluate_redteam() against GPT-OSS 20B
         ↓
Step 6: Run evaluate_redteam() against Gemma 4 26B
         ↓
Step 7: Read scores from attack.score / attack.findings
```

---

## Step 1: Publish the Dataset

### Prerequisites

```bash
pip install kaggle
# Place ~/.kaggle/kaggle.json:
# {"username": "marksusol", "key": "YOUR_API_KEY"}
# Get key from: https://www.kaggle.com/settings → API → Create New Token
```

### Build the wheel

```bash
cd jed_project
python -m build --wheel --outdir .
# → aicomp_sdk-3.1.0.dev0-py3-none-any.whl
```

### First publish

```bash
# Edit dataset-metadata.json first:
# Change "id": "KAGGLE_USERNAME/jed-aicomp-sdk" to your username
make publish-new
# → https://www.kaggle.com/datasets/marksusol/jed-aicomp-sdk
```

### Update after code changes

```bash
make publish-update    # creates a new dataset version
```

### What gets published

```
jed-aicomp-sdk dataset contains:
  aicomp_sdk-3.1.0.dev0-py3-none-any.whl   ← pip install this
  attack.py                                  ← starter algorithm
  local_harness.py                           ← local evaluation helper
  aicomp_sdk/                                ← source (for reference)
  tests/                                     ← test suite
  README.md
```

---

## Step 2: Set Up the Competition Notebook

### Required datasets to attach

In your Kaggle notebook settings → "Add Data":

1. **Competition data**: `AI Agent Security - Multi-Step Tool Attacks`
   - Path: `/kaggle/input/competitions/ai-agent-security-multi-step-tool-attacks/`

2. **Your SDK dataset**: `marksusol/jed-aicomp-sdk`
   - Path: `/kaggle/input/jed-aicomp-sdk/`

3. **Model files** (auto-attached by competition):
   - GPT-OSS: `/kaggle/input/models/llkh0a/gpt-oss-20b-gguf/...`
   - Gemma 4: `/kaggle/input/models/llkh0a/gemma-4-26b-a4b-it-ud-q4-k-m-gguf/...`

---

## Step 3: Notebook Cell Structure

The file `kaggle_notebook.ipynb` contains the full notebook. Below is a
walkthrough of each cell's purpose.

### Cell 1: Install SDK from dataset

```python
import subprocess, sys

subprocess.run([
    sys.executable, '-m', 'pip', 'install', '-q',
    '/kaggle/input/jed-aicomp-sdk/aicomp_sdk-3.1.0.dev0-py3-none-any.whl'
], check=True)

from aicomp_sdk.attacks import AttackAlgorithmBase, AttackCandidate, AttackRunConfig
from aicomp_sdk.core.predicates import eval_predicates
from aicomp_sdk import Env
print("✓ aicomp_sdk installed from dataset")
```

**Why:** The stub SDK provides `Env` for local smoke testing and ensures
the import paths (`aicomp_sdk.attacks`, `aicomp_sdk.core.predicates`) match
what `attack.py` expects before the real SDK loads.

### Cell 2: Copy attack.py from dataset

```python
import shutil
shutil.copy('/kaggle/input/jed-aicomp-sdk/attack.py', '/kaggle/working/attack.py')
print("Copied attack.py to /kaggle/working/")
```

**Alternative — write your own:**

```python
%%writefile /kaggle/working/attack.py
import glob, sys
from pathlib import Path

for c in glob.glob('/kaggle/input/**/kaggle_evaluation', recursive=True):
    sys.path.insert(0, str(Path(c).parent)); break

from aicomp_sdk.attacks import AttackAlgorithmBase, AttackCandidate, AttackRunConfig
from aicomp_sdk.core.predicates import eval_predicates

# Copy algorithms/ and payloads/ from your dataset:
sys.path.insert(0, '/kaggle/input/jed-aicomp-sdk/')

from algorithms.algo_a import AdaptiveProbeStrategy
from algorithms.algo_b import BeamSearchStrategy, BeamEntry
from algorithms.algo_c import TaintChainStrategy
from algorithms.algo_d import DiversityMaximizerStrategy
from algorithms.algo_e import TemporalDegradationStrategy

class AttackAlgorithm(AttackAlgorithmBase):
    def run(self, env, config: AttackRunConfig) -> list[AttackCandidate]:
        # Your implementation here
        ...
```

### Cell 3: Smoke test against stub

```python
import importlib.util, sys

def load_attack(path='/kaggle/working/attack.py'):
    spec = importlib.util.spec_from_file_location('attack', path)
    mod  = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.AttackAlgorithm

AttackAlgorithm = load_attack()
env    = Env(seed=123)
config = AttackRunConfig(time_budget_s=60, max_tool_hops=8, seed=123)

results = AttackAlgorithm().run(env, config)
print(f"Stub run: {len(results)} candidates found")
# Should show > 0 candidates before touching real LLMs
```

**Why this matters:** If this returns 0, your `attack.py` has a bug that would
waste the full 9000s GPU budget. Fix here first.

### Cell 4: Setup competition environment

```python
import os, sys, json, time, gc
from pathlib import Path

COMP_DIR     = Path('/kaggle/input/competitions/ai-agent-security-multi-step-tool-attacks')
GPT_OSS_PATH = Path('/kaggle/input/models/llkh0a/gpt-oss-20b-gguf/pytorch/default/1/gpt_oss/gpt-oss-20b-Q4_K_M.gguf')
GEMMA_PATH   = Path('/kaggle/input/models/llkh0a/gemma-4-26b-a4b-it-ud-q4-k-m-gguf/pytorch/default/1/gemma/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf')
ARTIFACTS    = Path('/kaggle/working/artifacts')
ARTIFACTS.mkdir(exist_ok=True)

sys.path.insert(0, str(COMP_DIR))
os.environ['GPT_OSS_MODEL_PATH'] = str(GPT_OSS_PATH)
os.environ['GEMMA_MODEL_PATH']   = str(GEMMA_PATH)

from kaggle_evaluation.jed_attack_134815 import jed_attack_gateway as gw
BUDGET_S    = gw.DEFAULT_BUDGET_S      # 9000
MAX_HOPS    = gw.DEFAULT_MAX_TOOL_HOPS # 8
SEED        = gw.ATTACK_SEED           # 123
MODEL_NAMES = list(gw.MODEL_NAMES)     # ["gpt_oss", "gemma"]
print(json.dumps({'budget_s': BUDGET_S, 'seed': SEED, 'models': MODEL_NAMES}, indent=2))
```

### Cell 5: Install llama-cpp-python (GPU wheel)

```python
import importlib.util
if importlib.util.find_spec('llama_cpp') is None:
    subprocess.run([
        sys.executable, '-m', 'pip', 'install', '-q', 'llama-cpp-python',
        '--extra-index-url', 'https://abetlen.github.io/llama-cpp-python/whl/cu124',
    ], check=True)
print('llama-cpp-python ready')
```

### Cell 6: Run against GPT-OSS 20B

```python
from kaggle_evaluation.jed_attack_134815.gguf_model_server import GgufModelServer
from kaggle_evaluation.jed_attack_134815 import gpt_oss_model_server
from aicomp_sdk.core.env.api import EnvSelection
from aicomp_sdk.evaluation.runner import evaluate_redteam
from aicomp_sdk.evaluation.diagnostics import RunDiagnostics, EvaluatorVerbosity

MODEL_NAME    = 'gpt_oss'
server        = GgufModelServer(gpt_oss_model_server.SPEC)
server.load_model()
agent_factory = lambda: server._load_agent()

t0 = time.time()
with RunDiagnostics(EvaluatorVerbosity.DEBUG,
        transcript_file=ARTIFACTS / f'{MODEL_NAME}_transcript.log',
        event_log_file=ARTIFACTS  / f'{MODEL_NAME}_framework.jsonl',
        agent_debug_file=ARTIFACTS/ f'{MODEL_NAME}_agent-debug.jsonl') as diag:
    execution = evaluate_redteam(
        AttackAlgorithm,
        budget_s=BUDGET_S,
        agent_factory=agent_factory,
        agent_label=f'{MODEL_NAME}_gguf',
        env_selection=EnvSelection.GYM,
        fixtures_dir=COMP_DIR / 'aicomp_sdk' / 'fixtures',
        diagnostics=diag,
        attack_env_seed=SEED,
    )

attack    = execution.attack
gpt_score = attack.score

print(json.dumps({
    'model':   MODEL_NAME,
    'score':   attack.score,
    'raw':     attack.score_raw,
    'cells':   attack.unique_cells,
    'time_s':  round(time.time() - t0, 1),
    'findings': attack.findings_count,
}, indent=2))

# Read findings for debugging
for i, finding in enumerate(attack.findings[:5]):
    print(f"\nFinding {i}: {finding.get('user_messages')}")
    print(f"  Predicates: {list(finding.get('predicates', {}).keys())}")

try: server.unload()
except: pass
gc.collect()
```

### Cell 7: Run against Gemma 4 26B

```python
from kaggle_evaluation.jed_attack_134815 import gemma_model_server

MODEL_NAME    = 'gemma'
server        = GgufModelServer(gemma_model_server.SPEC)
server.load_model()
agent_factory = lambda: server._load_agent()

t0 = time.time()
with RunDiagnostics(EvaluatorVerbosity.DEBUG,
        transcript_file=ARTIFACTS / f'{MODEL_NAME}_transcript.log',
        event_log_file=ARTIFACTS  / f'{MODEL_NAME}_framework.jsonl',
        agent_debug_file=ARTIFACTS/ f'{MODEL_NAME}_agent-debug.jsonl') as diag:
    execution = evaluate_redteam(
        AttackAlgorithm,
        budget_s=BUDGET_S,
        agent_factory=agent_factory,
        agent_label=f'{MODEL_NAME}_gguf',
        env_selection=EnvSelection.GYM,
        fixtures_dir=COMP_DIR / 'aicomp_sdk' / 'fixtures',
        diagnostics=diag,
        attack_env_seed=SEED,
    )

attack      = execution.attack
gemma_score = attack.score

print(json.dumps({
    'model':   MODEL_NAME,
    'score':   attack.score,
    'raw':     attack.score_raw,
    'cells':   attack.unique_cells,
    'time_s':  round(time.time() - t0, 1),
    'findings': attack.findings_count,
}, indent=2))

try: server.unload()
except: pass
gc.collect()
```

### Cell 8: Final scores

```python
public_scores = {
    'gpt_oss_public': float(gpt_score),
    'gemma_public':   float(gemma_score),
    'local_public_mean': (float(gpt_score) + float(gemma_score)) / 2,
}
print(json.dumps(public_scores, indent=2))
```

---

## Reading the Artifacts

After each run, three log files land in `/kaggle/working/artifacts/`:

| File | Contents | Use for |
|---|---|---|
| `*_transcript.log` | Full conversation: user → agent → tool results | Understanding why a prompt worked or didn't |
| `*_framework.jsonl` | Structured event log (tool calls, results, predicates) | Parsing what triggered |
| `*_agent-debug.jsonl` | Model internals (tokens, logprobs) | Deep debugging |

**Most valuable for iteration:** `transcript.log`. It shows the agent's actual
reasoning and tool calls. If your attack prompt succeeded, this tells you why.
If it didn't, you can see exactly where the agent refused or took a different path.

---

## Iteration Workflow

```
1. Edit payloads/library.py locally     (add new seeds)
2. python local_harness.py --budget 60  (quick validation)
3. make publish-update                  (new dataset version)
4. Re-run Cell 1 in Kaggle notebook     (pip install new wheel)
5. Re-run Cell 3                        (smoke test)
6. Re-run Cells 6–7                     (real model evaluation)
7. Read artifacts/ logs                 (diagnose what worked)
8. Repeat
```

---

## Submission vs Validation

This notebook is for **local validation** — understanding your score before
the official submission evaluator runs.

For the **official submission**:
1. Your notebook must write `attack.py` to `/kaggle/working/`
2. The evaluator automatically loads it and calls `AttackAlgorithm().run(env, config)`
3. You do **not** call `evaluate_redteam()` yourself in the submission notebook
4. Submission happens via the "Submit" button in the Kaggle notebook UI

The `evaluate_redteam()` calls in Cells 6–7 are for your own scoring visibility,
not required by the evaluator.

---

## Notebook Settings

| Setting | Value |
|---|---|
| GPU | T4 × 1 or P100 |
| Runtime | ≤ 10 hours |
| Internet | **DISABLED** (required by competition) |
| Accelerator | GPU |

The 10-hour limit covers: model load (~10 min each) + 9000s per model × 2 + overhead.
Total wall time is roughly 6–7 hours, well within the limit.

---

## Common Issues

**`assert GPT_OSS_PATH.exists()` fails**  
→ The model dataset isn't attached. Add it in notebook settings → "Add Data".

**`from aicomp_sdk.core.env.api import EnvSelection` fails**  
→ The real SDK (from competition data) wasn't found. Ensure `sys.path.insert(0, str(COMP_DIR))` ran before this import.

**`AttackAlgorithm().run()` returns 0 candidates on real model**  
→ Your payloads don't fire on this model. Check `transcript.log` to see the
agent's responses. Likely needs different framing or additional repair logic in Algorithm A.

**Budget exhausted before all phases complete**  
→ Each `env.interact()` call takes ~2–10s on real models. Reduce beam parameters
in `attack.py`: `beam_width=4, branch_factor=2` for conservative budget use.

**Score much lower on private leaderboard than public**  
→ The public `OptimalGuardrail` is permissive. The private guardrail is stricter.
Focus on genuine multi-step taint chains (Algorithm C) over direct single-step
attacks — taint chains are harder to block because they require real agent reasoning.
