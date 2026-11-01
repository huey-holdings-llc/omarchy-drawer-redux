import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "ui/drawer.js" as Drawer

// Omarchy Drawer Redux: collapse chosen bar widgets into a single menu button.
//
// Widgets listed in the `widgets` inline setting (or the manifest defaults)
// are removed from the bar layout but stay mounted here: invisibly, at the
// button's position in the bar: so clicking their entry in the drawer menu
// opens their own panel anchored to the bar, right underneath the drawer.
//
// Left-clicking the hamburger opens the menu with the hidden widgets; the pen
// switches to an edit list that moves widgets between the bar and the drawer.
BarWidget {
  id: root
  moduleName: "io.github.huey-holdings-llc.omarchy-drawer-redux"

  // Omarchy's `bar` facade has no widget registry, so read the snapshot the host
  // injects into this plugin's own service (Service.qml).
  readonly property var drawerService: root.bar && root.bar.shell
    && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.moduleName) : null
  readonly property var registryWidgets: root.drawerService && root.drawerService.barWidgetRegistry
    ? root.drawerService.barWidgetRegistry.widgets : ({})

  // Read-only snapshot of every bar section, handed to all bar widgets.
  readonly property var barLayout: root.bar ? root.bar.layoutConfig : null

  // Raw configured list, from this plugin's own injected settings, falling back
  // to the manifest defaults when the entry has no `widgets` key yet.
  readonly property var configuredIds: {
    var rev = root.manageRevision
    void rev
    var list = Drawer.toList(root.settings.widgets)
    return Drawer.cleanIds(list || root.defaultsFor(root.moduleName).widgets)
  }

  // Configured ids that are actually registered, so the drawer can mount them.
  readonly property var hiddenIds: {
    var out = []
    var configured = root.configuredIds
    for (var i = 0; i < configured.length; i++) {
      var id = String(configured[i] || "")
      if (id && root.registryWidgets[id]) out.push(id)
    }
    return out
  }

  // Everything the edit view lists: bar widgets from the layout snapshot, plus
  // what is already in the drawer so it can be unchecked.
  readonly property var allPlugins: Drawer.editIds(root.barLayout, root.configuredIds, root.moduleName, root.displayName)

  function defaultsFor(id) {
    var entry = root.registryWidgets[id]
    return entry && entry.metadata && entry.metadata.defaults ? entry.metadata.defaults : ({})
  }

  function displayName(id) {
    var entry = root.registryWidgets[id]
    return entry && entry.metadata && entry.metadata.displayName ? String(entry.metadata.displayName) : id
  }

  // --- menu state ------------------------------------------------------------

  property bool menuOpen: false
  // The host finds a panel widget by this, which is what makes `omarchy-shell
  // shell toggle <id>` work from a hotkey.
  readonly property bool opened: root.menuOpen
  property bool manageMode: false

  // Bumped whenever the edit menu closes so the drawer/plugin lists re-evaluate
  // from the freshly persisted config instead of showing stale entries.
  property int manageRevision: 0

  // Staged drawer membership while the edit menu is open: toggling a checkbox
  // only changes this list, so nothing moves or persists until the user leaves
  // the menu. Leaving commits the diff and restarts the shell if it changed.
  property var pendingDrawerIds: []

  function isPending(id) {
    return root.pendingDrawerIds.indexOf(String(id || "")) !== -1
  }

  function togglePending(id) {
    var key = String(id || "")
    if (!key) return
    var list = root.pendingDrawerIds.slice()
    var idx = list.indexOf(key)
    if (idx === -1) list.push(key)
    else list.splice(idx, 1)
    root.pendingDrawerIds = list
  }

  // --- view + hide state -----------------------------------------------------

  property string viewMode: root.entrySetting("viewMode", "grid") === "list" ? "list" : "grid"
  property bool showHidden: false

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string ffont: root.bar ? root.bar.fontFamily : Style.font.family

  // Window scaling is a sub-setting on the drawer entry (`scale` now expressed
  // as 10%-100% of the screen width); the sizing math is unchanged, just the
  // allowed range. Default 50% matches the previous behaviour.
  property real windowScale: Math.max(0.1, Math.min(1.0, root.entrySetting("scale", 0.5)))
  property int gridColumnSetting: Math.max(1, Math.round(root.entrySetting("gridColumns", 3)))

  readonly property int tileSize: Style.space(64)
  readonly property int tileGap: Style.space(10)
  readonly property int tileHeight: Style.space(74)
  // The card tops out here and the body scrolls past it.
  readonly property real maxBodyHeight: Math.max(Style.space(80),
    menuPopup.fittedContentHeight(Style.space(480)) - menuPopup.verticalContentInset - headerRow.height - menuColumn.spacing)
  readonly property int listIconSize: Style.space(40)
  readonly property int listRowHeight: 30

  FontMetrics {
    id: listMetrics
    font.family: root.ffont
    font.pixelSize: Style.font.bodySmall
  }

  // Columns and stretched cell width derived from the actual grid width, so the
  // tiles fill the row instead of leaving a gap on the right.
  readonly property int gridCols: Math.max(1, root.gridColumnSetting)
  readonly property real gridCellW: {
    var cols = root.gridCols
    if (cols < 1) cols = 1
    var w = drawerGrid.width
    if (w <= 0) return root.tileSize
    return (w - (cols - 1) * root.tileGap) / cols
  }

  // Plugin ids the user has hidden from the drawer view (a subset of the
  // configured drawer widgets). They stay mounted but are not shown unless
  // showHidden is on. Persisted on the drawer entry as `hidden`.
  readonly property var hiddenViewIds: {
    var rev = root.manageRevision
    void rev
    return Drawer.cleanIds(root.settings.hidden)
  }

  // Configured widgets that are not hidden from the view.
  readonly property var drawerVisibleIds: {
    var hv = {}
    var h = root.hiddenViewIds
    for (var i = 0; i < h.length; i++) hv[h[i]] = true
    var out = []
    var cfg = root.configuredIds
    for (var j = 0; j < cfg.length; j++) {
      var cid = cfg[j]
      if (!root.registryWidgets[cid]) continue
      if (!hv[cid]) out.push(cid)
    }
    return out
  }

  // What the drawer actually renders: visible widgets first, then (only while
  // showHidden is on) the hidden ones, dimmed, so they can be unhidden.
  readonly property var drawerDisplayIds: {
    var out = []
    var vis = root.drawerVisibleIds
    for (var i = 0; i < vis.length; i++) out.push({ id: vis[i], hidden: false })
    if (root.showHidden) {
      var hv = root.hiddenViewIds
      var cfgSet = {}
      for (var c = 0; c < root.configuredIds.length; c++) cfgSet[root.configuredIds[c]] = true
      for (var k = 0; k < hv.length; k++) {
        if (!root.registryWidgets[hv[k]]) continue
        if (cfgSet[hv[k]]) out.push({ id: hv[k], hidden: true })
      }
    }
    return out
  }

  function isHiddenView(id) {
    return root.hiddenViewIds.indexOf(String(id || "")) !== -1
  }

  function persistHidden(list) {
    root.persistOwnSettings({ hidden: list.slice() })
  }

  function toggleHiddenView(id) {
    var key = String(id || "")
    if (!key) return
    var list = root.hiddenViewIds.slice()
    var idx = list.indexOf(key)
    if (idx === -1) list.push(key)
    else list.splice(idx, 1)
    root.persistHidden(list)
    root.manageRevision++
  }

  function pluginGlyph(id) {
    var name = root.displayName(id)
    if (!name) return "\uf1b2"
    return name.charAt(0).toUpperCase()
  }

  // Generic reader for a sub-setting stored on the drawer's own entry in the
  // bar layout config. `root.settings` is this plugin's own injected inline
  // config, kept current by the host regardless of capability scoping.
  function entrySetting(name, fallback) {
    var rev = root.manageRevision
    void rev
    if (root.settings && name in root.settings
        && root.settings[name] !== undefined && root.settings[name] !== null)
      return root.settings[name]
    return fallback
  }

  // Persists a change to the drawer's own bar-layout entry. updateEntryInline
  // is the one write path a bar-widget plugin has, scoped to its own entry, and
  // it replaces the whole entry.
  function persistOwnSettings(overrides) {
    var shell = root.bar && root.bar.shell
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    return shell.updateEntryInline(root.moduleName, Drawer.mergedSettings(root.settings, overrides))
  }

  function persistEntrySetting(name, value) {
    var o = ({})
    o[name] = value
    root.persistOwnSettings(o)
  }

  function setViewMode(mode) {
    root.viewMode = mode
    root.persistEntrySetting("viewMode", mode)
  }

  function setGridColumns(n) {
    n = Math.max(1, Math.min(8, Math.round(n)))
    if (n === root.gridColumnSetting) return
    root.gridColumnSetting = n
    root.persistEntrySetting("gridColumns", n)
    root.manageRevision++
  }

  function setWindowScale(n) {
    n = Math.max(0.1, Math.min(1.0, Math.round(n * 100) / 100))
    if (Math.abs(n - root.windowScale) < 0.001) return
    root.windowScale = n
    root.persistEntrySetting("scale", n)
    root.manageRevision++
  }

  // The component the widget renders in the bar. Used as the tile's live
  // preview so the grid shows the plugin's real bar appearance, falling back
  // to the first-letter monogram when there is no component.
  function widgetComponent(c) {
    var entry = root.registryWidgets[String(c || "")]
    return entry && entry.component ? entry.component : null
  }

  // The list hugs its longest row. The grid and the edit view follow the scale
  // setting, so its controls change something visible.
  function drawerContentWidth() {
    if (root.viewMode === "list" && !root.manageMode) {
      var widths = root.drawerDisplayIds.map(function(row) {
        return listMetrics.advanceWidth(root.displayName(row.id))
      })
      var chrome = root.listIconSize + Style.space(24) + (menuPopup.padding + Style.space(2)) * 2
      return menuPopup.fittedContentWidth(Drawer.listWidth(widths, chrome, Style.space(240), Style.space(460)))
    }
    var avail = menuPopup.availableCardWidth
    if (!avail || avail <= 0) avail = Style.space(560)
    return menuPopup.fittedContentWidth(Math.max(avail * root.windowScale, Style.space(380)))
  }

  // Move every staged difference between the drawer and the bar, in one write.
  // The host sees the file change and reloads, which updates the lists.
  function commitDrawerChanges() {
    if (!root.manageMode || moveProcess.running) return
    var moves = Drawer.moveArgs(root.configuredIds, root.pendingDrawerIds)
    if (moves.length === 0) return
    var script = decodeURIComponent(Qt.resolvedUrl("scripts/move-widgets.sh").toString().replace("file://", ""))
    moveProcess.command = ["bash", script, root.moduleName].concat(moves)
    moveProcess.running = true
  }

  Process {
    id: moveProcess
    onExited: function(code) {
      if (code === 0) return
      root.pendingDrawerIds = root.configuredIds.slice()
      Quickshell.execDetached(["notify-send", "Omarchy Drawer Redux", "Could not move those widgets. Nothing was changed."])
    }
  }

  // In-drawer drag state: the id being dragged and the insertion index (before
  // that row).
  property string dragId: ""
  property bool dragActive: false
  property bool dragStarted: false
  property int dragTargetIndex: -1
  property real dragGhostX: 0
  property real dragGhostY: 0
  readonly property real dragThreshold: Style.space(6)

  function dragStart(id) {
    root.dragId = id
    root.dragActive = true
    root.dragStarted = false
    root.dragTargetIndex = -1
  }

  function dragMove(handle, mouseX, mouseY) {
    root.dragStarted = true
    var count = root.drawerVisibleIds.length
    if (root.viewMode === "grid") {
      var cellW = root.gridCellW + root.tileGap
      var cellH = root.tileHeight + root.tileGap
      var local = drawerGrid.mapFromItem(handle, mouseX, mouseY)
      var drop = Drawer.gridDrop(local.x, local.y, cellW, cellH, root.gridCols, count)
      root.dragTargetIndex = drop.index
      root.dragGhostX = drop.col * cellW
      root.dragGhostY = drop.row * cellH
    } else {
      var pitch = root.listRowHeight + Style.space(4)
      var rowY = drawerColumn.mapFromItem(handle, mouseX, mouseY).y
      root.dragTargetIndex = Drawer.listDrop(rowY, pitch, count)
      root.dragGhostX = 0
      // The ghost snaps to the slot it will land in so the drop position is
      // obvious instead of trailing the cursor.
      root.dragGhostY = Math.max(0, Math.min(count - 1, root.dragTargetIndex)) * pitch
    }
  }

  function dragEnd() {
    var id = root.dragId
    var targetIndex = root.dragTargetIndex
    root.dragCancel()
    if (id) root.moveWidgetToIndex(id, targetIndex)
  }

  function dragCancel() {
    root.dragId = ""
    root.dragActive = false
    root.dragStarted = false
    root.dragTargetIndex = -1
  }

  function open() {
    root.pendingDrawerIds = root.configuredIds.slice()
    root.cursorIndex = -1
    root.grabPreviews()
    root.menuOpen = true
    root.manageMode = false
  }

  // Keyboard cursor over whatever the card is showing.
  property int cursorIndex: -1
  onManageModeChanged: root.cursorIndex = -1
  onViewModeChanged: root.cursorIndex = -1

  function moveCursor(dx, dy) {
    var grid = !root.manageMode && root.viewMode === "grid"
    var cols = grid ? root.gridCols : 1
    var count = root.manageMode ? root.allPlugins.length : root.drawerDisplayIds.length
    root.cursorIndex = Drawer.moveCursor(root.cursorIndex, grid ? dx : 0, dy, cols, count)
    if (root.cursorIndex < 0) return
    var pitch = root.manageMode ? 34 + Style.space(4)
      : (grid ? root.tileHeight + root.tileGap : root.listRowHeight + Style.space(4))
    var row = grid ? Math.floor(root.cursorIndex / cols) : root.cursorIndex
    bodyFlick.contentY = Drawer.scrollTo(bodyFlick.contentY, row * pitch, pitch, bodyFlick.height)
  }

  function activateCursor() {
    if (root.cursorIndex < 0) return
    if (root.manageMode) {
      var id = root.allPlugins[root.cursorIndex]
      if (root.widgetComponent(id)) root.togglePending(id)
      return
    }
    var row = root.drawerDisplayIds[root.cursorIndex]
    if (!row) return
    if (row.hidden) root.toggleHiddenView(row.id)
    else root.openWidget(row.id)
  }
  function toggle() {
    if (root.menuOpen) root.close()
    else root.open()
  }
  function close() {
    root.commitDrawerChanges()
    root.menuOpen = false
    root.manageMode = false
    root.manageRevision++
  }
  function closeForPopoutSwitch() {
    root.close()
  }
  function leaveManageMode() {
    root.commitDrawerChanges()
    root.manageMode = false
    root.manageRevision++
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Invisible host at the button's spot. Each hidden widget stays mounted here
  // (not on the bar) so its panel anchors to the bar window and opens right
  // underneath the drawer when picked from the menu.
  Item {
    id: hiddenHost
    anchors.fill: button
    // These widgets stay live, so the stack is shown only while grabbing, as an
    // invisible item cannot be grabbed. Left visible, they take the button's
    // clicks through the bar's click targets.
    visible: root.pendingGrabs > 0
    opacity: 0

    Repeater {
      model: root.hiddenIds
      DrawerWidget {}
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0c9"
    tooltipText: "Omarchy Drawer Redux"
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }

  // Mounted hidden widget instances, keyed by id, so menu rows can toggle
  // their panels.
  property var mountedMap: ({})

  function registerMounted(id, item) {
    var m = root.mountedMap
    m[id] = item
    root.mountedMap = m
  }

  function unregisterMounted(id) {
    var m = root.mountedMap
    delete m[id]
    root.mountedMap = m
  }

  function mountedItem(id) {
    return root.mountedMap[id]
  }

  function openWidget(id) {
    var w = root.mountedItem(id)
    if (w) {
      // Panel-style widgets and most clones expose a root toggle().
      if (typeof w.toggle === "function") {
        w.toggle()
      } else if ("popupOpen" in w) {
        // Widgets that own a popupOpen boolean (prayer-times, kanban, ...).
        w.popupOpen = !w.popupOpen
      } else if ("opened" in w && typeof w.open === "function" && typeof w.close === "function") {
        if (w.opened) w.close()
        else w.open()
      } else if ("menuOpen" in w && typeof w.open === "function" && typeof w.close === "function") {
        if (w.menuOpen) w.close()
        else w.open()
      } else if (typeof w.open === "function" && typeof w.close === "function") {
        // Plain open/close pair with no exposed state property.
        w.open()
      }
    }
    root.menuOpen = false
    root.manageMode = false
  }

  component DrawerWidget: Item {
    id: slot
    required property int index
    required property var modelData
    readonly property string widgetId: String(modelData || "")
    readonly property var component: root.registryWidgets[widgetId] ? root.registryWidgets[widgetId].component : null

    implicitWidth: loader.item ? loader.item.implicitWidth : button.implicitWidth
    implicitHeight: loader.item ? loader.item.implicitHeight : button.implicitHeight

    Loader {
      id: loader
      anchors.fill: parent
      sourceComponent: slot.component
      onLoaded: {
        var w = loader.item
        if (!w) return
        if ("bar" in w) w.bar = Qt.binding(function() { return root.bar })
        if ("moduleName" in w) w.moduleName = slot.widgetId
        if ("settings" in w) w.settings = Object.assign({}, root.defaultsFor(slot.widgetId), (root.settings.parked || {})[slot.widgetId])
        // Panel-style widgets anchor their panel to this item; point them at
        // the drawer button (in the bar window) so the panel opens underneath
        // the drawer.
        if ("anchorItem" in w) w.anchorItem = button
        root.registerMounted(slot.widgetId, w)
      }
    }

    Component.onDestruction: {
      if (root) root.unregisterMounted(slot.widgetId)
    }
  }

  // How a widget looks on the bar, as a picture of the mounted instance. A live
  // copy would double its IPC handlers, and its panel cannot anchor inside the
  // card's window.
  property var previewGrabs: ({})
  property int pendingGrabs: 0

  function grabPreviews() {
    var ids = Object.keys(root.mountedMap)
    root.pendingGrabs = ids.length
    grabTimeout.restart()
    for (var i = 0; i < ids.length; i++) root.grabPreview(ids[i])
  }

  function grabPreview(id) {
    var w = root.mountedItem(id)
    var started = w && w.width > 0 && w.height > 0 && w.grabToImage(function(result) {
      var next = Object.assign({}, root.previewGrabs)
      next[id] = result
      root.previewGrabs = next
      root.pendingGrabs = Math.max(0, root.pendingGrabs - 1)
    })
    if (!started) root.pendingGrabs = Math.max(0, root.pendingGrabs - 1)
  }

  // A widget destroyed mid-grab never calls back, and the stack must not stay up.
  Timer {
    id: grabTimeout
    interval: 500
    onTriggered: root.pendingGrabs = 0
  }

  component WidgetPreview: Item {
    id: previewBox
    required property string widgetId
    readonly property var grab: root.previewGrabs[previewBox.widgetId] || null
    clip: true

    Image {
      id: previewImage
      anchors.centerIn: parent
      width: Math.min(implicitWidth, previewBox.width)
      height: Math.min(implicitHeight, previewBox.height)
      fillMode: Image.PreserveAspectFit
      source: previewBox.grab ? previewBox.grab.url : ""
    }

    Text {
      textFormat: Text.PlainText
      visible: previewImage.status !== Image.Ready
      anchors.fill: parent
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: root.pluginGlyph(previewBox.widgetId)
      color: root.fg
      font.family: root.ffont
      font.pixelSize: Math.round(previewBox.height * 0.6)
      font.bold: true
    }
  }

  // --- menu ------------------------------------------------------------------

  KeyboardPanel {
    id: menuPopup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.menuOpen
    focusTarget: keyCatcher
    contentWidth: root.drawerContentWidth()
    contentHeight: menuPopup.fittedContentHeight(menuColumn.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()

      Column {
        id: menuColumn
        anchors.fill: parent
        spacing: Style.space(6)

  Item {
            id: headerRow
            width: menuColumn.width
            implicitHeight: 32

            Row {
              id: titleGroup
              visible: !root.manageMode
              anchors.verticalCenter: parent.verticalCenter
              anchors.left: parent.left
              anchors.right: viewModeButton.left
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(10)
              clip: true

              Text {
                textFormat: Text.PlainText
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                text: "Omarchy Drawer Redux"
                color: root.fg
                font.family: root.ffont
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }
            }

            Row {
              id: manageControls
              visible: root.manageMode
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(12)

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Grid"
                  color: root.fg
                  font.family: root.ffont
                  font.pixelSize: Style.font.caption
                }

                Button {
                  width: 20
                  height: 18
                  text: "-"
                  horizontalPadding: 0
                  verticalPadding: 0
                  fontSize: 12
                  tooltipText: "Smaller grid"
                  onClicked: root.setGridColumns(root.gridColumnSetting - 1)
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(44)
                  horizontalAlignment: Text.AlignHCenter
                  text: root.gridColumnSetting + "x" + root.gridColumnSetting
                  color: root.fg
                  font.family: root.ffont
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Button {
                  width: 20
                  height: 18
                  text: "+"
                  horizontalPadding: 0
                  verticalPadding: 0
                  fontSize: 12
                  tooltipText: "Larger grid"
                  onClicked: root.setGridColumns(root.gridColumnSetting + 1)
                }
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Window"
                  color: root.fg
                  font.family: root.ffont
                  font.pixelSize: Style.font.caption
                }

                Button {
                  width: 20
                  height: 18
                  text: "-"
                  horizontalPadding: 0
                  verticalPadding: 0
                  fontSize: 12
                  tooltipText: "Smaller window"
                  onClicked: root.setWindowScale(root.windowScale - 0.1)
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(40)
                  horizontalAlignment: Text.AlignHCenter
                  text: Math.round(root.windowScale * 100) + "%"
                  color: root.fg
                  font.family: root.ffont
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Button {
                  width: 20
                  height: 18
                  text: "+"
                  horizontalPadding: 0
                  verticalPadding: 0
                  fontSize: 12
                  tooltipText: "Larger window"
                  onClicked: root.setWindowScale(root.windowScale + 0.1)
                }
              }
            }

            Button {
              id: viewModeButton
              visible: !root.manageMode
              anchors.right: eyeButton.left
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              text: root.viewMode === "grid" ? "\uf0ca" : "\uf009"
              tooltipText: root.viewMode === "grid" ? "Switch to list view" : "Switch to grid view"
              foreground: root.fg
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: root.setViewMode(root.viewMode === "grid" ? "list" : "grid")
            }

            Button {
              id: eyeButton
              visible: !root.manageMode
              anchors.right: penButton.left
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              text: root.showHidden ? "\uf06e" : "\uf070"
              tooltipText: root.showHidden ? "Hide hidden plugins" : "Show hidden plugins"
              foreground: root.showHidden ? Color.accent : root.fg
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: root.showHidden = !root.showHidden
            }

            Button {
              id: penButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf040"
              foreground: root.fg
              horizontalPadding: 8
              verticalPadding: 3
              fontSize: Style.font.bodySmall
              onClicked: {
                if (root.manageMode) {
                  root.leaveManageMode()
                } else {
                  root.pendingDrawerIds = root.configuredIds.slice()
                  root.manageMode = true
                }
              }
            }
          }

         Flickable {
          id: bodyFlick
          width: menuColumn.width
          height: Math.min(contentHeight, root.maxBodyHeight)
          contentWidth: width
          contentHeight: root.manageMode ? manageColumn.implicitHeight : (root.viewMode === "grid" ? drawerGrid.implicitHeight : drawerColumn.implicitHeight)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: drawerColumn
            visible: !root.manageMode && root.viewMode === "list"
            width: bodyFlick.width
            spacing: Style.space(4)

            Repeater {
              model: root.drawerDisplayIds

              delegate: Item {
                id: drow
                required property int index
                required property var modelData
                width: drawerColumn.width
                implicitHeight: root.listRowHeight

                readonly property string rowId: drow.modelData.id
                readonly property bool isHiddenItem: drow.modelData.hidden
                property real pressX: 0
                property real pressY: 0
                property bool dragged: false

                opacity: (root.dragId === drow.rowId ? 0.4 : 1.0) * (drow.isHiddenItem ? 0.5 : 1.0)

                Rectangle {
                  anchors.fill: parent
                  radius: Math.max(2, Style.cornerRadius)
                  color: root.dragActive && root.dragTargetIndex === drow.index
                    ? Util.alpha(Color.accent, 0.18)
                    : (!root.dragActive && (drowMouse.containsMouse || root.cursorIndex === drow.index)
                        ? Style.hoverFillFor(root.fg, root.fg)
                        : "transparent")
                }

                Rectangle {
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: 3
                  radius: 1.5
                  color: Color.accent
                  visible: root.dragActive && root.dragId !== drow.rowId && root.dragTargetIndex === drow.index
                }

                WidgetPreview {
                  id: drowIcon
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Style.space(4)
                  width: root.listIconSize
                  widgetId: drow.rowId
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: drowIcon.right
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  text: root.displayName(drow.rowId)
                  color: root.fg
                  font.family: root.ffont
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                MouseArea {
                  id: drowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: root.dragStarted ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                  onPressed: function(mouse) {
                    drow.dragged = false
                    if (drow.isHiddenItem || root.showHidden) return
                    drow.pressX = mouse.x
                    drow.pressY = mouse.y
                    root.dragStart(drow.rowId)
                  }

                  onPositionChanged: function(mouse) {
                    if (!(mouse.buttons & Qt.LeftButton)) return
                    if (!drow.dragged && (Math.abs(mouse.x - drow.pressX) + Math.abs(mouse.y - drow.pressY)) >= root.dragThreshold)
                      drow.dragged = true
                    if (drow.dragged) root.dragMove(drowMouse, mouse.x, mouse.y)
                  }

                  onReleased: {
                    if (root.dragActive) root.dragEnd()
                  }

                  onCanceled: {
                    root.dragCancel()
                  }

                  onClicked: {
                    if (!drow.dragged) {
                      if (drow.isHiddenItem) root.toggleHiddenView(drow.rowId)
                      else root.openWidget(drow.rowId)
                    }
                  }
                }
              }
            }

            Item {
              width: drawerColumn.width
              implicitHeight: Style.space(10)

                Rectangle {
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: 3
                  radius: 1.5
                  color: Color.accent
                  visible: root.dragActive && root.dragTargetIndex === root.drawerVisibleIds.length
                }
              }

              Text {
                textFormat: Text.PlainText
                visible: root.configuredIds.length === 0
                width: drawerColumn.width
                text: "No widgets hidden."
                color: Qt.darker(root.fg, 1.5)
                font.family: root.ffont
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }
          }

          Flow {
            id: drawerGrid
            visible: !root.manageMode && root.viewMode === "grid"
            width: bodyFlick.width
            spacing: root.tileGap
            flow: Flow.LeftToRight

            Repeater {
              model: root.drawerDisplayIds

              delegate: Item {
                id: gtile
                required property int index
                required property var modelData
                width: root.gridCellW
                height: root.tileHeight

                readonly property string rowId: gtile.modelData.id
                readonly property bool isHiddenItem: gtile.modelData.hidden
                readonly property bool isDragTarget: root.dragActive && root.dragId !== gtile.rowId && root.dragTargetIndex === gtile.index
                property real pressX: 0
                property real pressY: 0
                property bool dragged: false

                opacity: (root.dragId === gtile.rowId ? 0.4 : 1.0) * (gtile.isHiddenItem ? 0.5 : 1.0)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: gtile.isDragTarget
                    ? Util.alpha(Color.accent, 0.18)
                    : (gtileMouse.containsMouse || root.cursorIndex === gtile.index ? Style.hoverFillFor(root.fg, root.fg) : "transparent")
                }

                Rectangle {
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  height: 3
                  radius: 1.5
                  color: Color.accent
                  visible: gtile.isDragTarget
                }

                Text {
                  textFormat: Text.PlainText
                  id: label
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(6)
                  width: parent.width - Style.space(8)
                  horizontalAlignment: Text.AlignHCenter
                  text: root.displayName(gtile.rowId)
                  color: root.fg
                  font.family: root.ffont
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                }

                WidgetPreview {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.bottom: label.top
                  anchors.bottomMargin: Style.space(2)
                  widgetId: gtile.rowId
                }

                MouseArea {
                  id: gtileMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: root.dragStarted ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                  onPressed: function(mouse) {
                    gtile.dragged = false
                    if (gtile.isHiddenItem || root.showHidden) return
                    gtile.pressX = mouse.x
                    gtile.pressY = mouse.y
                    root.dragStart(gtile.rowId)
                  }

                  onPositionChanged: function(mouse) {
                    if (!(mouse.buttons & Qt.LeftButton)) return
                    if (!gtile.dragged && (Math.abs(mouse.x - gtile.pressX) + Math.abs(mouse.y - gtile.pressY)) >= root.dragThreshold)
                      gtile.dragged = true
                    if (gtile.dragged) root.dragMove(gtileMouse, mouse.x, mouse.y)
                  }

                  onReleased: {
                    if (root.dragActive) root.dragEnd()
                  }

                  onCanceled: {
                    root.dragCancel()
                  }

                  onClicked: {
                    if (!gtile.dragged) {
                      if (gtile.isHiddenItem) root.toggleHiddenView(gtile.rowId)
                      else root.openWidget(gtile.rowId)
                    }
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.configuredIds.length === 0
              width: drawerGrid.width
              text: "No widgets hidden."
              color: Qt.darker(root.fg, 1.5)
              font.family: root.ffont
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }

          Column {
            id: manageColumn
            visible: root.manageMode
            width: bodyFlick.width
            spacing: Style.space(4)

            Repeater {
              model: root.allPlugins

              delegate: Item {
                id: mrow
                required property int index
                required property string modelData
                width: manageColumn.width
                implicitHeight: 34

                readonly property string rowId: mrow.modelData
                readonly property bool isWidget: root.widgetComponent(mrow.rowId) !== null
                readonly property bool checked: root.isPending(mrow.rowId)

                Rectangle {
                  anchors.fill: parent
                  radius: Math.max(2, Style.cornerRadius)
                  color: mrowMouse.containsMouse || root.cursorIndex === mrow.index
                    ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, root.bar ? root.bar.foreground : Color.foreground)
                    : "transparent"
                }

                BorderSurface {
                  id: checkbox
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  width: Style.space(16)
                  height: Style.space(16)
                  radius: Math.max(2, Style.cornerRadius / 2)
                  visible: mrow.isWidget
                  color: mrow.checked
                    ? Style.selectedFillFor(root.bar ? root.bar.foreground : Color.foreground, root.bar ? root.bar.foreground : Color.foreground)
                    : "transparent"
                  borderSpec: mrow.checked
                    ? Border.controlSpec("selected", root.bar ? root.bar.foreground : Color.foreground, Color.accent)
                    : Border.controlSpec("normal", root.bar ? root.bar.foreground : Color.foreground, Color.accent)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: mrow.checked
                    text: "\u2713"
                    color: Style.selectedStateColor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Math.round(checkbox.height * 0.85)
                    font.bold: true
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: checkbox.right
                  anchors.right: rowActions.left
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  text: root.displayName(mrow.rowId)
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.italic: mrow.checked
                  elide: Text.ElideRight
                }

                MouseArea {
                  id: mrowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (mrow.isWidget) root.togglePending(mrow.rowId)
                  }
                }

                Row {
                  id: rowActions
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Button {
                    width: 24
                    height: 24
                    visible: root.configuredIds.indexOf(mrow.rowId) !== -1
                    text: root.isHiddenView(mrow.rowId) ? "\uf070" : "\uf06e"
                    tooltipText: root.isHiddenView(mrow.rowId) ? "Hidden: click to show in drawer" : "Hide from drawer"
                    foreground: root.isHiddenView(mrow.rowId) ? Color.accent : (root.bar ? root.bar.foreground : Color.foreground)
                    horizontalPadding: 0
                    verticalPadding: 0
                    onClicked: root.toggleHiddenView(mrow.rowId)
                  }

                }
              }
            }

          }

          Rectangle {
            id: dragGhost
            visible: root.dragActive
            z: 20
            x: root.dragGhostX
            y: root.dragGhostY
            width: root.viewMode === "grid" ? root.gridCellW : drawerColumn.width
            height: root.viewMode === "grid" ? root.tileHeight : root.listRowHeight
            radius: Math.max(2, Style.cornerRadius)
            color: Util.alpha(Color.accent, 0.25)
            border.width: 1.5
            border.color: Color.accent

            Text {
              textFormat: Text.PlainText
              id: dragGhostText
              anchors.fill: parent
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              horizontalAlignment: root.viewMode === "grid" ? Text.AlignHCenter : Text.AlignLeft
              verticalAlignment: Text.AlignVCenter
              text: root.displayName(root.dragId)
              color: root.fg
              font.family: root.ffont
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }

  // --- persistence -----------------------------------------------------------

  function persistWidgets(list) {
    root.persistOwnSettings({ widgets: list.slice() })
  }

  function moveWidgetToIndex(id, toIndex) {
    var list = root.configuredIds
    var next = Drawer.reorder(list, root.drawerVisibleIds, id, toIndex)
    if (next !== list) root.persistWidgets(next)
  }
}
