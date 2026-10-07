# Intent Interview Patterns

Condensed patterns embedded in `/problem` (`business-problem-identification`). Source: [references/agent-skills-main/skills/interview-me](../agent-skills-main/skills/interview-me/SKILL.md).

**Do not** persist intent to `docs/intent/` — confirmed intent flows into `nwob-docs/sdd/epic-spec.md` Problem/Context and Metrics.

---

## When Phase 0 applies

Run before standard problem analysis when:

- Ask is missing **who**, **why**, **success**, or binding **constraint**
- Request is conventional ("build me X", "make it faster") without specifics
- Problem is framed as a feature request ("we need a dashboard")
- User invokes: "interview me", "grill me", "are we sure?", "stress-test my thinking"

**Skip Phase 0** when ask is unambiguous or confidence is ≥95% with defensible evidence.

**Non-interactive contexts** (CI, `/loop`): flag blocker; do not guess.

---

## Phase 0 process

### 1. Hypothesize with confidence

```
HYPOTHESIS: <one sentence>
CONFIDENCE: ~N% — <reason if below 70%: what's missing>
```

### 2. One question at a time + GUESS

```
Q: <one focused question>
GUESS: <hypothesis for the answer>
```

Wait for reaction before the next question. No batching.

### 3. Want vs. should-want probe

When answers sound like best-practice talk or convention:

> *"If you didn't have to justify this to anyone, what would you actually want?"*

### 4. Restate intent

```
- Outcome:      <one line>
- User:         <who benefits>
- Why now:      <what changed>
- Success:      <how we know it worked>
- Constraint:   <binding limit>
- Out of scope: <explicit non-goals>
```

### 5. Explicit yes gate

Accept only explicit "yes." Reject: "whatever you think", "sounds good", "sure let's go."

### Stop condition

Can you predict the user's reaction to the next three questions? If yes → proceed to standard `/problem` steps (5 Whys, quantify impact, write `epic-spec.md`).

---

## Feature-request reframing

| User says | Probe |
|-----------|-------|
| "We need a dashboard" | What decision or question does the dashboard answer? |
| "Make it faster" | What number defines fast enough? For whom? |
| "Add AI to X" | What outcome does AI enable that rules-based logic cannot? |

---

## Verification (Phase 0)

- [ ] Hypothesis + confidence stated before questions
- [ ] Questions one-at-a-time with GUESS attached
- [ ] Want-vs-should-want probe used when needed
- [ ] Restate includes Out of scope
- [ ] Explicit yes before writing `epic-spec.md`
