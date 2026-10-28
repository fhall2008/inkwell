import SwiftUI

@main
struct InkwellApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}
