# Ideation Frameworks

Reference for `/ideate` (`product-ideation`). Adapted from [idea-refine](../agent-skills-main/skills/idea-refine/) `frameworks.md` and `refinement-criteria.md`.

**Output target:** `nwob-docs/sdd/epic-spec.md` ## Solutions — not `docs/ideas/` one-pagers.

Pick lenses selectively; do not run every framework mechanically.

---

## Divergent lenses (Phase 1)

### How Might We (HMW)

Reframe as: "How might we [outcome] for [user] without [constraint]?"

- Good: actionable, contains tension, not solution-embedded
- Bad: too broad ("make users happy"), too narrow ("add a button")

### Variation generators

Generate 5–8 variations using:

- **Inversion** — opposite of the obvious approach
- **Audience shift** — different persona or segment
- **Constraint removal** — what if budget/time/tech were unlimited or halved
- **SCAMPER** — Substitute, Combine, Adapt, Modify, Eliminate, Reverse
- **JTBD** — "When I [situation], I want to [motivation], so I can [outcome]"

See SCAMPER and JTBD detail in source [frameworks.md](../agent-skills-main/skills/idea-refine/frameworks.md).

---

## Convergent evaluation (Phase 2)

### Painkiller vs. vitamin

| Painkiller | Vitamin |
|------------|---------|
| Acute, frequent problem | Nice to have |
| Users built workarounds | "That's cool" — no behavior change |
| Users will switch | Users won't seek it out |

### Feasibility + differentiation matrix

| | High feasibility | Low feasibility |
|--|------------------|-----------------|
| **High value** | Do first | Worth the risk |
| **Low value** | Only if trivial | Don't do |

Use differentiation as tiebreaker within the same quadrant.

### Pre-mortem

Imagine the solution shipped and flopped in 12 months. List failure modes; flag which are preventable vs. dealbreakers.

---

## Assumption audit (per hypothesis)

| Category | Meaning |
|----------|---------|
| **Must be true** | Wrong → kills the idea; validate before build |
| **Should be true** | Wrong → adjust approach; core may survive |
| **Might be true** | Secondary; validate after core proven |

---

## `epic-spec.md` Solutions template

Each approved hypothesis in `## Solutions`:

```markdown
### Hypothesis: <name>

We believe building [Solution] for [Persona] achieves [Outcome]. Success is [Metric].

**Key assumptions**
- Must be true: ...
- Should be true: ...
- Might be true: ...

**Not doing**
- ...
- ...

**Validation:** <prototype, painted-door, or other minimal test>
```

---

## MVP scoping principles

1. **One job, done well** — one user job per MVP slice
2. **Riskiest assumption first** — MVP tests what is most likely wrong
3. **Time-box, not feature-list** — scope by timeframe, not wish list
4. **Not Doing list is mandatory** — explicit cuts prevent scope creep
5. **If not embarrassing, you waited too long** — first version should feel incomplete to the builder
