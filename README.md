# Smart Calendar Classifier
Mac app that uses onboard Apple Intelligence to add events to your calendar based on the context surrounding them. Their name, place, date, date range, time, etc. All automatically populated.

Highlight text in any app, press **⌃⌥C**, check the events in the panel that appears, and press **Return**. Everything is read on your Mac; nothing is sent anywhere.

See [PLAN.md](PLAN.md) for decisions, architecture and roadmap.

## Install
Requires macOS 26 or later. Apple Intelligence (Apple silicon, turned on in System Settings) is used when available; otherwise a basic date reader fills in what it can.

1. Download `SmartCalendarClassifier-<version>.zip` from [Releases](https://github.com/JamesWMace/Smart-Calendar-Classifier/releases), unzip it, and move **Smart Calendar Classifier** to Applications.
2. Open it. The app isn't notarized by Apple, so macOS blocks the first launch: open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the message about Smart Calendar Classifier. (Or run `xattr -dr com.apple.quarantine "/Applications/Smart Calendar Classifier.app"`.)
3. Follow the setup guide: allow calendar and Accessibility access, and optionally change the shortcut.

The app lives in the menu bar: click its icon for your history of added events, right-click for the menu.

## Build & run
Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
```bash
xcodegen generate            # creates SmartCalendarClassifier.xcodeproj from project.yml
open SmartCalendarClassifier.xcodeproj
```
It builds and runs as-is, signed to run locally. To sign with your own Apple team (so macOS keeps
the app's calendar and Accessibility permissions across rebuilds), copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your team ID; that file is
git-ignored.

## Tests
The extraction engine lives in `Packages/SmartCalendarCore` and is tested on its own:
```bash
cd Packages/SmartCalendarCore && swift test
```
`Model fixtures` runs real texts from `Tests/SmartCalendarCoreTests/Fixtures/extraction-cases.json`
through the on-device model (skipped when Apple Intelligence is unavailable). Add a case there
whenever the app misreads something.

## Release
```bash
scripts/release.sh           # builds, verifies the signature, and zips the app into build/release.noindex/
```
It prints the `gh release create` command to publish the zip. The icon is drawn by
`scripts/make-icon.swift`; run `scripts/make-icon.sh` after changing it.

## License
[MIT](LICENSE)
