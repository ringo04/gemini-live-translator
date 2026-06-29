import SwiftUI
import SwiftData

@main
struct realtimeTranslationAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [SavedKeyword.self, TranslationSession.self])
        }
    }
}
