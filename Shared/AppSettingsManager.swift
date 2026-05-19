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

    /// Widget'ta gösterilecek sonraki kelimeye geç
    public func forceNextWord() {
        let level = ProgressManager.shared.progress.currentLevel
        if let next = WordManager.shared.nextWord(for: level) {
            saveCurrentWordId(next.id)
            WordManager.shared.markWordAsSeen(id: next.id)
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
            levelStars: [:]
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
