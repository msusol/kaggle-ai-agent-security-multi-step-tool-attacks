#!/usr/bin/env bash
# llama-serve.sh  —  Serve GGUF competition models via llama.cpp on DGX Spark.
#
# Uses the llama-server C++ binary with --jinja — the same runtime the Kaggle
# evaluator uses.  --jinja evaluates the full embedded Jinja2 chat template
# (including render_tool_namespace) so GPT-OSS and Gemma 4 receive proper tool
# schemas.  The Python llama-cpp-python wrapper does not support --jinja and
# cannot inject tools correctly into these models (produces !!! garbage output).
#
# Usage:
#   MODEL=gpt-oss bash scripts/llama-serve.sh       # GPT-OSS 20B Q4_K_M (~9 GB, unsloth)
#   MODEL=gemma   bash scripts/llama-serve.sh       # Gemma 4 26B  (14 GB)
#
# Then run the harness against it in a second tmux window:
#   PORT=8080 MODEL=gpt_oss bash scripts/harness-run.sh
#   PORT=8080 MODEL=gemma   bash scripts/harness-run.sh
#
# Env vars:
#   MODEL       "gpt-oss" | "gemma"  (required; no default)
#   PORT        Host port (default: 8080)
#   NCTX        Context window size (default: 8192)
#   HF_TOKEN    HuggingFace token (optional; both models are publicly gated-free)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"   # jed-redteam-attack/
VENV="$HOME/LosusAI/Projects/Kaggle/.venv"

# Load .env if present (HF_TOKEN, etc.)
if [[ -f "${REPO_DIR}/.env" ]]; then
    set -a && source "${REPO_DIR}/.env" && set +a
fi

MODEL="${MODEL:-}"
PORT="${PORT:-8082}"   # 8080 is nginx on DGX Spark; 8000 is vLLM
NCTX="${NCTX:-8192}"

if [[ -z "$MODEL" ]]; then
    echo "Usage: MODEL=gpt-oss|gemma bash scripts/llama-serve.sh"
    exit 1
fi

# ── Model selection ────────────────────────────────────────────────────────────
# MODEL_ALIAS must match a key in payloads/library.py::_MODEL_HINT_MAP so that
# seeds_for_model() returns the correct model-specific seed set.
case "$MODEL" in
    gpt-oss|gpt_oss)
        HF_REPO="unsloth/gpt-oss-20b-GGUF"
        HF_FILE="gpt-oss-20b-Q4_K_M.gguf"
        MODEL_ALIAS="gpt_oss"          # → _MODEL_HINT_MAP["gpt_oss"]
        # --jinja: kept for consistency (has no effect on our /completion
        #   calls, but harmless; remove if it causes unexpected behaviour).
        # --reasoning off: suppress thinking tokens.
        # Note: --skip-chat-parsing was tried but ALSO bypasses Jinja2 on
        #   input → ??? degeneration. Removed. We bypass /v1/chat/completions
        #   entirely and use /completion with add_special=True tokenisation.
        SERVER_FLAGS="--jinja --reasoning off"
        ;;
    gemma|gemma4)
        HF_REPO="google/gemma-4-26B-A4B-it-qat-q4_0-gguf"
        HF_FILE="gemma-4-26B_q4_0-it.gguf"
        MODEL_ALIAS="gemma"            # → _MODEL_HINT_MAP["gemma"]
        # --jinja needed for Gemma: render_tool_namespace injects TypeScript tool
        # definitions into the developer block; Gemma's PEG output is valid.
        SERVER_FLAGS="--jinja"
        ;;
    *)
        echo "ERROR: Unknown MODEL '$MODEL'.  Use: gpt-oss | gemma"
        exit 1
        ;;
esac

# ── HF cache — prefer fast /raid storage ──────────────────────────────────────
_RAID_CACHE="/raid/hf_cache"
if [[ -n "${HF_HOME:-}" ]]; then
    :
elif mkdir -p "$_RAID_CACHE" 2>/dev/null; then
    HF_HOME="$_RAID_CACHE"
else
    HF_HOME="${HOME}/.cache/huggingface"
    mkdir -p "$HF_HOME"
fi

# Flat download dir — avoids hunting through the hub symlink tree.
DOWNLOAD_DIR="${HF_HOME}/gguf"
GGUF_PATH="${DOWNLOAD_DIR}/${HF_FILE}"

LOG="${REPO_DIR}/logs/llama_${MODEL_ALIAS}_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "${REPO_DIR}/logs"

