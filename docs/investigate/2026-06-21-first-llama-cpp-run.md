# First llama.cpp / GPT-OSS 20B Run — DGX Spark

**Date:** 2026-06-21  
**Model:** `unsloth/gpt-oss-20b-GGUF` → `gpt-oss-20b-Q4_K_M.gguf` (~9 GB)  
**Final server:** `jed-llama:latest` (llama-server C++ binary, CUDA SM 90/100/120)  
**Logs:** `harness_20260621_120237.log` (Attempt 1 — nginx 404),
`harness_20260621_120740.log` (Attempt 2 — connection error),
`harness_20260621_121258.log` (Attempt 3 — connection error, port 8082 but server on 8080),
`harness_20260621_121729.log` (Attempt 4 — connection error, missing `--host 0.0.0.0`),
`harness_20260621_122158.log` (Attempt 5 — 500 error, `jinja` not a valid named format),
`harness_20260621_122414.log` (Attempt 6 — `!!!` garbage, Python server missing `--jinja`),
`harness_20260621_123518.log` (Attempt 7 — running cleanly with llama-server C++ + `--jinja`)

---

## Summary

Seven harness attempts across one session. None of the failures were model
behaviour — all were infrastructure bugs discovered during first bring-up of
the `jed-llama` stack. Attempt 7 (12:35) is the first clean run: connected,
responses received, no errors. Score pending completion of the 300s budget.

---

## Bugs Found and Fixed (chronological)

### Bug 1: `huggingface-cli` deprecated

`huggingface_hub >= 1.20.0` renamed the CLI from `huggingface-cli` to `hf`.
The old command printed a deprecation notice and exited without downloading,
so the GGUF was never saved and the `[[ -f ]]` guard in `llama-serve.sh`
caused the script to exit silently.

**Fix:** `scripts/llama-serve.sh` now prefers `hf download` (system-level)
and falls back to `${VENV}/bin/huggingface-cli` for older installs.
Both Dockerfiles pinned to `huggingface_hub>=1.20.0`.

---

### Bug 2: `--chat_format chatml` overrides the embedded GGUF template

We initially passed `--chat_format chatml`, which forces ChatML tokens
(`<|im_start|>` / `<|im_end|>`) regardless of what the model was trained on.
GPT-OSS 20B's GGUF contains a baked-in Jinja2 template (`chat_template.default`)
with a completely different token scheme:

```
<|start|>system<|message|>....<|end|>
<|start|>developer<|message|>....<|end|>   ← tool schema injected here
<|start|>user<|message|>....<|end|>
<|start|>assistant<|channel|>final<|message|>....<|end|>
<|start|>assistant to=functions.X<|channel|>commentary json<|message|>....<|call|>
<|start|>functions.X to=assistant<|channel|>commentary<|message|>....<|end|>
```

**Fix attempted:** Changed to `--chat_format jinja` — but `jinja` is not a
valid named format in this version of llama-cpp-python (see Bug 5). Resolved
differently — see Bug 6.

---

### Bug 3: Port 8080 conflict with DGX nginx / VSCode port forwarding

The DGX Spark runs an nginx reverse proxy on port 8080. VS Code's SSH tunnel
also auto-forwards common ports including 8080. When Docker tried to bind
`-p 8080:8080`:

| Attempt | What happened |
|---|---|
| 12:02 | Docker bind failed silently; requests hit nginx → `404 Not Found (nginx/1.28.3)` |
| 12:07 | nginx paused by `make pause`; Docker bind succeeded but server mid-init → `Connection error` |

**Fix:** Changed default port in `llama-serve.sh` from 8080 to 8082. VS Code
does not auto-forward 8082; nginx does not use it. Ports in use on DGX:
8000 (vLLM), 8080 (nginx/VS Code tunnel).

---

### Bug 4: Harness pointed at 8082 but server still running on 8080

After pushing the port change, the running server was still on 8080 (started
before the git pull). Running `PORT=8082 bash scripts/harness-run.sh` against
a non-existent port → `Connection error`.

**Fix:** Restart the server after `git pull` to pick up the new default.
Diagnosis: `curl -s http://localhost:8080/v1/models` vs `curl -s http://localhost:8082/v1/models`.

---

### Bug 5: `--host` missing — server bound to container loopback only

`python -m llama_cpp.server` defaults to `--host localhost` (127.0.0.1) inside
the Docker container. Docker's `-p 8082:8082` port mapping routes host:8082
to the container's eth0:8082, not its loopback. So:

```
harness (--network=host) → host 127.0.0.1:8082
                         → Docker NAT → container eth0:8082
                         → server only listening on container 127.0.0.1:8082
                         → Connection refused
```

