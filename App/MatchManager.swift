import Foundation
import SwiftUI
import Supabase
import Realtime

// MARK: - Realtime Broadcast Payloads
struct PlayerJoinedPayload: Codable {
    let player2Id: String
    let player2Name: String
    let player2Avatar: String
    /// Maçın iki telefonda aynı anda başlaması için ortak başlangıç anı (epoch saniye)
    let startAt: Double?
}

struct ScoreUpdatePayload: Codable {
    let userId: String
    let score: Int
}

struct MatchFinishedPayload: Codable {
    let userId: String
    /// Son skor; bitirmeden hemen önceki score_update kaybolsa bile rakip doğru puanı görür
    let score: Int?
}

/// Sunucunun belirlediği kesin maç sonucu (ekrandaki yerel tahmini düzeltmek için)
public struct MatchResult: Equatable {
    public let myScore: Int
    public let opponentScore: Int
    public let won: Bool
    public let draw: Bool
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
    /// resetMatch bunu temizlemez; sonuç ekranı maç kapandıktan sonra da güncellenebilsin
    @Published public var lastMatchResult: MatchResult? = nil

    private let client = SupabaseManager.shared.client
    private var realtimeChannel: RealtimeChannelV2? = nil
    private var channelListenerTasks: [Task<Void, Never>] = []
    private var lobbyPollingTask: Task<Void, Never>? = nil

    /// Sunucu 3 dakikadan eski rastgele lobileri kapatıyor; istemci ondan önce vazgeçer.
    private let randomLobbyTimeout: TimeInterval = 150
    /// Katılan oyuncu bu kadar sonrasını başlangıç ilan eder; yayın kurucuya bu sürede ulaşır
    private let startDelay: TimeInterval = 2.5

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
        lastMatchResult = nil

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        do {
            // 1. Atomik olarak bekleyen bir maça katılmayı dene (sunucu tarafında kilitli)
            let joinedMatches: [DuelMatch] = try await client
                .rpc("join_random_match", params: ["p_mode": "random_\(gameMode)", "p_level": level.rawValue])
                .execute()
                .value

            if let joined = joinedMatches.first {
                searchStatus = "Rakip bulundu! Maça bağlanılıyor..."
                await enterJoinedMatch(joined, as: myProfile)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return
            }

            // 2. NO EXISTING MATCH: CREATE A WAITING MATCH & LOBBY
            let generatedCode = String(Int.random(in: 1000...9999))
            self.roomCode = generatedCode
            self.searchStatus = "Lobi açıldı (#\(generatedCode)). Çevrimiçi bir oyuncunun katılması bekleniyor..."

            let newMatch = try await insertMatch(
                roomCode: generatedCode,
                player2Id: nil,
                mode: "random_\(gameMode)",
                level: level,
                me: myProfile
            )

            self.activeMatch = newMatch
            await connectToMatchChannel(matchId: newMatch.id)
            startLobbyPolling(matchId: newMatch.id, timeout: randomLobbyTimeout)

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

        do {
            let match = try await insertMatch(
                roomCode: generatedCode,
                player2Id: nil,
                mode: "room_\(gameMode)",
                level: level,
                me: myProfile
            )
            self.activeMatch = match
            await connectToMatchChannel(matchId: match.id)
            startLobbyPolling(matchId: match.id, timeout: nil)
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
                .rpc("join_room_match", params: ["p_code": cleanCode])
                .execute()
                .value

            guard let joined = matches.first else {
                self.errorMessage = "Bu koda ait açık bir lobi bulunamadı."
                return
            }

            await enterJoinedMatch(joined, as: myProfile)
        } catch {
            self.errorMessage = "Odaya katılırken hata oluştu: \(error.localizedDescription)"
        }
    }

    // MARK: - 3. Direct Friend Invites

    public func sendDirectInvite(to friend: PublicProfile, gameMode: Int, level: CEFRLevel = ProgressManager.shared.progress.currentLevel) async {
        guard let myProfile = SocialManager.shared.myProfile else { return }

        isSearching = true
        self.searchStatus = "\(friend.displayName) davet ediliyor..."

        do {
            let match = try await insertMatch(
                roomCode: nil, // No code needed for direct invites
                player2Id: friend.id,
                mode: "friend_\(gameMode)",
                level: level,
                me: myProfile
            )
            self.activeMatch = match
            await connectToMatchChannel(matchId: match.id)
            startLobbyPolling(matchId: match.id, timeout: nil)
        } catch {
            self.errorMessage = "Davet gönderilemedi: \(error.localizedDescription)"
            self.isSearching = false
        }
    }

    public func acceptDirectInvite(match: DuelMatch) async {
        guard let myProfile = SocialManager.shared.myProfile else { return }

        do {
            let matches: [DuelMatch] = try await client
                .rpc("accept_match_invite", params: ["p_match_id": match.id])
                .execute()
                .value

            guard let joined = matches.first else {
                self.errorMessage = "Bu davet artık geçerli değil."
                return
            }

            await enterJoinedMatch(joined, as: myProfile)
        } catch {
            self.errorMessage = "Davet kabul edilemedi: \(error.localizedDescription)"
        }
    }

