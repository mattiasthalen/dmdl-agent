# Devcontainer Post-Create Script

## Overview

Create `.devcontainer/post_create.sh` to automate GitHub authentication and git commit signing setup when the devcontainer is created. Wire it into `devcontainer.json` via `postCreateCommand`.

## Motivation

VS Code's GitHub auth forwarding doesn't work well with `gh` CLI and SSH signing. The script handles interactive authentication inside the container and sets up SSH-based commit signing end-to-end.

## Design

### Location

- Script: `.devcontainer/post_create.sh`
- Trigger: `"postCreateCommand": ".devcontainer/post_create.sh"` in `devcontainer.json`

### Script Flow

1. **Ensure `~/.ssh` exists** — `mkdir -p ~/.ssh && chmod 700 ~/.ssh`.

2. **Authenticate with GitHub** — `gh auth login -p ssh -s admin:ssh_signing_key --skip-ssh-key`. Interactive browser-based auth; no key import since we generate our own.

3. **Generate SSH keypair** — `ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 <<< y` to overwrite any existing key without interactive prompt.

4. **Delete existing GitHub SSH keys with matching titles** — Query `gh api /user/keys` for authentication keys and `gh api /user/ssh_signing_keys` for signing keys. Filter by titles matching `"$(basename "$PWD")"` and `"$(basename "$PWD") (signing)"`. Extract the `id` field from matches and delete via `gh api -X DELETE /user/keys/{id}` and `gh api -X DELETE /user/ssh_signing_keys/{id}` respectively.

5. **Add SSH keys to GitHub** — `gh ssh-key add` the public key as both authentication and signing types.

6. **Configure git globally** — Store `user.name` and `user.email` from `gh api user -q .name` / `.email` into variables. Validate email is not `null` before proceeding (`[[ "$email" != "null" && -n "$email" ]]`). Configure SSH signing format, signing key path, and enable commit + tag signing.

7. **Set up allowed signers** — Write email + public key to `~/.ssh/allowed_signers` and point git at it via `gpg.ssh.allowedSignersFile`.

### Error Handling

- `set -euo pipefail` — fail fast on any error.
- Explicit null check on email — `gh api user -q .email` returns the string `null` (exit code 0) when the user has no public email. The script checks for this and exits with an error message.
- No fallbacks. If `gh auth` fails or email is null, the script fails and the user addresses it manually.

### Idempotency

Safe to re-run on container rebuilds. Existing SSH keys on GitHub with matching titles are deleted before new ones are added. Local keypair is overwritten.

### Known Limitations

- Key titles use `$(basename "$PWD")` (the repo directory name). If a user has multiple devcontainers for repos with the same directory name, keys would collide.

### `devcontainer.json` Change

Add `"postCreateCommand": ".devcontainer/post_create.sh"` to the existing configuration.
