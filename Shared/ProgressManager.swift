import Foundation

// MARK: - Kelime Hafızası (FSRS-5)
//
// ProgressManager sınıfı AppSettingsManager.swift içinde. Bu dosya her kelimenin hafıza
// durumunu tutar ve tekrar zamanını FSRS-5 ile hesaplar (open-spaced-repetition/fsrs).
// Hem uygulama hem widget derler; veri App Group'ta tutulur.

/// Kullanıcının bir kelimeyi hatırlama notu (FSRS ölçeği)
public enum ReviewGrade: Int, Codable {
    case again = 1  // bilemedi
    case hard = 2
    case good = 3   // doğru
    case easy = 4   // "biliyorum"
}

public enum MemoryState: String, Codable {
    case learning   // yeni öğreniliyor ya da unutuldu: kısa aralıkla tekrar
    case review     // hatırlanıyor: FSRS aralığıyla tekrar
    case skipped    // kullanıcı "atla" dedi: hiç gösterilmez
}

public struct WordMemory: Codable, Equatable {
    public var state: MemoryState
    public var stability: Double     // gün: hatırlama olasılığının %90'a düştüğü süre
    public var difficulty: Double    // 1 (kolay) ... 10 (zor)
    public var due: Date
    public var lastReview: Date
    public var reps: Int
    public var lapses: Int

    /// Seviye geçişinde "öğrenildi" sayılır: tekrar aşamasında ve en az bir hafta hatırlanıyor
    public var isMastered: Bool { state == .review && stability >= 7 }
}

enum FSRS {
    /// FSRS-5 varsayılan ağırlıkları
    static let w: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192,
        1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
    ]
    static let decay = -0.5
    static let factor = pow(0.9, 1 / decay) - 1  // 19/81
    static let desiredRetention = 0.9
    static let maxIntervalDays = 365.0
    static let relearnDelay: TimeInterval = 10 * 60

    static func retrievability(elapsedDays: Double, stability: Double) -> Double {
        pow(1 + factor * elapsedDays / stability, decay)
    }

    static func intervalDays(stability: Double) -> Double {
        let raw = stability / factor * (pow(desiredRetention, 1 / decay) - 1)
        return min(max(raw.rounded(), 1), maxIntervalDays)
    }

    static func initialDifficulty(_ g: ReviewGrade) -> Double {
        clampDifficulty(w[4] - exp(w[5] * Double(g.rawValue - 1)) + 1)
    }

    static func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    static func nextDifficulty(_ d: Double, _ g: ReviewGrade) -> Double {
        let delta = -w[6] * Double(g.rawValue - 3)
        let damped = d + delta * (10 - d) / 9
        return clampDifficulty(w[7] * initialDifficulty(.easy) + (1 - w[7]) * damped)
    }

    static func recallStability(d: Double, s: Double, r: Double, g: ReviewGrade) -> Double {
        let hardPenalty = g == .hard ? w[15] : 1
        let easyBonus = g == .easy ? w[16] : 1
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hardPenalty * easyBonus)
    }

    static func forgetStability(d: Double, s: Double, r: Double) -> Double {
        let next = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14])
        return min(next, s / exp(w[17] * w[18]))
    }

    static func shortTermStability(s: Double, g: ReviewGrade) -> Double {
        s * exp(w[17] * (Double(g.rawValue) - 3 + w[18]))
    }

    /// Bir notu uygular ve yeni hafıza durumunu döndürür
    static func review(_ memory: WordMemory?, grade: ReviewGrade, now: Date = Date()) -> WordMemory {
        var m: WordMemory
        if let memory, memory.state != .skipped {
            m = memory
            let elapsed = now.timeIntervalSince(m.lastReview) / 86_400
            if elapsed < 1 {
                m.stability = max(shortTermStability(s: m.stability, g: grade), 0.1)
            } else {
                let r = retrievability(elapsedDays: elapsed, stability: m.stability)
                m.stability = grade == .again
                    ? forgetStability(d: m.difficulty, s: m.stability, r: r)
                    : recallStability(d: m.difficulty, s: m.stability, r: r, g: grade)
            }
            m.difficulty = nextDifficulty(m.difficulty, grade)
            m.reps += 1
            if grade == .again && m.state == .review { m.lapses += 1 }
        } else {
            m = WordMemory(
                state: .learning,
                stability: max(w[grade.rawValue - 1], 0.1),
                difficulty: initialDifficulty(grade),
                due: now, lastReview: now, reps: 1, lapses: 0
            )
        }

        m.lastReview = now
        if grade == .again {
            m.state = .learning
            m.due = now.addingTimeInterval(relearnDelay)
        } else {
            m.state = .review
            m.due = now.addingTimeInterval(intervalDays(stability: m.stability) * 86_400)
        }
        return m
    }
}

// MARK: - MemoryStore

public final class MemoryStore {
    public static let shared = MemoryStore()

    private let defaults: UserDefaults
    private let key = "wordMemoryV1"

    private init() {
        self.defaults = UserDefaults(suiteName: "group.com.ufuk.DailyWordWidget") ?? .standard
    }

    /// Tüm kelimelerin hafıza durumu (id -> durum). Hiç görülmemiş kelime burada yoktur.
    public var all: [String: WordMemory] {
        get {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String: WordMemory].self, from: data) else { return [:] }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }

    public var hasData: Bool { defaults.data(forKey: key) != nil }

    public func memory(for wordID: String) -> WordMemory? { all[wordID] }

    /// Quiz cevabı, kaydırma vb. bir hatırlama notunu kaydeder
    public func record(wordID: String, grade: ReviewGrade, now: Date = Date()) {
        var map = all
        map[wordID] = FSRS.review(map[wordID], grade: grade, now: now)
        all = map
        NotificationCenter.default.post(name: .progressDidChange, object: nil)
    }

    /// "Bu kelimeyi atla": bir daha gösterme
    public func skip(wordID: String, now: Date = Date()) {
        var map = all
        map[wordID] = WordMemory(state: .skipped, stability: 0, difficulty: 5, due: .distantFuture,
                                 lastReview: now, reps: 0, lapses: 0)
        all = map
        NotificationCenter.default.post(name: .progressDidChange, object: nil)
    }

    /// Tekrar zamanı gelmiş kelimeler, en çok geciken önce
    public func dueWordIDs(among ids: Set<String>, now: Date = Date()) -> [String] {
        all.filter { ids.contains($0.key) && $0.value.state != .skipped && $0.value.due <= now }
            .sorted { $0.value.due < $1.value.due }
            .map(\.key)
    }

    public func masteredCount(among ids: Set<String>) -> Int {
        all.filter { ids.contains($0.key) && $0.value.isMastered }.count
    }

    /// Eski "biliyorum / bilmiyorum" listelerinden ilk hafıza durumunu oluştur (bir kere)
    func migrateIfNeeded(known: [String], unknown: [String], now: Date = Date()) {
        // Taşınacak bir şey yoksa yazma: aksi halde yeni kullanıcı "verisi var" görünür
        guard !hasData, !(known.isEmpty && unknown.isEmpty) else { return }
        var map: [String: WordMemory] = [:]
        for id in known { map[id] = FSRS.review(nil, grade: .easy, now: now) }
        for id in unknown { map[id] = FSRS.review(nil, grade: .again, now: now) }
        all = map
    }
}
