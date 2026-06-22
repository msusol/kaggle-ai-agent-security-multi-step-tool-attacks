#!/usr/bin/env bash
# push-kaggle-dgx.sh  —  Build and push to Kaggle from the DGX Spark.
#
# Uses miniconda python + kaggle CLI (installed at ~/miniconda3/).
# The project .venv does not have `build` or `kaggle`; this script avoids it.
#
# Usage (from jed-redteam-attack/):
#   bash scripts/push-kaggle-dgx.sh "version message"        # full push (dataset + competition notebook)
#   bash scripts/push-kaggle-dgx.sh --demo                   # push DGX demo notebook only
#
# After push: Kaggle auto-starts a committed run on T4.
# To use a different GPU: stop auto-run → Accelerator → Save & Run All.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"   # jed-redteam-attack/
PYTHON="$HOME/miniconda3/bin/python3"
PIP="$HOME/miniconda3/bin/pip"
KAGGLE="$HOME/miniconda3/bin/kaggle"

DATASET_STAGING="/tmp/jed-dataset"
KERNEL_STAGING="/tmp/jed-kernel"

# ── Argument parsing ──────────────────────────────────────────────────────────
PUSH_DEMO=false
MSG=""

for arg in "$@"; do
    case "$arg" in
        --demo) PUSH_DEMO=true ;;
        *)      MSG="$arg" ;;
    esac
done

# --demo: push only dgx_notebook.ipynb (no wheel build, no dataset push)
if [[ "$PUSH_DEMO" == "true" ]]; then
    echo ""
    echo "══════════════════════════════════════════════════════"
    echo "  JED Attack — DGX Demo Notebook Push (DGX)"
    echo "  kernel : gdataranger/jed-dgx-spark-gb10"
    echo "══════════════════════════════════════════════════════"
    echo ""
    [[ -f "$KAGGLE" ]] || { echo "ERROR: kaggle not found at $KAGGLE"; exit 1; }
    rm -rf "$KERNEL_STAGING" && mkdir -p "$KERNEL_STAGING"
    cp "$REPO_DIR/dgx_notebook.ipynb"       "$KERNEL_STAGING/"
    cp "$REPO_DIR/dgx-kernel-metadata.json" "$KERNEL_STAGING/kernel-metadata.json"
    echo "  staged: $(ls "$KERNEL_STAGING" | tr '\n' ' ')"
    "$KAGGLE" kernels push -p "$KERNEL_STAGING"
    echo ""
    echo "  DGX demo notebook pushed: gdataranger/jed-dgx-spark-gb10"
    echo "══════════════════════════════════════════════════════"
    echo ""
    exit 0
fi

if [[ -z "$MSG" ]]; then
    echo "Usage: $0 \"version message\""
    echo "       $0 --demo"
    exit 1
fi

echo ""
echo "══════════════════════════════════════════════════════"
echo "  JED Attack — Kaggle Push (DGX)"
echo "  python : $PYTHON"
echo "  kaggle : $KAGGLE"
echo "  message: $MSG"
echo "══════════════════════════════════════════════════════"
echo ""

[[ -f "$PYTHON" ]] || { echo "ERROR: python not found at $PYTHON"; exit 1; }
[[ -f "$KAGGLE" ]] || { echo "ERROR: kaggle not found at $KAGGLE"; exit 1; }

# ── Step 1: Ensure build is available, then build wheel ──────────────────────
echo "[1/4] Building aicomp_sdk wheel..."
"$PIP" install build --quiet --no-warn-script-location 2>/dev/null || true
cd "$REPO_DIR"
"$PYTHON" -m build --wheel --outdir . --no-isolation
WHEEL=$(ls "$REPO_DIR"/aicomp_sdk-*.whl 2>/dev/null | sort -V | tail -1)
[[ -f "$WHEEL" ]] || { echo "ERROR: wheel not found after build"; exit 1; }
echo "  wheel: $(basename "$WHEEL")"
echo ""

# ── Step 2: Zip algorithms/ + payloads/ ──────────────────────────────────────
echo "[2/4] Packaging jed-attack-src.zip..."
cd "$REPO_DIR"
rm -f jed-attack-src.zip
zip -r jed-attack-src.zip algorithms/ payloads/ \
    --exclude "*/__pycache__/*" --exclude "*/*.pyc" -q
echo "  jed-attack-src.zip: $(du -h jed-attack-src.zip | cut -f1)"
echo ""

# ── Step 3: Push dataset ──────────────────────────────────────────────────────
echo "[3/4] Pushing dataset (gdataranger/jed-aicomp-sdk)..."
rm -rf "$DATASET_STAGING" && mkdir -p "$DATASET_STAGING"
cp "$WHEEL"                           "$DATASET_STAGING/"
cp "$REPO_DIR/attack.py"              "$DATASET_STAGING/"
cp "$REPO_DIR/local_harness.py"       "$DATASET_STAGING/"
cp "$REPO_DIR/jed-attack-src.zip"     "$DATASET_STAGING/"
cp "$REPO_DIR/dataset-metadata.json"  "$DATASET_STAGING/"
[[ -f "$REPO_DIR/dataset-cover-image.jpg" ]] && cp "$REPO_DIR/dataset-cover-image.jpg" "$DATASET_STAGING/"
[[ -f "$REPO_DIR/dataset-cover-image.png" ]] && cp "$REPO_DIR/dataset-cover-image.png" "$DATASET_STAGING/"
echo "  staged: $(ls "$DATASET_STAGING" | tr '\n' ' ')"
"$KAGGLE" datasets version -p "$DATASET_STAGING" -m "$MSG"
echo ""

# ── Step 4: Push notebook ─────────────────────────────────────────────────────
echo "[4/4] Pushing notebook (gdataranger/jed-attack-agent-security)..."
rm -rf "$KERNEL_STAGING" && mkdir -p "$KERNEL_STAGING"
cp "$REPO_DIR/kaggle_notebook.ipynb"  "$KERNEL_STAGING/"
cp "$REPO_DIR/kernel-metadata.json"   "$KERNEL_STAGING/kernel-metadata.json"
echo "  staged: $(ls "$KERNEL_STAGING" | tr '\n' ' ')"
"$KAGGLE" kernels push -p "$KERNEL_STAGING"
echo ""

echo "══════════════════════════════════════════════════════"
echo "  Push complete."
echo ""
echo "  NOTE: Kaggle auto-started a committed run (T4 GPU)."
echo "  For a different GPU:"
echo "    1. Stop the auto-run in the Kaggle UI"
echo "    2. Accelerator → desired GPU"
echo "    3. Save Version → Save & Run All"
echo "══════════════════════════════════════════════════════"
echo ""
