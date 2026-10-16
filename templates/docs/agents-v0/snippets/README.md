# Design snippet packs (token-efficient fill-ins)

Copy these into a feature Design tree and replace `<placeholders>`. Prefer them over inventing structure from scratch (`contract-first-design`, `ux-design`).

| Snippet | Use when |
|---------|----------|
| `openapi-resource-crud.yaml` → `docs/agents-v0/design/<feature>/openapi.yaml` | Feature adds list/create/get/update/delete for one resource under `/api/v1` |
| `adr-sync-vs-async.md` → `docs/agents-v0/adr/<NN>-sync-vs-async.md` | Choosing sync HTTP vs async messaging between services |
| `ux-spec-one-screen.md` → `docs/agents-v0/design/<feature>/ux-spec.md` | UI story with a single primary screen (still add mockups per state) |

Still run `sh .agents-v0/ci/check-design.sh`, `sh .agents-v0/ci/check-openapi.sh`, and `sh .agents-v0/ci/check-ux-spec.sh`. Snippets do not waive gates.
