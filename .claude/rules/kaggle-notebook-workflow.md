# Kaggle Notebook Workflow

All Kaggle notebook changes (code, metadata, dataset sources) are managed via
`kaggle kernels push` from the local machine. **Never instruct the user to
make changes manually in the Kaggle UI** — all configuration lives in
version-controlled metadata files.

---

## Push workflow

```zsh
mkdir -p /tmp/jed-kernel
cp jed-redteam-attack/kaggle_notebook.ipynb /tmp/jed-kernel/
cp jed-redteam-attack/kernel-metadata.json /tmp/jed-kernel/kernel-metadata.json
/Users/marksusol/LosusAI/Projects/Kaggle/.venv/bin/kaggle kernels push \
  -p /tmp/jed-kernel
```

The staging dir is required because Kaggle's CLI expects the metadata file
named exactly `kernel-metadata.json`.

## GPU model selection — UI only

`enable_gpu: true` in metadata means "use a GPU" but Kaggle assigns T4 by
default. **Specific GPU selection (P100, T4 x2) must be done manually in the
Kaggle editor UI** — there is no metadata field for it.

Correct workflow after every push:

1. `kaggle kernels push` → updates code; auto-starts a committed run
2. If a different GPU tier is needed: **stop the auto-run in Kaggle UI**
3. Right panel → **Accelerator → desired GPU**
4. **Save Version → Save & Run All**

## kernel-metadata.json fields

`jed-redteam-attack/kernel-metadata.json` is the source of truth:

| Field | Value |
|---|---|
| `id` | `gdataranger/jed-attack-agent-security` |
| `title` | `JED Attack — Agent Security` |
| `code_file` | `kaggle_notebook.ipynb` |
| `language` | `python` |
| `kernel_type` | `notebook` |
| `is_private` | `true` |
| `enable_gpu` | `true` |
| `enable_internet` | `false` |
| `dataset_sources` | `["gdataranger/jed-aicomp-sdk"]` |
| `competition_sources` | `["ai-agent-security-multi-step-tool-attacks"]` |

To add or remove any input, edit the JSON and push — do not use the Kaggle UI.

## Updating the SDK dataset after code changes

When `attack.py`, `payloads/library.py`, `algorithms/`, or `aicomp_sdk/`
change, publish a new dataset version before pushing the notebook:

```zsh
# 1. Rebuild the wheel
cd jed-redteam-attack
/Users/marksusol/LosusAI/Projects/Kaggle/.venv/bin/python \
  -m build --wheel --outdir .

# 2. Publish updated dataset version
/Users/marksusol/LosusAI/Projects/Kaggle/.venv/bin/kaggle \
  datasets version \
  -p . \
  -m "describe what changed"

# 3. Push the notebook
mkdir -p /tmp/jed-kernel
cp kaggle_notebook.ipynb /tmp/jed-kernel/
cp kernel-metadata.json /tmp/jed-kernel/kernel-metadata.json
/Users/marksusol/LosusAI/Projects/Kaggle/.venv/bin/kaggle kernels push \
  -p /tmp/jed-kernel
```

## Committed runs vs interactive sessions

| Setting | Committed run (Save & Run All) | Interactive session |
|---|---|---|
| `dataset_sources` | Applied automatically ✓ | Applied automatically ✓ |
| `competition_sources` | Applied automatically ✓ | Applied automatically ✓ |
| `enable_internet` | Applied automatically ✓ | Must be toggled manually ✗ |

**Preferred mode: committed run (Save Version → Save & Run All).**
Do not guide the user to run cells interactively for the full evaluation —
use committed runs so the full 9000s budget per model is available.

## Submission vs validation notebook

The `kaggle_notebook.ipynb` serves two purposes:

- **Validation** (Cells 6–7): calls `evaluate_redteam()` locally to see your
  score before submitting. This is for your visibility only.
- **Submission**: the evaluator loads `/kaggle/working/attack.py` and calls
  `AttackAlgorithm().run(env, config)` automatically. You do NOT call
  `evaluate_redteam()` in the submission path.

For the official submission, ensure Cell 2 writes `attack.py` to
`/kaggle/working/` before the evaluator runs.

## Kaggle username

Kaggle account: `gdataranger`
Dataset: `gdataranger/jed-aicomp-sdk`
Notebook: `gdataranger/jed-attack-agent-security`
