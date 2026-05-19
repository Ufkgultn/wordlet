import SwiftUI
import WidgetKit

enum MenuOption {
    case home
    case library
    case quiz
    case level
    case settings
}

extension Notification.Name {
    static let menuButtonVisibilityDidChange = Notification.Name("menuButtonVisibilityDidChange")
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        Group {
            MainTabView()
        }
        .environmentObject(authManager)
        .preferredColorScheme(.dark)
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @State private var currentMenu: MenuOption = .home
    @State private var isMenuOpen: Bool = false
    @State private var isMenuButtonVisible: Bool = true

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.backgroundGradient.ignoresSafeArea()

            Group {
                switch currentMenu {
                case .home:    HomeView()
                case .library: LibraryView()
                case .quiz:    QuizView()
                case .level:   LevelView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Overlay dim
            Color.black.opacity(isMenuOpen ? 0.3 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isMenuOpen = false
                    }
                }
                .allowsHitTesting(isMenuOpen)

            // Menu button
            VStack {
                HStack {
                    if isMenuButtonVisible {
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isMenuOpen.toggle()
                            }
                        }) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                Spacer()
            }

            // Sidebar
            if isMenuOpen {
                SidebarMenu(currentMenu: $currentMenu, isMenuOpen: $isMenuOpen)
                    .frame(width: 280)
                    .transition(.move(edge: .leading))
                    .zIndex(2)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuButtonVisibilityDidChange)) { note in
            guard let visible = note.object as? Bool else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isMenuButtonVisible = visible
            }
        }
    }
}

// MARK: - SidebarMenu

struct SidebarMenu: View {
    @Binding var currentMenu: MenuOption
    @Binding var isMenuOpen: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.3)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 32) {
                Text("WordWidget")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 60)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 10) {
                    menuItem(icon: "house.fill", title: "Ana Sayfa", option: .home)
                    menuItem(icon: "brain.head.profile", title: "Sınav", option: .quiz)
                    menuItem(icon: "books.vertical.fill", title: "Kelimelerim", option: .library)
                    menuItem(icon: "chart.bar.fill", title: "Seviyeler", option: .level)
                    menuItem(icon: "gearshape.fill", title: "Ayarlar", option: .settings)
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func menuItem(icon: String, title: String, option: MenuOption) -> some View {
        let isSelected = currentMenu == option
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentMenu = option
                isMenuOpen = false
            }
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .foregroundColor(isSelected ? .white : Theme.textTertiary)
                    .frame(width: 24)
                Text(title)
                    .foregroundColor(isSelected ? .white : Theme.textTertiary)
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Theme.accent.opacity(0.7) : .clear)
            )
        }
    }
}
