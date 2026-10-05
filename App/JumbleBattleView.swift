import SwiftUI

struct JumbleBattleView: View {
    let opponentName: String
    var opponentProfile: PublicProfile? = nil
    var isRobot: Bool = false
    var robotLevel: Int = 1
    var targetCEFRLevel: CEFRLevel? = nil
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var matchManager = MatchManager.shared
    
    @State private var words: [Word] = []
    @State private var currentIndex = 0
    @State private var targetLetters: [String] = []
    @State private var jumbledLetters: [(id: UUID, letter: String, isUsed: Bool)] = []
    @State private var currentInput: [String] = []
    
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
                        VStack(spacing: 30) {
                            Text("Harfleri Sıraya Diz!")
                                .font(.caption.bold())
                                .foregroundColor(Theme.accent)
                            
                            Text(words[currentIndex].turkish)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            // Gösterilen Harfler (Çizgiler/Seçilenler)
                            HStack {
                                ForEach(0..<targetLetters.count, id: \.self) { i in
                                    Text(i < currentInput.count ? currentInput[i] : "_")
                                        .font(.title2.bold())
                                        .foregroundColor(i < currentInput.count ? .white : .white.opacity(0.3))
                                        .frame(width: 30, height: 40)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            
                            // Harf Butonları
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 12) {
                                ForEach(jumbledLetters.indices, id: \.self) { index in
                                    let item = jumbledLetters[index]
                                    Button(action: { selectLetter(index: index) }) {
                                        Text(item.letter)
                                            .font(.title3.bold())
                                            .foregroundColor(.white)
                                            .frame(width: 50, height: 50)
                                            .background(item.isUsed ? Color.white.opacity(0.1) : Theme.accent)
                                            .cornerRadius(12)
                                    }
                                    .disabled(item.isUsed)
                                }
                            }
                            .padding(.horizontal, 30)
                            
                            Button(action: resetCurrentInput) {
                                Text("Temizle")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.top, 20)
                    }
                } else {
                    resultView
                }
                Spacer()
            }
        }
        .onAppear { setupGame() }
        .onDisappear { cleanup() }
        .onChange(of: matchManager.opponentLiveScore) { newScore in
            if !isRobot { withAnimation(.spring()) { self.opponentMatches = newScore } }
        }
        .onChange(of: matchManager.matchFinishedEventReceived) { finished in
            if finished && !isRobot && gameState == .playing { endGame() }
        }
    }
    
    private func setupGame() {
        if !isRobot, let match = matchManager.activeMatch, !match.wordIds.isEmpty {
            let matchLevel = CEFRLevel(rawValue: match.level) ?? activeCEFRLevel
            let allWords = WordManager.shared.words(for: matchLevel)
            let matched = match.wordIds.compactMap { wid in allWords.first(where: { $0.id == wid }) }
            words = matched.isEmpty ? Array(allWords.shuffled().prefix(50)) : matched
        } else {
            words = Array(WordManager.shared.words(for: activeCEFRLevel).shuffled().prefix(50))
        }
        
        loadQuestion()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 { timeRemaining -= 1 } else { endGame() }
        }
        
        if isRobot {
            let aiInterval = max(2.5, 9.0 - Double(robotLevel) * 0.25)
            opponentTimer = Timer.scheduledTimer(withTimeInterval: aiInterval, repeats: true) { _ in
                guard gameState == .playing else { return }
                opponentMatches += 1
            }
        }
    }
    
    private func loadQuestion() {
        guard currentIndex < words.count else { return }
        let word = words[currentIndex].english.uppercased()
        targetLetters = word.map { String($0) }
        jumbledLetters = targetLetters.shuffled().map { (UUID(), $0, false) }
        currentInput = []
    }
    
    private func selectLetter(index: Int) {
        guard !jumbledLetters[index].isUsed else { return }
        jumbledLetters[index].isUsed = true
        currentInput.append(jumbledLetters[index].letter)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        if currentInput.count == targetLetters.count {
            if currentInput == targetLetters {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                userMatches += 1
                if !isRobot { Task { await matchManager.sendLiveScore(score: userMatches) } }
                currentIndex += 1
                loadQuestion()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                resetCurrentInput()
            }
        }
    }
    
    private func resetCurrentInput() {
        currentInput = []
        for i in 0..<jumbledLetters.count { jumbledLetters[i].isUsed = false }
    }
    
    // Boilerplate code
    private var headerView: some View { HStack { Button(action: { cleanup(); dismiss() }) { Image(systemName: "xmark").font(.headline).foregroundColor(.white).padding(12).background(Circle().fill(Color.white.opacity(0.1))) }; Spacer(); Text(isRobot ? "Robot Seviye \(robotLevel)" : "Harf Avı").font(.headline.bold()).foregroundColor(.white); Spacer(); Text("\(timeRemaining)s").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.orange).padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.orange.opacity(0.15))) }.padding(.horizontal).padding(.top, 10) }
    private var scoreBoard: some View { HStack(spacing: 16) { VStack(alignment: .leading, spacing: 6) { Text("Sen").font(.caption).foregroundColor(.white.opacity(0.6)); Text("\(userMatches)").font(.title3.bold()).foregroundColor(.green) }.padding(12).frame(maxWidth: .infinity).background(Color.white.opacity(0.06)).cornerRadius(12); VStack(alignment: .leading, spacing: 6) { Text(opponentName).font(.caption).foregroundColor(.white.opacity(0.6)); Text("\(opponentMatches)").font(.title3.bold()).foregroundColor(.red) }.padding(12).frame(maxWidth: .infinity).background(Color.white.opacity(0.06)).cornerRadius(12) }.padding(.horizontal) }
    private func cleanup() { timer?.invalidate(); timer = nil; opponentTimer?.invalidate(); opponentTimer = nil; if !isRobot { matchManager.resetMatch() } }
    private func endGame() { cleanup(); withAnimation { if userMatches > opponentMatches { gameState = .won; earnedXP = isRobot ? (15 + robotLevel * 2) : 50; if isRobot { let key = "robotDuelLevel_\(activeCEFRLevel.rawValue)"; let c = UserDefaults.standard.integer(forKey: key); let s = c == 0 ? 1 : c; if robotLevel == s { UserDefaults.standard.set(min(30, s + 1), forKey: key) } }; Task { await SocialManager.shared.recordDuelWin(xpGained: earnedXP, isWin: true) } } else if userMatches < opponentMatches { gameState = .lost; earnedXP = isRobot ? 5 : 15; Task { await SocialManager.shared.recordDuelWin(xpGained: earnedXP, isWin: false) } } else { gameState = .draw; earnedXP = isRobot ? 8 : 25; Task { await SocialManager.shared.recordDuelWin(xpGained: earnedXP, isWin: false) } }; if !isRobot, let myId = SocialManager.shared.myProfile?.id { Task { await matchManager.sendMatchFinished(winnerId: myId) } } } }
    private var resultView: some View { VStack(spacing: 24) { Spacer(); Text(gameState == .won ? "🏆" : (gameState == .lost ? "💔" : "🤝")).font(.system(size: 80)); Text(gameState == .won ? "Kazandın!" : (gameState == .lost ? "Kaybettin!" : "Berabere!")).font(.largeTitle.bold()).foregroundColor(.white); Text("Sen: \(userMatches) - \(opponentName): \(opponentMatches)").font(.headline).foregroundColor(.white.opacity(0.8)); if earnedXP > 0 { Text("+\(earnedXP) XP").font(.title3.bold()).foregroundColor(.yellow) }; Spacer(); Button(action: { dismiss() }) { Text("Kapat").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(RoundedRectangle(cornerRadius: 16).fill(Color.blue)).padding(.horizontal, 24) }.padding(.bottom, 20) } }
}
