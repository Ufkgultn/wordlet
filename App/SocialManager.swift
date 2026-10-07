import Foundation
import SwiftUI
import Supabase
import UserNotifications

@MainActor
public class SocialManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = SocialManager()
    
    @Published public var myProfile: PublicProfile? = nil
    @Published public var friends: [PublicProfile] = []
    @Published public var pendingRequests: [FriendRequest] = []
    @Published public var sentRequestReceiverIds: Set<String> = []
    @Published public var friendsLeaderboard: [PublicProfile] = []
    @Published public var incomingMatchInvites: [DuelMatch] = []
    
    // Notifications
    @Published public var showInAppNotification: Bool = false
    @Published public var inAppNotificationMessage: String = ""
    
    private var pollingTask: Task<Void, Never>? = nil
    @Published public var globalLeaderboard: [PublicProfile] = []
    @Published public var errorMessage: String? = nil
    @Published public var isLoading: Bool = false
    
    private let client = SupabaseManager.shared.client
    
    public struct FriendRequest: Identifiable, Codable, Hashable {
        public let id: String
        public let senderId: String
        public let senderName: String
        public let senderUsername: String
        public let avatarEmoji: String
        
        public init(id: String, senderId: String, senderName: String, senderUsername: String, avatarEmoji: String) {
            self.id = id
            self.senderId = senderId
            self.senderName = senderName
            self.senderUsername = senderUsername
            self.avatarEmoji = avatarEmoji
        }
    }
    
    private override init() {
        super.init()
        if let local = loadLocalProfile() {
            self.myProfile = local
        }
        requestNotificationPermission()
        // UNUserNotificationCenter delegate and request logic is now handled in AppDelegate
    }
    
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    
    private func requestNotificationPermission() {
        // Now handled in AppDelegate
    }
    
    public func triggerLocalNotification(title: String, body: String) {
        // In-app Toast
        DispatchQueue.main.async {
            self.inAppNotificationMessage = body
            withAnimation(.spring()) {
                self.showInAppNotification = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { self.showInAppNotification = false }
            }
        }
        
        // System Push Notification (works in background or foreground depending on delegate)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule local notification: \(error)")
            }
        }
    }
    
    // MARK: - Local Persistence
    
    private func saveLocalProfile(_ profile: PublicProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "local_user_profile")
        }
    }
    
    private func loadLocalProfile() -> PublicProfile? {
        if let data = UserDefaults.standard.data(forKey: "local_user_profile"),
           let decoded = try? JSONDecoder().decode(PublicProfile.self, from: data) {
            return decoded
        }
        return nil
    }
    
    /// Çıkışta önceki kullanıcının verisi bellekte / diskte kalmasın
    public func clearSession() {
        pollingTask?.cancel()
        pollingTask = nil
        myProfile = nil
        friends = []
        pendingRequests = []
        sentRequestReceiverIds = []
        friendsLeaderboard = []
        globalLeaderboard = []
        incomingMatchInvites = []
        UserDefaults.standard.removeObject(forKey: "local_user_profile")
    }

    // MARK: - Profile & Friends Fetching
    
    public func loadProfileAndFriends() async {
        guard let user = AuthManager.shared.currentUser else { return }

        // Misafirin Supabase hesabı yok (id UUID değil); online özellikler kapalı
        guard !AuthManager.shared.isGuest else {
            clearSession()
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // 1. Fetch current user's profile from Supabase
            let profileResponse: [PublicProfile] = try await client
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .execute()
                .value
            
            if let existing = profileResponse.first {
                self.myProfile = existing
                saveLocalProfile(existing)
            } else {
                // Profile row does not exist yet (normalde signup trigger'ı oluşturur)
                let cleanUsername = user.email.components(separatedBy: "@").first ?? "user_\(Int.random(in: 100...999))"
                let draft = ProfileInsert(
                    id: user.id,
                    username: cleanUsername.lowercased(),
                    display_name: "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces),
                    current_level: ProgressManager.shared.progress.currentLevel.rawValue,
                    avatar_emoji: "🚀"
                )

                let newProfile: PublicProfile = try await client
                    .from("profiles")
                    .insert(draft)
                    .select()
                    .single()
                    .execute()
                    .value

                self.myProfile = newProfile
                saveLocalProfile(newProfile)
            }
            
            // 2. Fetch real friends and requests
            await fetchRealFriends()
            await fetchRealRequests(isInitial: true)
            await fetchIncomingMatchInvites()
            await fetchLeaderboards()
            
            // Sync pending push token if available
            if let pendingToken = UserDefaults.standard.string(forKey: "pendingPushToken") {
                await updatePushToken(pendingToken)
            }
            
            // Start Polling
            startPolling()
        } catch {
            print("Supabase profile load error: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            if myProfile == nil, let local = loadLocalProfile() {
                self.myProfile = local
            }
        }
        
        isLoading = false
    }
    
    public func fetchLeaderboards() async {
        do {
            // Real Global Leaderboard from Supabase profiles
            let globals: [PublicProfile] = try await client
                .from("profiles")
                .select()
                .order("xp", ascending: false)
                .limit(50)
                .execute()
                .value
            self.globalLeaderboard = globals
        } catch {
            print("Failed to fetch global leaderboard: \(error)")
        }
        
        // Real Friends Leaderboard: My profile + accepted friends
        var list: [PublicProfile] = []
        if let me = myProfile {
            list.append(me)
        }
        for f in friends {
            if !list.contains(where: { $0.id == f.id }) {
                list.append(f)
            }
        }
        self.friendsLeaderboard = list.sorted(by: { $0.xp > $1.xp })
    }
    
    /// Robot düellosu sonucu. XP'yi sunucu verir (günlük limitli); online maç XP'si
    /// submit_match_score ile sunucuda hesaplanır.
    public func recordBotDuel(won: Bool) async {
        guard myProfile != nil else { return }
        do {
            let updated: PublicProfile = try await client
                .rpc("record_bot_duel", params: ["p_won": won])
                .execute()
                .value
            self.myProfile = updated
            saveLocalProfile(updated)
        } catch {
            print("Failed to record bot duel: \(error)")
        }
        await fetchLeaderboards()
    }

    /// Sunucudaki güncel XP / maç istatistiklerini çek
    public func refreshMyProfile() async {
        guard let id = myProfile?.id else { return }
        do {
            let rows: [PublicProfile] = try await client
                .from("profiles")
                .select()
                .eq("id", value: id)
                .execute()
                .value
            if let fresh = rows.first {
                self.myProfile = fresh
                saveLocalProfile(fresh)
            }
        } catch {
            print("Failed to refresh profile: \(error)")
        }
        await fetchLeaderboards()
    }
    
    public func updateProfile(username: String, displayName: String, avatarEmoji: String) async throws {
        guard let profile = myProfile else { return }
        
        let newUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if newUsername != profile.username {
            let currentYear = Calendar.current.component(.year, from: Date())
            let yearKey = "usernameChangesYear"
            let countKey = "usernameChangesCount"
            
            let savedYear = UserDefaults.standard.integer(forKey: yearKey)
            var count = UserDefaults.standard.integer(forKey: countKey)
            
            if savedYear != currentYear {
                count = 0
                UserDefaults.standard.set(currentYear, forKey: yearKey)
            }
            
            if count >= 2 {
                throw NSError(domain: "SocialManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "Kullanıcı adınızı yılda en fazla 2 kez değiştirebilirsiniz."])
            }
            
            do {
                let existingUsers: [PublicProfile] = try await client
                    .from("profiles")
                    .select()
                    .eq("username", value: newUsername)
                    .execute()
                    .value
                
                if !existingUsers.isEmpty {
                    throw NSError(domain: "SocialManager", code: 409, userInfo: [NSLocalizedDescriptionKey: "Bu kullanıcı adı zaten alınmış."])
                }
            } catch let error as NSError where error.domain == "SocialManager" {
                throw error
            } catch {
                throw NSError(domain: "SocialManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Kullanıcı adı kontrol edilemedi. Lütfen tekrar deneyin."])
            }
            
            UserDefaults.standard.set(count + 1, forKey: countKey)
        }
        
        var updated = profile
        updated.username = newUsername
        updated.displayName = displayName.trimmingCharacters(in: .whitespaces)
        updated.avatarEmoji = avatarEmoji
        
        saveLocalProfile(updated)
        self.myProfile = updated
        
        // Sadece istemcinin yazabildiği alanlar (xp / matches_* sunucuda korunuyor)
        try await client
            .from("profiles")
            .update(ProfileUpdate(
                username: updated.username,
                display_name: updated.displayName,
                avatar_emoji: updated.avatarEmoji
            ))
            .eq("id", value: profile.id)
            .execute()

        await fetchLeaderboards()
    }

    public func updatePushToken(_ token: String) async {
        UserDefaults.standard.set(token, forKey: "pendingPushToken")
        guard let profile = myProfile else { return }

        // Sadece token (veya kullanıcı) değişmişse veritabanını güncelle
        let syncedKey = "syncedPushToken_\(profile.id)"
        guard UserDefaults.standard.string(forKey: syncedKey) != token else { return }

        #if DEBUG
        let apnsEnv = "sandbox"
        #else
        let apnsEnv = "production"
        #endif

        do {
            try await client
                .from("device_tokens")
                .upsert(DeviceTokenRow(user_id: profile.id, token: token, apns_env: apnsEnv), onConflict: "user_id")
                .execute()
            UserDefaults.standard.set(token, forKey: syncedKey)
        } catch {
            print("Failed to update push token in Supabase: \(error)")
        }
    }
    
    public func searchUserByUsername(username: String) async -> PublicProfile? {
        let query = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return nil }
        
        do {
            let matches: [PublicProfile] = try await client
                .from("profiles")
                .select()
                .eq("username", value: query)
                .execute()
                .value
            return matches.first
        } catch {
            print("Real search user error: \(error)")
            return nil
        }
    }
    
    public func sendFriendRequest(receiverId: String) async throws {
        guard myProfile != nil else { return }

        // Karşı taraf zaten istek attıysa sunucu otomatik kabul eder
        let status: String = try await client
            .rpc("send_friend_request", params: ["p_receiver": receiverId])
            .execute()
            .value

        if status == "accepted" {
            await fetchRealRequests(isInitial: true)
            await fetchRealFriends()
            await fetchLeaderboards()
        } else {
            self.sentRequestReceiverIds.insert(receiverId)
        }
    }
    
    public func acceptFriendRequest(requestId: String) async {
        do {
            try await client
                .from("friendships")
                .update(["status": "accepted"])
                .eq("id", value: requestId)
                .execute()
            
            await fetchRealRequests(isInitial: true)
            await fetchRealFriends()
            await fetchLeaderboards()
        } catch {
            print("Accept friend request error: \(error)")
        }
    }
    
    public func rejectFriendRequest(requestId: String) async {
        do {
            try await client
                .from("friendships")
                .delete()
                .eq("id", value: requestId)
                .execute()
            
            await fetchRealRequests(isInitial: true)
        } catch {
            print("Reject request error: \(error)")
        }
    }
    
    // MARK: - Supabase Real Friends Fetching
    
    private func fetchRealFriends() async {
        guard let profile = myProfile else { return }
        do {
            let sent: [FriendshipWrapper] = try await client
                .from("friendships")
                .select("id, receiver_id, status")
                .eq("sender_id", value: profile.id)
                .eq("status", value: "accepted")
                .execute()
                .value
            
            let received: [FriendshipWrapper] = try await client
                .from("friendships")
                .select("id, sender_id, status")
                .eq("receiver_id", value: profile.id)
                .eq("status", value: "accepted")
                .execute()
                .value
            
            var friendIDs: [String] = []
            friendIDs.append(contentsOf: sent.compactMap { $0.receiver_id })
            friendIDs.append(contentsOf: received.compactMap { $0.sender_id })
            
            if friendIDs.isEmpty {
                self.friends = []
                return
            }
            
            let friendProfiles: [PublicProfile] = try await client
                .from("profiles")
                .select()
                .in("id", values: friendIDs)
                .execute()
                .value

            self.friends = friendProfiles.filter { $0.id != profile.id }
        } catch {
            print("Fetch real friends error: \(error)")
            self.friends = []
        }
    }
    
    private func fetchRealRequests(isInitial: Bool = false) async {
        guard let profile = myProfile else { return }
        do {
            let received: [FriendshipWithSender] = try await client
                .from("friendships")
                .select("id, sender_id, status, profiles:sender_id(id, username, display_name, avatar_emoji)")
                .eq("receiver_id", value: profile.id)
                .eq("status", value: "pending")
                .execute()
                .value
                
            let sent: [FriendshipWrapper] = try await client
                .from("friendships")
                .select("id, receiver_id, status")
                .eq("sender_id", value: profile.id)
                .eq("status", value: "pending")
                .execute()
                .value
            
            self.sentRequestReceiverIds = Set(sent.compactMap { $0.receiver_id })
            
            let previousCount = self.pendingRequests.count
            self.pendingRequests = received.map { wrapper in
                FriendRequest(
                    id: wrapper.id,
                    senderId: wrapper.profiles.id,
                    senderName: wrapper.profiles.display_name,
                    senderUsername: wrapper.profiles.username,
                    avatarEmoji: wrapper.profiles.avatar_emoji
                )
            }
            
            // If new requests arrived
            if !isInitial && self.pendingRequests.count > previousCount {
                if let newest = self.pendingRequests.last {
                    triggerLocalNotification(
                        title: "Yeni Arkadaşlık İsteği!",
                        body: "\(newest.senderName) sana arkadaşlık isteği gönderdi."
                    )
                }
            }
            
        } catch {
            print("Fetch real requests error: \(error)")
            self.pendingRequests = []
        }
    }
    
    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // Poll every 10 seconds
                await fetchRealRequests(isInitial: false)
                await fetchIncomingMatchInvites()
                await fetchRealFriends()
                await fetchLeaderboards()
            }
        }
    }
}

