# Repositories workspace

Git workspace for service codebases in this NWOB engagement. Cloned service trees under `repositories/` are **not committed** to this project (see the managed block in `.gitignore`); only `README.md` and `.gitkeep` are tracked here.

## Purpose

Each logical service (C4 container) maps to one subdirectory under `repositories/`:

```
repositories/{service-name}/
```

Register every service in [`nwob-docs/architecture/service-map.md`](../nwob-docs/architecture/service-map.md).

## Add a service (clone)

```bash
git clone <remote-url> repositories/{service-name}
```

Example:

```bash
git clone git@github.com:org/order-service.git repositories/order-service
```

Register the path and remote in `service-map.md`. Re-run `nwob init` or `nwob doctor` if `.gitignore` is missing the managed `repositories/` block.

## OpenAPI contracts

Solution Architect `/contracts` writes OpenAPI 3.0 specs to:

```
repositories/{service-name}/src/main/resources/swagger/
```

Record the exact file path in the **OpenAPI / contract** column of `service-map.md`.

## Rules

- Clone path must match **Repository path** in `service-map.md`.
- Use kebab-case service names (e.g. `order-service`, `payment-service`).
- Do not commit secrets or cloned service code into this engagement repo.
- Greenfield: `/contracts` may create the directory tree before the clone is added.
