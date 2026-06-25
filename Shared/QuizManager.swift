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

// MARK: - Distractor Difficulty

/// Şıkların zorluk seviyesini belirler.
/// Yıldız seviyesi arttıkça şıklar daha kafa karıştırıcı olur.
public enum DistractorDifficulty {
    case easy      // Yıldız 1-3: Açıkça farklı ama makul şıklar
    case medium    // Yıldız 4-7: Benzer yapıda, kafa karıştırabilecek şıklar
    case hard      // Yıldız 8-10: Anlam olarak çok yakın, zorlayıcı şıklar
    case exam      // Seviye sınavı: Karışık zorluk

    init(starLevel: Int?) {
        guard let star = starLevel else {
            self = .medium
            return
        }
        switch star {
        case 1...3:  self = .easy
        case 4...7:  self = .medium
        default:     self = .hard
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

        // Distractor pool: tüm seviyeden kelimeler (yanlış seçenekler için geniş havuz)
        let distractorPool = allLevelWords

        // Art arda aynı kelimenin gelmesini engelle
        let questionWords = selectWithoutConsecutiveDuplicates(
            from: baseWords,
            count: min(finalCount, baseWords.count)
        )

        // Yön dengeleme: yarısı EN→TR, yarısı TR→EN (karıştırılmış)
        let directions = balancedDirections(count: questionWords.count)

        // Zorluk seviyesini belirle
        let difficulty: DistractorDifficulty
        if levelTest {
            difficulty = .exam
        } else {
            difficulty = DistractorDifficulty(starLevel: starLevel)
        }

        return zip(questionWords, directions).compactMap { word, direction in
            makeQuestion(
                for: word,
                distractorPool: distractorPool,
                direction: direction,
                difficulty: difficulty
            )
        }
    }

    // MARK: - Smart Question Generation

    private func makeQuestion(
        for word: Word,
        distractorPool: [Word],
        direction: QuizDirection,
        difficulty: DistractorDifficulty
    ) -> QuizQuestion? {
        let correct = direction == .englishToTurkish ? word.turkish : word.english
        let isTurkishChoices = direction == .englishToTurkish

        // 1. Eş anlamlı / aynı çeviriye sahip kelimeleri filtrele (synonym koruması)
        let filteredPool = distractorPool.filter { candidate in
            guard candidate.id != word.id else { return false }
            if isTurkishChoices {
                return candidate.turkish.lowercased() != word.turkish.lowercased()
            } else {
                return candidate.english.lowercased() != word.english.lowercased()
            }
        }

        // 2. Benzersiz yanlış şık metinlerini çıkar
        let wrongStrings = filteredPool.map {
            isTurkishChoices ? $0.turkish : $0.english
        }
        let uniqueWrong = Array(Set(wrongStrings)).filter {
            $0.lowercased() != correct.lowercased()
        }

        guard uniqueWrong.count >= 3 else { return nil }

        // 3. Zorluk seviyesine göre akıllı şık seçimi
        let selected = selectSmartDistractors(
            from: uniqueWrong,
            correctAnswer: correct,
            count: 3,
            difficulty: difficulty,
            isTurkish: isTurkishChoices
        )

        let choices = ([correct] + selected).shuffled()

        return QuizQuestion(
            word: word,
            choices: choices,
            correctAnswer: correct,
            direction: direction
        )
    }

    // MARK: - Smart Distractor Selection (Zorluk Bazlı)

    /// Zorluk seviyesine göre şıkları seçer.
    /// - easy: Farklı ama mantıklı şıklar (kolay elenebilir değil ama ayırt edilebilir)
    /// - medium: Benzer yapıda şıklar (aynı kelime türü, benzer uzunluk)
    /// - hard: Anlam olarak çok yakın, kafa karıştırıcı şıklar (aynı kök, benzer yapı)
    /// - exam: Karışık zorlukta şıklar
    private func selectSmartDistractors(
        from pool: [String],
        correctAnswer: String,
        count: Int,
        difficulty: DistractorDifficulty,
        isTurkish: Bool
    ) -> [String] {
        guard pool.count >= count else {
            return Array(pool.shuffled().prefix(count))
        }

        // Her adayın doğru cevaba semantik benzerliğini hesapla
        let scored: [(String, Double)] = pool.map { candidate in
            let sim = computeSimilarity(correctAnswer, candidate, isTurkish: isTurkish)
            return (candidate, sim)
        }.sorted { $0.1 > $1.1 } // Benzerliğe göre azalan sıra (en benzer = en başta)

        let total = scored.count

        // Zorluk seviyesine göre hangi benzerlik diliminden seçim yapılacağını belirle
        let startIdx: Int
        let endIdx: Int

        switch difficulty {
        case .easy:
            // %30-%75 dilimi: açıkça farklı ama aynı kelime türünde olabilecek şıklar
            startIdx = total * 30 / 100
            endIdx = total * 75 / 100
        case .medium:
            // %10-%50 dilimi: benzer yapıda, biraz kafa karıştırıcı şıklar
            startIdx = total * 10 / 100
            endIdx = total * 50 / 100
        case .hard:
            // %0-%25 dilimi: en benzer, en kafa karıştırıcı şıklar
            startIdx = 0
            endIdx = total * 25 / 100
        case .exam:
            // %0-%40 dilimi: karışık zorluk (sınav modunda genel olarak zorlayıcı)
            startIdx = 0
            endIdx = total * 40 / 100
        }

        // Güvenli aralık hesaplama (en az 'count' kadar aday olmasını garanti et)
        let safeStart = min(startIdx, max(0, total - count))
        let safeEnd = max(min(endIdx, total), safeStart + count)
        let clampedEnd = min(safeEnd, total)

        let candidates = Array(scored[safeStart..<clampedEnd])
        let selected = Array(candidates.shuffled().prefix(count)).map { $0.0 }

        // Yeterli aday yoksa havuzdan rastgele tamamla
        if selected.count < count {
            let remaining = pool.filter { !selected.contains($0) }.shuffled()
            return selected + Array(remaining.prefix(count - selected.count))
        }

        return selected
    }

    // MARK: - Semantic Similarity (Anlam Benzerliği)

    /// İki metin arasındaki semantik benzerliği hesaplar (0.0 = tamamen farklı, 1.0 = aynı).
    /// Türkçe morfoloji, karakter trigram'ları, kelime örtüşmesi ve uzunluk benzerliği kullanır.
    private func computeSimilarity(
        _ a: String,
        _ b: String,
        isTurkish: Bool
    ) -> Double {
        let aLower = a.lowercased()
        let bLower = b.lowercased()

        // 1. Kelime örtüşmesi (çok kelimeli ifadeler için: "Davet Etmek" ~ "İma Etmek")
        let aWords = Set(aLower.split(separator: " ").map(String.init))
        let bWords = Set(bLower.split(separator: " ").map(String.init))
        let wordUnion = aWords.union(bWords).count
        let wordOverlap: Double = wordUnion > 0
            ? Double(aWords.intersection(bWords).count) / Double(wordUnion)
            : 0.0

        // 2. Karakter trigram Jaccard benzerliği (kök benzerliğini yakalar)
        //    "ağlamak" ~ "bağlamak" = yüksek, "araştırmak" ~ "artırmak" = orta
        let aTrigrams = characterTrigrams(aLower)
        let bTrigrams = characterTrigrams(bLower)
        let trigramUnion = aTrigrams.union(bTrigrams).count
        let trigramSim: Double = trigramUnion > 0
            ? Double(aTrigrams.intersection(bTrigrams).count) / Double(trigramUnion)
            : 0.0

        // 3. Uzunluk benzerliği (kısa kelimeler için daha önemli)
        let maxLen = max(a.count, b.count, 1)
        let lenSim = 1.0 - Double(abs(a.count - b.count)) / Double(maxLen)

        // 4. Morfolojik tür bonusu
        var typeBonus: Double = 0.0
        if isTurkish {
            let typeA = turkishWordType(aLower)
            let typeB = turkishWordType(bLower)
            if typeA == typeB && typeA != .other {
                // Aynı türdeki fiiller/sıfatlar/zarflar: yüksek bonus
                typeBonus = 0.15
            }
        }

        // 5. Son ek benzerliği (kısa kelimelerde trigramlar yetersiz kaldığında devreye girer)
        //    "Deprem" ~ "Devrem" veya "Güzel" ~ "Kuşak" gibi benzer son ekler
        let suffixSim = suffixSimilarity(aLower, bLower)

        // 6. Karakter kesişimi (kısa kelimelerde daha anlamlı)
        let aChars = Set(aLower)
        let bChars = Set(bLower)
        let charUnion = aChars.union(bChars).count
        let charOverlap: Double = charUnion > 0
            ? Double(aChars.intersection(bChars).count) / Double(charUnion)
            : 0.0

        // Ağırlıklı toplam — kısa kelimelerde uzunluk ve karakter benzerliği daha önemli
        let isShortWord = a.count <= 6 || b.count <= 6
        if isShortWord {
            // Kısa kelimeler: uzunluk + karakter kesişimi + suffix ağırlıklı
            return wordOverlap * 0.15 + trigramSim * 0.15 + lenSim * 0.25 +
                   charOverlap * 0.20 + suffixSim * 0.15 + typeBonus + 0.05
        } else {
            // Uzun kelimeler: trigram + kelime örtüşmesi ağırlıklı
            return wordOverlap * 0.25 + trigramSim * 0.30 + lenSim * 0.15 +
                   charOverlap * 0.05 + suffixSim * 0.10 + typeBonus + 0.05
        }
    }

    // MARK: - Suffix Similarity

    /// İki kelimenin son eklerinin benzerliğini hesaplar (0.0 - 1.0).
    /// Türkçe'de aynı son eke sahip kelimeler genellikle aynı kavram alanındadır.
    private func suffixSimilarity(_ a: String, _ b: String) -> Double {
        let minLen = min(a.count, b.count)
        guard minLen >= 2 else { return 0.0 }

        // En uzun ortak son eki bul (max 5 karakter)
        let checkLen = min(5, minLen)
        let aSuffix = String(a.suffix(checkLen))
        let bSuffix = String(b.suffix(checkLen))

        var commonSuffix = 0
        let aChars = Array(aSuffix.reversed())
        let bChars = Array(bSuffix.reversed())

        for i in 0..<checkLen {
            if aChars[i] == bChars[i] {
                commonSuffix += 1
            } else {
                break
            }
        }

        return Double(commonSuffix) / Double(checkLen)
    }

    // MARK: - Character Trigrams

    /// Bir metnin 3'lü karakter gruplarını (trigram) döndürür.
    /// "koşmak" → {"koş", "oşm", "şma", "mak"}
    private func characterTrigrams(_ text: String) -> Set<String> {
        let chars = Array(text)
        guard chars.count >= 3 else { return Set([text]) }
        var trigrams = Set<String>()
        for i in 0...(chars.count - 3) {
            trigrams.insert(String(chars[i..<(i + 3)]))
        }
        return trigrams
    }

    // MARK: - Turkish Morphological Type Detection

    /// Türkçe kelimenin morfolojik türünü tespit eder.
    /// Böylece fiiller fiillerle, sıfatlar sıfatlarla eşleştirilir.
    private enum TurkishWordType {
        case verb        // -mak/-mek, etmek/olmak/yapmak/vermek/almak
        case adjective   // -lı/-sız, -ıcı/-ici
        case adverb      // -ca/-ce, olarak
        case other       // İsimler ve diğer türler
    }

    private func turkishWordType(_ text: String) -> TurkishWordType {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Fiil tespiti: Türkçe fiiller -mak/-mek ile biter veya yardımcı fiil içerir
        if lower.hasSuffix("mak") || lower.hasSuffix("mek") {
            return .verb
        }
        let compoundVerbSuffixes = [" etmek", " olmak", " yapmak", " vermek",
                                    " almak", " gelmek", " kılmak", " düşmek",
                                    " çıkmak", " girmek", " koymak", " tutmak"]
        for suffix in compoundVerbSuffixes {
            if lower.hasSuffix(suffix) { return .verb }
        }

        // Sıfat tespiti: Türkçe sıfat ekleri
        let adjSuffixes = ["lı", "li", "lu", "lü",
                           "sız", "siz", "suz", "süz",
                           "ıcı", "ici", "ucu", "ücü",
                           "sal", "sel", "ımsı", "imsi"]
        for suffix in adjSuffixes {
            if lower.hasSuffix(suffix) { return .adjective }
        }

        // Zarf tespiti
        if lower.hasSuffix("ca") || lower.hasSuffix("ce") ||
           lower.hasSuffix("ça") || lower.hasSuffix("çe") ||
           lower.hasSuffix(" olarak") || lower.hasSuffix(" şekilde") {
            return .adverb
        }

        return .other
    }

    // MARK: - Direction Balancing

    /// EN→TR ve TR→EN yönlerini dengeli şekilde dağıtır.
    /// Tüm soruların aynı yönde gelmesini engeller.
    private func balancedDirections(count: Int) -> [QuizDirection] {
        let half = count / 2
        var directions: [QuizDirection] = []
        directions += Array(repeating: QuizDirection.englishToTurkish, count: half)
        directions += Array(repeating: QuizDirection.turkishToEnglish, count: count - half)
        return directions.shuffled()
    }

    // MARK: - Consecutive Duplicate Prevention

    /// Art arda aynı kelimenin gelmesini engelleyerek soru listesi oluşturur.
    /// Kullanıcı aynı kelimeyi peş peşe görmez.
    private func selectWithoutConsecutiveDuplicates(
        from words: [Word],
        count: Int
    ) -> [Word] {
        guard count > 0, !words.isEmpty else { return [] }

        var pool = words.shuffled()
        var result: [Word] = []

        for _ in 0..<count {
            if pool.isEmpty { break }

            // Bir önceki kelimeden farklı birini seçmeye çalış
            if let lastWord = result.last,
               let idx = pool.firstIndex(where: { $0.id != lastWord.id }) {
                result.append(pool[idx])
                pool.remove(at: idx)
            } else if let first = pool.first {
                // Farklı kelime kalmadıysa mecburen ilk elemanı al
                result.append(first)
                pool.removeFirst()
            }
        }

        return result
    }

    // MARK: - Daily Test

    public func generateDailyTest(for level: CEFRLevel) -> [QuizQuestion] {
        let allLevelWords = WordManager.shared.words(for: level)

        let knownIDs = Set(ProgressManager.shared.progress.knownWordIDs)
        let unknownIDs = Set(ProgressManager.shared.progress.unknownWordIDs)

        var knownWords = allLevelWords.filter { knownIDs.contains($0.id) }
        var unknownWords = allLevelWords.filter { unknownIDs.contains($0.id) }

        let totalCount = 20
        // %60 bilinen, %40 bilinmeyen → daha zorlayıcı test
        // (Eski oran: %90 bilinen, %10 bilinmeyen — çok kolaydı)
        var unknownCount = max(4, totalCount * 4 / 10) // %40, en az 4
        var knownCount = totalCount - unknownCount       // %60

        // Elimizde yeterince bilinmeyen yoksa, eksiği bilinenlerle tamamla
        if unknownWords.count < unknownCount {
            unknownCount = unknownWords.count
            knownCount = totalCount - unknownCount
        }

        // Elimizde yeterince bilinen yoksa, eksiği bilinmeyenlerle tamamla
        if knownWords.count < knownCount {
            knownCount = knownWords.count
            unknownCount = totalCount - knownCount

            // Hala yetmiyorsa, henüz kategorize edilmemiş kelimelerden tamamla
            if unknownWords.count < unknownCount {
                let otherWords = allLevelWords.filter {
                    !knownIDs.contains($0.id) && !unknownIDs.contains($0.id)
                }
                unknownWords.append(contentsOf: otherWords)
            }
        }

        let selectedKnown = Array(knownWords.shuffled().prefix(knownCount))
        let selectedUnknown = Array(unknownWords.shuffled().prefix(unknownCount))

        let combined = selectedKnown + selectedUnknown

        // Distractor pool olarak tüm seviye kelimelerini ver
        let distractorPool = allLevelWords

        // Art arda tekrarı engelle
        let ordered = selectWithoutConsecutiveDuplicates(from: combined, count: combined.count)

        // Yön dengeleme
        let directions = balancedDirections(count: ordered.count)

        // Günlük test zorluk seviyesi: orta-zor
        return zip(ordered, directions).compactMap { word, direction in
            makeQuestion(
                for: word,
                distractorPool: distractorPool,
                direction: direction,
                difficulty: .medium
            )
        }
    }
}
