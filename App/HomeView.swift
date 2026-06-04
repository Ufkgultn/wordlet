import SwiftUI
import WidgetKit

// MARK: - HomeView (Tinder Swipe Style)

struct HomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var words: [Word] = []
    @State private var isPremium: Bool = AppSettingsManager.shared.isPremium
    @State private var progress = ProgressManager.shared.progress
    @State private var showDailyTest = false

    private var firstName: String {
        authManager.currentUser?.firstName ?? "Kullanıcı"
    }

    private var currentLevel: CEFRLevel {
        progress.currentLevel
    }

    var body: some View {
        ZStack {
            // Background
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating Header & Progress
                floatingHeader
                    .padding(.top, 10)

                Spacer()

                // Card Stack
                if words.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(.white)
                        Text("Tüm kelimeleri gördün!")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Button("Baştan Başla") {
                            loadInitialWords(forceReset: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                } else {
                    ZStack {
                        ForEach(words.reversed(), id: \.id) { word in
                            SwipeCard(word: word) { direction in
                                handleSwipe(word: word, direction: direction)
                            }
                            .id(word.id)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()

                // Bottom Action Area
                bottomActionArea
                    .padding(.bottom, 20)
            }
        }
        .onAppear {
            progress = ProgressManager.shared.progress
            if words.isEmpty { loadInitialWords() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .progressDidChange)) { _ in
            progress = ProgressManager.shared.progress
        }
        .sheet(isPresented: $showDailyTest) {
            QuizView(dailyTestMode: true, targetLevel: currentLevel)
        }
    }

    // MARK: - Floating Header

    private var floatingHeader: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                LevelBadge(level: currentLevel)

                Text("Merhaba, \(firstName) ✨")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer()

                Button {
                    AppSettingsManager.shared.isPremium.toggle()
                    isPremium = AppSettingsManager.shared.isPremium
                } label: {
                    Text(isPremium ? "👑" : "Premium Al")
                        .font(.caption.bold())
                        .foregroundColor(isPremium ? .yellow : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 16)

            // Progress Bar (Known Words)
            VStack(spacing: 6) {
                let totalLevelWords = WordManager.shared.words(for: currentLevel).count
                let knownLevelWords = knownWordsCount()
                let progressFraction = totalLevelWords > 0 ? Double(knownLevelWords) / Double(totalLevelWords) : 0

                HStack {
                    Text("Öğrenilen Kelimeler")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(knownLevelWords) / \(totalLevelWords)")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 24)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(0, geo.size.width * progressFraction))
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Bottom Action Area

    private var bottomActionArea: some View {
        VStack(spacing: 20) {
            // Manual Swipe Buttons
            HStack(spacing: 40) {
                Button {
                    if let topWord = words.first {
                        handleSwipe(word: topWord, direction: .left)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 64, height: 64)
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.wrong)
                    }
                }
                .disabled(words.isEmpty)

                Button {
                    if let topWord = words.first {
                        handleSwipe(word: topWord, direction: .right)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 64, height: 64)
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.correct)
                    }
                }
                .disabled(words.isEmpty)
            }

            // Daily Test Button
            Button {
                showDailyTest = true
            } label: {
                HStack {
                    Image(systemName: "target")
                    Text(ProgressManager.shared.hasTakenDailyTest() ? "Günlük Test (Tamamlandı)" : "Günlük Teste Başla")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ProgressManager.shared.hasTakenDailyTest() ? Theme.accent.opacity(0.5) : Theme.accent)
                )
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Logic

    private func knownWordsCount() -> Int {
        let levelWords = WordManager.shared.words(for: currentLevel).map { $0.id }
        return progress.knownWordIDs.filter { levelWords.contains($0) }.count
    }

    private func handleSwipe(word: Word, direction: SwipeDirection) {
        if direction == .right {
            ProgressManager.shared.swipeRight(wordID: word.id)
        } else {
            ProgressManager.shared.swipeLeft(wordID: word.id)
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            words.removeAll { $0.id == word.id }
        }

        if words.count < 3 {
            loadMoreWords()
        }
    }

    private func loadInitialWords(forceReset: Bool = false) {
        let level = currentLevel
        let allWords = WordManager.shared.words(for: level)
        
        let knownIDs = Set(progress.knownWordIDs)
        let unknownIDs = Set(progress.unknownWordIDs)

        var feed: [Word] = []

        if !forceReset {
            // Henüz sağa kaydırılmamış kelimeler (biliyorum denmemiş)
            let unseenOrUnknown = allWords.filter { !knownIDs.contains($0.id) }
            // Önce hiç görülmemişler, sonra bilinmeyenler
            let totallyUnseen = unseenOrUnknown.filter { !unknownIDs.contains($0.id) }
            let stillUnknown = unseenOrUnknown.filter { unknownIDs.contains($0.id) }
            
            feed.append(contentsOf: totallyUnseen.shuffled().prefix(10))
            feed.append(contentsOf: stillUnknown.shuffled().prefix(10))
            feed.shuffle()
        } else {
            // Baştan başla (sadece gösterim amaçlı, progressi sıfırlamıyoruz)
            feed.append(contentsOf: allWords.shuffled().prefix(20))
        }

        words = feed
    }

    private func loadMoreWords() {
        let level = currentLevel
        let allWords = WordManager.shared.words(for: level)
        let knownIDs = Set(progress.knownWordIDs)
        let existingIDs = Set(words.map { $0.id })
        
        let unseenOrUnknown = allWords.filter { !knownIDs.contains($0.id) && !existingIDs.contains($0.id) }
        
        if !unseenOrUnknown.isEmpty {
            words.append(contentsOf: unseenOrUnknown.shuffled().prefix(10))
        }
    }
}

// MARK: - Swipe Card

enum SwipeDirection {
    case left, right
}

struct SwipeCard: View {
    let word: Word
    let onSwiped: (SwipeDirection) -> Void

    @State private var offset: CGSize = .zero
    @State private var color: Color = .clear

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 24) {
                // Word Header
                Text(word.english)
                    .font(.system(size: 42, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)

                Text(word.turkish)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.background)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())

                Spacer()

                // Example
                VStack(spacing: 12) {
                    Text("\"\(word.example)\"")
                        .font(.body.italic())
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)

                    if let tr = word.exampleTurkish {
                        Divider()
                            .background(Color.white.opacity(0.15))

                        Text("\"\(tr)\"")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
                .background(Color.black.opacity(0.2))
                .cornerRadius(16)

                Spacer()

                // Audio Actions
                HStack(spacing: 20) {
                    Button {
                        SpeechManager.shared.speakEnglish(word: word.english, example: word.example)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }

                    Button {
                        SpeechManager.shared.speakTurkish(meaning: word.turkish, exampleTurkish: word.exampleTurkish)
                    } label: {
                        Text("TR")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                }
                .padding(.bottom, 30)
            }
            .padding(20)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(
                ZStack {
                    Theme.accent.opacity(0.8) // Base card color
                    color // Swipe overlay color
                }
            )
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            // Overlay Labels
            .overlay(
                ZStack {
                    // Right Swipe Label (Know)
                    Text("BİLİYORUM")
                        .font(.title.bold())
                        .foregroundColor(Theme.correct)
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.correct, lineWidth: 3)
                        )
                        .rotationEffect(.degrees(-15))
                        .opacity(offset.width > 20 ? Double(offset.width / swipeThreshold) : 0)
                        .position(x: 100, y: 80)

                    // Left Swipe Label (Don't Know)
                    Text("BİLMİYORUM")
                        .font(.title.bold())
                        .foregroundColor(Theme.wrong)
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.wrong, lineWidth: 3)
                        )
                        .rotationEffect(.degrees(15))
                        .opacity(offset.width < -20 ? Double(-offset.width / swipeThreshold) : 0)
                        .position(x: geo.size.width - 120, y: 80)
                }
            )
        }
        .offset(x: offset.width, y: offset.height * 0.4)
        .rotationEffect(.degrees(Double(offset.width / 15)))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation
                    withAnimation {
                        changeColor(width: offset.width)
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring()) {
                        swipeCard(width: offset.width)
                    }
                }
        )
    }

    private func swipeCard(width: CGFloat) {
        if width > swipeThreshold {
            offset = CGSize(width: 1000, height: 0)
            onSwiped(.right)
        } else if width < -swipeThreshold {
            offset = CGSize(width: -1000, height: 0)
            onSwiped(.left)
        } else {
            offset = .zero
            color = .clear
        }
    }

    private func changeColor(width: CGFloat) {
        if width > 0 {
            color = Theme.correct.opacity(Double(width / swipeThreshold) * 0.5)
        } else if width < 0 {
            color = Theme.wrong.opacity(Double(-width / swipeThreshold) * 0.5)
        }
    }
}