    public func declineDirectInvite(matchId: String) async {
        _ = try? await client
            .rpc("cancel_match", params: ["p_match_id": matchId])
            .execute()
    }

    // MARK: - Shared Match Helpers

    private func insertMatch(roomCode: String?, player2Id: String?, mode: String, level: CEFRLevel, me: PublicProfile) async throws -> DuelMatch {
        let words = WordManager.shared.words(for: level).shuffled().prefix(50).map { $0.id }
        let draft = DuelMatch(
            id: UUID().uuidString,
            roomCode: roomCode,
            player1Id: me.id,
            player2Id: player2Id,
            player1Name: me.displayName,
            player1Avatar: me.avatarEmoji,
            status: "waiting",
            mode: mode,
            level: level.rawValue,
            wordIds: Array(words)
        )
        // Sunucu trigger'ı isim/skor/durum alanlarını kendisi doldurur; dönen satırı kullan
        return try await client
            .from("matches")
            .insert(draft)
            .select()
            .single()
            .execute()
            .value
    }

    private func enterJoinedMatch(_ joined: DuelMatch, as me: PublicProfile) async {
        self.lastMatchResult = nil
        self.opponentLiveScore = 0
        self.matchFinishedEventReceived = false
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

        let startAt = Date().addingTimeInterval(startDelay)
        try? await realtimeChannel?.broadcast(
            event: "player_joined",
            message: PlayerJoinedPayload(
                player2Id: me.id,
                player2Name: me.displayName,
                player2Avatar: me.avatarEmoji,
                startAt: startAt.timeIntervalSince1970
            )
        )

        searchStatus = "Rakip bulundu! Maç başlıyor..."
        await openArena(at: startAt)
    }

    // MARK: - 4. Realtime Channel & Live Sync

    private func connectToMatchChannel(matchId: String) async {
        tearDownChannel()
        lastMatchResult = nil

        let channel = client.realtimeV2.channel("match_\(matchId)") {
            $0.broadcast.acknowledgeBroadcasts = true // skor mesajları sunucuya ulaştığı teyit edilsin
        }
        self.realtimeChannel = channel

        let joinedStream = channel.broadcastStream(event: "player_joined")
        let scoreStream = channel.broadcastStream(event: "score_update")
        let finishedStream = channel.broadcastStream(event: "match_finished")

        await channel.subscribe()

        // Listen for player joined broadcast
        channelListenerTasks.append(Task { [weak self] in
            for await message in joinedStream {
                let payload = try? message.decode(as: PlayerJoinedPayload.self)
                let name = payload?.player2Name ?? message["player2Name"]?.stringValue
                let avatar = payload?.player2Avatar ?? message["player2Avatar"]?.stringValue
                let id = payload?.player2Id ?? message["player2Id"]?.stringValue

                guard let self, let name, let avatar, let id else { continue }
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
                self.searchStatus = "Rakip bulundu! Maç başlıyor..."
                let startAt = (payload?.startAt).map { Date(timeIntervalSince1970: $0) } ?? Date()
                await self.openArena(at: startAt)
            }
        })

        // Listen for live score updates from opponent
        channelListenerTasks.append(Task { [weak self] in
            for await message in scoreStream {
                let payload = try? message.decode(as: ScoreUpdatePayload.self)
                let senderId = payload?.userId ?? message["userId"]?.stringValue
                let score = payload?.score ?? message["score"]?.intValue

                guard let self, let senderId, let score,
                      senderId != SocialManager.shared.myProfile?.id else { continue }
                // Mesajlar sırasız gelebilir; skor asla geri düşmesin
                self.opponentLiveScore = max(self.opponentLiveScore, score)
            }
        })

        // Listen for game finished event
        channelListenerTasks.append(Task { [weak self] in
            for await message in finishedStream {
                guard let self else { continue }
                let payload = try? message.decode(as: MatchFinishedPayload.self)
                let senderId = payload?.userId ?? message["userId"]?.stringValue
                guard senderId != SocialManager.shared.myProfile?.id else { continue }
                if let score = payload?.score ?? message["score"]?.intValue {
                    self.opponentLiveScore = max(self.opponentLiveScore, score)
                }
                self.matchFinishedEventReceived = true
            }
        })
    }

    private func tearDownChannel() {
        channelListenerTasks.forEach { $0.cancel() }
        channelListenerTasks.removeAll()
        if let channel = realtimeChannel {
            Task { await client.realtimeV2.removeChannel(channel) }
        }
        realtimeChannel = nil
    }

    public func sendLiveScore(score: Int) async {
        guard let myId = SocialManager.shared.myProfile?.id else { return }
        try? await realtimeChannel?.broadcast(
            event: "score_update",
            message: ScoreUpdatePayload(userId: myId, score: score)
        )
    }

