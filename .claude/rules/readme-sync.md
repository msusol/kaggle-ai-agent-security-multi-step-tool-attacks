# README.md synchronization

Update both `README.md` and `jed-redteam-attack/README.md` whenever any of
the following change:

| Change | README section to update |
|---|---|
| `attack.py` algorithm structure or phase order | Architecture overview / algorithm table |
| New or renamed algorithm in `algorithms/` | Algorithm descriptions |
| `local_harness.py` CLI flags or output format | Local testing / workflow section |
| `vllm-serve.sh` usage or port | DGX Spark / Phase 3 setup commands |
| `Dockerfile` or `docker-compose.yml` targets/profiles | Docker workflow section |
| `Makefile` targets added or removed | Commands section |
| `payloads/library.py` seed count or structure changes | Payload library description |
| Scoring formula or predicate weights change | Competition Scoring section |
| `requirements-dev.txt` or `requirements-llm.txt` change | Setup / requirements notes |

## What to keep accurate

- **Project structure block** — every file listed must exist; remove entries
  for deleted files.
- **Commands** — instructions must match actual script/Makefile behavior.
- **Scoring table** — predicate weights and formula must match `aicomp_sdk/__init__.py`.

## What not to add

- Do not document internal functions or class APIs — README covers usage.
- Do not add implementation detail that belongs in `docs/plans/*.md`.
- Do not create a new README section for every minor change; batch related
  changes into one update.

## Sync both files

`README.md` (repo root) and `jed-redteam-attack/README.md` are identical in
content. Keep them in sync — any change to one must be mirrored in the other.
