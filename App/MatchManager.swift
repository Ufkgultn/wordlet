import Foundation
import SwiftUI
import Supabase
import Realtime

// MARK: - Realtime Broadcast Payloads
struct PlayerJoinedPayload: Codable {
    let player2Id: String
    let player2Name: String
    let player2Avatar: String
}

struct ScoreUpdatePayload: Codable {
    let userId: String
    let score: Int
}

struct MatchFinishedPayload: Codable {
    let winnerId: String
}

@MainActor
public class MatchManager: ObservableObject {
    public static let shared = MatchManager()
    
    // Matchmaking State
    @Published public var isSearching: Bool = false
    @Published public var searchStatus: String = "Lobi oluşturuluyor..."
    @Published public var roomCode: String? = nil
    @Published public var currentOpponent: PublicProfile? = nil
    @Published public var activeMatch: DuelMatch? = nil
    @Published public var showBattleArena: Bool = false
    @Published public var opponentLiveScore: Int = 0
    @Published public var matchFinishedEventReceived: Bool = false
    @Published public var errorMessage: String? = nil
    
    private let client = SupabaseManager.shared.client
    private var realtimeChannel: RealtimeChannelV2? = nil
    private var lobbyPollingTask: Task<Void, Never>? = nil
    
    private init() {}
    
    // MARK: - 1. Random Matchmaking (100% Real Online Network Match)
    
    public func startRandomMatchmaking(level: CEFRLevel = ProgressManager.shared.progress.currentLevel, gameMode: Int = UserDefaults.standard.integer(forKey: "selectedMinigame")) async {
        guard !isSearching else { return }
        guard let myProfile = SocialManager.shared.myProfile else {
            self.errorMessage = "Maça başlamak için profil yüklenemedi. Lütfen giriş yapın."
            return
        }
        
        isSearching = true
        searchStatus = "Çevrimiçi açık maç aranıyor..."
        roomCode = nil
        currentOpponent = nil
        activeMatch = nil
        opponentLiveScore = 0
        matchFinishedEventReceived = false
        errorMessage = nil
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        do {
            // 1. Search database for an existing waiting match at this level
            let openMatches: [DuelMatch] = try await client
                .from("matches")
                .select()
                .eq("status", value: "waiting")
                .eq("mode", value: "random_\(gameMode)")
                .eq("level", value: level.rawValue)
                .neq("player1_id", value: myProfile.id)
                .limit(1)
                .execute()
                .value
            
            if let availableMatch = openMatches.first {
                // JOIN EXISTING MATCH!
                searchStatus = "Rakip bulundu! Maça bağlanılıyor..."
                
                try await client
                    .from("matches")
                    .update([
                        "player2_id": myProfile.id,
                        "player2_name": myProfile.displayName,
                        "player2_avatar": myProfile.avatarEmoji,
                        "status": "in_progress"
                    ])
                    .eq("id", value: availableMatch.id)
                    .execute()
                
                var joined = availableMatch
                joined.player2Id = myProfile.id
                joined.player2Name = myProfile.displayName
                joined.player2Avatar = myProfile.avatarEmoji
                joined.status = "in_progress"
                
                self.activeMatch = joined
                self.currentOpponent = PublicProfile(
                    id: joined.player1Id,
                    username: "rakip",
                    displayName: joined.player1Name,
                    currentLevel: joined.level,
                    xp: 0,
                    avatarEmoji: joined.player1Avatar
                )
                
                // Connect to real-time sync channel
                await connectToMatchChannel(matchId: joined.id)
                
                // Broadcast that we joined
                try? await realtimeChannel?.broadcast(
                    event: "player_joined",
                    message: PlayerJoinedPayload(
                        player2Id: myProfile.id,
                        player2Name: myProfile.displayName,
                        player2Avatar: myProfile.avatarEmoji
                    )
                )
                
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                self.isSearching = false
                self.showBattleArena = true
                return
            }
            
            // 2. NO EXISTING MATCH: CREATE A WAITING MATCH & LOBBY
            let generatedCode = String(Int.random(in: 1000...9999))
            self.roomCode = generatedCode
            self.searchStatus = "Lobi açıldı (#\(generatedCode)). Çevrimiçi bir oyuncunun katılması bekleniyor..."
            
            // Pick random words for this match
            let words = WordManager.shared.words(for: level).shuffled().prefix(50).map { $0.id }
            
            let newMatch = DuelMatch(
                id: UUID().uuidString,
                roomCode: generatedCode,
                player1Id: myProfile.id,
                player2Id: nil,
                player1Name: myProfile.displayName,
                player2Name: nil,
                player1Avatar: myProfile.avatarEmoji,
                player2Avatar: nil,
                player1Score: 0,
                player2Score: 0,
                status: "waiting",
                winnerId: nil,
                mode: "random_\(gameMode)",
                level: level.rawValue,
                wordIds: Array(words)
            )
            
            try await client
                .from("matches")
                .insert(newMatch)
                .execute()
            
            self.activeMatch = newMatch
            
            // Connect to Realtime channel
            await connectToMatchChannel(matchId: newMatch.id)
            
            // Start waiting for player 2 (listen via WebSocket + polling backup)
            startLobbyPolling(matchId: newMatch.id)
            
        } catch {
            print("Matchmaking error: \(error)")
            self.errorMessage = "Eşleşme sunucusuna bağlanılamadı: \(error.localizedDescription)"
            self.isSearching = false
        }
    }
    
