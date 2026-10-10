import SwiftUI

struct WordMatchBattleView: View {
    let opponentName: String
    var opponentProfile: PublicProfile? = nil
    var isRobot: Bool = false
    var robotLevel: Int = 1
    var targetCEFRLevel: CEFRLevel? = nil
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var matchManager = MatchManager.shared
    
    // Kelime eşleştirme verisi (iki sütun için)
    @State private var leftItems: [MatchItem] = []
    @State private var rightItems: [MatchItem] = []
    @State private var selectedId: UUID? = nil
    
    // Yanlış cevap bekleme cezası
    @State private var isSelectionDisabled = false
    
    // Skorlar ve Oyun Durumu
    @State private var userMatches = 0
    @State private var opponentMatches = 0
    @State private var timeRemaining = 60
    @State private var gameState: GameState = .playing
    @State private var earnedXP: Int = 0
    @State private var timer: Timer? = nil
    
    // Opponent AI timer (Yalnızca yapay zeka robot maçlarında kullanılır)
    @State private var opponentTimer: Timer? = nil
    
    private var activeCEFRLevel: CEFRLevel {
        targetCEFRLevel ?? ProgressManager.shared.progress.currentLevel
    }
    
    private var totalPairs: Int {
        if isRobot {
            if robotLevel <= 5 {
                return 5
            } else if robotLevel <= 10 {
                return 6
            } else if robotLevel <= 15 {
                return 7
            } else if robotLevel <= 20 {
                return 8
            } else if robotLevel <= 25 {
                return 10
            } else {
                return 12
            }
        } else {
            return 6
        }
    }
    
    enum GameState {
        case playing, won, lost, draw
    }
    
    struct MatchItem: Identifiable, Equatable {
        let id = UUID()
        let wordId: String
        let text: String
        let isEnglish: Bool
        var isMatched: Bool = false
        var isSelected: Bool = false
        var isWrong: Bool = false
    }
    
