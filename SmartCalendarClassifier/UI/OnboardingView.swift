import SmartCalendarCore
import SwiftUI

/// First-launch setup: checks what the app needs, sets the shortcut, and offers a sentence
/// to practise on. Also reachable later from the menu bar icon's menu.
struct OnboardingView: View {
    let done: () -> Void

    private let shortcuts = ShortcutStore.shared
    private let launchAtLogin = LaunchAtLogin.shared
    @State private var practice = "Coffee with Alex next Thursday at 10am at Blue Bottle on Valencia St."

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Smart Calendar Classifier").font(.title2.bold())
                    Text("Highlight text anywhere, press your shortcut, and the events in it go into your calendar. Everything is read on this Mac by Apple Intelligence.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            step(1, "Apple Intelligence", detail: "Reads the dates, times and places in your text.") {
                AppleIntelligenceStatusView()
            }
            step(2, "Calendar", detail: "Lets the app add events and warn you about clashes.") {
                CalendarAccessView()
            }
            step(3, "Accessibility", detail: "Lets the app read the text you highlight, and the text around it, in other apps.") {
                AccessibilityAccessView()
            }
            step(4, "Your shortcut", detail: "Press it with text selected in any app.") {
                ShortcutRecorder()
            }
            step(5, "Try it", detail: "Select the sentence below and press \(shortcuts.shortcut.display).") {
                TextEditor(text: $practice)
                    .font(.body)
                    .frame(height: 44)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary, in: .rect(cornerRadius: 8))
            }

            HStack {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        // Shown automatically once; the menu's Setup Guide… opens it again.
        .onAppear { UserDefaults.standard.set(true, forKey: SettingsKey.onboardingCompleted) }
    }

    private func step(_ number: Int, _ title: String, detail: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                content()
            }
        }
    }
}
