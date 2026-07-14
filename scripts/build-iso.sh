#!/usr/bin/env bash
# Build the Sovox Server installer ISO.
set -euo pipefail

cd "$(dirname "$0")/.."

out=$(nix build .#iso --no-link --print-out-paths "$@")
echo "ISO: $out"
ls -lh "$out"/iso/*.iso
