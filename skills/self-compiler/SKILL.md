---
name: self-compiler
description: Analyse accumulated feedback memories (L2) and propose updates to CLAUDE.md and USER.md. Invoke when operator says "recompile yourself", "update your rules", "update your behavior", or when many feedback memories have piled up.
---

# self-compiler

Read L2 feedback memories + CLAUDE.md + USER.md, distill repeating patterns into
rule updates, and **propose** the diff. Never silently apply.

## When to use

- Operator says "recompile yourself", "update your rules", "fix your behavior".
- 5+ feedback memories in `~/.claude/projects/-home-claude/memory/` (files with `type: feedback`).
- A recurring correction keeps appearing across sessions.

## Workflow

1. **Collect** — read all files in `~/.claude/projects/-home-claude/memory/` whose frontmatter has `type: feedback`. List them.
2. **Cluster** — group by topic (e.g., response style, safety, tool usage, code comments).
3. **Promote** — for each cluster with 2+ entries, draft a concrete rule in imperative form.
4. **Diff** — show proposed changes to CLAUDE.md (Operational Rules section) and/or USER.md.
5. **Confirm** — wait for operator approval before writing.
6. **Apply** — only after explicit "yes, apply" or "go ahead" — edit the files.

## Rules

- NEVER edit CLAUDE.md or USER.md without explicit confirmation.
- One rule per cluster — short, imperative, actionable.
- Preserve existing rules unless they contradict a promoted pattern.
- Show a unified diff before applying.
- After applying: save a project memory noting what was updated and why.

## Output format

```
## self-compiler report

Feedback memories analysed: N
Clusters identified: M

### Proposed changes to CLAUDE.md

--- CLAUDE.md (before)
+++ CLAUDE.md (after)
@@ -42,6 +42 @@
 ...existing rule...
+**New rule:** ...

### No changes to USER.md

Proceed? (yes / no / edit)
```