    /// Oyun bitince çağrılır (resetMatch'ten ÖNCE). Skoru sunucuya gönderir; kazananı ve XP'yi
    /// sunucu belirler. Rakip skor göndermeden ayrılırsa 20 sn sonra maç sunucuda kapatılır.
    public func finishMatch(score: Int) {
        guard let matchId = activeMatch?.id,
              let myId = SocialManager.shared.myProfile?.id else { return }

        // Kanalı bu görev sahiplensin ki resetMatch broadcast'i yarıda kesmesin
        let channel = realtimeChannel
        channelListenerTasks.forEach { $0.cancel() }
        channelListenerTasks.removeAll()
        realtimeChannel = nil

        let client = self.client
        Task {
            try? await channel?.broadcast(event: "match_finished", message: MatchFinishedPayload(userId: myId, score: score))
            if let channel { await client.realtimeV2.removeChannel(channel) }

            do {
                var result: [DuelMatch] = try await client
                    .rpc("submit_match_score", params: SubmitScoreParams(p_match_id: matchId, p_score: score))
                    .execute()
                    .value

                if result.first?.status == "in_progress" {
                    try? await Task.sleep(nanoseconds: 22_000_000_000)
                    result = try await client
                        .rpc("finalize_match", params: ["p_match_id": matchId])
                        .execute()
                        .value
                }
                if let final = result.first, final.status == "completed" {
                    let amP1 = final.player1Id == myId
                    await MainActor.run {
                        self.lastMatchResult = MatchResult(
                            myScore: amP1 ? final.player1Score : final.player2Score,
                            opponentScore: amP1 ? final.player2Score : final.player1Score,
                            won: final.winnerId == myId,
                            draw: final.winnerId == nil
                        )
                    }
                }
            } catch {
                print("Submit match score error: \(error)")
            }

            await SocialManager.shared.refreshMyProfile()
        }
    }

    // MARK: - 5. Lobby Waiting Poller

    private func startLobbyPolling(matchId: String, timeout: TimeInterval?) {
        lobbyPollingTask?.cancel()
        let startedAt = Date()
        lobbyPollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Poll every 2 seconds
                guard self.isSearching else { break }

                if let timeout, Date().timeIntervalSince(startedAt) > timeout {
                    self.cancelSearch()
                    self.errorMessage = "Şu an çevrimiçi rakip bulunamadı. Robotla oynamayı dene!"
                    break
                }

                do {
                    let updated: [DuelMatch] = try await client
                        .from("matches")
                        .select()
                        .eq("id", value: matchId)
                        .execute()
                        .value

                    guard let current = updated.first else { continue }

                    if current.status == "cancelled" {
                        let wasInvite = current.mode.hasPrefix("friend_")
                        self.cancelSearch()
                        self.errorMessage = wasInvite ? "Davet reddedildi." : "Lobi kapandı. Tekrar dene."
                        break
                    }

                    if current.status == "in_progress", let oppName = current.player2Name {
                        self.currentOpponent = PublicProfile(
                            id: current.player2Id ?? "opponent",
                            username: "rakip",
                            displayName: oppName,
                            currentLevel: current.level,
                            xp: 0,
                            avatarEmoji: current.player2Avatar ?? "⚡️"
                        )
                        self.activeMatch = current
                        // Yayın kaçtıysa: katılım 0-2 sn önce oldu, rakip ~startDelay sonra başlıyor
                        self.searchStatus = "Rakip bulundu! Maç başlıyor..."
                        await self.openArena(at: Date().addingTimeInterval(self.startDelay - 1))
                        break
                    }
                } catch {
                    // Keep waiting
                }
            }
        }
    }

    /// İki telefonda arenayı aynı anda aç (zamanlayıcılar senkron başlasın)
    private func openArena(at startAt: Date) async {
        guard !showBattleArena else { return }
        let wait = min(max(startAt.timeIntervalSinceNow, 0), 5) // saat farkına karşı üst sınır
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        // Yoklama görevi iptal edildiyse (yayın daha önce geldi) açılışı yayın yolu yapar
        guard !Task.isCancelled, activeMatch != nil, !showBattleArena else { return }
        isSearching = false
        showBattleArena = true
    }

    public func cancelSearch() {
        lobbyPollingTask?.cancel()
        lobbyPollingTask = nil

        if let match = activeMatch, match.status == "waiting" {
            Task {
                _ = try? await client
                    .rpc("cancel_match", params: ["p_match_id": match.id])
                    .execute()
            }
        }

        tearDownChannel()

        isSearching = false
        roomCode = nil
        currentOpponent = nil
        activeMatch = nil
    }

    public func resetMatch() {
        lobbyPollingTask?.cancel()
        lobbyPollingTask = nil
        tearDownChannel()

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

private struct SubmitScoreParams: Encodable {
    let p_match_id: String
    let p_score: Int
}
