import SwiftUI

struct TypingBattleView: View {
    let opponentName: String
    var opponentProfile: PublicProfile? = nil
    var isRobot: Bool = false
    var robotLevel: Int = 1
    var targetCEFRLevel: CEFRLevel? = nil
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var matchManager = MatchManager.shared
    
    @State private var words: [Word] = []
    @State private var currentIndex = 0
    /// Hedef kelimenin karakterleri (büyük harf). Harf olmayanlar (tire vb.) otomatik dolu gelir.
    @State private var targetChars: [Character] = []
    /// Kullanıcının doldurduğu kutular: harf kutusu için seçilen tile'ın id'si
    @State private var filled: [UUID] = []
    /// Alttaki harf tuşları: kelimenin harfleri + birkaç şaşırtmaca harf
    @State private var letterTiles: [LetterTile] = []
    @State private var wrongShake = false
    
    private struct LetterTile: Identifiable {
        let id = UUID()
        let letter: Character
        var isUsed = false
    }
    
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
                // Header
                headerView
                scoreBoard
                
                if gameState == .playing {
                    if currentIndex < words.count {
                        VStack(spacing: 30) {
                            Text("Harflere Basarak İngilizcesini Yaz!")
                                .font(.caption.bold())
                                .foregroundColor(Theme.accentText)
                            
                            Text(words[currentIndex].turkish)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(Theme.fg)
                                .multilineTextAlignment(.center)
                            
                            answerSlots
                                .offset(x: wrongShake ? -8 : 0)
                            
                            letterKeyboard
                            
                            HStack(spacing: 12) {
                                Button(action: skipWord) {
                                    Label("Pas", systemImage: "forward.fill")
                                        .font(.subheadline.bold())
                                        .foregroundColor(Theme.fg.opacity(0.7))
                                        .padding(.horizontal, 18).padding(.vertical, 10)
                                        .background(Capsule().fill(Theme.fg.opacity(0.08)))
                                }
                                Button(action: deleteLast) {
                                    Label("Sil", systemImage: "delete.left.fill")
                                        .font(.subheadline.bold())
                                        .foregroundColor(Theme.fg)
                                        .padding(.horizontal, 18).padding(.vertical, 10)
                                        .background(Capsule().fill(Color.red.opacity(0.35)))
                                }
                                .disabled(filled.isEmpty)
                                .opacity(filled.isEmpty ? 0.4 : 1)
                            }
                        }
                        .padding(.top, 24)
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
            if !isRobot {
                withAnimation(.spring()) { self.opponentMatches = newScore }
            }
        }
        .onChange(of: matchManager.matchFinishedEventReceived) { finished in
            if finished && !isRobot && gameState == .playing { endGame() }
        }
    }
    
    // MARK: - Letter Input
    
    private var letterSlotCount: Int { targetChars.filter { $0.isLetter }.count }
    
    private var slotSize: CGFloat {
        let count = CGFloat(max(targetChars.count, 1))
        let available = UIScreen.main.bounds.width - 32 - (count - 1) * 4
        return min(36, floor(available / count))
    }
    
