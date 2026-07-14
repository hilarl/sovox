#!/usr/bin/env bash
# Reproducibility gate: two independent builds of the same flake rev must be
# closure-identical. Locally this builds into two throwaway stores; in CI the
# same comparison runs across two separate runners (.github/workflows/ci.yml).
set -euo pipefail

cd "$(dirname "$0")/.."

attr=".#nixosConfigurations.server-example.config.system.build.toplevel"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

hash_for_store() {
  local store=$1
  nix build "$attr" --store "$store" --no-link --print-out-paths >/dev/null
  local out
  out=$(nix eval --raw "$attr")
  nix path-info --store "$store" --json "$out" | nix run nixpkgs#jq -- -r 'if type == "object" then to_entries[].value.narHash else .[].narHash end'
}

echo "building twice into independent stores (this is deliberately slow)..."
h1=$(hash_for_store "$work/store-1")
h2=$(hash_for_store "$work/store-2")

echo "build 1: $h1"
echo "build 2: $h2"

if [ "$h1" != "$h2" ]; then
  echo "REPRO-CHECK FAILED: closure hashes differ — builds are not reproducible" >&2
  exit 1
fi
echo "repro-check OK: closure-identical builds"