Compare with `vllm-serve.sh` which explicitly passes `--host 0.0.0.0` —
the same flag was missing from the llama command.

**Fix:** Added `--host 0.0.0.0` to the `python -m llama_cpp.server` invocation.

---

### Bug 6: `--chat_format jinja` not a valid named format

Once connectivity was fixed (Attempt 5, 12:22), requests got HTTP 500:

```
"Invalid chat handler: jinja (valid formats: ['llama-2', 'llama-3', 'alpaca',
'qwen', 'vicuna', 'chatml', 'functionary', 'functionary-v2', ...])"
```

`jinja` is not in the named-format list for this version of llama-cpp-python.
Removing `--chat_format` entirely triggers auto-detection from GGUF metadata,
which loaded `chat_template.default` successfully — server startup confirmed:
`Available chat formats from metadata: chat_template.default`.

**Fix:** Removed `--chat_format` entirely from the Python server command.

---

### Bug 7: `python -m llama_cpp.server` cannot inject tools via embedded Jinja2 template

Attempt 6 (12:24) was connected and received responses, but the model output
was a stream of `!` characters:

```
[llm] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!...
```

Performance stats from the llama-server log confirmed the model ran at
75 tokens/second and generated 511 tokens — the model was responding, but
with garbage. Root cause:

The auto-detected template is used by `python -m llama_cpp.server` for
**message formatting**, but the server does NOT call the template's
`render_tool_namespace` macro when injecting tools. The model received
prompts with no tool definitions → couldn't make tool calls → generated
degenerate repetitive output.

The Kaggle evaluator uses `llama-server` (C++ binary) with `--jinja`. The
`--jinja` flag enables full Jinja2 evaluation including all macros, so tool
schemas are correctly injected into `<|start|>developer<|message|>`.

**Fix:** Rebuilt `Dockerfile.llama` to compile `llama-server` from the
llama.cpp C++ source (with CUDA SM 90/100/120). `llama-serve.sh` now runs:

```bash
llama-server \
    --model "/models/${HF_FILE}" \
    --alias "${MODEL_ALIAS}" \
    --host 0.0.0.0 \
    --port "${PORT}" \
    --ctx-size "${NCTX}" \
    --n-gpu-layers -1 \
    --jinja
```

Note: C++ flag names use dashes (`--n-gpu-layers`, `--ctx-size`, `--alias`),
not underscores as the Python wrapper uses.

Also added `REBUILD=1` flag to `llama-serve.sh` so a forced image rebuild
requires only one command:

```zsh
MODEL=gpt-oss REBUILD=1 bash scripts/llama-serve.sh
```

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
chat eos_token:                 <|return|>
chat bos_token:                 <|startoftext|>
```

**MoE implication:** 32 experts / 4 active per token. Safety training for MoE
models can differ from dense models — expert routing is influenced by prompt
framing, which is relevant for prompt injection attacks.

**Tool call routing:** Tools are injected into the `developer` role (not
`system`), and tool calls are emitted on the `commentary` channel. The C++
`llama-server` translates these to/from the OpenAI `tool_calls` format that
`LLMEnv` expects when `--jinja` is active.

---

## What Healthy Server Startup Looks Like (llama-server C++ binary)

```
────────────────────────────────────────────
  llama.cpp server on DGX Spark
  model  : unsloth/gpt-oss-20b-GGUF / gpt-oss-20b-Q4_K_M.gguf
  alias  : gpt_oss  (pass as MODEL= to harness-run.sh)
  host   : 0.0.0.0:8082
  ctx    : 8192
  cache  : /home/msusol/.cache/huggingface/gguf
────────────────────────────────────────────
  gguf: ...gpt-oss-20b-Q4_K_M.gguf (9G)

... [GGUF metadata + model load to GPU] ...

llama server listening at http://0.0.0.0:8082
```

Key differences from the Python server (uvicorn):
- No `Uvicorn running on ...` — look for `llama server listening at`
- `http://0.0.0.0:8082` confirms all-interface binding

Verify before running harness:

```zsh
curl -s http://localhost:8082/v1/models | python3 -m json.tool
```

---

## Bug 8: `--jinja` PEG parser rejects GPT-OSS tool call output

**Attempt 7** (`harness_20260621_123518.log`) — first clean connection with
`llama-server --jinja`. Most seeds produced blank lines (model responded
in text, no tool calls). Two seeds triggered:

```
Error code: 500 - {'error': {'message':
  'The model produced output that does not match the expected peg-native format',
  'type': 'server_error'}}
```

**What this means:** GPT-OSS **did** attempt tool calls (it generated
`<|call|>` tokens — confirmed progress). With `--jinja`, `llama-server`
intercepts ALL `<|call|>` tokens in the output stream and tries to parse
them through an internal PEG grammar. The parse failed.