    private var answerSlots: some View {
        // Harf kutularına sırayla dolan karakterleri hesapla
        var letterIndex = 0
        let display: [(char: Character?, isFixed: Bool, tileId: UUID?)] = targetChars.map { ch in
            guard ch.isLetter else { return (ch, true, nil) }
            defer { letterIndex += 1 }
            guard letterIndex < filled.count,
                  let tile = letterTiles.first(where: { $0.id == filled[letterIndex] }) else { return (nil, false, nil) }
            return (tile.letter, false, tile.id)
        }
        
        return HStack(spacing: 4) {
            ForEach(Array(display.enumerated()), id: \.offset) { _, slot in
                if slot.isFixed {
                    Text(String(slot.char ?? " "))
                        .font(.system(size: slotSize * 0.6, weight: .bold))
                        .foregroundColor(Theme.fg.opacity(0.6))
                        .frame(width: slotSize * 0.5, height: slotSize * 1.25)
                } else {
                    Text(slot.char.map { String($0) } ?? "")
                        .font(.system(size: slotSize * 0.6, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.fg)
                        .frame(width: slotSize, height: slotSize * 1.25)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(slot.char == nil ? Theme.fg.opacity(0.08) : Theme.accent.opacity(0.35))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(wrongShake ? Color.red : Theme.fg.opacity(0.15), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Kutudaki harfe basınca harf alttaki tuşlara geri döner
                            if let id = slot.tileId { returnLetter(id) }
                        }
                }
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var letterKeyboard: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(letterTiles) { tile in
                Button(action: { tile.isUsed ? returnLetter(tile.id) : tapLetter(tile.id) }) {
                    Text(String(tile.letter))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.fg.opacity(tile.isUsed ? 0.03 : 0.14))
                        )
                        .opacity(tile.isUsed ? 0.25 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }
    
    private func loadQuestion() {
        guard currentIndex < words.count else { return }
        targetChars = Array(words[currentIndex].english.trimmingCharacters(in: .whitespaces).uppercased())
        filled = []
        
        let wordLetters = targetChars.filter { $0.isLetter }
        let alphabet = Array("AEIOURSTLNMDCPBGHKWY") // yaygın harfler: şaşırtmacalar kolay elenmesin
        let decoyCount = Self.decoyCount(for: words[currentIndex].level)
        let decoys = (0..<decoyCount).compactMap { _ in alphabet.randomElement() }
        letterTiles = (wordLetters + decoys).shuffled().map { LetterTile(letter: $0) }
    }
    
    /// Şaşırtmaca harf sayısı seviyeye göre artar: A1'de hiç yok
    private static func decoyCount(for level: CEFRLevel) -> Int {
        switch level {
        case .a1: return 0
        case .a2: return 2
        case .b1: return 3
        case .b2: return 4
        }
    }
    
    private func tapLetter(_ id: UUID) {
        guard let idx = letterTiles.firstIndex(where: { $0.id == id }),
              !letterTiles[idx].isUsed,
              filled.count < letterSlotCount else { return }
        letterTiles[idx].isUsed = true
        filled.append(id)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        if filled.count == letterSlotCount { checkAnswer() }
    }
    
    private func returnLetter(_ id: UUID) {
        guard let pos = filled.firstIndex(of: id),
              let idx = letterTiles.firstIndex(where: { $0.id == id }) else { return }
        filled.remove(at: pos)
        letterTiles[idx].isUsed = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func deleteLast() {
        guard let last = filled.popLast(),
              let idx = letterTiles.firstIndex(where: { $0.id == last }) else { return }
        letterTiles[idx].isUsed = false
    }
    
    private func skipWord() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        currentIndex += 1
        loadQuestion()
    }
    
    private func checkAnswer() {
        guard currentIndex < words.count else { return }
        let answer = filled.compactMap { id in letterTiles.first(where: { $0.id == id })?.letter }
        
        if answer == targetChars.filter({ $0.isLetter }) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            userMatches += 1
            if !isRobot { Task { await matchManager.sendLiveScore(score: userMatches) } }
            currentIndex += 1
            loadQuestion()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) { wrongShake = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                wrongShake = false
                filled = []
                for i in letterTiles.indices { letterTiles[i].isUsed = false }
            }
        }
    }
    
    // Boilerplate code (Header, Setup, EndGame, Result)
    private var headerView: some View {
        HStack {
            Button(action: { cleanup(); dismiss() }) {
                Image(systemName: "xmark").font(.headline).foregroundColor(Theme.fg).padding(12).background(Circle().fill(Theme.fg.opacity(0.1)))
            }
            Spacer()
            Text(isRobot ? "Robot Seviye \(robotLevel)" : "Yazma Yarışı").font(.headline.bold()).foregroundColor(Theme.fg)
            Spacer()
            Text("\(timeRemaining)s").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.orange).padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(Color.orange.opacity(0.15)))
        }.padding(.horizontal).padding(.top, 10)
    }
    
    private var scoreBoard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sen").font(.caption).foregroundColor(Theme.fg.opacity(0.6))
                Text("\(userMatches)").font(.title3.bold()).foregroundColor(.green)
            }.padding(12).frame(maxWidth: .infinity).background(Theme.fg.opacity(0.06)).cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(opponentName).font(.caption).foregroundColor(Theme.fg.opacity(0.6))
                Text("\(opponentMatches)").font(.title3.bold()).foregroundColor(.red)
            }.padding(12).frame(maxWidth: .infinity).background(Theme.fg.opacity(0.06)).cornerRadius(12)
        }.padding(.horizontal)
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
            let aiInterval = max(2.0, 8.0 - Double(robotLevel) * 0.2)
            opponentTimer = Timer.scheduledTimer(withTimeInterval: aiInterval, repeats: true) { _ in
                guard gameState == .playing else { return }
                opponentMatches += 1
            }
        }
    }
    
    private func cleanup() {
        timer?.invalidate(); timer = nil
        opponentTimer?.invalidate(); opponentTimer = nil
        if !isRobot { matchManager.resetMatch() }
    }
    
    private func endGame() {
        if !isRobot { matchManager.finishMatch(score: userMatches) }
        cleanup()
        withAnimation {
            if userMatches > opponentMatches {
                gameState = .won; earnedXP = isRobot ? 20 : 50
                if isRobot { RobotArenaProgress.recordWin(level: activeCEFRLevel, robotLevel: robotLevel) }
                if isRobot { Task { await SocialManager.shared.recordBotDuel(won: true) } }
            } else if userMatches < opponentMatches {
                gameState = .lost; earnedXP = isRobot ? 5 : 15
                if isRobot { Task { await SocialManager.shared.recordBotDuel(won: false) } }
            } else {
                gameState = .draw; earnedXP = isRobot ? 5 : 25
                if isRobot { Task { await SocialManager.shared.recordBotDuel(won: false) } }
            }
        }
    }
    
    private var resultView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(gameState == .won ? "🏆" : (gameState == .lost ? "💔" : "🤝")).font(.system(size: 80))
            Text(gameState == .won ? "Kazandın!" : (gameState == .lost ? "Kaybettin!" : "Berabere!")).font(.largeTitle.bold()).foregroundColor(Theme.fg)
            Text("Sen: \(userMatches) - \(opponentName): \(opponentMatches)").font(.headline).foregroundColor(Theme.fg.opacity(0.8))
            if earnedXP > 0 { Text("+\(earnedXP) XP").font(.title3.bold()).foregroundColor(.yellow) }
            Spacer()
            Button(action: { dismiss() }) {
                Text("Kapat").font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(RoundedRectangle(cornerRadius: 16).fill(Color.blue)).padding(.horizontal, 24)
            }
            .padding(.bottom, 20)
        }
    }
}
