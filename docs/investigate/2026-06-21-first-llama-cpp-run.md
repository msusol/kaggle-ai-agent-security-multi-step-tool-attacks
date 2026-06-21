# First llama.cpp / GPT-OSS 20B Run — DGX Spark

**Date:** 2026-06-21  
**Model:** `ggml-org/gpt-oss-20b-GGUF` → `gpt-oss-20b-mxfp4.gguf` (12.1 GB)  
**Server:** `jed-llama:latest` (llama-cpp-python 0.3.x, CUDA SM 90/100/120)  
**Logs:** `harness_20260621_120237.log` (Attempt 1), `harness_20260621_120740.log` (Attempt 2)

---

## Summary

Both harness runs scored 0.0 — not due to model behaviour, but due to two
infrastructure bugs discovered during first bring-up. The server itself
started cleanly on the third attempt (12:10) with all bugs fixed.

---

## Bugs Found and Fixed

### Bug 1: `huggingface-cli` deprecated

`huggingface_hub >= 1.20.0` renamed the CLI from `huggingface-cli` to `hf`.
The old command printed a deprecation notice and exited without downloading,
leaving the GGUF absent and the `[[ -f ]]` guard in `llama-serve.sh` failing.

**Fix:** `scripts/llama-serve.sh` now prefers `hf download` (system-level)
and falls back to `${VENV}/bin/huggingface-cli` for older installs.
Both Dockerfiles pinned to `huggingface_hub>=1.20.0`.

### Bug 2: Wrong `--chat_format` overrides the embedded GGUF template

We passed `--chat_format chatml` which tells llama-cpp-python to apply the
ChatML formatter (`<|im_start|>` / `<|im_end|>` tokens) to every conversation.
The GPT-OSS 20B GGUF contains a baked-in Jinja2 template
(`chat_template.default`) that uses a completely different token scheme:

```
<|start|>system<|message|>....<|end|>
<|start|>developer<|message|>....<|end|>   ← tool schema injected here
<|start|>user<|message|>....<|end|>
<|start|>assistant<|channel|>final<|message|>....<|end|>
<|start|>assistant to=functions.X<|channel|>commentary json<|message|>....<|call|>
<|start|>functions.X to=assistant<|channel|>commentary<|message|>....<|end|>
```

Forcing `chatml` means every prompt is formatted with `<|im_start|>` tokens
the model never saw in training → degraded responses (and tool calls would
likely never fire).

**Fix:** Changed to `--chat_format jinja` so llama-cpp-python loads and uses
the Jinja2 template embedded in the GGUF. Confirmed working — server startup
log shows: `Available chat formats from metadata: chat_template.default`.

### Bug 3: Port 8080 conflicts with DGX nginx

The DGX Spark runs an nginx reverse proxy on port 8080. When our
`docker run -p 8080:8080` attempted to bind host port 8080:

| Attempt | nginx state | Result |
|---|---|---|
| 12:02 (Attempt 1) | Running | Docker port bind silently failed; harness hit nginx → `404 Not Found (nginx/1.28.3)` |
| 12:07 (Attempt 2) | Paused by `make pause` | Docker bind succeeded but server was mid-init; harness got `Connection error` |
| 12:10 (Attempt 3) | Paused | Server fully initialised; Uvicorn ready on 8080 ✓ |

**Fix (pending):** Change default port in `llama-serve.sh` from 8080 to 8082.
Port 8080 is reserved by nginx and causes intermittent conflicts depending on
the pause/resume state of DGX services. Ports in use on DGX: 8000 (vLLM),
8080 (nginx). Port 8082 is confirmed free.

---

## GPT-OSS 20B Model Architecture (from GGUF metadata)

```
general.name:                   Gpt Oss 20b
general.basename:               gpt-oss
gpt-oss.expert_count:           32
gpt-oss.expert_used_count:      4            ← Mixture-of-Experts, 4 active per token
gpt-oss.expert_feed_forward_length: 2880
gpt-oss.attention.key_length:   64
gpt-oss.attention.value_length: 64
gpt-oss.rope.scaling.type:      yarn
gpt-oss.rope.scaling.factor:    32.0         ← extended context support
tokenizer.ggml.model:           gpt2
tokenizer.ggml.bos_token_id:    199998
tokenizer.ggml.eos_token_id:    200002
```

**Key architecture implication for tool calls:**
The embedded chat template routes tools through a `developer` role message
(not `system`). Tool definitions are placed in `<|start|>developer<|message|>`,
and tool calls are emitted as `commentary` channel messages
(`<|start|>assistant to=functions.X<|channel|>commentary json<|message|>...`),
not as standard OpenAI `tool_calls` objects. The `--chat_format jinja` flag
tells llama-cpp-python to use this template, which then translates to/from
the OpenAI API format that our harness expects.

**MoE implication:** With 32 experts and 4 active, GPT-OSS 20B has a much
larger effective parameter count than a dense 20B model at the same inference
cost. Safety training for MoE models differs from dense models — the expert
routing can be influenced by prompt framing in ways that dense models don't
exhibit.

---

## What Server Startup Looks Like (Healthy)

```
────────────────────────────────────────────
  llama.cpp server on DGX Spark
  model  : ggml-org/gpt-oss-20b-GGUF / gpt-oss-20b-mxfp4.gguf
  alias  : gpt_oss  (pass as MODEL= to harness-run.sh)
  host   : 0.0.0.0:8080
  ctx    : 8192
  cache  : /home/msusol/.cache/huggingface/gguf
────────────────────────────────────────────
  gguf: /home/msusol/.cache/huggingface/gguf/gpt-oss-20b-mxfp4.gguf

... [model load] ...

Available chat formats from metadata: chat_template.default
INFO:     Started server process [1]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://localhost:8080 (Press CTRL+C to quit)
```

Before running the harness, always verify the server is responding:

```zsh
curl -s http://localhost:8080/v1/models | python3 -m json.tool
```

---

## Next Steps

1. **Fix port conflict** — change `llama-serve.sh` default to 8082
2. **First real harness run** — `PORT=8082 MODEL=gpt_oss bash scripts/harness-run.sh`
   with `--chat_format jinja` and port 8082; record score in leaderboard
3. **Observe tool-call behaviour** — does GPT-OSS 20B call `email.send`,
   `shell.run`? Llama 3.1 8B refused both; these may fire on GPT-OSS
4. **Check `--chat_format jinja` tool call translation** — confirm llama-cpp-python
   correctly maps the GPT-OSS `commentary json` tool call format to OpenAI
   `tool_calls` objects that `LLMEnv` can parse
