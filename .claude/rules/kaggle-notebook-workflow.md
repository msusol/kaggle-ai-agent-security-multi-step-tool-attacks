# Kaggle Notebook Workflow

All Kaggle notebook changes (code, metadata, dataset sources) are managed via
`kaggle kernels push` from the local machine. **Never instruct the user to
make changes manually in the Kaggle UI** — all configuration lives in
version-controlled metadata files.

---

## Push workflow

Before every push, update Cell 1 (id `md-header`) of `kaggle_notebook.ipynb`
with the version, strategy, and budget so the kernel version history is
self-documenting. Format: `v0.## ATTACK_TYPES strategy budget`.

Example Cell 1 line:
```
v0.24 EXF+CD dynamic-N 9000s: `SECRET_MARKER` posts + `CONFUSED_DEPUTY`.
```

`kaggle kernels push` has no `--message` flag; Cell 1 is the only audit trail.

```zsh
mkdir -p /tmp/jed-kernel
cp jed-redteam-attack/kaggle_notebook.ipynb /tmp/jed-kernel/
cp jed-redteam-attack/kernel-metadata.json /tmp/jed-kernel/kernel-metadata.json
/home/msusol/miniconda3/bin/kaggle kernels push \
  -p /tmp/jed-kernel
```

The staging dir is required because Kaggle's CLI expects the metadata file
named exactly `kernel-metadata.json`.

## GPU / accelerator selection

Our competition notebook does **not** need a GPU. It copies `attack.py` and
calls `serve()` — a lightweight Python server. LLM inference (GPT-OSS 20B,
Gemma 4 26B) is done by the competition evaluator on its own GPU infrastructure.
GPU is intentionally disabled (`enable_gpu: false`) — P100 is not allowed in
the competition and a GPU adds no value to our notebook.

The `machine_shape` field in `kernel-metadata.json` (or `--accelerator ACC` on
`kaggle kernels push`) can specify: `NvidiaTeslaT4`, `NvidiaTeslaP100`, or
`Tpu1VmV38`. **2×T4 is not available via the API** — it must be set in the
Kaggle editor UI. Do not add `machine_shape` to our metadata.

Correct workflow after every push:

1. `kaggle kernels push` → updates code; auto-starts a committed run
2. No GPU change needed for this competition notebook.

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
| `enable_gpu` | `false` (competition notebook doesn't run LLMs; evaluator has its own GPU) |
| `enable_internet` | `false` |
| `dataset_sources` | `["gdataranger/jed-aicomp-sdk"]` |
| `competition_sources` | `["ai-agent-security-multi-step-tool-attacks"]` |
| `model_sources` | `["llkh0a/gpt-oss-20b-gguf/pytorch/default/1", "llkh0a/gemma-4-26b-a4b-it-ud-q4-k-m-gguf/pytorch/default/1"]` |

Model source format: `{owner}/{model-slug}/{framework}/{instance}/{version}` — derived from the mount path `/kaggle/input/models/{owner}/{model-slug}/{framework}/{instance}/{version}/`.

**First-time model attachment requires the Kaggle UI** (same pattern as CC0 license for datasets):
1. Open notebook editor → **+ Add Input** → Models tab
2. Search and select each model, accept any license prompts
3. Save Version — after this, `model_sources` in `kernel-metadata.json` persists the attachment on all future `kaggle kernels push` calls

Do not add or remove inputs via the Kaggle UI after the first-time setup — use `kernel-metadata.json` and push.

## Updating the dataset after code changes

When `attack.py` or `local_harness.py` change, publish a new dataset version before
pushing the notebook. The dataset contains only these two files — no wheel, no SDK.
The competition environment provides `aicomp_sdk` itself.

```zsh
# 1. Stage only the needed files — kaggle CLI uploads everything in -p dir
cd jed-redteam-attack
mkdir -p /tmp/jed-dataset
cp attack.py /tmp/jed-dataset/
cp local_harness.py /tmp/jed-dataset/
cp dataset-metadata.json /tmp/jed-dataset/
cp dataset-cover-image.png /tmp/jed-dataset/  # CLI auto-uploads as cover image

# 2. Publish updated dataset version
/home/msusol/miniconda3/bin/kaggle \
  datasets version \
  -p /tmp/jed-dataset/ \
  -m "v0.## brief description of change"

# 3. Push the notebook (after updating Cell 1 version label)
mkdir -p /tmp/jed-kernel
cp kaggle_notebook.ipynb /tmp/jed-kernel/
cp kernel-metadata.json /tmp/jed-kernel/kernel-metadata.json
/home/msusol/miniconda3/bin/kaggle kernels push \
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

## Dataset metadata usability

Kaggle shows a usability score for datasets based on these items. All are set
in `dataset-metadata.json` and applied via `kaggle datasets version`.

### What each field maps to

| Usability item | JSON field | Notes |
|---|---|---|
| Subtitle | `subtitle` | 20–80 characters; required |
| Description | `description` | Markdown; use headers, tables, code blocks |
| License | `licenses[0].name` | Must be set to `"CC0-1.0"` via **Kaggle UI first** (Settings → License → CC0: Public Domain); subsequent `datasets version` pushes will preserve it. `"MIT"` and `"other"` are silently ignored by the API. |
| File information | `data[].description` | Per-file description entries; counts toward usability |
| Provenance | `userSpecifiedSources` | Plain string; maps to the Provenance metadata tab |
| Cover image | `dataset-cover-image.png` | Place alongside metadata in staging dir; CLI auto-detects and uploads via separate API path (no progress shown) |

### Confirmed working values

```json
{
  "subtitle": "20–80 char one-liner",
  "description": "Markdown body — tables, code blocks, headers",
  "userSpecifiedSources": "One paragraph: who made it, where it came from, GitHub link",
  "licenses": [{"name": "CC0-1.0"}],
  "keywords": ["nlp", "deep learning", "python", "classification"],
  "data": [
    {"name": "file.whl", "description": "Install with pip install file.whl"},
    {"name": "attack.py", "description": "What it does"}
  ]
}
```

### Tags — valid vs invalid

Multi-word tags without hyphens may not register. Confirmed working:
`"nlp"`, `"deep learning"`, `"python"`, `"classification"`.
Not working: `"kaggle competition"`, `"agent security"`, `"text data"`, `"MIT"`.

### Cover image specs

Kaggle requires **minimum 564×284 pixels**. Generate at exactly 564×284 so
the content fills the header crop precisely. Use JPEG (RGB) — PNG with RGBA
(transparency) may not apply correctly.

Name the file `dataset-cover-image.jpg` (or `.png`, `.jpeg`, `.webp`) and
place it alongside `dataset-metadata.json` in the staging dir. The CLI
auto-detects it by filename and uploads via a separate API path (no progress
bar shown for the image upload). When both `.png` and `.jpg` are present, the
`.jpg` is used (last match wins in the CLI's canonical filename list).

### `.kaggleignore` is not supported

The `kaggle datasets version -p <dir>` command uploads all non-directory files
in `<dir>`. `.kaggleignore` is not processed. Always use a staging directory
with only the files that should appear in the dataset.

## Kaggle username

Kaggle account: `gdataranger`
Dataset: `gdataranger/jed-aicomp-sdk`
Notebook: `gdataranger/jed-attack-agent-security`