    // MARK: - 2. Room Code Real-Time Duel (Oda Kodu ile Canlı Maç)
    
    public func createPrivateRoom(level: CEFRLevel = ProgressManager.shared.progress.currentLevel, gameMode: Int = UserDefaults.standard.integer(forKey: "selectedMinigame")) async {
        guard let myProfile = SocialManager.shared.myProfile else { return }
        
        isSearching = true
        let generatedCode = String(Int.random(in: 1000...9999))
        self.roomCode = generatedCode
        self.searchStatus = "Oda Kodu: \(generatedCode)\nArkadaşının bu kodu girmesini bekle..."
        
        let words = WordManager.shared.words(for: level).shuffled().prefix(50).map { $0.id }
        let match = DuelMatch(
            id: UUID().uuidString,
            roomCode: generatedCode,
            player1Id: myProfile.id,
            player1Name: myProfile.displayName,
            player1Avatar: myProfile.avatarEmoji,
            status: "waiting",
            mode: "room_\(gameMode)",
            level: level.rawValue,
            wordIds: Array(words)
        )
        
        do {
            try await client.from("matches").insert(match).execute()
            self.activeMatch = match
            await connectToMatchChannel(matchId: match.id)
            startLobbyPolling(matchId: match.id)
        } catch {
            self.errorMessage = "Oda açılamadı: \(error.localizedDescription)"
            self.isSearching = false
        }
    }
    
