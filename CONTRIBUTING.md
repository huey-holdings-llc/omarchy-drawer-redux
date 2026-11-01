# Contributing to Omarchy Drawer Redux

Thank you for looking at this. This is a part-time hobby project, built with AI
assistance by someone who is not a professional developer. Pull requests from
people who know this territory better are the best thing that can happen to it.
Issues and pull requests are handled as time allows, so please be patient, and
feel free to fork if you would rather move at your own pace.

## Principles

1. **Base Omarchy first.** The plugin works on a fresh Omarchy install with
   nothing added. If a feature needs a new package, it does not go in.
2. **Simplicity and efficiency over features.** No daemons, and nothing running
   while idle.
3. **Follow Omarchy's design and theming.** Use the shell's `qs.Ui` kit and the
   theme tokens (`Color.*`, `Style.*`, `bar.foreground`) rather than hard-coded
   colours, fonts or sizes.
4. **Data is never code.** Commands are argument arrays. `tests/lint.sh` fails
   the build on `bash -c` in QML.
5. **Say what it does.** A README sentence must describe what the code does
   today. If you change behaviour, change the README and the CHANGELOG in the
   same pull request.

## Practical bits

* **Dev loop**: `scripts/dev-sync.sh --enable`, then `omarchy restart shell` for
  QML changes. `bash tests/lint.sh` must pass.
* **Nothing instantiates the QML in CI.** Do not claim a QML change works unless
  you ran it in a shell. For anything touching the bar reference, add and remove
  a monitor (`hyprctl output create headless TEST`, then
  `hyprctl output remove TEST`) and check the journal for `of null`.
* **Commits**: `type(scope): summary`, with `feat`, `fix`, `ux`, `security`,
  `docs` or `chore`. Pull requests target `main`.
