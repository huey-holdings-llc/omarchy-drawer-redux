// Pure drawer logic: no Qt, no host calls, so it runs under node (tests/drawer.test.js).
.pragma library

// Settings arrive through a QML `var` property, so a list inside them can be a
// QVariantList sequence that Array.isArray rejects. Accept any array-like.
function toList(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value === "object" && typeof value.length === "number")
    return Array.prototype.slice.call(value)
  return null
}

// Non-empty string ids, in order. Anything that is not a list gives [].
function cleanIds(value) {
  var list = toList(value) || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var id = String(list[i] || "")
    if (id) out.push(id)
  }
  return out
}

// Every section the host gives us, not a fixed list: 4.5 adds centerBegin,
// centerEnd and tray, and a hard-coded left/center/right would miss them.
function layoutIds(layout) {
  var out = []
  if (!layout || typeof layout !== "object") return out
  var names = Object.keys(layout)
  for (var s = 0; s < names.length; s++) {
    var entries = toList(layout[names[s]])
    if (!entries) continue
    for (var i = 0; i < entries.length; i++) {
      var id = entries[i] ? String(entries[i].id || "") : ""
      if (id && out.indexOf(id) === -1) out.push(id)
    }
  }
  return out
}

// The edit list: everything on the bar plus everything in the drawer, minus the
// drawer itself. Drawer members first, then alphabetical by name().
function editIds(layout, configured, selfId, name) {
  var out = layoutIds(layout)
  for (var c = 0; c < configured.length; c++)
    if (out.indexOf(configured[c]) === -1) out.push(configured[c])
  out = out.filter(function(id) { return id !== selfId })
  out.sort(function(a, b) {
    var ra = configured.indexOf(a) !== -1 ? 0 : 1
    var rb = configured.indexOf(b) !== -1 ? 0 : 1
    if (ra !== rb) return ra - rb
    var na = String(name(a)).toLowerCase()
    var nb = String(name(b)).toLowerCase()
    return na < nb ? -1 : (na > nb ? 1 : 0)
  })
  return out
}

// `id` added to or dropped from `list`, without touching the input.
function withMember(list, id, member) {
  var out = list.slice()
  var i = out.indexOf(id)
  if (member && i === -1) out.push(id)
  else if (!member && i !== -1) out.splice(i, 1)
  return out
}

// Drag indices count the rows on screen; the stored list also holds widgets
// hidden from the view. Move `id` to just before the visible row at `toIndex`
// (or past the last row) and keep hidden entries where they are relative to it.
function reorder(configured, visible, id, toIndex) {
  if (configured.indexOf(id) === -1 || visible.indexOf(id) === -1 || toIndex < 0) return configured
  var rest = visible.filter(function(v) { return v !== id })
  var from = visible.indexOf(id)
  var slot = Math.min(toIndex > from ? toIndex - 1 : toIndex, rest.length)
  if (slot === from) return configured
  var out = configured.filter(function(v) { return v !== id })
  var at = slot < rest.length ? out.indexOf(rest[slot]) : out.indexOf(rest[rest.length - 1]) + 1
  out.splice(at, 0, id)
  return out
}

// updateEntryInline replaces the whole entry, so carry every field over.
function mergedSettings(settings, overrides) {
  var next = {}
  for (var k in settings) {
    if (k === "id") continue
    var list = toList(settings[k])
    next[k] = list ? list.slice() : settings[k]
  }
  for (var o in overrides) next[o] = overrides[o]
  return next
}

// Which cell a drag over the grid lands in. Rows pitch by tile height, columns
// by cell width: they are different sizes.
function gridDrop(x, y, cellW, cellH, cols, count) {
  var col = Math.max(0, Math.min(cols - 1, Math.floor(x / cellW)))
  var row = Math.max(0, Math.floor(y / cellH))
  return { index: Math.min(row * cols + col, count), col: col, row: row }
}

// Which gap a drag over the list lands in: the top half of a row is above it.
function listDrop(y, pitch, count) {
  var row = Math.floor(y / pitch)
  if (row < 0) return 0
  if (row >= count) return count
  return (y - row * pitch) < pitch / 2 ? row : row + 1
}

// Arrow-key cursor over `count` items laid out in `cols` columns. From nothing,
// any key lands on the first item. Moves off the edge stay put.
function moveCursor(index, dx, dy, cols, count) {
  if (count <= 0) return -1
  if (index < 0 || index >= count) return 0
  var next = index + dx + dy * cols
  return next < 0 || next >= count ? index : next
}

// contentY that brings [top, top + height] into a view of `viewH`.
function scrollTo(contentY, top, height, viewH) {
  if (top < contentY) return top
  if (top + height > contentY + viewH) return top + height - viewH
  return contentY
}

// Card width for the list view: the longest row, inside the given bounds.
function listWidth(textWidths, chrome, min, max) {
  var w = 0
  for (var i = 0; i < textWidths.length; i++) w = Math.max(w, textWidths[i])
  return Math.ceil(Math.max(min, Math.min(max, w + chrome)))
}
