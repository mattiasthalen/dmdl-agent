# Git Workflow

- NEVER commit directly to main.
- NEVER use non-conventional commit formats. See .claude/rules/conventional-commits.md
- NEVER leave commits unpushed.
- NEVER use raw git for remote operations when a CLI is available for the remote platform (e.g., `gh` for GitHub, `az repos` for Azure DevOps).
- NEVER rely on global git email. Before committing, check `git config --local user.email`. If not set, prompt the user.
- NEVER open PRs as ready. Always open as draft (e.g., `gh pr create --draft`).
- NEVER enable auto-merge on draft PRs. Enable auto-merge only after the PR is marked as ready (e.g., `gh pr ready` then `gh pr merge --auto --merge`).
- NEVER enable auto-merge on PRs from external contributors. Only repo admins/owners may use auto-merge.
- NEVER use squash or rebase merges. Always use regular merge commits (`--merge`).
