import Foundation

public class WordManager {
    public static let shared = WordManager()

    public var allWords: [Word] = []

    /// Seen kelimeler için key — sıralı queue (en eski = en önce)
    private let seenKey = "seenWordIDsQueue"
    private let defaults: UserDefaults

    private init() {
        self.defaults = UserDefaults(suiteName: "group.com.ufuk.DailyWordWidget") ?? .standard
        loadWords()
    }

    // MARK: - Load

    private func loadWords() {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json") else {
            print("WordManager: Could not find words.json in Bundle.")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Word].self, from: data)
            self.allWords = decoded.map { word in
                let isDummy = word.example.contains("I am learning the word") || word.example.isEmpty
                let finalExample: String
                let finalExampleTr: String
                
                if !isDummy {
                    finalExample = word.example
                    finalExampleTr = word.exampleTurkish ?? ""
                } else {
                    let fallback = generatedExamples(for: word.english, turkishMeaning: word.turkish)
                    finalExample = fallback.english
                    finalExampleTr = fallback.turkish
                }
                
                return Word(
                    id: word.id,
                    english: word.english,
                    turkish: word.turkish,
                    example: finalExample,
                    exampleTurkish: finalExampleTr,
                    level: word.level,
                    imageURL: word.imageURL,
                    audioURL: word.audioURL
                )
            }
            print("WordManager: Loaded \(self.allWords.count) words.")
        } catch {
            print("WordManager: Failed to decode words.json. \(error)")
        }
    }

    // MARK: - Level Filtering

    public func words(for level: CEFRLevel) -> [Word] {
        allWords.filter { $0.level == level }
    }

    // MARK: - Next Word (Optimize Algoritma)

    /// Bir sonraki kelimeyi döndür.
    /// - Önce hiç görülmemiş kelimelerden seç (sıralı, karıştırılmış)
    /// - Hepsi görüldüyse: en eski görülen kelimeyi getir (spaced repetition lite)
    public func nextWord(for level: CEFRLevel) -> Word? {
        let levelWords = words(for: level)
        guard !levelWords.isEmpty else { return nil }

        let seen = seenWordIDs()
        let levelIDs = Set(levelWords.map { $0.id })

        // Henüz görülmemiş kelimeler (shuffle ile random sıra)
        let unseen = levelWords.filter { !seen.contains($0.id) }
        if !unseen.isEmpty {
            return unseen.randomElement()
        }

        // Hepsi görüldüyse: en eski seen (queue'nun başı) ama mevcut kelimenin kendisi değil
        let currentId = AppSettingsManager.shared.getCurrentWordId()
        let seenInLevel = seen.filter { levelIDs.contains($0) }

        // Mevcut kelimeden farklı olan en eskiyi seç
        if let oldestId = seenInLevel.first(where: { $0 != currentId }),
           let word = getWord(byId: oldestId) {
            return word
        }

        // Sadece 1 kelime var (mevcut)
        return levelWords.first
    }

    /// Geriye dönük uyumluluk — currentLevel kullanır
    public func nextWord() -> Word? {
        let level = ProgressManager.shared.progress.currentLevel
        return nextWord(for: level)
    }

    // MARK: - Seen Tracking

    public func markWordAsSeen(id: String) {
        var ids = seenWordIDs()
        // Eğer zaten listede varsa, sona taşı (spaced repetition: en son görülen = en son tekrar edilir)
        ids.removeAll { $0 == id }
        ids.append(id)
        defaults.set(ids, forKey: seenKey)
        defaults.synchronize()
        NotificationCenter.default.post(name: .wordFlowDidChange, object: nil)
    }

    public func seenWordIDs() -> [String] {
        // Hem eski key hem yeni key'den oku (migration)
        let new = defaults.stringArray(forKey: seenKey) ?? []
        if !new.isEmpty { return new }
        let old = defaults.stringArray(forKey: "seenWordIDs") ?? []
        if !old.isEmpty {
            defaults.set(old, forKey: seenKey)
            return old
        }
        return []
    }

    public var seenWords: [Word] {
        let ids = seenWordIDs()
        return ids.compactMap { id in allWords.first(where: { $0.id == id }) }
    }

    public var learnedWords: [Word] {
        let learned = Set(ProgressManager.shared.progress.learnedWordIDs)
        return allWords.filter { learned.contains($0.id) }
    }

    // MARK: - Lookup

    public func getWord(byId id: String) -> Word? {
        allWords.first(where: { $0.id == id })
    }

    // MARK: - Deprecated (kept for compilation safety)

    @available(*, deprecated, renamed: "nextWord(for:)")
    public func getRandomWord(for level: CEFRLevel, excludingId: String? = nil) -> Word? {
        let pool = words(for: level)
        guard !pool.isEmpty else { return nil }
        if let exclude = excludingId, pool.count > 1 {
            return pool.filter { $0.id != exclude }.randomElement()
        }
        return pool.randomElement()
    }

    @available(*, deprecated, renamed: "nextWord()")
    public func getRandomWord(excludingId: String? = nil) -> Word? {
        nextWord()
    }

    @available(*, deprecated, renamed: "nextWord(for:)")
    public func nextWordForCurrentLevel() -> Word? {
        nextWord()
    }

    // MARK: - Example Generator

    private func generatedExamples(for englishWord: String, turkishMeaning: String) -> (english: String, turkish: String) {
        let word = englishWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = word.lowercased()
        let first = lower.first ?? "a"
        let article = ["a", "e", "i", "o", "u"].contains(first) ? "an" : "a"

        let templates: [(String, String)] = [
            (
                "I used \(word) in a real conversation today.",
                "Bugün \(turkishMeaning) anlamına gelen \(word) kelimesini gerçek bir konuşmada kullandım."
            ),
            (
                "My teacher asked me to use \(word) in class.",
                "Öğretmenim derste \(word) kelimesini kullanmamı istedi."
            ),
            (
                "I wrote \(article) \(lower) in my vocabulary notebook.",
                "Kelime defterime \(word) (\(turkishMeaning)) kelimesini yazdım."
            ),
            (
                "I can now understand \(word) when I read English texts.",
                "Artık İngilizce metinlerde \(word) kelimesini görünce anlıyorum."
            ),
            (
                "I practiced \(word) by saying it out loud three times.",
                "\(word) kelimesini üç kez yüksek sesle söyleyerek pratik yaptım."
            )
        ]

        let index = abs(word.hashValue) % templates.count
        return (templates[index].0, templates[index].1)
    }
}
