import SwiftUI
import WidgetKit

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        TabView {
            Tab("Ana Sayfa", systemImage: "house.fill") {
                HomeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { Theme.backgroundGradient.ignoresSafeArea() }
            }

            Tab("Sınav", systemImage: "brain.head.profile") {
                QuizView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { Theme.backgroundGradient.ignoresSafeArea() }
            }

            Tab("Kelimelerim", systemImage: "books.vertical.fill") {
                LibraryView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { Theme.backgroundGradient.ignoresSafeArea() }
            }

            Tab("Seviyeler", systemImage: "chart.bar.fill") {
                LevelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { Theme.backgroundGradient.ignoresSafeArea() }
            }

            Tab("Ayarlar", systemImage: "gearshape.fill") {
                SettingsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { Theme.backgroundGradient.ignoresSafeArea() }
            }
        }
        .environmentObject(authManager)
        .preferredColorScheme(.dark)
    }
}
