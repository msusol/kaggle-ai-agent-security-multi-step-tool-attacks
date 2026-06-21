#!/usr/bin/env bash
# vllm-serve.sh  —  Run vLLM inside Docker on DGX Spark.
#
# Usage:
#   bash vllm-serve.sh                                      # default model
#   MODEL=mistralai/Mistral-7B-Instruct-v0.3 bash vllm-serve.sh
#   IMAGE=jed-vllm:latest bash vllm-serve.sh               # use our own image
#
# Env vars:
#   MODEL       HuggingFace model ID (default: meta-llama/Llama-3.1-8B-Instruct)
#   IMAGE       Docker image with vLLM (default: nemotron-vllm-gb10:latest)
#   PORT        Host port to expose (default: 8000)
#   HF_TOKEN    HuggingFace token — required for gated models (Llama, Gemma)
#   HF_HOME     Override cache dir inside container
#
# Build our own image first (optional — nemotron-vllm-gb10 works as a drop-in):
#   make build-vllm
#
# From your Mac once server is up:
#   SPARK_IP=<dgx-ip> docker compose --profile spark up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"   # jed-redteam-attack/

# Load .env if present (HF_TOKEN, etc.)
if [[ -f "${REPO_DIR}/.env" ]]; then
    set -a && source "${REPO_DIR}/.env" && set +a
fi

MODEL="${MODEL:-meta-llama/Llama-3.1-8B-Instruct}"
IMAGE="${IMAGE:-nemotron-vllm-gb10:latest}"
PORT="${PORT:-8000}"
GPU_MEM="${GPU_MEM_UTIL:-0.85}"
MAX_LEN="${MAX_MODEL_LEN:-8192}"

# Prefer fast /raid storage; fall back to ~/.cache/huggingface if not writable.
_RAID_CACHE="/raid/hf_cache"
if [[ -n "${HF_HOME:-}" ]]; then
    : # caller-provided override
elif mkdir -p "$_RAID_CACHE" 2>/dev/null; then
    HF_HOME="$_RAID_CACHE"
else
    HF_HOME="${HOME}/.cache/huggingface"
    mkdir -p "$HF_HOME"
fi

# Pause other long-lived containers to free GPU memory; resume on exit.
make -C "$REPO_DIR" pause
trap 'make -C "$REPO_DIR" resume' EXIT

echo "────────────────────────────────────────────"
echo "  vLLM server on DGX Spark"
echo "  image : $IMAGE"
echo "  model : $MODEL"
echo "  host  : 0.0.0.0:$PORT"
echo "  gpu   : $GPU_MEM utilization"
echo "  cache : $HF_HOME"
echo "────────────────────────────────────────────"

docker run --rm \
    --privileged \
    --ipc=host \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -e NVIDIA_VISIBLE_DEVICES=all \
    -e HF_HOME=/cache/huggingface \
    -e HUGGINGFACE_HUB_CACHE=/cache/huggingface \
    ${HF_TOKEN:+-e HF_TOKEN="${HF_TOKEN}"} \
    -v "${HF_HOME}:/cache/huggingface" \
    -p "${PORT}:${PORT}" \
    "$IMAGE" \
    python -m vllm.entrypoints.openai.api_server \
        --model "$MODEL" \
        --host 0.0.0.0 \
        --port "$PORT" \
        --gpu-memory-utilization "$GPU_MEM" \
        --max-model-len "$MAX_LEN" \
        --dtype bfloat16 \
        --trust-remote-code \
        --served-model-name "$(basename "$MODEL")"

# ── Notes ──────────────────────────────────────────────────────────────────────
#
# For competition-parity testing, use scripts/llama-serve.sh instead —
# it serves the exact GGUF quantizations the Kaggle evaluator uses:
#
#   MODEL=gpt-oss bash scripts/llama-serve.sh   # ggml-org/gpt-oss-20b-GGUF (12 GB)
#   MODEL=gemma   bash scripts/llama-serve.sh   # google/gemma-4-26B-A4B-it-qat-q4_0-gguf (14 GB)
#
# vllm-serve.sh is best for HF safetensors models (Llama, Mistral, etc.)
# and for rapid iteration before committing to a full competition run.
#
# To use our own image instead of nemotron's:
#   make build-vllm
#   IMAGE=jed-vllm:latest bash scripts/vllm-serve.sh