    public func joinPrivateRoom(code: String) async {
        guard let myProfile = SocialManager.shared.myProfile else { return }
        let cleanCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCode.isEmpty else { return }
        
        do {
            let matches: [DuelMatch] = try await client
                .from("matches")
                .select()
                .eq("room_code", value: cleanCode)
                .eq("status", value: "waiting")
                .limit(1)
                .execute()
                .value
            
            guard let match = matches.first else {
                self.errorMessage = "Bu koda ait açık bir lobi bulunamadı."
                return
            }
            
            // Join room
            try await client
                .from("matches")
                .update([
                    "player2_id": myProfile.id,
                    "player2_name": myProfile.displayName,
                    "player2_avatar": myProfile.avatarEmoji,
                    "status": "in_progress"
                ])
                .eq("id", value: match.id)
                .execute()
            
            var joined = match
            joined.player2Id = myProfile.id
            joined.player2Name = myProfile.displayName
            joined.player2Avatar = myProfile.avatarEmoji
            joined.status = "in_progress"
            
            self.activeMatch = joined
            self.currentOpponent = PublicProfile(
                id: joined.player1Id,
                username: "rakip",
                displayName: joined.player1Name,
                currentLevel: joined.level,
                xp: 0,
                avatarEmoji: joined.player1Avatar
            )
            
            await connectToMatchChannel(matchId: joined.id)
            
            try? await realtimeChannel?.broadcast(
                event: "player_joined",
                message: PlayerJoinedPayload(
                    player2Id: myProfile.id,
                    player2Name: myProfile.displayName,
                    player2Avatar: myProfile.avatarEmoji
                )
            )
            
            self.isSearching = false
            self.showBattleArena = true
        } catch {
            self.errorMessage = "Odaya katılırken hata oluştu: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 3. Realtime Channel & Live Sync
    
    private func connectToMatchChannel(matchId: String) async {
        let channel = client.realtimeV2.channel("match_\(matchId)")
        self.realtimeChannel = channel
        
        await channel.subscribe()
        
        // Listen for player joined broadcast
        Task {
            for await message in channel.broadcastStream(event: "player_joined") {
                let payload = try? message.decode(as: PlayerJoinedPayload.self)
                let name = payload?.player2Name ?? message["player2Name"]?.stringValue
                let avatar = payload?.player2Avatar ?? message["player2Avatar"]?.stringValue
                let id = payload?.player2Id ?? message["player2Id"]?.stringValue
                
                if let name, let avatar, let id {
                    await MainActor.run {
                        self.currentOpponent = PublicProfile(
                            id: id,
                            username: "rakip",
                            displayName: name,
                            currentLevel: self.activeMatch?.level ?? "A1",
                            xp: 0,
                            avatarEmoji: avatar
                        )
                        self.activeMatch?.player2Id = id
                        self.activeMatch?.player2Name = name
                        self.activeMatch?.player2Avatar = avatar
                        self.activeMatch?.status = "in_progress"
                        self.lobbyPollingTask?.cancel()
                        self.isSearching = false
                        self.showBattleArena = true
                    }
                }
            }
        }
        
        // Listen for live score updates from opponent
        Task {
            for await message in channel.broadcastStream(event: "score_update") {
                let payload = try? message.decode(as: ScoreUpdatePayload.self)
                let senderId = payload?.userId ?? message["userId"]?.stringValue
                let score = payload?.score ?? message["score"]?.intValue
                let myId = SocialManager.shared.myProfile?.id
                
                if let senderId, let score, senderId != myId {
                    await MainActor.run {
                        self.opponentLiveScore = score
                    }
                }
            }
        }
        
        // Listen for game finished event
        Task {
            for await _ in channel.broadcastStream(event: "match_finished") {
                await MainActor.run {
                    self.matchFinishedEventReceived = true
                }
            }
        }
    }
    
    public func sendLiveScore(score: Int) async {
        guard let myId = SocialManager.shared.myProfile?.id else { return }
        try? await realtimeChannel?.broadcast(
            event: "score_update",
            message: ScoreUpdatePayload(userId: myId, score: score)
        )
    }
    
    public func sendMatchFinished(winnerId: String) async {
        try? await realtimeChannel?.broadcast(
            event: "match_finished",
            message: MatchFinishedPayload(winnerId: winnerId)
        )
        
        if let match = activeMatch {
            _ = try? await client
                .from("matches")
                .update(["status": "completed", "winner_id": winnerId])
                .eq("id", value: match.id)
                .execute()
        }
    }
    
    // MARK: - 4. Lobby Waiting Poller
    
    private func startLobbyPolling(matchId: String) {
        lobbyPollingTask?.cancel()
        lobbyPollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Poll every 2 seconds
                guard self.isSearching else { break }
                
                do {
                    let updated: [DuelMatch] = try await client
                        .from("matches")
                        .select()
                        .eq("id", value: matchId)
                        .execute()
                        .value
                    
                    if let current = updated.first, current.status == "in_progress", let oppName = current.player2Name {
                        self.currentOpponent = PublicProfile(
                            id: current.player2Id ?? "opponent",
                            username: "rakip",
                            displayName: oppName,
                            currentLevel: current.level,
                            xp: 0,
                            avatarEmoji: current.player2Avatar ?? "⚡️"
                        )
                        self.activeMatch = current
                        self.isSearching = false
                        self.showBattleArena = true
                        break
                    }
                } catch {
                    // Keep waiting
                }
            }
        }
    }
    
    public func cancelSearch() {
        lobbyPollingTask?.cancel()
        lobbyPollingTask = nil
        
        if let match = activeMatch, match.status == "waiting" {
            Task {
                _ = try? await client
                    .from("matches")
                    .update(["status": "cancelled"])
                    .eq("id", value: match.id)
                    .execute()
            }
        }
        
        if let channel = realtimeChannel {
            Task {
                await client.realtimeV2.removeChannel(channel)
            }
        }
        
        isSearching = false
        roomCode = nil
        currentOpponent = nil
        activeMatch = nil
    }
    
    public func resetMatch() {
        lobbyPollingTask?.cancel()
        lobbyPollingTask = nil
        
        if let channel = realtimeChannel {
            Task {
                await client.realtimeV2.removeChannel(channel)
            }
            self.realtimeChannel = nil
        }
        
        isSearching = false
        roomCode = nil
        currentOpponent = nil
        activeMatch = nil
        showBattleArena = false
        opponentLiveScore = 0
        matchFinishedEventReceived = false
        errorMessage = nil
    }
}
