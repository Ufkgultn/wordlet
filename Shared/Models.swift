import Foundation
import AVFoundation

public enum CEFRLevel: String, Codable, CaseIterable, Identifiable {
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"

    public var id: String { rawValue }

    public var next: CEFRLevel? {
        switch self {
        case .a1: return .a2
        case .a2: return .b1
        case .b1: return .b2
        case .b2: return nil
        }
    }

    public var displayName: String { rawValue }

    public var description: String {
        switch self {
        case .a1: return "Başlangıç"
        case .a2: return "Temel"
        case .b1: return "Orta"
        case .b2: return "Orta-İleri"
        }
    }

    public var color: String {
        switch self {
        case .a1: return "green"
        case .a2: return "blue"
        case .b1: return "orange"
        case .b2: return "purple"
        }
    }
}

public struct Word: Codable, Identifiable, Hashable {
    public let id: String
    public let english: String
    public let turkish: String
    public let example: String
    public let exampleTurkish: String?
    public let level: CEFRLevel
    public let imageURL: String?
    public let audioURL: String?

    enum CodingKeys: String, CodingKey {
        case id, english, turkish, example, level
        case exampleTurkish = "exampleTurkish"
        case imageURL = "imageUrl"
        case audioURL = "audioUrl"
    }

    public init(
        id: String,
        english: String,
        turkish: String,
        example: String,
        exampleTurkish: String? = nil,
        level: CEFRLevel,
        imageURL: String? = nil,
        audioURL: String? = nil
    ) {
        self.id = id
        self.english = english
        self.turkish = turkish
        self.example = example
        self.exampleTurkish = exampleTurkish
        self.level = level
        self.imageURL = imageURL
        self.audioURL = audioURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        english = try c.decode(String.self, forKey: .english)
        turkish = try c.decode(String.self, forKey: .turkish)
        example = try c.decode(String.self, forKey: .example)
        exampleTurkish = try c.decodeIfPresent(String.self, forKey: .exampleTurkish)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        audioURL = try c.decodeIfPresent(String.self, forKey: .audioURL)

        if let explicit = try c.decodeIfPresent(CEFRLevel.self, forKey: .level) {
            level = explicit
        } else {
            level = Word.levelFrom(id: id)
        }
    }

    private static func levelFrom(id: String) -> CEFRLevel {
        let n = Int(id) ?? 1
        switch n {
        case 1...500:    return .a1
        case 501...1000: return .a2
        case 1001...1500: return .b1
        default:          return .b2
        }
    }
}

public struct UserProfile: Codable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let email: String
}

public struct AppSettings: Codable {
    /// Widget'ın kelimeyi kaç dakikada bir yenileyeceği (minimum 5 dk)
    public var widgetUpdateIntervalMinutes: Int
    /// Eski alan için geriye dönük uyumluluk
    public var widgetUpdateIntervalHours: Int {
        get { widgetUpdateIntervalMinutes / 60 }
        set { widgetUpdateIntervalMinutes = newValue * 60 }
    }

    public static let defaultSettings = AppSettings(widgetUpdateIntervalMinutes: 30)
}

/// Kullanıcının seviye ve öğrenme ilerlemesi
public struct UserProgress: Codable {
    public var currentLevel: CEFRLevel
    public var learnedWordIDs: [String]
    public var quizScores: [Int]
    /// Sınav geçilerek açılan seviyeler. A1 varsayılan olarak açık.
    public var unlockedLevels: [CEFRLevel]
    /// Her seviye için kazanılan yıldız sayısı (Practice testler için)
    public var levelStars: [String: Int]
    
    /// Sağa kaydırılan kelimeler (biliyorum)
    public var knownWordIDs: [String]
    /// Sola kaydırılan kelimeler (bilmiyorum)
    public var unknownWordIDs: [String]
    /// Tamamlanan günlük test sayısı (her seviye için, level.rawValue -> count)
    public var dailyTestsCompleted: [String: Int]
    /// Son günlük testin tarihi (yyyy-MM-dd formatında)
    public var lastDailyTestDate: String?

    public static let initial = UserProgress(
        currentLevel: .a1,
        learnedWordIDs: [],
        quizScores: [],
        unlockedLevels: [.a1],
        levelStars: [:],
        knownWordIDs: [],
        unknownWordIDs: [],
        dailyTestsCompleted: [:],
        lastDailyTestDate: nil
    )

    public func isUnlocked(_ level: CEFRLevel) -> Bool {
        unlockedLevels.contains(level)
    }

    public func stars(for level: CEFRLevel) -> Int {
        levelStars[level.rawValue] ?? 0
    }
}