// Write payloads: only the columns the client is granted on the server
private struct ProfileInsert: Encodable {
    let id: String
    let username: String
    let display_name: String
    let current_level: String
    let avatar_emoji: String
}

private struct ProfileUpdate: Encodable {
    let username: String
    let display_name: String
    let avatar_emoji: String
}

private struct DeviceTokenRow: Encodable {
    let user_id: String
    let token: String
    let apns_env: String
}

// Swift Codable wrappers for parsing complex joins
struct FriendshipWrapper: Codable {
    let id: String
    let sender_id: String?
    let receiver_id: String?
    let status: String
}

struct FriendshipWithSender: Codable {
    let id: String
    let sender_id: String
    let status: String
    let profiles: ProfileSubWrapper
}

struct ProfileSubWrapper: Codable {
    let id: String
    let username: String
    let display_name: String
    let avatar_emoji: String
}
import Foundation
import SwiftUI

extension SocialManager {
    // Polled inside startPolling()
    public func fetchIncomingMatchInvites() async {
        guard let profile = myProfile else { return }
        
        do {
            let matches: [DuelMatch] = try await SupabaseManager.shared.client
                .from("matches")
                .select()
                .eq("player2_id", value: profile.id)
                .eq("status", value: "waiting")
                .execute()
                .value
            
            // Only keep mode starting with "friend_"
            let invites = matches.filter { $0.mode.starts(with: "friend_") }
            
            await MainActor.run {
                if invites.count > self.incomingMatchInvites.count {
                    if let newest = invites.last {
                        self.triggerLocalNotification(
                            title: "Yeni Maç Daveti!",
                            body: "\(newest.player1Name) seni düelloya davet ediyor!"
                        )
                    }
                }
                self.incomingMatchInvites = invites
            }
        } catch {
            print("Fetch match invites error: \(error)")
        }
    }
}
