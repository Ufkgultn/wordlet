import Foundation
import SwiftUI

extension MatchManager {
    // MARK: - Direct Friend Invites
    
    public func sendDirectInvite(to friend: PublicProfile, gameMode: Int, level: CEFRLevel = ProgressManager.shared.progress.currentLevel) async {
        guard let myProfile = SocialManager.shared.myProfile else { return }
        
        isSearching = true
        self.searchStatus = "\(friend.displayName) davet ediliyor..."
        
        let words = WordManager.shared.words(for: level).shuffled().prefix(50).map { $0.id }
        let match = DuelMatch(
            id: UUID().uuidString,
            roomCode: nil, // No code needed for direct invites
            player1Id: myProfile.id,
            player2Id: friend.id,
            player1Name: myProfile.displayName,
            player1Avatar: myProfile.avatarEmoji,
            status: "waiting",
            mode: "friend_\(gameMode)",
            level: level.rawValue,
            wordIds: Array(words)
        )
        
        do {
            try await SupabaseManager.shared.client.from("matches").insert(match).execute()
            self.activeMatch = match
            await connectToMatchChannel(matchId: match.id)
            startLobbyPolling(matchId: match.id)
        } catch {
            self.errorMessage = "Davet gönderilemedi: \(error.localizedDescription)"
            self.isSearching = false
        }
    }
    
    public func acceptDirectInvite(match: DuelMatch) async {
        guard let myProfile = SocialManager.shared.myProfile else { return }
        
        do {
            var joined = match
            joined.player2Name = myProfile.displayName
            joined.player2Avatar = myProfile.avatarEmoji
            joined.status = "in_progress"
            
            try await SupabaseManager.shared.client
                .from("matches")
                .update([
                    "player2_name": myProfile.displayName,
                    "player2_avatar": myProfile.avatarEmoji,
                    "status": "in_progress"
                ])
                .eq("id", value: match.id)
                .execute()
            
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
            self.errorMessage = "Davet kabul edilemedi: \(error.localizedDescription)"
        }
    }
    
    public func declineDirectInvite(matchId: String) async {
        _ = try? await SupabaseManager.shared.client
            .from("matches")
            .update(["status": "cancelled"])
            .eq("id", value: matchId)
            .execute()
    }
}
