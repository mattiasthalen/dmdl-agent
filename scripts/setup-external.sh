#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCKFILE="$ROOT_DIR/external.lock"
EXTERNAL_DIR="$ROOT_DIR/external"

if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Install it with your package manager."
  exit 1
fi

if [ ! -f "$LOCKFILE" ]; then
  echo "Error: $LOCKFILE not found."
  exit 1
fi

mkdir -p "$EXTERNAL_DIR"

repo_count=$(jq '.repos | length' "$LOCKFILE")

for i in $(seq 0 $((repo_count - 1))); do
  name=$(jq -r ".repos[$i].name" "$LOCKFILE")
  url=$(jq -r ".repos[$i].url" "$LOCKFILE")
  commit=$(jq -r ".repos[$i].commit" "$LOCKFILE")
  target="$EXTERNAL_DIR/$name"

  echo "--- $name ---"

  if [ -d "$target/.git" ]; then
    echo "Fetching updates..."
    git -C "$target" fetch --quiet
  else
    echo "Cloning..."
    git clone --no-recurse-submodules --quiet "$url" "$target"
  fi

  echo "Checking out $commit..."
  git -C "$target" checkout --quiet "$commit"

  actual=$(git -C "$target" rev-parse HEAD)
  echo "Pinned at: $actual"
  echo ""
done

echo "All external repos are set up."
