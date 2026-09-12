import QtQuick

// Omarchy 4.0.3 stopped handing a third-party bar widget's `bar` facade a
// widget registry, so the drawer had nothing to mount. The host still injects
// a detached registry snapshot into a plugin's own service (shell.qml
// ensureService), and a widget may look up its own service, so the drawer
// reads the registry from here instead.
QtObject {
  property var barWidgetRegistry: null
}
