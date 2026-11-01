#!/usr/bin/env bash
# Static checks that need no shell: run in CI and before a release.
#   bash tests/lint.sh
# Checks that need what only a dev machine has say so instead of passing quietly:
# qmllint needs the omarchy shell's QML modules and omarchy-plugin-validate needs
# Omarchy itself. Set LINT_EXPECT_SKIPS to pin how many are allowed to go quiet.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; cd "$HERE" || exit 1
fail=0
skips=0; skip_names=""
step() { printf '== %s\n' "$1"; }
bad() { echo "  ✗ $1"; fail=1; }
ok() { echo "  ✓ $1"; }
# A skip is not a pass. Set LINT_EXPECT_SKIPS to the number this environment is
# allowed to skip and the run fails when the count moves: that is the only thing
# that would have caught qmllint sitting dead for weeks because its binary was
# off PATH, or the node suites never running in CI.
skipped() { echo "  - skipped: $1"; skips=$((skips + 1)); skip_names="$skip_names\n    - $1"; }

step "shellcheck"
if shellcheck -S warning scripts/*.sh tests/*.sh; then ok "clean"; else bad "shellcheck findings"; fi

step "manifest.json"
m=manifest.json
jq -e '.schemaVersion == 1' "$m" >/dev/null && ok "schemaVersion is the number 1" || bad "schemaVersion must be the number 1"
jq -e '.id | test("^[A-Za-z0-9][A-Za-z0-9._-]*$") and (startswith("omarchy.") | not)' "$m" >/dev/null && ok "id well-formed" || bad "id"
jq -e '.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' "$m" >/dev/null && ok "version is semver" || bad "version"
for k in name author license description homepage; do jq -e --arg k "$k" '.[$k] | type == "string" and length > 0' "$m" >/dev/null && ok "$k present" || bad "$k missing"; done
for kind in $(jq -r '.kinds[]' "$m"); do
  case "$kind" in bar-widget) key=barWidget ;; *) key=$kind ;; esac
  ep=$(jq -r --arg k "$key" '.entryPoints[$k] // empty' "$m")
  [[ -n "$ep" && -f "$ep" ]] && ok "entry point for $kind: $ep" || bad "entry point for $kind missing or absent on disk"
done
[[ "$(jq -r .version "$m")" == "$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | tr -d '[]# ')" ]] && ok "CHANGELOG top release matches manifest version" || bad "CHANGELOG top release != manifest version"
if find . -path ./.git -prune -o -type l -print | grep -q .; then bad "symlinks in the plugin tree (validator rejects them)"; else ok "no symlinks"; fi
if command -v omarchy-plugin-validate >/dev/null; then
  omarchy-plugin-validate . >/dev/null && ok "omarchy-plugin-validate" || bad "omarchy-plugin-validate"
else skipped "omarchy-plugin-validate (not installed)"; fi

step "QML hygiene"
QML=(*.qml)
if grep -nE '"bash", *"-c"|"sh", *"-c"|bash -c' -- "${QML[@]}"; then bad "shell strings built in QML"; else ok "no shell strings in QML"; fi
if grep -nE '(^|[^A-Za-z])/tmp(/|\b)' -- "${QML[@]}" | grep -vE '^[^:]+:[0-9]+:\s*(#|//)'; then bad "/tmp referenced"; else ok "no /tmp paths (comments aside)"; fi
for f in "${QML[@]}"; do [[ -s "$f" ]] || bad "$f empty"; done
# User strings render as plain text: the hardening pass set PlainText everywhere and nothing may undo it.
if grep -nE 'textFormat: *(Text|TextEdit)\.(RichText|StyledText|AutoText)' -- "${QML[@]}"; then bad "rich text format on a Text element"; else ok "no RichText/StyledText/AutoText"; fi
# And every Text says so: left unset a Text is AutoText, which renders a title
# or note containing "<b>" as markup. A title is data, not formatting.
missing_fmt=$(awk '
  FNR == 1 { blk = 0 }
  !blk && /(^|[^A-Za-z.])Text[[:space:]]*\{/ { blk = 1; start = FNR; body = ""; depth = 0 }
  blk {
    body = body $0 "\n"; o = gsub(/\{/, "{"); c = gsub(/\}/, "}"); depth += o - c
    if (depth <= 0) { if (body !~ /textFormat:/) print FILENAME ":" start; blk = 0 }
  }' "${QML[@]}")
if [[ -n "$missing_fmt" ]]; then printf '  %s\n' $missing_fmt; bad "Text elements without textFormat (add textFormat: Text.PlainText)"; else ok "every Text sets textFormat"; fi
# Theme tokens only (Color.*, Style.*): no colour literals, no hand-picked pixel sizes.
if grep -nE '"#[0-9a-fA-F]{3,8}"|Qt\.rgba\(' -- "${QML[@]}"; then bad "colour literal in QML (use Color.* tokens)"; else ok "no colour literals"; fi
# Commands are argv arrays; a string here would be a shell line.
if grep -nE 'command: *"|execDetached\("' -- "${QML[@]}"; then bad "command given as a string, not an argv array"; else ok "commands are argv arrays"; fi
if grep -nE 'console\.' -- "${QML[@]}"; then bad "console.* left in"; else ok "no console output left in"; fi
# qmllint, with the shell's own modules registered. Three classes are noise here
# and disabled: missing-property (the shell's Style/Color token groups are untyped
# QtObjects), signal-handler-parameters (onExited(code) drops exitStatus on
# purpose), uncreatable-type (PanelWindow is a Quickshell interface type).
QMLLINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"; command -v "$QMLLINT" >/dev/null 2>&1 || QMLLINT=$(command -v qmllint || true)
SHELLQML=/usr/share/omarchy/shell
if [[ -n "$QMLLINT" && -f "$SHELLQML/Commons/qmldir" && -f "$SHELLQML/Ui/qmldir" ]]; then
  if "$QMLLINT" -i "$SHELLQML/Commons/qmldir" -i "$SHELLQML/Ui/qmldir" \
       --missing-property disable --signal-handler-parameters disable --uncreatable-type disable "${QML[@]}"; then ok "qmllint clean"; else bad "qmllint findings"; fi
else skipped "qmllint (needs the omarchy shell's QML modules)"; fi
# The shell's nested token groups (Style.spacing.*, Style.font.*, Style.bar.*)
# are untyped QtObjects, which is why missing-property is off above: a token
# Omarchy renames would only fail at runtime. Check every one the plugin uses
# against the groups the shell's Style.qml declares.
# style_tokens <Style.qml>: "group.name" for every property declared directly
# in a nested group. Braces are counted per character and // comments dropped,
# so a "}}" or a commented-out property cannot throw the grouping off; the
# fixture proves it in CI too, where the shell itself is absent.
style_tokens() {
  awk '
    {
      line = $0; sub(/\/\/.*/, "", line)
      if (g == "" && match(line, /readonly property QtObject [a-z]+: QtObject \{/)) {
        s = substr(line, RSTART, RLENGTH); sub(/^readonly property QtObject /, "", s); sub(/:.*/, "", s)
        g = s; depth = 1; line = substr(line, RSTART + RLENGTH)
      }
      if (g == "") next
      if (depth == 1 && match(line, /property [A-Za-z]+ [A-Za-z_]+/)) { split(substr(line, RSTART, RLENGTH), a, " "); print g "." a[3] }
      o = gsub(/\{/, "{", line); c = gsub(/\}/, "}", line); depth += o - c
      if (depth <= 0) g = ""
    }' "$1" | sort -u
}
got=$(style_tokens tests/fixtures/Style.qml | paste -sd' ')
[[ "$got" == "font.body font.caption spacing.nested spacing.sm spacing.xs" ]] && ok "kit-token parser reads its fixture right" || bad "kit-token parser misread its fixture: $got"
STYLEQML="$SHELLQML/Commons/Style.qml"
if [[ -f "$STYLEQML" ]]; then
  declared=$(style_tokens "$STYLEQML")
  unknown=$(grep -ohE 'Style\.(spacing|font|bar)\.[A-Za-z_]+' "${QML[@]}" | sed 's/^Style\.//' | sort -u | comm -23 - <(printf '%s\n' "$declared"))
  if [[ -z "$unknown" ]]; then ok "every nested kit token the plugin uses exists in the shell's Style.qml"
  else bad "kit tokens the shell's Style.qml does not declare: $(printf '%s ' $unknown)"; fi
