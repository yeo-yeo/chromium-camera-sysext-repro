import SwiftUI

@main
struct ChromiumFeedbackApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}
