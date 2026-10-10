import SwiftUI

struct TrueFalseBattleView: View {
    let opponentName: String
    var opponentProfile: PublicProfile? = nil
    var isRobot: Bool = false
    var robotLevel: Int = 1
    var targetCEFRLevel: CEFRLevel? = nil
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var matchManager = MatchManager.shared
    
    @State private var words: [Word] = []
    @State private var allWordsForOptions: [Word] = []
    @State private var currentIndex = 0
    @State private var displayedTurkish = ""
    @State private var isCorrectMatch = false
    
    @State private var userMatches = 0
    @State private var opponentMatches = 0
    @State private var timeRemaining = 60
    @State private var gameState: WordMatchBattleView.GameState = .playing
    @State private var earnedXP: Int = 0
    
    @State private var timer: Timer? = nil
    @State private var opponentTimer: Timer? = nil
    
    private var activeCEFRLevel: CEFRLevel { targetCEFRLevel ?? ProgressManager.shared.progress.currentLevel }
    
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                headerView
                scoreBoard
                
                if gameState == .playing {
                    if currentIndex < words.count {
                        VStack(spacing: 40) {
                            Text("Eşleştirme Doğru mu?")
                                .font(.caption.bold())
                                .foregroundColor(Theme.accentText)
                            
                            VStack(spacing: 16) {
                                Text(words[currentIndex].english)
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .foregroundColor(Theme.fg)
                                
                                Text("=")
                                    .font(.title)
                                    .foregroundColor(Theme.fg.opacity(0.5))
                                
                                Text(displayedTurkish)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.accentText)
                            }
                            .multilineTextAlignment(.center)
                            
                            HStack(spacing: 20) {
                                Button(action: { checkAnswer(true) }) {
                                    VStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 40))
                                        Text("DOĞRU")
                                            .font(.headline.bold())
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(Color.green)
                                    .cornerRadius(16)
                                }
                                
                                Button(action: { checkAnswer(false) }) {
                                    VStack {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 40))
                                        Text("YANLIŞ")
                                            .font(.headline.bold())
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 20)
                                    .background(Color.red)
                                    .cornerRadius(16)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .padding(.top, 40)
                    }
                } else {
                    resultView
                }
                Spacer()
            }
        }
        .onAppear { setupGame() }
        .onDisappear { cleanup() }
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
            if !isRobot { withAnimation(.spring()) { self.opponentMatches = newScore } }
        }
        .onChange(of: matchManager.matchFinishedEventReceived) { finished in
            if finished && !isRobot && gameState == .playing { endGame() }
        }
    }
    
    private func setupGame() {
        allWordsForOptions = WordManager.shared.words(for: activeCEFRLevel)
        if !isRobot, let match = matchManager.activeMatch, !match.wordIds.isEmpty {
            let matchLevel = CEFRLevel(rawValue: match.level) ?? activeCEFRLevel
            let all = WordManager.shared.words(for: matchLevel)
            allWordsForOptions = all
            let matched = match.wordIds.compactMap { wid in all.first(where: { $0.id == wid }) }
            words = matched.isEmpty ? Array(all.shuffled().prefix(50)) : matched
        } else {
            words = Array(allWordsForOptions.shuffled().prefix(50))
        }
        
        loadQuestion()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 { timeRemaining -= 1 } else { endGame() }
        }
        
        if isRobot {
            let aiInterval = max(1.5, 6.0 - Double(robotLevel) * 0.15)
            opponentTimer = Timer.scheduledTimer(withTimeInterval: aiInterval, repeats: true) { _ in
                guard gameState == .playing else { return }
                opponentMatches += 1
            }
        }
    }
    
    private func loadQuestion() {
        guard currentIndex < words.count else { return }
        isCorrectMatch = Bool.random()
        if isCorrectMatch {
            displayedTurkish = words[currentIndex].turkish
        } else {
            let others = allWordsForOptions.filter { $0.id != words[currentIndex].id }
            displayedTurkish = others.randomElement()?.turkish ?? words[currentIndex].turkish
        }
    }
    
    private func checkAnswer(_ choice: Bool) {
        guard currentIndex < words.count else { return }
        if choice == isCorrectMatch {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            userMatches += 1
            if !isRobot { Task { await matchManager.sendLiveScore(score: userMatches) } }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            timeRemaining = max(0, timeRemaining - 2) // Yanlış cevap -2 saniye
        }
        currentIndex += 1
        loadQuestion()
    }
    
    // Boilerplate code
    private var headerView: some View { HStack { Button(action: { cleanup(); dismiss() }) { Image(systemName: "xmark").font(.headline).foregroundColor(Theme.fg).padding(12).background(Circle().fill(Theme.fg.opacity(0.1))) }; Spacer(); Text(isRobot ? "Robot Seviye \(robotLevel)" : "Doğru/Yanlış").font(.headline.bold()).foregroundColor(Theme.fg); Spacer(); Text("\(timeRemaining)s").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.orange).padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.orange.opacity(0.15))) }.padding(.horizontal).padding(.top, 10) }
    private var scoreBoard: some View { HStack(spacing: 16) { VStack(alignment: .leading, spacing: 6) { Text("Sen").font(.caption).foregroundColor(Theme.fg.opacity(0.6)); Text("\(userMatches)").font(.title3.bold()).foregroundColor(.green) }.padding(12).frame(maxWidth: .infinity).background(Theme.fg.opacity(0.06)).cornerRadius(12); VStack(alignment: .leading, spacing: 6) { Text(opponentName).font(.caption).foregroundColor(Theme.fg.opacity(0.6)); Text("\(opponentMatches)").font(.title3.bold()).foregroundColor(.red) }.padding(12).frame(maxWidth: .infinity).background(Theme.fg.opacity(0.06)).cornerRadius(12) }.padding(.horizontal) }
    private func cleanup() { timer?.invalidate(); timer = nil; opponentTimer?.invalidate(); opponentTimer = nil; if !isRobot { matchManager.resetMatch() } }
    private func endGame() { if !isRobot { matchManager.finishMatch(score: userMatches) }; cleanup(); withAnimation { if userMatches > opponentMatches { gameState = .won; earnedXP = isRobot ? 20 : 50; if isRobot { RobotArenaProgress.recordWin(level: activeCEFRLevel, robotLevel: robotLevel) }; if isRobot { Task { await SocialManager.shared.recordBotDuel(won: true) } } } else if userMatches < opponentMatches { gameState = .lost; earnedXP = isRobot ? 5 : 15; if isRobot { Task { await SocialManager.shared.recordBotDuel(won: false) } } } else { gameState = .draw; earnedXP = isRobot ? 5 : 25; if isRobot { Task { await SocialManager.shared.recordBotDuel(won: false) } } }; } }
    private var resultView: some View { VStack(spacing: 24) { Spacer(); Text(gameState == .won ? "🏆" : (gameState == .lost ? "💔" : "🤝")).font(.system(size: 80)); Text(gameState == .won ? "Kazandın!" : (gameState == .lost ? "Kaybettin!" : "Berabere!")).font(.largeTitle.bold()).foregroundColor(Theme.fg); Text("Sen: \(userMatches) - \(opponentName): \(opponentMatches)").font(.headline).foregroundColor(Theme.fg.opacity(0.8)); if earnedXP > 0 { Text("+\(earnedXP) XP").font(.title3.bold()).foregroundColor(.yellow) }; Spacer(); Button(action: { dismiss() }) { Text("Kapat").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(RoundedRectangle(cornerRadius: 16).fill(Color.blue)).padding(.horizontal, 24) }.padding(.bottom, 20) } }
}