else skipped "kit tokens (needs the omarchy shell's Style.qml)"; fi

step "hosted widgets"
# The bar destroys and recreates a plugin's bar API object when module slots
# change (a monitor hotplug does it). A one-time copy leaves hosted widgets
# holding a dead reference, so new rows in their panels render black.
if grep -nE '\.bar = root\.bar' -- "${QML[@]}"; then bad "hosted widget given a one-time bar copy (use Qt.binding)"; else ok "hosted widgets bind bar live"; fi

step "marketplace scan"
# The marketplace's security baseline lists an explicit privilege command (sudo,
# pkexec) and a clone from a remote as capabilities a reviewer has to accept.
# The drawer needs neither. Keep it that way.
if git grep -nIE '\b(sudo|pkexec) +[a-z]|git clone +[a-z]+://' -- . ':!tests/lint.sh'; then bad "privilege or remote-clone command in the tree"; else ok "no privilege or remote-clone commands"; fi
# It also counts an install command spelled out in code (pacman -S ...) as
# package management, and any file named *install* or *setup* as an
# installer. The dev script is dev-sync.sh.
if git grep -nIE '\b(pacman|paru|yay|apt|apt-get|dnf|zypper|apk) +(-[A-Za-z]*[SRU]|install|remove|upgrade|add|del)\b' -- '*.qml' scripts; then bad "package-manager command in the code (name the package instead)"; else ok "no package-manager commands in the code"; fi
if git ls-files | sed 's#.*/##' | grep -iE '(^|[-_])(install|installer|setup|uninstall)([-_.]|$)'; then bad "a file name the marketplace reads as an installer"; else ok "no installer-looking file names"; fi

step "docs"
grep -q '## Remove' README.md && ok "README has a Remove section" || bad "README lacks Remove"
grep -q '## Update' README.md && ok "README has an Update section" || bad "README lacks Update"
grep -q 'omarchy plugin add' README.md && ok "README has the install command" || bad "README lacks install command"
[[ -f LICENSE && -f preview.png ]] && ok "LICENSE and preview.png present" || bad "LICENSE/preview.png"
[[ "$(tail -n1 LICENSE)" == "SOFTWARE." && -f THIRD-PARTY.md ]] && ok "LICENSE is the bare MIT text, so GitHub reads it as MIT" || bad "LICENSE has text after the MIT body; dependency notes belong in THIRD-PARTY.md"

echo
if [[ -n "${LINT_EXPECT_SKIPS:-}" && "$skips" != "$LINT_EXPECT_SKIPS" ]]; then
  echo "✗ expected $LINT_EXPECT_SKIPS skipped check(s), got $skips:"
  printf '%b\n' "${skip_names:-    (none)}"
  fail=1
fi
[[ $skips == 0 ]] || echo "lint: $skips check(s) skipped"
[[ $fail == 0 ]] && echo "lint: ok" || { echo "lint: FAILED"; exit 1; }