    var body: some View {
        ZStack {
            AppBackground()
            
            VStack(spacing: 20) {
                // Header / Opponent Info
                HStack {
                    Button(action: {
                        cleanup()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundColor(Theme.fg)
                            .padding(12)
                            .background(Circle().fill(Theme.fg.opacity(0.1)))
                    }
                    Spacer()
                    
                    // Show robot level and active CEFR level dynamically
                    Text(isRobot ? "Robot Seviye \(robotLevel) (\(activeCEFRLevel.rawValue))" : "Kelime Düellosu (\(activeCEFRLevel.rawValue))")
                        .font(.headline.bold())
                        .foregroundColor(Theme.fg)
                    
                    Spacer()
                    Text("\(timeRemaining)s")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                // Scoreboards
                HStack(spacing: 16) {
                    // User Score
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sen")
                            .font(.caption)
                            .foregroundColor(Theme.fg.opacity(0.6))
                        HStack {
                            Text("⚡️")
                            Text("\(userMatches)/\(totalPairs)")
                                .font(.title3.bold())
                                .foregroundColor(Theme.fg)
                        }
                        ProgressView(value: Double(userMatches), total: Double(totalPairs))
                            .tint(.green)
                    }
                    .padding(12)
                    .background(Theme.fg.opacity(0.06))
                    .cornerRadius(12)
                    
                    // Opponent Score
                    VStack(alignment: .leading, spacing: 6) {
                        Text(opponentName)
                            .font(.caption)
                            .foregroundColor(Theme.fg.opacity(0.6))
                        HStack {
                            Text(isRobot ? "🤖" : "👤")
                            Text("\(opponentMatches)/\(totalPairs)")
                                .font(.title3.bold())
                                .foregroundColor(Theme.fg)
                        }
                        ProgressView(value: Double(opponentMatches), total: Double(totalPairs))
                            .tint(.red)
                    }
                    .padding(12)
                    .background(Theme.fg.opacity(0.06))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                if gameState == .playing {
                    // Two Columns layout (Left English, Right Turkish)
                    ScrollView(showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            // Left Column: English Words
                            VStack(spacing: 10) {
                                ForEach(leftItems) { item in
                                    cardButton(for: item)
                                }
                            }
                            
                            // Right Column: Turkish Words
                            VStack(spacing: 10) {
                                ForEach(rightItems) { item in
                                    cardButton(for: item)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                    }
                } else {
                    resultView
                }
                
                Spacer()
            }
        }
        .onAppear {
            setupGame()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: matchManager.lastMatchResult) { result in
            // Kazananı ve kesin skorları sunucu belirler; yerel tahmini düzelt
            guard let result, !isRobot, gameState != .playing else { return }
            withAnimation {
                userMatches = result.myScore
                opponentMatches = result.opponentScore
                gameState = result.draw ? .draw : (result.won ? .won : .lost)
                earnedXP = result.draw ? 25 : (result.won ? 50 : 15)
            }
        }
        .onChange(of: matchManager.opponentLiveScore) { newScore in
            guard gameState == .playing else { return } // resetMatch skoru 0'a çekince sonuç ekranı bozulmasın
            if !isRobot {
                withAnimation(.spring()) {
                    self.opponentMatches = newScore
                }
                if opponentMatches >= totalPairs {
                    endGame()
                }
            }
        }
        .onChange(of: matchManager.matchFinishedEventReceived) { finished in
            if finished && !isRobot && gameState == .playing {
                endGame()
            }
        }
    }
    
    // MARK: - Card View
    
    private func cardButton(for item: MatchItem) -> some View {
        Button(action: {
            handleSelection(item)
        }) {
            Text(item.text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(textColor(for: item))
                .multilineTextAlignment(.center)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(backgroundColor(for: item))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor(for: item), lineWidth: 1.5)
                )
        }
        .disabled(item.isMatched || isSelectionDisabled)
        .opacity(item.isMatched ? 0.0 : 1.0)
    }
    
    // MARK: - Game Setup
    
    private func setupGame() {
        let words: [Word]
        if !isRobot, let match = matchManager.activeMatch, !match.wordIds.isEmpty {
            // Both players get the exact same words from database
            let matchLevel = CEFRLevel(rawValue: match.level) ?? activeCEFRLevel
            let allWords = WordManager.shared.words(for: matchLevel)
            let matched = match.wordIds.compactMap { wid in allWords.first(where: { $0.id == wid }) }
            words = matched.isEmpty ? Array(allWords.shuffled().prefix(totalPairs)) : matched
        } else {
            words = Array(WordManager.shared.words(for: activeCEFRLevel).shuffled().prefix(totalPairs))
        }
        
        var left: [MatchItem] = []
        var right: [MatchItem] = []
        
        for word in words {
            left.append(MatchItem(wordId: word.id, text: word.english, isEnglish: true))
            right.append(MatchItem(wordId: word.id, text: word.turkish, isEnglish: false))
        }
        
        self.leftItems = left.shuffled()
        self.rightItems = right.shuffled()
        
        // Timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                endGame()
            }
        }
        
        // Opponent Timer:
        if isRobot {
            // AI Robot practice timer
            let aiInterval = max(2.5, 10.0 - Double(robotLevel) * 0.25)
            opponentTimer = Timer.scheduledTimer(withTimeInterval: aiInterval, repeats: true) { _ in
                guard gameState == .playing else { return }
                if opponentMatches < totalPairs {
                    opponentMatches += 1
                    if opponentMatches == totalPairs {
                        endGame()
                    }
                }
            }
        } else if matchManager.activeMatch == nil {
            // Friend duel in direct/offline challenge mode (simulated against friend's profile)
            let friendInterval = Double.random(in: 4.5...7.5)
            opponentTimer = Timer.scheduledTimer(withTimeInterval: friendInterval, repeats: true) { _ in
                guard gameState == .playing else { return }
                if opponentMatches < totalPairs {
                    opponentMatches += 1
                    if opponentMatches == totalPairs {
                        endGame()
                    }
                }
            }
        }
        // If matchManager.activeMatch != nil, score syncs in real-time via WebSocket!
    }
    
    private func cleanup() {
        timer?.invalidate()
        timer = nil
        opponentTimer?.invalidate()
        opponentTimer = nil
        if !isRobot {
            matchManager.resetMatch()
        }
    }
    
    // MARK: - Game Logic
    
    private func handleSelection(_ clickedItem: MatchItem) {
        guard !isSelectionDisabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        let inLeft = leftItems.contains(where: { $0.id == clickedItem.id })
        let leftIdx = leftItems.firstIndex(where: { $0.id == clickedItem.id })
        let rightIdx = rightItems.firstIndex(where: { $0.id == clickedItem.id })
        
        // 1. Case: Nothing selected yet
        if selectedId == nil {
            clearSelectionStates()
            if inLeft, let idx = leftIdx { leftItems[idx].isSelected = true }
            if !inLeft, let idx = rightIdx { rightItems[idx].isSelected = true }
            selectedId = clickedItem.id
            return
        }
        
        // 2. Case: Tapped already selected card
        if selectedId == clickedItem.id {
            clearSelectionStates()
            selectedId = nil
            return
        }
        
        // 3. Case: Second card selected
        let isFirstInLeft = leftItems.contains(where: { $0.id == selectedId })
        
        // If clicking in the same column, deselect old one and select new
        if isFirstInLeft == inLeft {
            clearSelectionStates()
            if inLeft, let idx = leftIdx { leftItems[idx].isSelected = true }
            if !inLeft, let idx = rightIdx { rightItems[idx].isSelected = true }
            selectedId = clickedItem.id
            return
        }
        
        // Different columns selection: check matching
        let firstItem: MatchItem?
        if isFirstInLeft {
            firstItem = leftItems.first(where: { $0.id == selectedId })
        } else {
            firstItem = rightItems.first(where: { $0.id == selectedId })
        }
        
        guard let first = firstItem else { return }
        
        if first.wordId == clickedItem.wordId {
            // SUCCESSFUL MATCH
            if let idx1 = leftItems.firstIndex(where: { $0.wordId == first.wordId }),
               let idx2 = rightItems.firstIndex(where: { $0.wordId == first.wordId }) {
                withAnimation(.spring()) {
                    leftItems[idx1].isMatched = true
                    rightItems[idx2].isMatched = true
                }
            }
            userMatches += 1
            if !isRobot {
                Task {
                    await matchManager.sendLiveScore(score: userMatches)
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            selectedId = nil
            
            if userMatches == totalPairs {
                endGame()
            }
        } else {
            // WRONG MATCH - Lock board for 1 second penalty!
            isSelectionDisabled = true
            
            let firstIdx = leftItems.firstIndex(where: { $0.id == selectedId }) ?? rightItems.firstIndex(where: { $0.id == selectedId })
            let clickedIdx = leftIdx ?? rightIdx
            
            if isFirstInLeft {
                if let idx1 = firstIdx { leftItems[idx1].isWrong = true }
                if let idx2 = clickedIdx { rightItems[idx2].isWrong = true }
            } else {
                if let idx1 = firstIdx { rightItems[idx1].isWrong = true }
                if let idx2 = clickedIdx { leftItems[idx2].isWrong = true }
            }
            
            selectedId = nil
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            
            // Clean up error state after exactly 1.0 second and unlock board
            let targetFirstId = first.id
            let targetClickedId = clickedItem.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let idx1 = leftItems.firstIndex(where: { $0.id == targetFirstId }) { leftItems[idx1].isWrong = false }
                if let idx1 = rightItems.firstIndex(where: { $0.id == targetFirstId }) { rightItems[idx1].isWrong = false }
                if let idx2 = leftItems.firstIndex(where: { $0.id == targetClickedId }) { leftItems[idx2].isWrong = false }
                if let idx2 = rightItems.firstIndex(where: { $0.id == targetClickedId }) { rightItems[idx2].isWrong = false }
                
                isSelectionDisabled = false // Unlock interactions
            }
        }
    }
    
    private func clearSelectionStates() {
        for i in 0..<leftItems.count {
            leftItems[i].isSelected = false
            leftItems[i].isWrong = false
        }
        for i in 0..<rightItems.count {
            rightItems[i].isSelected = false
            rightItems[i].isWrong = false
        }
    }
    
    private func endGame() {
        if !isRobot { matchManager.finishMatch(score: userMatches) }
        cleanup()
        withAnimation {
            if userMatches > opponentMatches {
                gameState = .won
                earnedXP = isRobot ? 20 : 50
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Unlock next level if matched level is the current maximum level
                if isRobot { RobotArenaProgress.recordWin(level: activeCEFRLevel, robotLevel: robotLevel) }
                if isRobot {
                    Task { await SocialManager.shared.recordBotDuel(won: true) }
                }
            } else if userMatches < opponentMatches {
                gameState = .lost
                earnedXP = isRobot ? 5 : 15
                if isRobot {
                    Task { await SocialManager.shared.recordBotDuel(won: false) }
                }
            } else {
                gameState = .draw
                earnedXP = isRobot ? 5 : 25
                if isRobot {
                    Task { await SocialManager.shared.recordBotDuel(won: false) }
                }
            }
        }
    }
    
    // MARK: - Styling
    
    private func textColor(for item: MatchItem) -> Color {
        if item.isSelected { return Theme.fg }
        if item.isWrong { return Theme.fg }
        return Theme.fg.opacity(0.9)
    }
    
    private func backgroundColor(for item: MatchItem) -> Color {
        if item.isSelected { return Theme.accent.opacity(0.3) }
        if item.isWrong { return Theme.wrong.opacity(0.25) }
        return Theme.fg.opacity(0.06)
    }
    
    private func borderColor(for item: MatchItem) -> Color {
        if item.isSelected { return Theme.accent }
        if item.isWrong { return Theme.wrong }
        return Theme.fg.opacity(0.12)
    }
    
    // MARK: - Result View
    
    private var resultView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(resultColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Text(resultEmoji)
                    .font(.system(size: 60))
            }
            
            VStack(spacing: 8) {
                Text(resultTitle)
                    .font(.title.bold())
                    .foregroundColor(Theme.fg)
                
                Text(resultMessage)
                    .font(.body)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                if earnedXP > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(.yellow)
                        Text("+\(earnedXP) XP Kazanıldı!")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.yellow.opacity(0.18)))
                    .padding(.top, 6)
                }
            }
            
            // Scores summary
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text("Sen")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                    Text("\(userMatches)")
                        .font(.title.bold())
                        .foregroundColor(.green)
                }
                
                Text("vs")
                    .font(.headline)
                    .foregroundColor(Theme.fg.opacity(0.3))
                
                VStack(spacing: 4) {
                    Text(opponentName)
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                    Text("\(opponentMatches)")
                        .font(.title.bold())
                        .foregroundColor(.red)
                }
            }
            .padding()
            .background(Theme.fg.opacity(0.05))
            .cornerRadius(16)
            
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                Text("Kapat")
                    .font(.headline)
                    .foregroundColor(Theme.fg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(resultColor))
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 20)
        }
    }
    
    private var resultEmoji: String {
        switch gameState {
        case .won: return "🏆"
        case .lost: return "💔"
        case .draw: return "🤝"
        case .playing: return ""
        }
    }
    
    private var resultColor: Color {
        switch gameState {
        case .won: return .green
        case .lost: return .red
        case .draw: return .gray
        case .playing: return .blue
        }
    }
    
    private var resultTitle: String {
        switch gameState {
        case .won: return isRobot ? "Robot Seviyesi Geçildi! 🎉" : "Kazandın! 🏆"
        case .lost: return isRobot ? "Başaramadın! 💔" : "Kaybettin! 💔"
        case .draw: return "Berabere! 🤝"
        case .playing: return ""
        }
    }
    
    private var resultMessage: String {
        switch gameState {
        case .won:
            return isRobot
                ? "Seviye \(robotLevel) Yapay Zekasını yenerek bir sonraki robot seviyesinin kilidini açtın! Harika gidiyorsun."
                : "\(opponentName) isimli arkadaşını kelime hızında yenmeyi başardın! Harika iş çıkardın."
        case .lost:
            return isRobot
                ? "Robot senden daha hızlı kelimeleri eşleştirdi. Hızını arttırıp tekrar dene!"
                : "\(opponentName) senden biraz daha hızlı çıktı. Bir dahaki sefere daha hızlı eşleştirmeye çalış!"
        case .draw: return "İkiniz de aynı hızda bitirdiniz! Harika bir rekabetti."
        case .playing: return ""
        }
    }
}
