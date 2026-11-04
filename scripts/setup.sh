#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# The private checkout and launcher may never be redirected through a .work
# symlink. Check this BEFORE deleting an old launcher or opening compiler data.
if [[ -L "$root/.work" ]]; then
  echo "compiler work directory must not be a symlink" >&2
  exit 65
fi
mkdir -p "$root/.work"
if [[ "$(cd "$root/.work" && pwd -P)" != "$root/.work" ]]; then
  echo "compiler work directory resolves outside repository" >&2
  exit 65
fi
# A failed build in a valid owned work directory must not leave an old launcher.
rm -f "$root/.work/ores"
# Prevent Maven's classpath output from following a caller-owned symlink.
if [[ -L "$root/.work/classpath.txt" ]]; then
  echo "compiler classpath path must not be a symlink" >&2
  exit 65
fi
revision="$(tr -d '[:space:]' < "$root/compiler.lock")"
expected_tree="$(tr -d '[:space:]' < "$root/compiler-tree.txt")"
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ || ! "$expected_tree" =~ ^[0-9a-f]{40}$ ]]; then
  echo "compiler revision and tree must be full Git SHAs" >&2
  exit 65
fi
source_dir="$root/.work/compiler"
mkdir -p "$root/.work"
if [[ -L "$source_dir" ]]; then
  echo "compiler path must not be a symlink" >&2
  exit 65
fi
# A tree-complete, verified mirror can pre-populate .work/compiler.
# Offline mode MUST never attempt a private origin clone with an unrelated
# organization's GITHUB_TOKEN (or fall back to implicit network access).
case "${ORESLANG_OFFLINE:-0}" in
  0|1) ;;
  *) echo "ORESLANG_OFFLINE must be 0 or 1" >&2; exit 65 ;;
esac
if [[ ! -e "$source_dir" ]]; then
  if [[ "${ORESLANG_OFFLINE:-0}" == "1" ]]; then
    echo "offline compiler checkout missing: $source_dir" >&2
    exit 69
  fi
  git clone --depth 1 --single-branch --branch "compiler-mirror/$revision" \
    https://github.com/ores-truffle-oreslang/oreslang-ssr.git "$source_dir"
fi
if [[ "$(git -C "$source_dir" rev-parse --show-toplevel)" != "$(cd "$source_dir" && pwd -P)" ]]; then
  echo "compiler path must be its own Git checkout" >&2
  exit 65
fi
actual_commit="$(git -C "$source_dir" rev-parse 'HEAD')" || {
  echo "compiler checkout has no readable HEAD" >&2
  exit 65
}
actual_tree="$(git -C "$source_dir" rev-parse 'HEAD^{tree}')" || {
  echo "compiler checkout has no readable Git tree" >&2
  exit 65
}
if [[ "$actual_tree" != "$expected_tree" ]]; then
  echo "compiler source tree does not match compiler-tree.txt; preserving checkout" >&2
  exit 65
fi
# Maven clean must not touch an ignored symlinked target directory.
if [[ -L "$source_dir/target" ]]; then
  echo "compiler target directory must not be a symlink" >&2
  exit 65
fi
if [[ -n "$(git -C "$source_dir" status --porcelain --untracked-files=all)" ]]; then
  echo "compiler checkout must be clean; preserving local changes" >&2
  exit 65
fi
# Generated classes are ignored by Git; a previous build might leave valid-
# looking artifacts that could conceal a zero-exit but non-producing Maven
# invocation. Reject symlinked ancestors before removing anything. Never
# delete an artifact through a redirect into another directory or repository.
entry="$source_dir/target/classes/dev/oreslang/launcher/OresMain.class"
for artifact_dir in \
  "$source_dir/target/classes" \
  "$source_dir/target/classes/dev" \
  "$source_dir/target/classes/dev/oreslang" \
  "$source_dir/target/classes/dev/oreslang/launcher"; do
  if [[ -L "$artifact_dir" ]]; then
    echo "compiler class-output directory must not be a symlink" >&2
    exit 65
  fi
done
if [[ -L "$entry" ]]; then
  echo "compiler entrypoint must not be a symlink" >&2
  exit 65
fi
rm -f -- "$root/.work/classpath.txt" "$entry"
maven_mode=()
if [[ "${ORESLANG_OFFLINE:-0}" == "1" ]]; then
  maven_mode=(-o)
fi
mvn -B -ntp -q "${maven_mode[@]}" -f "$source_dir/pom.xml" -DskipTests clean package dependency:build-classpath \
  -Dmdep.outputFile="$root/.work/classpath.txt"
# A zero-exit Maven process is not proof that the intended compiler exists.
# Refuse to publish a launcher which cannot read its dependency classpath or
# load the exact main class it is configured to execute. This also protects
# against mock/synthetic builds being mistakenly promoted as native evidence.
if [[ -L "$root/.work/classpath.txt" || ! -f "$root/.work/classpath.txt" || ! -s "$root/.work/classpath.txt" ]]; then
  echo "compiler build did not produce a nonempty regular classpath file" >&2
  exit 65
fi
if [[ -L "$entry" || ! -f "$entry" || ! -s "$entry" ]]; then
  echo "compiler build did not produce the expected OresMain class" >&2
  exit 65
fi
launcher="$(mktemp "$root/.work/.ores.XXXXXX")"
trap 'rm -f "$launcher"' EXIT
cat > "$launcher" <<'RUNNER'
#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
classpath="$root/.work/compiler/target/classes:$(cat "$root/.work/classpath.txt")"
exec java --enable-native-access=ALL-UNNAMED \
  -Dpolyglot.engine.WarnInterpreterOnly=false -cp "$classpath" \
  dev.oreslang.launcher.OresMain "$@"
RUNNER
chmod +x "$launcher"
mv -f "$launcher" "$root/.work/ores"
printf 'compiler snapshot: pinned_ref=%s checkout_ref=%s tree=%s\n' "$revision" "$actual_commit" "$actual_tree"
echo "compiler ready: bash scripts/test.sh"
