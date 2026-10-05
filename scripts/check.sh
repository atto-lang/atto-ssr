#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for example in "$root"/examples/*.ores; do
  echo "==> oreslang check ${example#$root/}"
  oreslang check "$example"
done
