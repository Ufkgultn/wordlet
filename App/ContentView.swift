import SwiftUI
import WidgetKit

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @AppStorage("themeMode") private var themeMode: String = "dark"

    var body: some View {
        ZStack {
            TabView {
                HomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
                    .tabItem {
                        Label("Ana Sayfa", systemImage: "house.fill")
                    }

                QuizView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
                    .tabItem {
                        Label("Alıştırmalar", systemImage: "brain.head.profile")
                    }

                DuelsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
                    .tabItem {
                        Label("Düello", systemImage: "bolt.horizontal.fill")
                    }

                LibraryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
                    .tabItem {
                        Label("Kelimelerim", systemImage: "books.vertical.fill")
                    }

                LevelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
                    .tabItem {
                        Label("Seviyeler", systemImage: "chart.bar.fill")
                    }

                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
                    .tabItem {
                        Label("Ayarlar", systemImage: "gearshape.fill")
                    }
            }
            .environmentObject(authManager)
            .preferredColorScheme(themeMode == "light" ? .light : themeMode == "dark" ? .dark : nil)
            
            InAppNotificationBanner()
        }
    }
}
