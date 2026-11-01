#!/usr/bin/env bash
# Move widgets between the bar and the drawer, as one atomic write of shell.json,
# so a widget is always in exactly one place. Run by the edit view.
#   move-widgets.sh <drawer-id> [--to-drawer <id>]... [--to-bar <id>]...
# Omarchy has no command that takes a widget off the bar and keeps it loaded. A
# third-party widget stays loaded while it has a plugins[] entry, so it gets one.
# Its layout entry goes in the drawer's `parked` setting, for its way back.
set -euo pipefail

fail() { echo "move-widgets: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || fail "usage: move-widgets.sh <drawer-id> [--to-drawer <id>]... [--to-bar <id>]..."
self=$1; shift
to_drawer=(); to_bar=()
while (( $# > 0 )); do
  [[ $# -ge 2 && -n $2 ]] || fail "$1 needs a widget id"
  case "$1" in
    --to-drawer) to_drawer+=("$2") ;;
    --to-bar) to_bar+=("$2") ;;
    *) fail "unknown option: $1" ;;
  esac
  shift 2
done

config=$(readlink -f "$HOME/.config/omarchy/shell.json")
[[ -s $config ]] || fail "no shell.json to edit"

# Same directory as the config, so the final mv is atomic.
tmp=$(mktemp "$config.XXXXXX")
snapshot=$(mktemp "$config.XXXXXX")
trap 'rm -f "$tmp" "$snapshot"' EXIT
cp -p "$config" "$snapshot"

jq --arg self "$self" \
  --argjson toDrawer "$(jq -n '$ARGS.positional' --args -- ${to_drawer[@]+"${to_drawer[@]}"})" \
  --argjson toBar "$(jq -n '$ARGS.positional' --args -- ${to_bar[@]+"${to_bar[@]}"})" '
  def instances($id): [.bar.layout[]? | arrays | .[] | objects | select(.id == $id)];
  def drawer: .bar.layout[]? | arrays | .[] | objects | select(.id == $self);
  def section: first(.bar.layout | to_entries[]
    | select(.value | arrays | any(.[]; objects | .id == $self)) | .key);

  def park($id):
    (instances($id)[0] // {} | del(.id)) as $entry
    | del(.bar.layout[]? | arrays | .[] | objects | select(.id == $id))
    | if ($id | startswith("omarchy.")) or any(.plugins[]?; .id? == $id) then .
      else .plugins = ((.plugins // []) + [{id: $id}]) end
    | (drawer) |= (
        .widgets = ((.widgets // []) | if index([$id]) then . else . + [$id] end)
        | if $entry == {} then . else .parked[$id] = $entry end);

  def unpark($id):
    if instances($id) == [] then
      section as $s
      | ({id: $id} + ((drawer | .parked[$id]?) // {})) as $entry
      | (.bar.layout[$s] | map(.id? == $self) | index(true)) as $at
      | .bar.layout[$s] |= .[:$at] + [$entry] + .[$at:]
    else . end
    | (drawer) |= (
        .widgets = ((.widgets // []) - [$id])
        | if .hidden then .hidden -= [$id] else . end
        | del(.parked[$id]?)
        | if .parked == {} then del(.parked) else . end);

  if .version != 1 then error("shell.json is not version 1")
  elif ([drawer] | length) != 1 then error("the drawer must be on the bar exactly once")
  elif ($toDrawer + $toBar | index([$self])) then error("the drawer cannot hold itself")
  elif any($toDrawer[]; . as $id | ($id | IN($toBar[]))) then error("a widget cannot go both ways")
  else . end
  | . as $config
  | if any($toDrawer[]; . as $id | ($config | instances($id) | length) > 1)
    then error("a widget with several instances on the bar stays there") else . end
  | reduce $toDrawer[] as $id (.; park($id))
  | reduce $toBar[] as $id (.; unpark($id))
' "$snapshot" >"$tmp"

# The shell writes this file too. ponytail: it takes no lock we could share, so a
# write in the instant between this check and the mv still loses; the window is
# microseconds and the backup holds what it replaced.
cmp -s "$config" "$snapshot" || fail "shell.json changed while moving, nothing written"
chmod --reference="$config" "$tmp"
mv "$snapshot" "$config.drawer-backup"
mv "$tmp" "$config"
omarchy-shell shell reloadConfig >/dev/null 2>&1 || true