echo "────────────────────────────────────────────"
echo "  llama.cpp server on DGX Spark"
echo "  model  : $HF_REPO / $HF_FILE"
echo "  alias  : $MODEL_ALIAS  (pass as MODEL= to harness-run.sh)"
echo "  host   : 0.0.0.0:$PORT"
echo "  ctx    : $NCTX"
echo "  cache  : $DOWNLOAD_DIR"
echo "  log    : $LOG"
echo "────────────────────────────────────────────"

# ── Build jed-llama image if missing or REBUILD=1 ─────────────────────────────
# REBUILD=1 forces a fresh build after Dockerfile.llama changes.
_NEEDS_BUILD=false
if [[ "${REBUILD:-0}" == "1" ]]; then
    echo "REBUILD=1: removing existing jed-llama image..."
    docker rmi jed-llama:latest 2>/dev/null || true
    _NEEDS_BUILD=true
elif ! docker image inspect jed-llama:latest > /dev/null 2>&1; then
    _NEEDS_BUILD=true
fi

if [[ "$_NEEDS_BUILD" == "true" ]]; then
    echo ""
    echo "Building jed-llama image (llama-server C++ binary + CUDA)..."
    echo "First build clones llama.cpp and compiles CUDA kernels — expect ~20 minutes."
    docker build -t jed-llama:latest -f "${REPO_DIR}/Dockerfile.llama" "${REPO_DIR}"
fi

# ── Download GGUF if not cached ───────────────────────────────────────────────
if [[ ! -f "$GGUF_PATH" ]]; then
    echo ""
    echo "Downloading $HF_FILE from $HF_REPO ..."
    mkdir -p "$DOWNLOAD_DIR"

    # huggingface_hub >= 1.20.0 renamed the CLI from 'huggingface-cli' to 'hf'.
    # Prefer 'hf' (system-level) if available; fall back to venv's huggingface-cli.
    if command -v hf &>/dev/null; then
        hf download "$HF_REPO" "$HF_FILE" \
            --local-dir "$DOWNLOAD_DIR" \
            ${HF_TOKEN:+--token "${HF_TOKEN}"}
    elif [[ -x "${VENV}/bin/huggingface-cli" ]]; then
        "${VENV}/bin/huggingface-cli" download \
            "$HF_REPO" "$HF_FILE" \
            --local-dir "$DOWNLOAD_DIR" \
            --local-dir-use-symlinks False \
            ${HF_TOKEN:+--token "${HF_TOKEN}"}
    else
        echo "ERROR: neither 'hf' nor '${VENV}/bin/huggingface-cli' found"
        exit 1
    fi
fi

[[ -f "$GGUF_PATH" ]] || { echo "ERROR: download failed — $GGUF_PATH not found"; exit 1; }
echo "  gguf: $GGUF_PATH ($(du -h "$GGUF_PATH" | cut -f1))"
echo ""

# Pause other long-lived containers to free GPU memory; resume on exit.
make -C "$REPO_DIR" pause
trap 'make -C "$REPO_DIR" resume' EXIT

# ── Serve ──────────────────────────────────────────────────────────────────────
# /models is mounted read-only inside the container.
# SERVER_FLAGS is set per-model above:
#   gpt-oss: "--jinja --reasoning off"
#     LLMEnv bypasses /v1/chat/completions entirely for GPT-OSS and uses
#     the native /completion endpoint with manually-tokenized prompts
#     (parse_special=True, add_special=True to include BOS 199998).
#     This avoids the PEG grammar error without needing --skip-chat-parsing.
#     --jinja is kept but has no effect on /completion calls.
#     --reasoning off: suppress thinking tokens.
#   gemma: "--jinja"
#     --jinja: render_tool_namespace injects TypeScript tool defs;
#     Gemma's PEG output is valid, uses /v1/chat/completions normally.
# --n_gpu_layers -1 offloads all layers to GPU (fits in 128 GB unified memory).
docker run --rm \
    --privileged \
    --ipc=host \
    --gpus all \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -e NVIDIA_VISIBLE_DEVICES=all \
    ${HF_TOKEN:+-e HF_TOKEN="${HF_TOKEN}"} \
    -v "${DOWNLOAD_DIR}:/models:ro" \
    -p "${PORT}:${PORT}" \
    jed-llama:latest \
    llama-server \
        --model "/models/${HF_FILE}" \
        --alias "${MODEL_ALIAS}" \
        --host 0.0.0.0 \
        --port "${PORT}" \
        --ctx-size "${NCTX}" \
        --n-gpu-layers -1 \
        ${SERVER_FLAGS} \
    2>&1 | tee "${LOG}"

echo "Log saved to ${LOG}"
