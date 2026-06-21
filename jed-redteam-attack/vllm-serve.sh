#!/usr/bin/env bash
# vllm-serve.sh  —  Run on DGX Spark to start vLLM OpenAI-compatible server
#
# Usage:
#   bash vllm-serve.sh                            # default model
#   MODEL=mistralai/Mistral-7B-Instruct-v0.3 bash vllm-serve.sh
#
# Then from your Mac:
#   SPARK_IP=<spark-ip> docker compose --profile spark up
#
# Requirements on Spark:
#   pip install vllm

set -euo pipefail

MODEL="${MODEL:-meta-llama/Llama-3.1-8B-Instruct}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
GPU_MEM="${GPU_MEM_UTIL:-0.85}"
MAX_LEN="${MAX_MODEL_LEN:-8192}"

echo "────────────────────────────────────────────"
echo "  vLLM server on DGX Spark"
echo "  model : $MODEL"
echo "  host  : $HOST:$PORT"
echo "  gpu   : $GPU_MEM utilization"
echo "────────────────────────────────────────────"

# Ensure HF_HOME is on fast storage
export HF_HOME="${HF_HOME:-/raid/hf_cache}"
mkdir -p "$HF_HOME"

python -m vllm.entrypoints.openai.api_server \
    --model "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    --gpu-memory-utilization "$GPU_MEM" \
    --max-model-len "$MAX_LEN" \
    --dtype bfloat16 \
    --trust-remote-code \
    --served-model-name "$(basename $MODEL)"

# ── Notes ──────────────────────────────────────────────────────────────────────
#
# For the competition, the actual agents are:
#   GPT-OSS 20B   (gpt-oss-20b-Q4_K_M.gguf)   — run via llama.cpp on Kaggle T4
#   Gemma 4 26B   (gemma-4-26B-A4B-it-UD-Q4_K_M.gguf) — same
#
# Closest locally available approximations:
#   For GPT-OSS 20B behavior:   try "microsoft/phi-4" or "mistralai/Mistral-7B-Instruct-v0.3"
#   For Gemma 4 26B behavior:   try "google/gemma-3-9b-it" or "google/gemma-3-27b-it"
#
# To download a GGUF and run via llama.cpp instead (matches Kaggle exactly):
#   pip install llama-cpp-python
#   huggingface-cli download llkh0a/gpt-oss-20b-gguf gpt-oss-20b-Q4_K_M.gguf
#   python -m llama_cpp.server --model gpt-oss-20b-Q4_K_M.gguf --port 8000 --n_gpu_layers -1
