import SwiftUI
import WidgetKit

// MARK: - QuizView

struct QuizView: View {
    let levelTestMode: Bool
    @State private var targetLevel: CEFRLevel
    @State private var starLevel: Int? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var questions: [QuizQuestion] = []
    @State private var currentIndex = 0
    @State private var score = 0
    @State private var selectedChoice: String? = nil
    @State private var showFeedback = false
    @State private var showResult = false
    @State private var didUnlock = false
    @State private var progressAnim: CGFloat = 0
    @State private var isStarted = false

    init(levelTestMode: Bool = false, targetLevel: CEFRLevel? = nil, starLevel: Int? = nil) {
        self.levelTestMode = levelTestMode
        self._targetLevel = State(initialValue: targetLevel ?? ProgressManager.shared.progress.currentLevel)
        self._starLevel = State(initialValue: starLevel)
        self._isStarted = State(initialValue: levelTestMode || starLevel != nil)
    }

    // MARK: Computed

    private var progressFraction: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentIndex) / Double(questions.count)
    }

    private var scorePercent: Int {
        Int((Double(score) / Double(max(questions.count, 1))) * 100)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if !isStarted {
                selectionScreen
            } else if questions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Header
                    quizHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    // Progress Bar
                    progressBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    // Question Card
                    ScrollView {
                        VStack(spacing: 20) {
                            questionCard
                            choicesStack
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear { 
            if isStarted && questions.isEmpty {
                startQuiz() 
            }
        }
        .sheet(isPresented: $showResult) {
            resultSheet
                .interactiveDismissDisabled()
        }
    }

    // MARK: - Subviews

    private var selectionScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Alıştırma Seç")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 40)

                ForEach(CEFRLevel.allCases) { level in
                    if ProgressManager.shared.progress.isUnlocked(level) {
                        levelPracticeSection(for: level)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private func levelPracticeSection(for level: CEFRLevel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(level.description)
                .font(.headline)
                .foregroundColor(Theme.textSecondary)

            HStack(spacing: 12) {
                ForEach(1...3, id: \.self) { star in
                    starButton(level: level, star: star)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
    }

    private func starButton(level: CEFRLevel, star: Int) -> some View {
        let isAchieved = ProgressManager.shared.progress.stars(for: level) >= star
        return Button(action: {
            targetLevel = level
            starLevel = star
            withAnimation { isStarted = true }
            startQuiz()
        }) {
            VStack(spacing: 8) {
                Image(systemName: isAchieved ? "star.fill" : "star")
                    .font(.system(size: 24))
                    .foregroundColor(isAchieved ? .yellow : .white.opacity(0.3))
                
                Text("\(star * 5 + 5) Soru")
                    .font(.caption2.bold())
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isAchieved ? Color.yellow.opacity(0.3) : Color.clear, lineWidth: 1))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 60))
                .foregroundColor(Theme.textSecondary)
            Text(levelTestMode
                 ? "\(targetLevel.rawValue) seviyesinde yeterli kelime yok."
                 : "Bu seviyede yeterli kelime yok. Lütfen başka bir seviye seç.")
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Geri") { 
                if levelTestMode { dismiss() }
                else { withAnimation { isStarted = false } }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private var quizHeader: some View {
        HStack {
            Button(action: { 
                if levelTestMode { dismiss() }
                else { withAnimation { isStarted = false } }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(.ultraThinMaterial))
            }

            Spacer()

            VStack(spacing: 2) {
                Text(levelTestMode ? "\(targetLevel.rawValue) Seviye Sınavı" : "\(targetLevel.rawValue) - \(starLevel ?? 1) Yıldız")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Soru \(min(currentIndex + 1, questions.count))/\(questions.count)")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            // Skor
            Text("\(score) ✓")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.correct)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.correct.opacity(0.15)))
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.7)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * progressAnim, height: 6)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progressAnim)
            }
        }
        .frame(height: 6)
        .onChange(of: currentIndex) { _ in
            progressAnim = progressFraction
        }
        .onAppear {
            progressAnim = progressFraction
        }
    }

    private var questionCard: some View {
        VStack(spacing: 12) {
            Text(questions[currentIndex].direction == .englishToTurkish ? "🇬🇧 → 🇹🇷" : "🇹🇷 → 🇬🇧")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)

            Text(questions[currentIndex].prompt)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .glassCard(cornerRadius: 20)
    }

    private var choicesStack: some View {
        VStack(spacing: 12) {
            ForEach(questions[currentIndex].choices, id: \.self) { choice in
                Button {
                    guard !showFeedback else { return }
                    answer(choice)
                } label: {
                    HStack {
                        Text(choice)
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                        Spacer()
                        if showFeedback {
                            if choice == questions[currentIndex].correctAnswer {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.correct)
                            } else if selectedChoice == choice {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Theme.wrong)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(choiceBackground(choice))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(choiceBorder(choice), lineWidth: 1.5)
                    )
                }
                .disabled(showFeedback)
                .animation(.easeInOut(duration: 0.2), value: showFeedback)
            }
        }
    }

    // MARK: Result Sheet

    private var resultSheet: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Emoji & Level
                VStack(spacing: 8) {
                    Text(scoreEmoji)
                        .font(.system(size: 70))
                    Text("\(targetLevel.rawValue) \(starLevel != nil ? "- \(starLevel!) Yıldız" : "Sınav")")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.accent))
                }

                // Score Circle
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 12)
                        .frame(width: 140, height: 140)
                    Circle()
                        .trim(from: 0, to: CGFloat(scorePercent) / 100)
                        .stroke(scorePercent >= 70 ? Theme.correct : Theme.wrong,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 140, height: 140)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1, dampingFraction: 0.7), value: scorePercent)

                    VStack(spacing: 4) {
                        Text("%\(scorePercent)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("\(score)/\(questions.count)")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                // Result Message
                VStack(spacing: 8) {
                    Text(resultTitle)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text(resultMessage)
                        .font(.body)
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Actions
                VStack(spacing: 12) {
                    Button {
                        showResult = false
                        if levelTestMode && scorePercent >= 70 {
                            dismiss()
                        } else {
                            withAnimation { isStarted = false }
                        }
                    } label: {
                        Text("Tamam")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 24)

                    if scorePercent < 70 {
                        Button("Tekrar Dene") {
                            showResult = false
                            startQuiz()
                        }
                        .foregroundColor(.white)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Logic

    private func startQuiz() {
        questions = QuizManager.shared.generateQuiz(
            targetLevel: targetLevel,
            levelTest: levelTestMode,
            starLevel: starLevel
        )
        currentIndex = 0
        score = 0
        selectedChoice = nil
        showFeedback = false
        didUnlock = false
        progressAnim = 0
    }

    private func answer(_ choice: String) {
        selectedChoice = choice
        showFeedback = true

        if choice == questions[currentIndex].correctAnswer {
            score += 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            selectedChoice = nil
            showFeedback = false
            if currentIndex + 1 < questions.count {
                currentIndex += 1
                progressAnim = progressFraction
            } else {
                completeQuiz()
            }
        }
    }

    private func completeQuiz() {
        if levelTestMode {
            didUnlock = ProgressManager.shared.attemptLevelUnlock(
                scorePercent: scorePercent,
                targetLevel: targetLevel
            )
        } else if let star = starLevel, scorePercent >= 80 {
            ProgressManager.shared.saveStar(for: targetLevel, star: star)
            ProgressManager.shared.addQuizScore(scorePercent)
        } else {
            ProgressManager.shared.addQuizScore(scorePercent)
        }
        showResult = true
    }

    // MARK: - Styling Helpers

    private func choiceBackground(_ choice: String) -> Color {
        guard showFeedback else { return Color.white.opacity(0.08) }
        if choice == questions[currentIndex].correctAnswer { return Theme.correct.opacity(0.2) }
        if selectedChoice == choice { return Theme.wrong.opacity(0.2) }
        return Color.white.opacity(0.05)
    }

    private func choiceBorder(_ choice: String) -> Color {
        guard showFeedback else { return Color.white.opacity(0.12) }
        if choice == questions[currentIndex].correctAnswer { return Theme.correct }
        if selectedChoice == choice { return Theme.wrong }
        return Color.white.opacity(0.08)
    }

    private var scoreEmoji: String {
        switch scorePercent {
        case 90...100: return "🏆"
        case 70...89:  return "🎉"
        case 50...69:  return "💪"
        default:        return "📚"
        }
    }

    private var resultTitle: String {
        if levelTestMode {
            return scorePercent >= 70 ? "\(targetLevel.rawValue) Seviyesi Açıldı!" : "Bir Daha Dene!"
        }
        return scorePercent >= 80 ? "Yıldızı Kaptın!" : "Devam Et!"
    }

    private var resultMessage: String {
        if levelTestMode {
            return scorePercent >= 70
                ? "Tebrikler! \(targetLevel.rawValue) kelimelerini görmeye başlayabilirsin."
                : "Geçmek için en az %70 gerekli. Biraz daha pratik yap!"
        }
        return scorePercent >= 80
            ? "Harika iş! Bu seviyede bir yıldız daha kazandın."
            : "Yıldız kazanmak için %80 başarı gerekli. Biraz daha çalışmaya ne dersin?"
    }
}
