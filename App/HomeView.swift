import SwiftUI
import WidgetKit

struct HomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var currentWord: Word?
    @State private var cardScale: CGFloat = 1.0
    @State private var cardOpacity: Double = 1.0
    @State private var lastScrollOffset: CGFloat = 0

    @State private var isPremium: Bool = AppSettingsManager.shared.isPremium

    private var firstName: String {
        authManager.currentUser?.firstName ?? "Kullanıcı"
    }

    private var currentLevel: CEFRLevel {
        ProgressManager.shared.progress.currentLevel
    }

    var body: some View {
        ScrollView {
            GeometryReader { geo in
                Color.clear
                    .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("homeScroll")).minY)
            }
            .frame(height: 0)

            VStack(spacing: 0) {
                // MARK: Header
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Today's Word")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.textPrimary)
                        HStack(spacing: 8) {
                            LevelBadge(level: currentLevel)
                            Text("İyi çalışmalar, \(firstName) ✨")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 8) {
                        Button(action: { Task { await authManager.logout() } }) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        Button(action: {
                            AppSettingsManager.shared.isPremium.toggle()
                            isPremium = AppSettingsManager.shared.isPremium
                        }) {
                            Text(isPremium ? "Premium 👑" : "Premium Al")
                                .font(.caption.bold())
                                .foregroundColor(isPremium ? .yellow : .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isPremium ? Color.yellow.opacity(0.2) : Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)

                // MARK: Word Card
                if let word = currentWord {
                    VStack(spacing: 16) {
                        if let imageURL = word.imageURL, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Color.white.opacity(0.1)
                                }
                            }
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }

                        Text(word.english)
                            .font(.system(size: 42, weight: .bold, design: .serif))
                            .foregroundColor(.white)

                        Text(word.turkish)
                            .font(.title3).fontWeight(.semibold)
                            .foregroundColor(Theme.background)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Theme.accent)
                            .cornerRadius(20)

                        Text("\"\(word.example)\"")
                            .font(.body).italic()
                            .foregroundColor(Theme.textPrimary)
                            .multilineTextAlignment(.center)

                        if let trExample = word.exampleTurkish {
                            Text("\"\(trExample)\"")
                                .font(.footnote)
                                .foregroundColor(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 12) {
                            Button {
                                SpeechManager.shared.speakEnglish(word: word.english, example: word.example)
                            } label: {
                                Label("EN Listen", systemImage: "speaker.wave.2.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                SpeechManager.shared.speakTurkish(meaning: word.turkish, exampleTurkish: word.exampleTurkish)
                            } label: {
                                Label("TR Listen", systemImage: "speaker.wave.1.fill")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(action: changeWord) {
                            Label("Sonraki Kelime", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .glassCard(cornerRadius: 28)
                    .padding(.horizontal, 24)
                    .scaleEffect(cardScale)
                    .opacity(cardOpacity)
                } else {
                    ProgressView().padding(.top, 120)
                }

                Spacer().frame(height: 120)
            }
        }
        .coordinateSpace(name: "homeScroll")
        .scrollIndicators(.hidden)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            let delta = offset - lastScrollOffset
            if delta < -4 {
                NotificationCenter.default.post(name: .menuButtonVisibilityDidChange, object: false)
            } else if delta > 4 {
                NotificationCenter.default.post(name: .menuButtonVisibilityDidChange, object: true)
            }
            lastScrollOffset = offset
        }
        .onAppear {
            NotificationCenter.default.post(name: .menuButtonVisibilityDidChange, object: true)
            if currentWord == nil { loadCurrent() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wordFlowDidChange)) { _ in
            if let id = AppSettingsManager.shared.getCurrentWordId(),
               let synced = WordManager.shared.getWord(byId: id) {
                withAnimation { currentWord = synced }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .progressDidChange)) { _ in
            // Seviye değişince yeni seviyeden kelime yükle
            loadCurrent()
        }
    }

    // MARK: - Word Loading

    /// Mevcut kaydedilmiş kelimeyi yükle; yoksa yeni seç
    private func loadCurrent() {
        let level = ProgressManager.shared.progress.currentLevel
        if let id = AppSettingsManager.shared.getCurrentWordId(),
           let saved = WordManager.shared.getWord(byId: id),
           saved.level == level {
            currentWord = saved
        } else {
            advanceToNextWord()
        }
    }

    /// Bir sonraki kelimeye geç (tek kaynak — WordManager.nextWord)
    private func advanceToNextWord() {
        let level = ProgressManager.shared.progress.currentLevel
        if let word = WordManager.shared.nextWord(for: level) {
            currentWord = word
            WordManager.shared.markWordAsSeen(id: word.id)
            AppSettingsManager.shared.saveCurrentWordId(word.id)
        }
    }

    private func changeWord() {
        withAnimation(.easeOut(duration: 0.15)) {
            cardScale = 0.92
            cardOpacity = 0.6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            advanceToNextWord()
            WidgetCenter.shared.reloadAllTimelines()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                cardScale = 1.0
                cardOpacity = 1.0
            }
        }
    }
}

// MARK: - Level Badge

struct LevelBadge: View {
    let level: CEFRLevel

    private var badgeColor: Color {
        switch level {
        case .a1: return .green
        case .a2: return .blue
        case .b1: return .orange
        case .b2: return .purple
        }
    }

    var body: some View {
        Text(level.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(badgeColor))
    }
}

// MARK: - Scroll Preference Key

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
