#!/usr/bin/env bash
# push-kaggle.sh  —  Build, stage, and push to Kaggle (dataset + notebook).
#
# Usage:
#   bash push-kaggle.sh "version message"          # push dataset AND notebook
#   bash push-kaggle.sh --dataset "message"        # dataset only
#   bash push-kaggle.sh --notebook "message"       # notebook only (message optional)
#
# Run from anywhere — the script resolves paths relative to its own location.
#
# What it does:
#   1. Rebuilds the aicomp_sdk wheel (python -m build --wheel)
#   2. Zips algorithms/ + payloads/ as jed-attack-src.zip
#   3. Stages dataset files → /tmp/jed-dataset  then kaggle datasets version
#   4. Stages kernel files  → /tmp/jed-kernel   then kaggle kernels push
#
# After kaggle kernels push, Kaggle auto-starts a committed run on the default
# GPU (usually T4). If you need a different GPU:
#   1. Stop the auto-run in the Kaggle UI
#   2. Right panel → Accelerator → desired GPU
#   3. Save Version → Save & Run All
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"   # jed-redteam-attack/
VENV="$HOME/LosusAI/Projects/Kaggle/.venv"
PYTHON="$VENV/bin/python"
# Prefer venv kaggle; fall back to miniconda/system kaggle
if [[ -f "$VENV/bin/kaggle" ]]; then
    KAGGLE="$VENV/bin/kaggle"
elif command -v kaggle &>/dev/null; then
    KAGGLE="$(command -v kaggle)"
else
    KAGGLE="$VENV/bin/kaggle"  # will fail sanity check below with helpful message
fi

DATASET_STAGING="/tmp/jed-dataset"
KERNEL_STAGING="/tmp/jed-kernel"

# ── Argument parsing ──────────────────────────────────────────────────────────
PUSH_DATASET=true
PUSH_NOTEBOOK=true
MSG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dataset)
            PUSH_NOTEBOOK=false
            shift
            ;;
        --notebook)
            PUSH_DATASET=false
            shift
            ;;
        -*)
            echo "Unknown flag: $1"
            echo "Usage: $0 [--dataset|--notebook] \"version message\""
            exit 1
            ;;
        *)
            MSG="$1"
            shift
            ;;
    esac
done

if [[ -z "$MSG" && "$PUSH_DATASET" == "true" ]]; then
    echo "Usage: $0 [--dataset|--notebook] \"version message\""
    echo "  A version message is required when pushing the dataset."
    exit 1
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  JED Attack — Kaggle Push"
echo "  dataset=${PUSH_DATASET}  notebook=${PUSH_NOTEBOOK}"
[[ -n "$MSG" ]] && echo "  message: ${MSG}"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Sanity checks ─────────────────────────────────────────────────────────────
[[ -f "$PYTHON" ]] || { echo "ERROR: venv not found at $VENV"; exit 1; }
[[ -f "$KAGGLE" ]] || { echo "ERROR: kaggle CLI not found at $KAGGLE"; exit 1; }
[[ -f "$REPO_DIR/attack.py" ]] || { echo "ERROR: attack.py not found at $REPO_DIR — check script location"; exit 1; }

# ── Step 1: Rebuild wheel ─────────────────────────────────────────────────────
if [[ "$PUSH_DATASET" == "true" ]]; then
    echo "[1/4] Building aicomp_sdk wheel..."
    cd "$REPO_DIR"
    "$PYTHON" -m build --wheel --outdir . --no-isolation 2>&1 | grep -E "wheel|error|warning|Successfully"
    WHEEL=$(ls "$SCRIPT_DIR"/aicomp_sdk-*.whl 2>/dev/null | sort -V | tail -1)
    [[ -f "$WHEEL" ]] || { echo "ERROR: wheel not found after build"; exit 1; }
    echo "  wheel: $(basename "$WHEEL")"
    echo ""
fi

# ── Step 2: Package algorithms/ + payloads/ as jed-attack-src.zip ─────────────
if [[ "$PUSH_DATASET" == "true" ]]; then
    echo "[2/4] Packaging jed-attack-src.zip..."
    cd "$REPO_DIR"
    rm -f jed-attack-src.zip
    zip -r jed-attack-src.zip algorithms/ payloads/ \
        --exclude "**/__pycache__/*" --exclude "**/*.pyc" -q
    echo "  jed-attack-src.zip: $(du -h jed-attack-src.zip | cut -f1)"
    echo ""
fi

# ── Step 3: Push dataset ──────────────────────────────────────────────────────
if [[ "$PUSH_DATASET" == "true" ]]; then
    echo "[3/4] Staging and pushing dataset (gdataranger/jed-aicomp-sdk)..."
    rm -rf "$DATASET_STAGING"
    mkdir -p "$DATASET_STAGING"

    cp "$WHEEL"                            "$DATASET_STAGING/"
    cp "$REPO_DIR/attack.py"             "$DATASET_STAGING/"
    cp "$REPO_DIR/local_harness.py"      "$DATASET_STAGING/"
    cp "$REPO_DIR/jed-attack-src.zip"   "$DATASET_STAGING/"
    cp "$REPO_DIR/dataset-metadata.json" "$DATASET_STAGING/"
    # Cover image: prefer .jpg (kaggle CLI picks last match; .jpg wins over .png)
    if [[ -f "$REPO_DIR/dataset-cover-image.jpg" ]]; then
        cp "$REPO_DIR/dataset-cover-image.jpg" "$DATASET_STAGING/"
    elif [[ -f "$REPO_DIR/dataset-cover-image.png" ]]; then
        cp "$REPO_DIR/dataset-cover-image.png" "$DATASET_STAGING/"
    fi

    echo "  staged files:"
    ls -lh "$DATASET_STAGING" | awk 'NR>1 {printf "    %-40s %s\n", $NF, $5}'
    echo ""

    "$KAGGLE" datasets version -p "$DATASET_STAGING" -m "$MSG"
    echo ""
fi

# ── Step 4: Push notebook ─────────────────────────────────────────────────────
if [[ "$PUSH_NOTEBOOK" == "true" ]]; then
    echo "[4/4] Staging and pushing notebook (gdataranger/jed-attack-agent-security)..."
    rm -rf "$KERNEL_STAGING"
    mkdir -p "$KERNEL_STAGING"

    cp "$REPO_DIR/kaggle_notebook.ipynb" "$KERNEL_STAGING/"
    # kaggle CLI requires the metadata file to be named exactly kernel-metadata.json
    cp "$REPO_DIR/kernel-metadata.json"  "$KERNEL_STAGING/kernel-metadata.json"

    echo "  staged files:"
    ls -lh "$KERNEL_STAGING" | awk 'NR>1 {printf "    %-40s %s\n", $NF, $5}'
    echo ""

    "$KAGGLE" kernels push -p "$KERNEL_STAGING"
    echo ""
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════════════"
echo "  Push complete."
if [[ "$PUSH_NOTEBOOK" == "true" ]]; then
    echo ""
    echo "  NOTE: Kaggle auto-started a committed run on the default GPU."
    echo "  If a different GPU is needed:"
    echo "    1. Stop the auto-run in the Kaggle UI"
    echo "    2. Accelerator → desired GPU"
    echo "    3. Save Version → Save & Run All"
fi
echo "══════════════════════════════════════════════════════"
echo ""
