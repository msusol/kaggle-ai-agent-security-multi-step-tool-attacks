#!/usr/bin/env bash
# harness-run.sh  —  Run local_harness.py in Docker on DGX Spark.
#
# Connects to either:
#   - llama-server (llama-serve.sh) on port 8082 (GPT-OSS 20B, Gemma 4 26B)
#   - vLLM server (vllm-serve.sh) on port 8000 (Llama 3.1 8B)
# Builds the jed-llm image if not present, logs output to logs/.
#
# Usage:
#   # GPT-OSS 20B via llama-server (default):
#   bash harness-run.sh                       # 300s budget
#   MODEL=gpt_oss BUDGET=900 bash harness-run.sh
#
#   # Gemma 4 26B via llama-server:
#   MODEL=gemma bash harness-run.sh
#
#   # Llama 3.1 8B via vLLM:
#   PORT=8000 MODEL=Llama-3.1-8B-Instruct bash harness-run.sh
#
# Env vars:
#   BUDGET   Time budget in seconds (default: 300)
#   MODEL    Served model name: gpt_oss | gemma | Llama-3.1-8B-Instruct
#   PORT     Server port on localhost (default: 8082 for llama-server)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"   # jed-redteam-attack/

BUDGET="${BUDGET:-300}"
MODEL="${MODEL:-gpt_oss}"
PORT="${PORT:-8082}"
LOG="${REPO_DIR}/logs/harness_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "${REPO_DIR}/logs"

echo "────────────────────────────────────────────"
echo "  JED harness on DGX Spark"
echo "  vllm  : http://localhost:${PORT}/v1"
echo "  model : ${MODEL}"
echo "  budget: ${BUDGET}s"
echo "  log   : ${LOG}"
echo "────────────────────────────────────────────"

# Build jed-llm image if not already present.
if ! docker image inspect jed-llm:latest > /dev/null 2>&1; then
    echo "Building jed-llm image..."
    docker build --target llm -t jed-llm:latest "${REPO_DIR}"
fi

docker run --rm \
    --network=host \
    -v "${REPO_DIR}:/workspace" \
    -e PYTHONUNBUFFERED=1 \
    -e VLLM_BASE_URL="http://localhost:${PORT}/v1" \
    -e VLLM_MODEL="${MODEL}" \
    jed-llm:latest \
    python local_harness.py --budget "${BUDGET}" --llm --verbose \
    2>&1 | tee "${LOG}"

echo "Log saved to ${LOG}"
