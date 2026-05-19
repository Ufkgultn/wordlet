import SwiftUI
import WidgetKit

// MARK: - LevelView

struct LevelView: View {
    @State private var progress = ProgressManager.shared.progress
    @State private var selectedLevelForTest: CEFRLevel? = nil
    @State private var showUnlockCelebration = false
    @State private var unlockedLevel: CEFRLevel? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Seviyelerim")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Sınavı geç, yeni kelimeleri aç!")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 28)

                // Level Cards
                VStack(spacing: 16) {
                    ForEach(CEFRLevel.allCases) { level in
                        LevelCard(
                            level: level,
                            isUnlocked: progress.isUnlocked(level),
                            isCurrent: progress.currentLevel == level,
                            wordCount: WordManager.shared.words(for: level).count,
                            seenCount: seenCount(for: level),
                            onTakTest: {
                                selectedLevelForTest = level
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)

                // Son Sınav Skorları
                if !progress.quizScores.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Son Sınav Skorları")
                            .font(.headline)
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 24)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(progress.quizScores.suffix(8).enumerated()), id: \.offset) { _, score in
                                    ScoreChip(score: score)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear { progress = ProgressManager.shared.progress }
        .onReceive(NotificationCenter.default.publisher(for: .progressDidChange)) { _ in
            progress = ProgressManager.shared.progress
        }
        .onReceive(NotificationCenter.default.publisher(for: .levelDidUnlock)) { note in
            if let levelRaw = note.object as? String, let level = CEFRLevel(rawValue: levelRaw) {
                unlockedLevel = level
                withAnimation { showUnlockCelebration = true }
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .sheet(item: $selectedLevelForTest) { level in
            QuizView(levelTestMode: true, targetLevel: level)
                .onDisappear {
                    progress = ProgressManager.shared.progress
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
        .overlay(alignment: .top) {
            if showUnlockCelebration, let level = unlockedLevel {
                UnlockBanner(level: level)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { showUnlockCelebration = false }
                        }
                    }
            }
        }
    }

    private func seenCount(for level: CEFRLevel) -> Int {
        let levelIDs = Set(WordManager.shared.words(for: level).map { $0.id })
        return WordManager.shared.seenWordIDs().filter { levelIDs.contains($0) }.count
    }
}

// MARK: - Level Card

private struct LevelCard: View {
    let level: CEFRLevel
    let isUnlocked: Bool
    let isCurrent: Bool
    let wordCount: Int
    let seenCount: Int
    let onTakTest: () -> Void

    private var progress: Double {
        guard wordCount > 0 else { return 0 }
        return Double(seenCount) / Double(wordCount)
    }

    private var badgeColor: Color {
        switch level {
        case .a1: return .green
        case .a2: return .blue
        case .b1: return .orange
        case .b2: return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top Row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(level.rawValue)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        
                        // Stars
                        HStack(spacing: 2) {
                            ForEach(1...3, id: \.self) { star in
                                Image(systemName: ProgressManager.shared.progress.stars(for: level) >= star ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundColor(ProgressManager.shared.progress.stars(for: level) >= star ? .yellow : .white.opacity(0.2))
                            }
                        }
                        
                        Text(level.description)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text("\(wordCount) kelime")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                // Status icon
                ZStack {
                    Circle()
                        .fill(isUnlocked ? badgeColor.opacity(0.2) : Color.white.opacity(0.07))
                        .frame(width: 44, height: 44)
                    Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isUnlocked ? badgeColor : .white.opacity(0.4))
                }
            }

            if isUnlocked {
                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Görülen: \(seenCount)/\(wordCount)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(badgeColor)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(colors: [badgeColor, badgeColor.opacity(0.7)],
                                                   startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: geo.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                // Current level badge
                if isCurrent {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.caption)
                        Text("Aktif Seviye")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(badgeColor.opacity(0.15)))
                }
            } else {
                // Locked state — show exam button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bu seviyeyi açmak için")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        Text("sınava gir ve %70 al")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Button(action: onTakTest) {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.and.list.clipboard")
                            Text("Sınava Gir")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(badgeColor.opacity(0.8))
                        )
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            isCurrent ? badgeColor.opacity(0.6) : Color.white.opacity(0.08),
                            lineWidth: isCurrent ? 2 : 1
                        )
                )
        )
        .opacity(isUnlocked ? 1 : 0.75)
    }
}

// MARK: - Score Chip

private struct ScoreChip: View {
    let score: Int

    private var chipColor: Color {
        score >= 70 ? Theme.correct : Theme.wrong
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("%\(score)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(chipColor.opacity(0.2))
                .overlay(Capsule().stroke(chipColor.opacity(0.4), lineWidth: 1))
        )
    }
}

// MARK: - Unlock Banner

private struct UnlockBanner: View {
    let level: CEFRLevel

    var body: some View {
        HStack(spacing: 12) {
            Text("🎉")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(level.rawValue) Açıldı!")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Artık \(level.description) kelimelerini görebilirsin.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.correct.opacity(0.5), lineWidth: 1))
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }
}