**Score: 0.0** — PEG errors surface as 500s that `LLMEnv` catches as API errors;
the tool call is not returned to the harness.

**Root cause:** llama.cpp's PEG parser is incompatible with GPT-OSS's output
format for tool calls, regardless of quantization (MXFP4 or Q4_K_M). Even with
proper `tools=` injection enabling `render_tool_namespace`, the model's output
does not match the expected peg-native format.

**Attempted fixes (all failed):**
1. `--reasoning off` — disables thinking tokens (confirmed working)
2. Removing `--jinja` — bypasses PEG parser (model then produces garbled text)
3. Switching to unsloth Q4_K_M quantization — basic text works but PEG still fails

**Current status:** GPT-OSS GGUF + llama.cpp PEG parser = fundamentally incompatible
for tool calling on GB10. See `2026-06-21-first-dgx-llm-run.md` for working
alternatives.

---

## Bug 9: `LLMEnv` never sends `tools=` — `render_tool_namespace` never fires

**Root cause confirmed (Attempt 8 / `harness_20260621_123518.log`):**

`LLMEnv._llm_call()` called `chat.completions.create(model=..., messages=...,
temperature=0, max_tokens=512)` — no `tools=` parameter. With `--jinja` active,
llama-server evaluates the Jinja2 template for every request. The template only
injects the `# Tools` JSON section when `tools` is truthy:

```jinja2
{%- if tools -%}
    {{- "# Tools\n\n" }}
    {{- render_tool_namespace("functions", tools) }}
{%- endif -%}
```

Because `tools=None`, `render_tool_namespace` was never called. GPT-OSS received
the developer message with our plain-English `TOOL_SCHEMA` but no structured `#
Tools` JSON section. Without the JSON schema it was trained to call, the model
fell into degenerate repetition — 512 `?` tokens — across all Attempts 7 and 8.

**Fix:** `LLMEnv` now detects competition models (`gpt_oss`, `gemma`) and
sends `tools=COMPETITION_TOOLS` in tools-API mode:

```python
# In llm_env.py
_COMPETITION_MODELS = {"gpt_oss", "gemma"}

class LLMEnv:
    def __init__(self, ...):
        self._use_tools_api = model in _COMPETITION_MODELS

    def _llm_call(self, messages):
        kwargs = dict(model=..., messages=messages, temperature=0, max_tokens=512)
        if self._use_tools_api:
            kwargs["tools"] = COMPETITION_TOOLS   # ← triggers render_tool_namespace
            kwargs["tool_choice"] = "auto"
        resp = self._client.chat.completions.create(**kwargs)
        tool_calls = resp.choices[0].message.tool_calls or []
        content    = resp.choices[0].message.content or ""
        return content, tool_calls
```

`COMPETITION_TOOLS` uses underscore names (`fs_read`, `http_post`) as required
by the OpenAI spec. `render_tool_namespace("functions", tools)` then injects
them into GPT-OSS's developer message as `functions.fs_read`, `functions.http_post`,
etc. — the exact namespace format the model was trained to call.

`interact()` now handles both code paths:
- **tool_calls response** (competition models): maps `"functions.fs_read"` →
  `"fs.read"` via `.removeprefix("functions.").replace("_", ".", 1)`, appends
  `{"role": "tool", "tool_call_id": tc.id, ...}` results.
- **text content response** (all other models): existing JSON parse path unchanged.

**No server restart needed** — `--jinja` stays in `llama-serve.sh`; the fix is
purely in `LLMEnv`.

**Attempt 9:** stop current harness run; rebuild wheel; re-run:

```zsh
# Rebuild wheel (llm_env.py changed)
cd jed-redteam-attack
source ~/LosusAI/Projects/Kaggle/.venv/bin/activate
python -m build --wheel --outdir .

# New harness run — same llama-server, updated LLMEnv
PORT=8082 MODEL=gpt_oss bash scripts/harness-run.sh
```

Expected: GPT-OSS sees the `# Tools` JSON section → emits `<|call|>` tokens in
correct format → PEG parser succeeds → `tool_calls` returned → first non-zero score.

---

## Next Steps

1. **Run Attempt 9** with updated `llm_env.py` (`tools=` fix) — expect first
   non-zero score from GPT-OSS 20B
2. **Record score in leaderboard** when first non-zero result is achieved
3. **Run Gemma 4 26B** once GPT-OSS pipeline confirmed (`MODEL=gemma bash scripts/llama-serve.sh`)
4. **Push to Kaggle** once DGX scores confirm algorithm effectiveness
5. **Run at 900s** once tool-call patterns confirmed