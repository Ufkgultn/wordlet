import Foundation
import SwiftUI
import Supabase
import UserNotifications

@MainActor
public class SocialManager: ObservableObject {
    public static let shared = SocialManager()
    
    @Published public var myProfile: PublicProfile? = nil
    @Published public var friends: [PublicProfile] = []
    @Published public var pendingRequests: [FriendRequest] = []
    @Published public var friendsLeaderboard: [PublicProfile] = []
    
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
    
    private init() {
        if let local = loadLocalProfile() {
            self.myProfile = local
        }
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
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
    
    // MARK: - Profile & Friends Fetching
    
    public func loadProfileAndFriends() async {
        guard let user = AuthManager.shared.currentUser else { return }
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
                // Profile row does not exist yet: create it in the database
                let cleanUsername = user.email.components(separatedBy: "@").first ?? "user_\(Int.random(in: 100...999))"
                let newProfile = PublicProfile(
                    id: user.id,
                    username: cleanUsername.lowercased(),
                    displayName: "\(user.firstName) \(user.lastName)".trimmingCharacters(in: .whitespaces),
                    currentLevel: ProgressManager.shared.progress.currentLevel.rawValue,
                    xp: 0,
                    avatarEmoji: "🚀",
                    matchesWon: 0,
                    matchesPlayed: 0
                )
                
                try await client
                    .from("profiles")
                    .insert(newProfile)
                    .execute()
                
                self.myProfile = newProfile
                saveLocalProfile(newProfile)
            }
            
            // 2. Fetch real friends and requests
            await fetchRealFriends()
            await fetchRealRequests(isInitial: true)
            await fetchLeaderboards()
            
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
    
    public func recordDuelWin(xpGained: Int, isWin: Bool) async {
        guard var profile = myProfile else { return }
        
        profile.matchesPlayed += 1
        if isWin {
            profile.matchesWon += 1
            profile.xp += xpGained
        } else {
            profile.xp += max(5, xpGained / 4)
        }
        
        saveLocalProfile(profile)
        self.myProfile = profile
        
        // Sync with real Supabase database
        do {
            let updatePayload: [String: AnyJSON] = [
                "xp": .integer(profile.xp),
                "matches_won": .integer(profile.matchesWon),
                "matches_played": .integer(profile.matchesPlayed)
            ]
            try await client
                .from("profiles")
                .update(updatePayload)
                .eq("id", value: profile.id)
                .execute()
        } catch {
            print("Failed to sync duel win to database: \(error)")
        }
        
        await fetchLeaderboards()
    }
    
    public func updateProfile(username: String, displayName: String, avatarEmoji: String) async throws {
        guard let profile = myProfile else { return }
        var updated = profile
        updated.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        updated.displayName = displayName.trimmingCharacters(in: .whitespaces)
        updated.avatarEmoji = avatarEmoji
        
        saveLocalProfile(updated)
        self.myProfile = updated
        
        try await client
            .from("profiles")
            .update(updated)
            .eq("id", value: profile.id)
            .execute()
        
        await fetchLeaderboards()
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
        guard let profile = myProfile else { return }
        
        let requestData: [String: AnyJSON] = [
            "id": .string(UUID().uuidString),
            "sender_id": .string(profile.id),
            "receiver_id": .string(receiverId),
            "status": .string("pending")
        ]
        
        try await client
            .from("friendships")
            .insert(requestData)
            .execute()
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
            
            let allProfiles: [PublicProfile] = try await client
                .from("profiles")
                .select()
                .execute()
                .value
            
            self.friends = allProfiles.filter { friendIDs.contains($0.id) && $0.id != profile.id }
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
            }
        }
    }
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
