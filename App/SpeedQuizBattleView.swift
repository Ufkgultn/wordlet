import SwiftUI

struct SpeedQuizBattleView: View {
    let opponentName: String
    var opponentProfile: PublicProfile? = nil
    var isRobot: Bool = false
    var robotLevel: Int = 1
    
    @Environment(\.dismiss) var dismiss
    @AppStorage("robotDuelLevel") private var robotDuelLevelStorage: Int = 1
    @ObservedObject private var matchManager = MatchManager.shared
    
    @State private var words: [Word] = []
    @State private var allWordsForOptions: [Word] = []
    @State private var currentIndex = 0
    @State private var currentOptions: [String] = []
    
    @State private var userMatches = 0
    @State private var opponentMatches = 0
    @State private var timeRemaining = 60
    @State private var gameState: WordMatchBattleView.GameState = .playing
    @State private var earnedXP: Int = 0
    
    @State private var timer: Timer? = nil
    @State private var opponentTimer: Timer? = nil
    
    private var activeCEFRLevel: CEFRLevel { ProgressManager.shared.progress.currentLevel }
    
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 20) {
                headerView
                scoreBoard
                
                if gameState == .playing {
                    if currentIndex < words.count && !currentOptions.isEmpty {
                        VStack(spacing: 30) {
                            Text("Doğru Anlamı Seç!")
                                .font(.caption.bold())
                                .foregroundColor(Theme.accent)
                            
                            Text(words[currentIndex].english)
                                .font(.system(size: 38, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                            
                            VStack(spacing: 12) {
                                ForEach(currentOptions, id: \.self) { opt in
                                    Button(action: { checkAnswer(opt) }) {
                                        Text(opt)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 16)
                                            .background(Color.white.opacity(0.1))
                                            .cornerRadius(12)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.2), lineWidth: 1))
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
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
            if !isRobot {
                withAnimation(.spring()) { self.opponentMatches = newScore }
            }
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
        var opts = [words[currentIndex].turkish]
        let others = allWordsForOptions.filter { $0.id != words[currentIndex].id }.shuffled().prefix(3)
        opts.append(contentsOf: others.map { $0.turkish })
        currentOptions = opts.shuffled()
    }
    
    private func checkAnswer(_ opt: String) {
        guard currentIndex < words.count else { return }
        if opt == words[currentIndex].turkish {
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
    private var headerView: some View {
        HStack {
            Button(action: { cleanup(); dismiss() }) { Image(systemName: "xmark").font(.headline).foregroundColor(.white).padding(12).background(Circle().fill(Color.white.opacity(0.1))) }
            Spacer()
            Text(isRobot ? "Robot Seviye \(robotLevel)" : "Hızlı Seçim").font(.headline.bold()).foregroundColor(.white)
            Spacer()
            Text("\(timeRemaining)s").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.orange).padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.orange.opacity(0.15)))
        }.padding(.horizontal).padding(.top, 10)
    }
    
    private var scoreBoard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) { Text("Sen").font(.caption).foregroundColor(.white.opacity(0.6)); Text("\(userMatches)").font(.title3.bold()).foregroundColor(.green) }.padding(12).frame(maxWidth: .infinity).background(Color.white.opacity(0.06)).cornerRadius(12)
            VStack(alignment: .leading, spacing: 6) { Text(opponentName).font(.caption).foregroundColor(.white.opacity(0.6)); Text("\(opponentMatches)").font(.title3.bold()).foregroundColor(.red) }.padding(12).frame(maxWidth: .infinity).background(Color.white.opacity(0.06)).cornerRadius(12)
        }.padding(.horizontal)
    }
    
    private func cleanup() { timer?.invalidate(); timer = nil; opponentTimer?.invalidate(); opponentTimer = nil; if !isRobot { matchManager.resetMatch() } }
    
    private func endGame() {
        cleanup()
        withAnimation {
            if userMatches > opponentMatches {
                gameState = .won; earnedXP = isRobot ? (15 + robotLevel * 2) : 50
                if isRobot && robotLevel == robotDuelLevelStorage { robotDuelLevelStorage = min(30, robotDuelLevelStorage + 1) }
                Task { await SocialManager.shared.recordDuelWin(xpGained: earnedXP, isWin: true) }
            } else if userMatches < opponentMatches {
                gameState = .lost; earnedXP = isRobot ? 5 : 15
                Task { await SocialManager.shared.recordDuelWin(xpGained: earnedXP, isWin: false) }
            } else {
                gameState = .draw; earnedXP = isRobot ? 8 : 25
                Task { await SocialManager.shared.recordDuelWin(xpGained: earnedXP, isWin: false) }
            }
            if !isRobot, let myId = SocialManager.shared.myProfile?.id { Task { await matchManager.sendMatchFinished(winnerId: myId) } }
        }
    }
    
    private var resultView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(gameState == .won ? "🏆" : (gameState == .lost ? "💔" : "🤝")).font(.system(size: 80))
            Text(gameState == .won ? "Kazandın!" : (gameState == .lost ? "Kaybettin!" : "Berabere!")).font(.largeTitle.bold()).foregroundColor(.white)
            Text("Sen: \(userMatches) - \(opponentName): \(opponentMatches)").font(.headline).foregroundColor(.white.opacity(0.8))
            if earnedXP > 0 { Text("+\(earnedXP) XP").font(.title3.bold()).foregroundColor(.yellow) }
            Spacer()
            Button(action: { dismiss() }) { Text("Kapat").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(RoundedRectangle(cornerRadius: 16).fill(Color.blue)).padding(.horizontal, 24) }.padding(.bottom, 20)
        }
    }
}
