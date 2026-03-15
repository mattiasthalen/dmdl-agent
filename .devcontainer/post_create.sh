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
while read -r key_id; do
  gh api -X DELETE "/user/keys/$key_id"
done < <(gh api /user/keys --jq ".[] | select(.title == \"$KEY_TITLE\") | .id")

# Delete existing signing keys with matching title
while read -r key_id; do
  gh api -X DELETE "/user/ssh_signing_keys/$key_id"
done < <(gh api /user/ssh_signing_keys --jq ".[] | select(.title == \"$KEY_TITLE (signing)\") | .id")

# Add new keys to GitHub
gh ssh-key add ~/.ssh/id_ed25519.pub --type authentication --title "$KEY_TITLE"
gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title "$KEY_TITLE (signing)"

# Get user details from GitHub
name="$(gh api user -q .name)"
email="$(gh api user -q .email)"

# Validate name and email
if [[ "$name" == "null" || -z "$name" ]]; then
  echo "Error: GitHub name is not set. Set a name at https://github.com/settings/profile" >&2
  exit 1
fi

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
