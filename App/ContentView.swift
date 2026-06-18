import SwiftUI
import WidgetKit

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @AppStorage("themeMode") private var themeMode: String = "dark"

    var body: some View {
        TabView {
            Tab("Ana Sayfa", systemImage: "house.fill") {
                HomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
            }

            Tab("Alıştırmalar", systemImage: "brain.head.profile") {
                QuizView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
            }

            Tab("Düello", systemImage: "bolt.horizontal.fill") {
                DuelsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
            }

            Tab("Kelimelerim", systemImage: "books.vertical.fill") {
                LibraryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
            }

            Tab("Seviyeler", systemImage: "chart.bar.fill") {
                LevelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
            }

            Tab("Ayarlar", systemImage: "gearshape.fill") {
                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
            }
        }
        .environmentObject(authManager)
        .preferredColorScheme(themeMode == "light" ? .light : themeMode == "dark" ? .dark : nil)
    }
}
