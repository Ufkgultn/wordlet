import SwiftUI
import Supabase

@main
struct DailyWordWidgetApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task {
                        do {
                            _ = try await SupabaseManager.shared.client.auth.session(from: url)
                            await AuthManager.shared.restoreSession()
                        } catch {
                            print("Error handling auth callback: \(error)")
                        }
                    }
                }
        }
    }
}
