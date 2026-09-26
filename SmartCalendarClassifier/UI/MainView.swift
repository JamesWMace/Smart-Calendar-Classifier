import SwiftUI

/// The window the menu bar icon opens: what's been added, and a playground.
struct MainView: View {
    enum Page: Hashable { case history, tryIt }

    @State private var page = Page.history

    var body: some View {
        TabView(selection: $page) {
            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryView()
            }
            Tab("Try It", systemImage: "text.cursor", value: .tryIt) {
                TryItView()
            }
        }
        .frame(minWidth: 620, minHeight: 520)
    }
}
