// Run by tests/lint.sh with ui/drawer.js prepended (.pragma removed).
const assert = require("assert")
const eq = assert.deepStrictEqual

eq(toList(["a"]), ["a"])
eq(toList({ length: 2, 0: "a", 1: "b" }), ["a", "b"])
eq(toList("abc"), null)
eq(toList(null), null)

eq(cleanIds(["a", "", null, 0, "b"]), ["a", "b"])
eq(cleanIds(undefined), [])

// Unknown sections count: this is what 4.5's tray and centerEnd need.
const layout = { left: [{ id: "a" }], tray: [{ id: "b" }, null], centerEnd: [{ id: "a" }, { id: "c" }], note: "x" }
eq(layoutIds(layout), ["a", "b", "c"])
eq(layoutIds(null), [])

const name = id => ({ a: "Zed", b: "alpha", c: "Beta", self: "Drawer", gone: "Mid" })[id]
eq(editIds(layout, ["gone"], "self", name), ["gone", "b", "c", "a"])
eq(editIds({ right: [{ id: "self" }] }, [], "self", name), [])

eq(moveArgs(["a", "b"], ["b", "c"]), ["--to-drawer", "c", "--to-bar", "a"])
eq(moveArgs(["a"], ["a"]), [])


eq(reorder(["a", "b", "c"], ["a", "b", "c"], "a", 2), ["b", "a", "c"])
eq(reorder(["a", "b", "c"], ["a", "b", "c"], "a", 3), ["b", "c", "a"])
eq(reorder(["a", "b", "c"], ["a", "b", "c"], "c", 0), ["c", "a", "b"])
eq(reorder(["a", "b", "c"], ["a", "b", "c"], "b", 1), ["a", "b", "c"])
eq(reorder(["a", "b", "c"], ["a", "b", "c"], "b", 2), ["a", "b", "c"])
// A hidden widget (h) sits between visible rows: indices are visible ones.
eq(reorder(["a", "h", "b", "c"], ["a", "b", "c"], "c", 1), ["a", "h", "c", "b"])
eq(reorder(["a", "h", "b", "c"], ["a", "b", "c"], "a", 3), ["h", "b", "c", "a"])
eq(reorder(["a", "b"], ["a", "b"], "z", 0), ["a", "b"])
eq(reorder(["a", "b"], ["a", "b"], "a", -1), ["a", "b"])

const src = { id: "me", widgets: { length: 1, 0: "a" }, scale: 0.4 }
eq(mergedSettings(src, { scale: 0.5 }), { widgets: ["a"], scale: 0.5 })

eq(gridDrop(250, 90, 100, 80, 3, 7), { index: 5, col: 2, row: 1 })
eq(gridDrop(-5, -5, 100, 80, 3, 7), { index: 0, col: 0, row: 0 })
eq(gridDrop(950, 900, 100, 80, 3, 7).index, 7)

eq(listDrop(-3, 34, 4), 0)
eq(listDrop(40, 34, 4), 1)
eq(listDrop(60, 34, 4), 2)
eq(listDrop(500, 34, 4), 4)

eq(moveCursor(-1, 0, 1, 3, 5), 0)
eq(moveCursor(0, 1, 0, 3, 5), 1)
eq(moveCursor(1, 0, 1, 3, 5), 4)
eq(moveCursor(4, 0, 1, 3, 5), 4)
eq(moveCursor(0, -1, 0, 3, 5), 0)
eq(moveCursor(3, 0, 0, 1, 0), -1)

eq(scrollTo(100, 50, 30, 200), 50)
eq(scrollTo(100, 280, 30, 200), 110)
eq(scrollTo(100, 150, 30, 200), 100)

eq(listWidth([40, 90.2, 60], 50, 100, 300), 141)
eq(listWidth([], 50, 100, 300), 100)
eq(listWidth([900], 50, 100, 300), 300)

console.log("drawer.js: ok")
