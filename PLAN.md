# Smart Calendar Classifier — Plan

Highlight text anywhere on the Mac → press a hotkey (or right-click → Services) → Apple's
on-device model reads the selection *and its surroundings* → an editable preview appears →
the event lands in Apple Calendar.

## Decisions

| # | Topic | Decision |
|---|-------|----------|
| 1 | App shape | Menu bar app (menu bar icon, no Dock icon). Left-click the icon opens the app window; right-click shows capture / last result / Settings / Quit. Stays alive with no windows open; idle cost ≈ zero (no timers, model loaded only on demand). |
| 2 | Distribution | Personal first → notarized download from GitHub later → Mac App Store long-term. **Not sandboxed** for now (Accessibility API needs it). |
| 3 | Triggers | Global hotkey **and** Services menu **and** an App Intent (Shortcuts/Spotlight). |
| 4 | Context | As much as possible: selection, surrounding text of the focused element, app name, window title, page URL, email subject. Trimmed to fit the model's ~4K token window. |
| 5 | Multiple events | Extract all; show a checklist, all checked. |
| 6 | Fields | Title, start/end, all-day, location, notes, URL, alerts, recurrence, time zone. |
| 7 | Missing info | A missing date must be filled in before Save is enabled; the model never guesses one. No stated time → all-day (switchable to timed). No end time → start + default duration, marked as the default length. |
| 8 | Time zones | Converted to local time. Notes keep "Originally 3:00 PM ET". |
| 9 | Notes | AI summary, then the original text, then the source (app / URL). |
| 10 | Calendar | Model suggests one of your calendars by name; full calendar access. |
| 11 | Conflicts | Inline warning in the preview panel. |
| 12 | Confirmation | Always preview. "Trust mode" (save instantly + Undo notification) as a setting. |
| 13 | Panel | Floating panel near the mouse cursor. |
| 14 | After save | Notification with "Open in Calendar". |
| 15 | Min OS | macOS 26+. NSDataDetector-only fallback when Apple Intelligence is unavailable. |
| 16 | Language | English first. |
| 17 | Tests | Deterministic unit tests + fixture-based model tests. |
| 18 | Name | Smart Calendar Classifier (`com.jamesmace.SmartCalendarClassifier`). |

## Architecture

```
SmartCalendarClassifier.app  (SwiftUI + AppKit, thin)
  ├─ Capture/     hotkey, Accessibility reader, Services provider, App Intent
  └─ UI/          preview panel, Try-It window, settings, onboarding
        │
        ▼
Packages/SmartCalendarCore  (pure Swift, unit-tested with `swift test`)
  ├─ Context/     CaptureContext — everything we know about the selection
  ├─ Extraction/  PromptBuilder, FoundationModelsExtractor, DataDetectorExtractor
  ├─ Schema/      @Generable ExtractionResult (what the model fills in)
  ├─ Resolution/  DateResolver, TimeZoneResolver — deterministic date math
  ├─ Model/       EventCandidate (resolved, ready for UI / EventKit), NotesComposer
  └─ Calendar/    CalendarService (permission, calendars, save, undo), EventMapper, ConflictDetector
```

**Key idea:** the ~3B on-device model is good at *understanding* ("this is a midterm, it's next
Tuesday at 3, in Bourns A265") and bad at *calendar arithmetic*. In testing it also left optional
numeric fields (month, day) empty, while reliably copying the right words. So the model returns
**verbatim phrases** (`startDatePhrase: "next Tuesday"`, `timePhrase: "3-5pm"`) and
`DatePhraseParser` / `TimePhraseParser` / `DateResolver` turn them into real dates against a
reference date and time zone. The model's own structured time is only used to settle ambiguous
phrases ("at 7" → dinner → 19:00). Locations and links are dropped unless they appear in the text.
All of that is pure and unit-tested.

## Phases

Status: phases 1–6 done (76 tests passing, incl. 18 on-device model fixtures).

1. **Scaffold** — XcodeGen project, menu bar app lifecycle, core Swift package.
2. **Extraction engine** — schema, prompt, resolvers, fallback extractor, tests, Try-It window.
3. **EventKit** — permission flow, calendar list, save, conflicts, recurrence/alerts mapping.
4. **Capture** — Carbon global hotkey; AX reader (selection, surrounding text, window title,
   `AXURL`/`AXDocument`); ⌘C fallback that restores the clipboard; Services provider; App Intent.
5. **Preview panel** — keyboard-first NSPanel near cursor; required-field gating; multi-event checklist.
6. **Settings & onboarding** — permissions walkthrough, hotkey recorder, defaults, trust mode.
7. **Polish** — notifications, undo, history, app icon, notarized release on GitHub.

## Future ideas
- Resolve relative dates against an email's *sent* date found in surrounding context.
- Travel time, MapKit location lookup, attendees shown as notes.
- Other languages.
