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

    public var previous: CEFRLevel? {
        switch self {
        case .a1: return nil
        case .a2: return .a1
        case .b1: return .a2
        case .b2: return .b1
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

public struct PublicProfile: Codable, Identifiable, Hashable {
    public var id: String
    public var username: String
    public var displayName: String
    public var currentLevel: String
    public var xp: Int
    public var avatarEmoji: String
    public var matchesWon: Int
    public var matchesPlayed: Int
    public var pushToken: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, xp
        case displayName = "display_name"
        case currentLevel = "current_level"
        case avatarEmoji = "avatar_emoji"
        case matchesWon = "matches_won"
        case matchesPlayed = "matches_played"
        case pushToken = "push_token"
        // Fallback keys for local storage
        case altDisplayName = "displayName"
        case altCurrentLevel = "currentLevel"
        case altAvatarEmoji = "avatarEmoji"
        case altMatchesWon = "matchesWon"
        case altMatchesPlayed = "matchesPlayed"
        case altPushToken = "pushToken"
    }
    
    public init(
        id: String,
        username: String,
        displayName: String,
        currentLevel: String,
        xp: Int,
        avatarEmoji: String,
        matchesWon: Int = 0,
        matchesPlayed: Int = 0,
        pushToken: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.currentLevel = currentLevel
        self.xp = xp
        self.avatarEmoji = avatarEmoji
        self.matchesWon = matchesWon
        self.matchesPlayed = matchesPlayed
        self.pushToken = pushToken
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.username = try container.decode(String.self, forKey: .username)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? container.decodeIfPresent(String.self, forKey: .altDisplayName)
            ?? "Kullanıcı"
        self.currentLevel = try container.decodeIfPresent(String.self, forKey: .currentLevel)
            ?? container.decodeIfPresent(String.self, forKey: .altCurrentLevel)
            ?? "A1"
        self.xp = try container.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        self.avatarEmoji = try container.decodeIfPresent(String.self, forKey: .avatarEmoji)
            ?? container.decodeIfPresent(String.self, forKey: .altAvatarEmoji)
            ?? "🚀"
        self.matchesWon = try container.decodeIfPresent(Int.self, forKey: .matchesWon)
            ?? container.decodeIfPresent(Int.self, forKey: .altMatchesWon)
            ?? 0
        self.matchesPlayed = try container.decodeIfPresent(Int.self, forKey: .matchesPlayed)
            ?? container.decodeIfPresent(Int.self, forKey: .altMatchesPlayed)
            ?? 0
        self.pushToken = try container.decodeIfPresent(String.self, forKey: .pushToken)
            ?? container.decodeIfPresent(String.self, forKey: .altPushToken)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(currentLevel, forKey: .currentLevel)
        try container.encode(xp, forKey: .xp)
        try container.encode(avatarEmoji, forKey: .avatarEmoji)
        try container.encode(matchesWon, forKey: .matchesWon)
        try container.encode(matchesPlayed, forKey: .matchesPlayed)
        try container.encodeIfPresent(pushToken, forKey: .pushToken)
    }
}

public struct DuelMatch: Codable, Identifiable {
    public let id: String
    public var roomCode: String?
    public let player1Id: String
    public var player2Id: String?
    public var player1Name: String
    public var player2Name: String?
    public var player1Avatar: String
    public var player2Avatar: String?
    public var player1Score: Int
    public var player2Score: Int
    public var status: String // "waiting", "in_progress", "completed", "cancelled"
    public var winnerId: String?
    public var mode: String // "random", "friend", "room"
    public var level: String
    public var wordIds: [String]
    
    enum CodingKeys: String, CodingKey {
        case id
        case roomCode = "room_code"
        case player1Id = "player1_id"
        case player2Id = "player2_id"
        case player1Name = "player1_name"
        case player2Name = "player2_name"
        case player1Avatar = "player1_avatar"
        case player2Avatar = "player2_avatar"
        case player1Score = "player1_score"
        case player2Score = "player2_score"
        case status
        case winnerId = "winner_id"
        case mode, level
        case wordIds = "word_ids"
    }
    
    public init(
        id: String,
        roomCode: String? = nil,
        player1Id: String,
        player2Id: String? = nil,
        player1Name: String,
        player2Name: String? = nil,
        player1Avatar: String = "🚀",
        player2Avatar: String? = nil,
        player1Score: Int = 0,
        player2Score: Int = 0,
        status: String = "waiting",
        winnerId: String? = nil,
        mode: String = "random",
        level: String = "A1",
        wordIds: [String] = []
    ) {
        self.id = id
        self.roomCode = roomCode
        self.player1Id = player1Id
        self.player2Id = player2Id
        self.player1Name = player1Name
        self.player2Name = player2Name
        self.player1Avatar = player1Avatar
        self.player2Avatar = player2Avatar
        self.player1Score = player1Score
        self.player2Score = player2Score
        self.status = status
        self.winnerId = winnerId
        self.mode = mode
        self.level = level
        self.wordIds = wordIds
    }
}
