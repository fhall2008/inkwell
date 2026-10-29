import SwiftUI

@main
struct InkwellApp: App {
    @StateObject private var store = Store()
    @StateObject private var account = AccountManager()
    @StateObject private var sync = SyncEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .environmentObject(account)
                .environmentObject(sync)
                .tint(Theme.accent)
                .task {
                    // Connect accounts to syncing, then reopen the saved session if there is one.
                    sync.attach(store: store)
                    account.onSignedIn = { api, master, user in sync.start(api: api, master: master, user: user) }
                    account.onSignedOut = { sync.stop() }
                    sync.onUnauthorized = { account.signOut(message: "Your session has ended. Please sign in again.") }
                    account.restore()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sync.syncNow() }
        }
    }
}
