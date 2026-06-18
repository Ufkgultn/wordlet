import Foundation

// MARK: - Notification Names

public extension Notification.Name {
    static let wordFlowDidChange   = Notification.Name("wordFlowDidChange")
    static let progressDidChange   = Notification.Name("progressDidChange")
    static let levelDidUnlock      = Notification.Name("levelDidUnlock")
}

// MARK: - AppSettingsManager

public class AppSettingsManager {
    public static let shared = AppSettingsManager()

    private let defaults: UserDefaults
    private let settingsKey = "appSettings"

    private init() {
        self.defaults = UserDefaults(suiteName: "group.com.ufuk.DailyWordWidget") ?? .standard
    }

    public var settings: AppSettings {
        get {
            if let data = defaults.data(forKey: settingsKey),
               let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
                return decoded
            }
            return AppSettings.defaultSettings
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: settingsKey)
            }
        }
    }

    public func saveCurrentWordId(_ id: String) {
        defaults.set(id, forKey: "currentWordId")
        defaults.synchronize()
        NotificationCenter.default.post(name: .wordFlowDidChange, object: nil)
    }

    public func getCurrentWordId() -> String? {
        return defaults.string(forKey: "currentWordId")
    }

    public func saveNextRefreshDate(_ date: Date) {
        defaults.set(date, forKey: "nextRefreshDate")
    }

    public func getNextRefreshDate() -> Date? {
        return defaults.object(forKey: "nextRefreshDate") as? Date
    }

    public func saveLastWordChangeDate(_ date: Date) {
        defaults.set(date, forKey: "lastWordChangeDate")
        defaults.synchronize()
    }

    public func getLastWordChangeDate() -> Date? {
        return defaults.object(forKey: "lastWordChangeDate") as? Date
    }

    /// Widget'ta gösterilecek sonraki kelimeye geç
    public func forceNextWord() {
        let level = ProgressManager.shared.progress.currentLevel
        if let next = WordManager.shared.nextWord(for: level) {
            saveCurrentWordId(next.id)
            WordManager.shared.markWordAsSeen(id: next.id)
            saveLastWordChangeDate(Date())
        }
        NotificationCenter.default.post(name: .wordFlowDidChange, object: nil)
    }

    // MARK: - Premium & Limits

    public var isPremium: Bool {
        get { defaults.bool(forKey: "isPremium") }
        set { defaults.set(newValue, forKey: "isPremium"); defaults.synchronize() }
    }

    public func checkAndResetDailyLimits() {
        let now = Date()
        let lastReset = defaults.object(forKey: "lastResetDate") as? Date ?? Date(timeIntervalSince1970: 0)
        
        if !Calendar.current.isDateInToday(lastReset) {
            defaults.set(0, forKey: "dailyManualChangeCount")
            defaults.set(0, forKey: "dailyAutoChangeCount")
            defaults.set(0, forKey: "dailySwipeCount")
            defaults.set(0, forKey: "dailyDuelCount")
            defaults.set(now, forKey: "lastResetDate")
            defaults.synchronize()
        }
    }

    public var dailyManualChangeCount: Int {
        get { checkAndResetDailyLimits(); return defaults.integer(forKey: "dailyManualChangeCount") }
        set { defaults.set(newValue, forKey: "dailyManualChangeCount"); defaults.synchronize() }
    }

    public var dailyAutoChangeCount: Int {
        get { checkAndResetDailyLimits(); return defaults.integer(forKey: "dailyAutoChangeCount") }
        set { defaults.set(newValue, forKey: "dailyAutoChangeCount"); defaults.synchronize() }
    }

    public var dailySwipeCount: Int {
        get { checkAndResetDailyLimits(); return defaults.integer(forKey: "dailySwipeCount") }
        set { defaults.set(newValue, forKey: "dailySwipeCount"); defaults.synchronize() }
    }

    public var dailyDuelCount: Int {
        get { checkAndResetDailyLimits(); return defaults.integer(forKey: "dailyDuelCount") }
        set { defaults.set(newValue, forKey: "dailyDuelCount"); defaults.synchronize() }
    }
}

