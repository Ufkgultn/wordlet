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
            finalCount = 20 // Seviye sınavları artık 20 soru
        } else if let star = starLevel {
            switch star {
            case 1: finalCount = 10
            case 2: finalCount = 15
            case 3: finalCount = 20
            default: finalCount = 10
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
        var wrongPool = distractorPool
            .filter { $0.id != word.id }
            .map { direction == .englishToTurkish ? $0.turkish : $0.english }
            .filter { $0 != correct }

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
}
