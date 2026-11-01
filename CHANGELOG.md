# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Removed
- Enable, disable and remove buttons in the edit view. Omarchy no longer gives
  bar widgets the access they needed, and `omarchy plugin` does all three.

### Fixed
- Hosted widgets get the drawer button as their anchor. They were getting
  nothing, because of a bad reference.
- Dragging lands where it shows: rows in the grid, and with hidden widgets in the
  list, no longer put a widget in the wrong slot.
- The edit list and widget scanning see every bar section, not just left, center
  and right.

## [0.9.0] - 2026-11-01

First development version of Redux. Numbering restarts here because the new
plugin id has no update path from Plugin Drawer; 1.0.0 will be the first public
release.

### Changed
- Continued as Omarchy Drawer Redux under Huey Holdings LLC, with the new plugin
  id `io.github.huey-holdings-llc.omarchy-drawer-redux`.
- Removing a plugin now calls `omarchy-plugin-remove` instead of a generated
  shell script.

### Fixed
- Works on Omarchy 4.0.3 and later: the drawer reads the widget registry through
  its own service, and settings and the edit checklist work again.
- Panels hosted in the drawer keep their bar reference when the bar rebuilds. It
  used to go null after a monitor change, and new rows in the Bluetooth panel
  rendered black on a dark background.
- All text renders as plain text, so a plugin name cannot inject markup.

## [1.2.0] - 2026-09-12

The last version of Plugin Drawer by Aly Sarhan, the starting point for this
project.
