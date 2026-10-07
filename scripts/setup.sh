#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
revision="$(tr -d '[:space:]' < "$root/compiler.lock")"
expected_tree="$(tr -d '[:space:]' < "$root/compiler-tree.txt")"
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ || ! "$expected_tree" =~ ^[0-9a-f]{40}$ ]]; then
  echo "compiler revision and tree must be full Git SHAs" >&2
  exit 65
fi
source_dir="$root/.work/compiler"
mkdir -p "$root/.work"
if [[ ! -e "$source_dir" ]]; then
  git clone --depth 1 --single-branch --branch "compiler-mirror/$revision" \
    https://github.com/ores-truffle-oreslang/oreslang-ssr.git "$source_dir"
fi
if [[ "$(git -C "$source_dir" rev-parse --show-toplevel)" != "$(cd "$source_dir" && pwd -P)" ]]; then
  echo "compiler path must be its own Git checkout" >&2
  exit 65
fi
if [[ "$(git -C "$source_dir" rev-parse 'HEAD^{tree}')" != "$expected_tree" ]]; then
  echo "compiler source tree does not match compiler-tree.txt; preserving checkout" >&2
  exit 65
fi
if [[ -n "$(git -C "$source_dir" status --porcelain --untracked-files=all)" ]]; then
  echo "compiler checkout must be clean; preserving local changes" >&2
  exit 65
fi
mvn -B -ntp -q -f "$source_dir/pom.xml" -DskipTests package dependency:build-classpath \
  -Dmdep.outputFile="$root/.work/classpath.txt"
cat > "$root/.work/ores" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
classpath="$root/.work/compiler/target/classes:$(cat "$root/.work/classpath.txt")"
exec java --enable-native-access=ALL-UNNAMED \
  -Dpolyglot.engine.WarnInterpreterOnly=false -cp "$classpath" \
  dev.oreslang.launcher.OresMain "$@"
RUNNER
chmod +x "$root/.work/ores"
echo "compiler ready: bash scripts/test.sh"
