#!/usr/bin/env bash
# Run by tests/lint.sh. Works on a throwaway HOME, with a stub omarchy-shell so it
# never reloads the real shell.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME=$TMP PATH="$TMP/bin:$PATH"
mkdir -p "$HOME/.config/omarchy" "$HOME/bin"
printf '#!/bin/sh\n' >"$HOME/bin/omarchy-shell"; chmod +x "$HOME/bin/omarchy-shell"
CONFIG=$HOME/.config/omarchy/shell.json
D=drawer

reset_config() {
  cat >"$CONFIG" <<'JSON'
{
  "version": 1,
  "bar": {
    "position": "bottom",
    "layout": {
      "left": [{"id": "spacer"}, {"id": "spacer"}],
      "center": [{"id": "omarchy.clock", "format": "HH:mm"}],
      "right": [{"id": "third.party", "color": "é"}, {"id": "drawer", "scale": 0.4, "widgets": ["old"], "hidden": ["old"]}],
      "tray": [{"id": "in.tray"}]
    }
  },
  "plugins": [{"id": "other", "keep": true}],
  "extra": {"untouched": 1.50}
}
JSON
  chmod 600 "$CONFIG"
}
move() { bash "$HERE/scripts/move-widgets.sh" "$D" "$@"; }
q() { jq -c "$1" "$CONFIG"; }
eq() { [[ "$2" == "$3" ]] || { echo "$1: expected $3, got $2" >&2; exit 1; }; }
refused() { local before; before=$(<"$CONFIG"); if move "$@" 2>/dev/null; then echo "not refused: $*" >&2; exit 1; fi; eq "unchanged after refusal" "$(<"$CONFIG")" "$before"; }
on_bar() { q "[.bar.layout[][] | .id] | index(\"$1\") != null"; }

reset_config
original=$(<"$CONFIG")

# To the drawer: off the bar, in the list, settings kept, third party stays loaded.
move --to-drawer third.party --to-drawer omarchy.clock --to-drawer in.tray
eq "left the bar" "$(on_bar third.party)$(on_bar omarchy.clock)$(on_bar in.tray)" "falsefalsefalse"
eq "listed" "$(q '.bar.layout.right[0].widgets')" '["old","third.party","omarchy.clock","in.tray"]'
eq "parked settings" "$(q '.bar.layout.right[0].parked')" '{"third.party":{"color":"é"},"omarchy.clock":{"format":"HH:mm"}}'
eq "kept loaded" "$(q '[.plugins[].id]')" '["other","third.party","in.tray"]'
eq "first party needs no entry" "$(q '[.plugins[].id] | index("omarchy.clock")')" "null"
eq "the rest is left alone" "$(q '[.bar.position, .extra.untouched, .bar.layout.right[0].scale]')" '["bottom",1.50,0.4]'
eq "backup is the previous file" "$(<"$CONFIG.drawer-backup")" "$original"
eq "mode kept" "$(stat -c %a "$CONFIG")" "600"

# Running it again changes nothing, including the settings it stashed.
after=$(<"$CONFIG")
move --to-drawer third.party
eq "idempotent" "$(<"$CONFIG")" "$after"

# And back: before the drawer, with its settings.
move --to-bar third.party --to-bar omarchy.clock --to-bar old
eq "back on the bar" "$(q '[.bar.layout.right[].id]')" '["third.party","omarchy.clock","old","drawer"]'
eq "settings restored" "$(q '.bar.layout.right[0:2]')" '[{"id":"third.party","color":"é"},{"id":"omarchy.clock","format":"HH:mm"}]'
eq "drawer list" "$(q '.bar.layout.right[3].widgets')" '["in.tray"]'
eq "hidden cleared" "$(q '.bar.layout.right[3].hidden')" '[]'
eq "parked gone" "$(q '.bar.layout.right[3] | has("parked")')" "false"
eq "our plugins entry gone" "$(q '[.plugins[].id]')" '["other","in.tray"]'

# A plugins entry the user gave settings to is theirs.
reset_config
move --to-drawer other
move --to-bar other
eq "their entry kept" "$(q '.plugins')" '[{"id":"other","keep":true}]'

# String entries count as instances.
reset_config
jq '.bar.layout.center = ["str.widget"]' "$CONFIG" >"$CONFIG.new" && mv "$CONFIG.new" "$CONFIG"
move --to-drawer str.widget
eq "string entry left the bar" "$(q '.bar.layout.center')" '[]'
jq '.bar.layout.right = ["str.other"] + .bar.layout.right' "$CONFIG" >"$CONFIG.new" && mv "$CONFIG.new" "$CONFIG"
move --to-bar str.widget
eq "placed before the drawer" "$(q '[.bar.layout.right[] | if type == "string" then . else .id end]')" '["str.other","third.party","str.widget","drawer"]'

# A widget already on the bar is not added a second time.
reset_config
jq '.bar.layout.right[1].widgets += ["third.party"]' "$CONFIG" >"$CONFIG.new" && mv "$CONFIG.new" "$CONFIG"
move --to-bar third.party
eq "no duplicate" "$(q '[.bar.layout[][] | select(.id == "third.party")] | length')" "1"

# No `widgets` key yet.
reset_config
jq 'del(.bar.layout.right[1].widgets)' "$CONFIG" >"$CONFIG.new" && mv "$CONFIG.new" "$CONFIG"
move --to-drawer third.party
eq "first member" "$(q '.bar.layout.right[0].widgets')" '["third.party"]'

# Refusals leave the file exactly as it was.
reset_config
refused --to-drawer spacer
refused --to-drawer drawer
refused --to-drawer third.party --to-bar third.party
refused --bogus x
D=missing refused --to-drawer third.party
jq '.version = 2' "$CONFIG" >"$CONFIG.new" && mv "$CONFIG.new" "$CONFIG"
refused --to-drawer third.party
printf 'not json' >"$CONFIG"
refused --to-drawer third.party

# Another writer between the read and the write wins, and we say so.
reset_config
real_jq=$(command -v jq)
printf '#!/bin/sh\n"%s" "$@"; rc=$?; printf " " >>"%s"; exit $rc\n' "$real_jq" "$CONFIG" >"$HOME/bin/jq"
chmod +x "$HOME/bin/jq"
if move --to-drawer third.party 2>/dev/null; then echo "not refused: concurrent write" >&2; exit 1; fi
rm "$HOME/bin/jq"
eq "other writer kept" "$(on_bar third.party)" "true"

# A failure leaves no temp file beside the config.
eq "no temp files" "$(find "$HOME/.config/omarchy" -name 'shell.json.??????' | wc -l)" "0"
echo "move-widgets ok"
