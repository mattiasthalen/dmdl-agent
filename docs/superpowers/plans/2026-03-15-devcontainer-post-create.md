# Devcontainer Post-Create Script Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a post-create script that automates GitHub SSH auth and git commit signing setup in the devcontainer.

**Architecture:** Single shell script (`.devcontainer/post_create.sh`) triggered by `postCreateCommand` in `devcontainer.json`. No libraries or dependencies beyond `gh` CLI and `ssh-keygen`.

**Tech Stack:** Bash, GitHub CLI (`gh`), OpenSSH (`ssh-keygen`)

---

## Chunk 1: Implementation

### Task 1: Create post_create.sh

**Files:**
- Create: `.devcontainer/post_create.sh`

- [ ] **Step 1: Create the script**

```bash
#!/bin/bash
set -euo pipefail

# Ensure ~/.ssh directory exists
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# Authenticate with GitHub
gh auth login -p ssh -s admin:ssh_signing_key --skip-ssh-key

# Generate SSH keypair (overwrite existing without prompt)
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 <<< y > /dev/null

# Derive key title from repo directory name
KEY_TITLE="$(basename "$PWD")"

# Delete existing authentication keys with matching title
gh api /user/keys --jq ".[] | select(.title == \"$KEY_TITLE\") | .id" | \
  while read -r key_id; do
    gh api -X DELETE "/user/keys/$key_id"
  done

# Delete existing signing keys with matching title
gh api /user/ssh_signing_keys --jq ".[] | select(.title == \"$KEY_TITLE (signing)\") | .id" | \
  while read -r key_id; do
    gh api -X DELETE "/user/ssh_signing_keys/$key_id"
  done

# Add new keys to GitHub
gh ssh-key add ~/.ssh/id_ed25519.pub --type authentication --title "$KEY_TITLE"
gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "$KEY_TITLE (signing)"

# Get user details from GitHub
name="$(gh api user -q .name)"
email="$(gh api user -q .email)"

# Validate email is not null (private email setting)
if [[ "$email" == "null" || -z "$email" ]]; then
  echo "Error: GitHub email is not public. Set a public email at https://github.com/settings/profile" >&2
  exit 1
fi

# Configure git identity and signing
git config --global user.name "$name"
git config --global user.email "$email"
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# Set up allowed signers for verification
echo "$email $(cat ~/.ssh/id_ed25519.pub)" > ~/.ssh/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
```

- [ ] **Step 2: Make the script executable**

Run: `chmod +x .devcontainer/post_create.sh`

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/post_create.sh
git commit -m "feat: add devcontainer post-create script for GitHub SSH auth and signing"
```

### Task 2: Wire into devcontainer.json

**Files:**
- Modify: `.devcontainer/devcontainer.json`

- [ ] **Step 1: Add postCreateCommand**

Add `"postCreateCommand": ".devcontainer/post_create.sh"` to the top-level object in `devcontainer.json`.

The result should be:

```json
{
	"name": "daana-modeler",
	"image": "mcr.microsoft.com/devcontainers/base:noble",
	"features": {
		"ghcr.io/devcontainers/features/github-cli:1": {},
		"ghcr.io/stu-bell/devcontainer-features/claude-code:0": {}
	},
	"postCreateCommand": ".devcontainer/post_create.sh",
	"customizations": {
		"vscode": {
			"extensions": [
				"anthropic.claude-code",
				"eamodio.gitlens"
			],
			"settings": {
				"claudeCode.allowDangerouslySkipPermissions": true,
				"claudeCode.initialPermissionMode": "bypassPermissions",
				"claudeCode.preferredLocation": "panel",
				"claudeCode.respectGitIgnore": false,
				"claudeCode.useTerminal": false
			}
		}
	}
}
```

- [ ] **Step 2: Commit**

```bash
git add .devcontainer/devcontainer.json
git commit -m "feat: wire post_create.sh into devcontainer.json"
```
