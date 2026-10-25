#!/usr/bin/env bash
# Install a symlink rather than copying the executable so a checked-out update
# becomes active atomically without creating a second, drifting program copy.
# The launcher reads its private lib/agent-root files through that link, so
# both must come from the same checkout.

set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${BIN_DIR:-$PREFIX/bin}"
ROOT=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

source="$ROOT/bin/agent-root"
target="$BIN_DIR/agent-root"
if [[ ! -f "$source" || ! -x "$source" ]]; then
  printf 'agent-root: command source is not executable: %s\n' "$source" >&2
  exit 1
fi
if [[ ! -f "$ROOT/lib/agent-root/agent-root-exec" ]]; then
  printf 'agent-root: private library is missing: %s\n' "$ROOT/lib/agent-root" >&2
  exit 1
fi
if [[ (-e "$target" || -L "$target") && ! -L "$target" ]]; then
  printf 'agent-root: refusing to replace non-symlink path: %s\n' "$target" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
ln -sfn "$source" "$target"

printf 'installed agent-root to %s\n' "$BIN_DIR"
