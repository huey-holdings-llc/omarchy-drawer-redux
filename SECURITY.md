# Security

## Supported versions

The latest tagged release is the only one that gets fixes. There are no
maintenance branches: a security fix goes out as the next patch release, and
`omarchy plugin update io.github.huey-holdings-llc.omarchy-drawer-redux` is how
you get it. Older tags are kept for reference and are not patched.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting on this repository
(Security tab, "Report a vulnerability") rather than a public issue, so a fix
can ship before the details are out. If you cannot use that, open an issue
saying only that you have a security report and how to reach you.

You can expect an acknowledgement within a few days. This is a part-time
project, but a confirmed vulnerability will be fixed and released ahead of any
other work.

## What counts

Anything that executes code from data (a plugin id, name or manifest field), and
anything that deletes or overwrites files other than the plugin a user chose to
remove.

## Scope notes

Quickshell and the Omarchy shell are separate projects; issues in them should go
upstream, though a report here that helps route the problem is still welcome.
Plugins hosted in the drawer are their authors' responsibility.