// MARK: - ProgressManager// MARK: - ProgressRequirements

public struct ProgressRequirements {
    public let requiredDailyTests: Int
    public let requiredKnownWords: Int
    public let examQuestionCount: Int
    
    public static func requirements(for level: CEFRLevel) -> ProgressRequirements {
        switch level {
        case .a1:
            return ProgressRequirements(requiredDailyTests: 7, requiredKnownWords: 50, examQuestionCount: 20)
        case .a2:
            return ProgressRequirements(requiredDailyTests: 15, requiredKnownWords: 100, examQuestionCount: 35)
        case .b1:
            return ProgressRequirements(requiredDailyTests: 25, requiredKnownWords: 200, examQuestionCount: 50)
        case .b2:
            return ProgressRequirements(requiredDailyTests: 30, requiredKnownWords: 300, examQuestionCount: 60)
        }
    }
}

// MARK: - ProgressManager

public final class ProgressManager {
    public static let shared = ProgressManager()

    private let defaults: UserDefaults
    private let progressKey = "userProgressV3"

    private init() {
        self.defaults = UserDefaults(suiteName: "group.com.ufuk.DailyWordWidget") ?? .standard
        migrateIfNeeded()
    }

    // MARK: Progress

    public var progress: UserProgress {
        get {
            guard let data = defaults.data(forKey: progressKey),
                  let decoded = try? JSONDecoder().decode(UserProgress.self, from: data) else {
                return .initial
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: progressKey)
                defaults.synchronize()
            }
        }
    }

    // MARK: Word Learning

    public func markLearned(wordID: String, learned: Bool) {
        var p = progress
        var set = Set(p.learnedWordIDs)
        if learned {
            set.insert(wordID)
        } else {
            set.remove(wordID)
        }
        p.learnedWordIDs = Array(set)
        progress = p
        NotificationCenter.default.post(name: .progressDidChange, object: nil)
    }

    // MARK: Quiz Scores

    public func addQuizScore(_ percent: Int) {
        var p = progress
        p.quizScores.append(percent)
        progress = p
        NotificationCenter.default.post(name: .progressDidChange, object: nil)
    }

    public func saveStar(for level: CEFRLevel, star: Int) {
        var p = progress
        let currentStars = p.levelStars[level.rawValue] ?? 0
        if star > currentStars {
            p.levelStars[level.rawValue] = star
            progress = p
            NotificationCenter.default.post(name: .progressDidChange, object: nil)
        }
    }

    // MARK: Level Unlock

    /// Belirli bir seviye için sınav sonucunu değerlendir
    /// - Returns: true → seviye açıldı, false → geçilemedi
    @discardableResult
    public func attemptLevelUnlock(scorePercent: Int, targetLevel: CEFRLevel) -> Bool {
        addQuizScore(scorePercent)
        guard scorePercent >= 70 else { return false }

        var p = progress
        if !p.unlockedLevels.contains(targetLevel) {
            p.unlockedLevels.append(targetLevel)
        }
        // Şu anki seviyeyi de güncelle (en yüksek açık seviyeye çek)
        p.currentLevel = targetLevel
        progress = p

        NotificationCenter.default.post(name: .progressDidChange, object: nil)
        NotificationCenter.default.post(name: .levelDidUnlock, object: targetLevel.rawValue)
        return true
    }

    /// Geriye dönük uyumluluk — eski API
    @discardableResult
    public func attemptLevelUnlock(scorePercent: Int) -> Bool {
        let current = progress.currentLevel
        guard let next = current.next else { return false }
        return attemptLevelUnlock(scorePercent: scorePercent, targetLevel: next)
    }

    // MARK: - Swipe Logic
    
    public func swipeRight(wordID: String) {
        var p = progress
        // Biliniyor listesine ekle
        if !p.knownWordIDs.contains(wordID) {
            p.knownWordIDs.append(wordID)
        }
        // Bilinmiyor listesinden çıkar
        p.unknownWordIDs.removeAll { $0 == wordID }
        
        // learned listesine de ekleyelim ki mevcut mantığı bozmayalım
        if !p.learnedWordIDs.contains(wordID) {
             p.learnedWordIDs.append(wordID)
        }
        
        progress = p
        NotificationCenter.default.post(name: .progressDidChange, object: nil)
    }
    
    public func swipeLeft(wordID: String) {
         var p = progress
         // Bilinmiyor listesine ekle
         if !p.unknownWordIDs.contains(wordID) {
              p.unknownWordIDs.append(wordID)
         }
         // Biliniyor listesinden çıkar
         p.knownWordIDs.removeAll { $0 == wordID }
         
         // learned listesinden de çıkaralım
         p.learnedWordIDs.removeAll { $0 == wordID }
         
         progress = p
         NotificationCenter.default.post(name: .progressDidChange, object: nil)
    }
    
    // MARK: - Daily Test Logic
    
    public func completeDailyTest() {
        var p = progress
        let level = p.currentLevel.rawValue
        
        // Sayacı artır
        let count = p.dailyTestsCompleted[level] ?? 0
        p.dailyTestsCompleted[level] = count + 1
        
        // Tarihi kaydet
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        p.lastDailyTestDate = dateFormatter.string(from: Date())
        
        progress = p
        NotificationCenter.default.post(name: .progressDidChange, object: nil)
    }
    
    public func hasTakenDailyTest() -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())
        
        return progress.lastDailyTestDate == todayString
    }
    
    public func dailyTestsCount(for level: CEFRLevel) -> Int {
        progress.dailyTestsCompleted[level.rawValue] ?? 0
    }
    
    public func canTakeExam(for level: CEFRLevel) -> Bool {
        guard level != .a1 else { return false }
        guard let sourceLevel = level.previous else { return false }
        
        let req = ProgressRequirements.requirements(for: sourceLevel)
        let dailyTestCount = dailyTestsCount(for: sourceLevel)
        
        let levelWords = WordManager.shared.words(for: sourceLevel).map { $0.id }
        let knownLevelWordsCount = progress.knownWordIDs.filter { levelWords.contains($0) }.count
        
        let earnedStars = progress.stars(for: sourceLevel)
        
        return dailyTestCount >= req.requiredDailyTests &&
               knownLevelWordsCount >= req.requiredKnownWords &&
               earnedStars >= 10
    }

    // MARK: Migration

    private func migrateIfNeeded() {
        // Eski userProgressV2 formatından migrate et
        guard defaults.data(forKey: progressKey) == nil,
              let oldData = defaults.data(forKey: "userProgressV2"),
              let old = try? JSONDecoder().decode(UserProgressLegacy.self, from: oldData) else { return }

        let migrated = UserProgress(
            currentLevel: old.currentLevel,
            learnedWordIDs: old.learnedWordIDs,
            quizScores: old.quizScores,
            unlockedLevels: [.a1, old.currentLevel].removingDuplicates(),
            levelStars: [:],
            knownWordIDs: old.learnedWordIDs,
            unknownWordIDs: [],
            dailyTestsCompleted: [:],
            lastDailyTestDate: nil
        )
        progress = migrated
    }
}

// MARK: - Legacy Migration Helper

private struct UserProgressLegacy: Codable {
    var currentLevel: CEFRLevel
    var learnedWordIDs: [String]
    var quizScores: [Int]
}

private extension Array where Element: Equatable {
    func removingDuplicates() -> [Element] {
        var seen = [Element]()
        for element in self {
            if !seen.contains(element) { seen.append(element) }
        }
        return seen
    }
}
