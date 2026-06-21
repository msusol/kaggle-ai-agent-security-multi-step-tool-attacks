# ── JED Attack Development Container ─────────────────────────────────────────
#
# Targets:
#   --target dev      Local dev on Mac (default) — stub env only
#   --target llm      Same + openai client for Ollama/vLLM integration
#
# Architecture: linux/arm64 (DGX Spark aarch64) AND linux/amd64 (Mac x86)
# Python: 3.11 (matches Kaggle's runtime)
#
# Build:
#   docker build --target dev -t jed-dev .
#   docker build --target llm -t jed-llm .
#
# Run (Mac, stub only):
#   docker run --rm -v $(pwd):/workspace jed-dev python local_harness.py --budget 60
#
# Run (Mac + Ollama):
#   docker run --rm -v $(pwd):/workspace \
#     -e OLLAMA_BASE_URL=http://host.docker.internal:11434/v1 \
#     -e OLLAMA_MODEL=llama3.1:8b \
#     jed-llm python local_harness.py --budget 120 --llm
#
# Run (DGX Spark + vLLM):
#   docker run --rm -v $(pwd):/workspace \
#     -e VLLM_BASE_URL=http://<spark-ip>:8000/v1 \
#     -e VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct \
#     jed-llm python local_harness.py --budget 300 --llm
# ─────────────────────────────────────────────────────────────────────────────

FROM python:3.11-slim AS base

# System deps: git for version pinning, curl for health checks
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Copy SDK package first (changes less often → better layer cache)
COPY setup.py .
COPY aicomp_sdk/ aicomp_sdk/

# Install SDK in editable mode
RUN pip install --no-cache-dir -e .

# ── dev target: stub env only, minimal deps ───────────────────────────────────
FROM base AS dev

COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt

# Copy project files
COPY attack.py local_harness.py ./

# Default: run the harness with 60s budget (fast feedback loop)
CMD ["python", "local_harness.py", "--budget", "60"]

# ── llm target: adds openai client for Ollama / vLLM / OpenAI ────────────────
FROM dev AS llm

COPY requirements-llm.txt .
RUN pip install --no-cache-dir -r requirements-llm.txt

CMD ["python", "local_harness.py", "--budget", "300", "--llm"]
