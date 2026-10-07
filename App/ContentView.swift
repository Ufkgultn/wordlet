import SwiftUI
import WidgetKit

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @AppStorage("themeMode") private var themeMode: String = "dark"
    @AppStorage("placementDone") private var placementDone = false
    @State private var showPlacement = false
    @State private var selectedTab = 0

    #if DEBUG
    /// Geliştirme kısayolu: WORDLET_DEBUG_SCREEN ortam değişkeniyle bir sekmeyi ya da oyunu doğrudan aç
    /// (simülatörde arayüz/tema kontrolü için). Örn: SIMCTL_CHILD_WORDLET_DEBUG_SCREEN=wordmatch
    /// Değerler: home, quiz, duels, library, settings, room, wordmatch, typing, speed, truefalse, jumble, levels, paywall, login
    @State private var debugScreen: String? = ProcessInfo.processInfo.environment["WORDLET_DEBUG_SCREEN"]
    @State private var showDebugScreen = false
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground()
                .tabItem {
                    Label("Ana Sayfa", systemImage: "house.fill")
                }
                .tag(0)

            QuizView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground()
                .tabItem {
                    Label("Alıştırmalar", systemImage: "brain.head.profile")
                }
                .tag(1)

            DuelsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground()
                .tabItem {
                    Label("Düello", systemImage: "bolt.horizontal.fill")
                }
                .tag(2)

            LibraryView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground()
                .tabItem {
                    Label("Kelimelerim", systemImage: "books.vertical.fill")
                }
                .tag(3)

            SettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .appBackground()
                .tabItem {
                    Label("Ayarlar", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(Theme.tabTint)
        .environmentObject(authManager)
        .onAppear {
            #if DEBUG
            if let screen = debugScreen {
                let tabs = ["home": 0, "quiz": 1, "duels": 2, "library": 3, "settings": 4]
                if let tab = tabs[screen] { selectedTab = tab } else { showDebugScreen = true }
                return
            }
            #endif
            // Seviye tespit testi sadece hiç ilerlemesi olmayan yeni kullanıcılara sorulur
            if !placementDone {
                if ProgressManager.shared.isFreshUser {
                    showPlacement = true
                } else {
                    placementDone = true
                    AppDelegate.requestNotificationPermission()
                }
            }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showDebugScreen) {
            debugScreenView(debugScreen ?? "")
        }
        #endif
        .fullScreenCover(isPresented: $showPlacement) {
            PlacementIntroView(onFinish: {
                placementDone = true
                showPlacement = false
                AppDelegate.requestNotificationPermission()
            })
        }
        .preferredColorScheme(themeMode == "light" ? .light : themeMode == "dark" ? .dark : nil)
    }
}

#if DEBUG
extension ContentView {
    @ViewBuilder
    func debugScreenView(_ name: String) -> some View {
        switch name {
        case "wordmatch": WordMatchBattleView(opponentName: "Robot", isRobot: true, robotLevel: 1)
        case "typing": TypingBattleView(opponentName: "Robot", isRobot: true, robotLevel: 1)
        case "speed": SpeedQuizBattleView(opponentName: "Robot", isRobot: true, robotLevel: 1)
        case "truefalse": TrueFalseBattleView(opponentName: "Robot", isRobot: true, robotLevel: 1)
        case "jumble": JumbleBattleView(opponentName: "Robot", isRobot: true, robotLevel: 1)
        case "room": ModeRoomView(modeId: 0, modeTitle: "Eşleştirme Odası", modeDescription: "Kelime ve anlamını hızlıca eşleştir. Klasik mod!", modeIcon: "rectangle.split.2x2.fill", modeColor: .blue)
        case "daily": QuizView(dailyTestMode: true)
        case "levels": LevelView()
        case "paywall": PremiumPaywallView()
        case "login": LoginView()
        default: Text("Bilinmeyen ekran: \(name)")
        }
    }
}
#endif

// MARK: - Placement Intro

/// İlk açılış: kullanıcıya seviye tespit testi önerir ya da A1'den başlatır
private struct PlacementIntroView: View {
    let onFinish: () -> Void
    @State private var startTest = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                Spacer()
                Text("🎯").font(.system(size: 72))
                Text("Seviyeni Belirleyelim")
                    .font(.largeTitle.bold())
                    .foregroundColor(Theme.fg)
                Text("20 kısa soruyla İngilizce kelime seviyeni bulalım. Böylece bildiğin kelimelerle vakit kaybetmezsin.")
                    .font(.body)
                    .foregroundColor(Theme.fg.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
                Button {
                    startTest = true
                } label: {
                    Text("Teste Başla")
                        .font(.headline)
                        .foregroundColor(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent))
                }
                .padding(.horizontal, 24)
                Button("Yeni başlıyorum, A1'den başla") {
                    onFinish()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.fg.opacity(0.7))
                .padding(.bottom, 24)
            }
        }
        .fullScreenCover(isPresented: $startTest, onDismiss: onFinish) {
            QuizView(placementMode: true)
        }
    }
}
