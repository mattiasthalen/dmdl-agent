# Superpowers

- NEVER store plans and design specs in `docs/plans/`. Store plans in `docs/superpowers/plans/` and design specs in `docs/superpowers/specs/`.
- NEVER default plans to sequential execution. Optimize for parallelization.
- NEVER dispatch parallel subagents into the same worktree — they will conflict on git operations.
- NEVER use `isolation: "worktree"` when the parent is on a non-main branch — it branches from main, not the parent branch. Create worktrees manually from the current branch (via `using-git-worktrees`) instead.
- NEVER write plans, specs, or implementation files before setting up an isolated worktree.
- NEVER finish brainstorming without logging design decisions (approach chosen, alternatives rejected) to the feature's `*-adr.md` file in `docs/superpowers/adr/`.
- NEVER make an implementation decision between competing alternatives (libraries, patterns, architectures) without logging it to the feature's `*-adr.md` file in `docs/superpowers/adr/`.
