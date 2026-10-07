import Foundation

public enum QuizDirection {
    case englishToTurkish
    case turkishToEnglish
}

public struct QuizQuestion: Identifiable {
    public let id = UUID()
    public let word: Word
    public let choices: [String]
    public let correctAnswer: String
    public let direction: QuizDirection

    public var prompt: String {
        switch direction {
        case .englishToTurkish:
            return "\(word.english) kelimesinin Türkçesi nedir?"
        case .turkishToEnglish:
            return "\(word.turkish) anlamına gelen İngilizce kelime hangisi?"
        }
    }
}

public class QuizManager {
    public static let shared = QuizManager()
    private init() {}

    /// Quiz oluştur
    /// - Parameters:
    ///   - count: Soru sayısı (starLevel verilirse ezilir)
    ///   - targetLevel: Hangi seviye için quiz yapılacak (nil = mevcut seviye)
    ///   - levelTest: true → tüm seviye kelimelerinden, false → görülen kelimelerden
    ///   - starLevel: 1, 2 veya 3 yıldız seviyesi (soru sayısını belirler)
    public func generateQuiz(
        count: Int? = nil,
        targetLevel: CEFRLevel? = nil,
        levelTest: Bool = false,
        starLevel: Int? = nil
    ) -> [QuizQuestion] {
        let level = targetLevel ?? ProgressManager.shared.progress.currentLevel
        let allLevelWords = WordManager.shared.words(for: level)

        // Soru sayısını belirle
        let finalCount: Int
        if levelTest {
            if let sourceLevel = level.previous {
                finalCount = ProgressRequirements.requirements(for: sourceLevel).examQuestionCount
            } else {
                finalCount = 20
            }
        } else if let star = starLevel {
            if star <= 3 {
                finalCount = 10
            } else if star <= 7 {
                finalCount = 15
            } else {
                finalCount = 20
            }
        } else {
            finalCount = count ?? 10
        }

        let baseWords: [Word]
        if levelTest {
            // Level test: tüm seviye kelimelerinden rastgele seç
            baseWords = allLevelWords
        } else {
            // Normal quiz: sadece görülen kelimeler
            let seenIDs = Set(WordManager.shared.seenWordIDs())
            let seenLevelWords = allLevelWords.filter { seenIDs.contains($0.id) }
            // Eğer görülen kelime azsa tüm seviyeden seç ki quiz boş kalmasın
            baseWords = seenLevelWords.count >= 4 ? seenLevelWords : allLevelWords
        }

        guard baseWords.count >= 4 else { return [] }

        // Distractor pool: tüm seviyeden kelimeler (yanlış seçenekler için daha geniş havuz)
        let distractorPool = allLevelWords

        let questionWords = Array(baseWords.shuffled().prefix(min(finalCount, baseWords.count)))
        return questionWords.compactMap { makeQuestion(for: $0, distractorPool: distractorPool) }
    }

    private func makeQuestion(for word: Word, distractorPool: [Word]) -> QuizQuestion? {
        let direction: QuizDirection = Bool.random() ? .englishToTurkish : .turkishToEnglish

        let correct = direction == .englishToTurkish ? word.turkish : word.english
        let answers: ([Word]) -> [String] = { pool in
            Array(Set(pool
                .filter { $0.id != word.id }
                .map { direction == .englishToTurkish ? $0.turkish : $0.english }
                .filter { $0 != correct }))
        }
        // Yanlış şıklar aynı kelime türünden olsun (fiile fiil, isme isim); yetmezse tüm havuz
        var wrongPool = answers(distractorPool.filter { word.pos != nil && $0.pos == word.pos })
        if wrongPool.count < 3 {
            wrongPool = answers(distractorPool)
        }

        guard wrongPool.count >= 3 else { return nil }
        wrongPool.shuffle()

        let choices = ([correct] + Array(wrongPool.prefix(3))).shuffled()

        return QuizQuestion(
            word: word,
            choices: choices,
            correctAnswer: correct,
            direction: direction
        )
    }
    
    /// Seviye tespit testi: her seviyeden, o seviyenin en yaygın 150 kelimesi arasından 5 soru
    public static let placementQuestionsPerLevel = 5

    public func generatePlacementTest() -> [QuizQuestion] {
        CEFRLevel.allCases.flatMap { level -> [QuizQuestion] in
            let levelWords = WordManager.shared.words(for: level)
            let common = levelWords
                .sorted { ($0.freqRank ?? Int.max) < ($1.freqRank ?? Int.max) }
                .prefix(150)
            return common.shuffled()
                .prefix(Self.placementQuestionsPerLevel)
                .compactMap { makeQuestion(for: $0, distractorPool: levelWords) }
        }
    }

    /// Günlük test: önce tekrar zamanı gelenler, sonra öğrenilmekte olanlar, sonra 4-5 yeni kelime
    /// (en yaygından başlayarak). Eksik kalırsa en zayıf hatırlanan kelimelerle tamamlanır.
    public func generateDailyTest(for level: CEFRLevel) -> [QuizQuestion] {
        let allLevelWords = WordManager.shared.words(for: level)
        let byId = Dictionary(uniqueKeysWithValues: allLevelWords.map { ($0.id, $0) })
        let memory = MemoryStore.shared.all
        let totalCount = 20
        let maxReview = 15
        let newCount = 5

        var picked: [Word] = []
        var used = Set<String>()
        func take(_ words: [Word], upTo limit: Int) {
            for w in words where picked.count < limit && !used.contains(w.id) {
                picked.append(w)
                used.insert(w.id)
            }
        }

        let due = MemoryStore.shared.dueWordIDs(among: Set(byId.keys)).compactMap { byId[$0] }
        take(due, upTo: maxReview)

        let learning = allLevelWords.filter { memory[$0.id]?.state == .learning }
        take(learning, upTo: maxReview)

        let fresh = allLevelWords
            .filter { memory[$0.id] == nil }
            .sorted { ($0.freqRank ?? Int.max) < ($1.freqRank ?? Int.max) }
        take(fresh, upTo: picked.count + newCount)

        // Hâlâ eksikse: en düşük stabiliteli (en kolay unutulacak) kelimeler
        let weakest = allLevelWords
            .filter { memory[$0.id].map { $0.state == .review } ?? false }
            .sorted { (memory[$0.id]?.stability ?? 0) < (memory[$1.id]?.stability ?? 0) }
        take(weakest, upTo: totalCount)
        take(fresh, upTo: totalCount)

        return picked.shuffled().compactMap { makeQuestion(for: $0, distractorPool: allLevelWords) }
    }
}
