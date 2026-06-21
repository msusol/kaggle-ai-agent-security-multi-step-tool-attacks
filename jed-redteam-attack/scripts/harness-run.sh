#!/usr/bin/env bash
# harness-run.sh  —  Run local_harness.py in Docker on DGX Spark.
#
# Connects to the vLLM server started by vllm-serve.sh (localhost:8000).
# Builds the jed-llm image if not present, logs output to logs/.
#
# Usage:
#   bash harness-run.sh                       # 300s budget, default model
#   BUDGET=900 bash harness-run.sh            # longer run
#   MODEL=Llama-3.1-8B-Instruct bash harness-run.sh
#
# Env vars:
#   BUDGET   Time budget in seconds (default: 300)
#   MODEL    Served model name — must match vllm-serve.sh's --served-model-name
#            (default: Llama-3.1-8B-Instruct, i.e. basename of the HF model id)
#   PORT     vLLM port on localhost (default: 8000)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"   # jed-redteam-attack/

BUDGET="${BUDGET:-300}"
MODEL="${MODEL:-Llama-3.1-8B-Instruct}"
PORT="${PORT:-8000}"
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
