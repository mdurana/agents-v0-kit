# Service Map

> Maps logical services (C4 containers) to code repositories under `repositories/`.
>
> **Owners:** `/services` (boundaries, rows); `/contracts` (OpenAPI paths, catalogue).
> **Brownfield:** populate **Existing services** before `/services`; run `nwob doctor` if `repositories/` is missing.

## Code root

All application codebases live under `repositories/` at project root (git submodules).

## OpenAPI path convention

Fixed subpath inside each service repo (written by `/contracts`):

```
repositories/{service-name}/src/main/resources/swagger/{spec-file}.yaml
```

## Services

| Logical service | Repository path | Type | Git remote | OpenAPI / contract | Sequence diagram | Component plan | Status |
|-----------------|-----------------|------|------------|-------------------|------------------|----------------|--------|
| _example-service_ | `repositories/example-service/` | backend | | `repositories/example-service/src/main/resources/swagger/example-service-api.yaml` | `nwob-docs/diagrams/sequences/example-service.md` | `nwob-docs/sdd/components/example-service-plan.md` | planned |

**Type:** `backend` | `frontend` | `bff` | `infra`

**Status:** `active` | `planned` | `deprecated`

## Brownfield checklist

1. Run `nwob doctor` to ensure `repositories/` and this file exist.
2. Add submodules: `git submodule add <url> repositories/{service-name}`
3. Add one table row per service; set **Status** to `active` when submodule is initialized.
4. Invoke `/services` to align C4 containers and sequence diagrams.
5. Invoke `/contracts` to write OpenAPI specs to the swagger subpath.

## Notes

<!-- Optional: legacy migration notes, shared libraries, infra-only repos -->
