# Smart Calendar Classifier
Mac app that uses onboard Apple Intelligence to add events to your calendar based on the context surrounding them. Their name, place, date, date range, time, etc. All automatically populated.

See [PLAN.md](PLAN.md) for decisions, architecture and roadmap.

## Requirements
- macOS 26+ with Apple Intelligence enabled (falls back to a basic date detector otherwise)
- Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build & run
```bash
xcodegen generate            # creates SmartCalendarClassifier.xcodeproj from project.yml
open SmartCalendarClassifier.xcodeproj
```

## Tests
The extraction engine lives in `Packages/SmartCalendarCore` and is tested on its own:
```bash
cd Packages/SmartCalendarCore && swift test
```
`Model fixtures` runs real texts from `Tests/SmartCalendarCoreTests/Fixtures/extraction-cases.json`
through the on-device model (skipped when Apple Intelligence is unavailable). Add a case there
whenever the app misreads something.
