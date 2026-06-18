import Foundation
import SwiftUI
import Supabase

@MainActor
public class SocialManager: ObservableObject {
    public static let shared = SocialManager()
    
    @Published public var myProfile: PublicProfile? = nil
    @Published public var friends: [PublicProfile] = []
    @Published public var pendingRequests: [FriendRequest] = []
    
    private let client = SupabaseManager.shared.client
    
    // Fallback local mock arrays
    private var useMock: Bool = false
    private var mockFriends: [PublicProfile] = [
        PublicProfile(id: "mock1", username: "elif_demir", displayName: "Elif Demir", currentLevel: "B1", xp: 1250, avatarEmoji: "🦊"),
        PublicProfile(id: "mock2", username: "can_y", displayName: "Can Yılmaz", currentLevel: "A2", xp: 750, avatarEmoji: "🦁"),
        PublicProfile(id: "mock3", username: "merve_k", displayName: "Merve Kaya", currentLevel: "A1", xp: 350, avatarEmoji: "🐨")
    ]
    private var mockRequests: [FriendRequest] = [
        FriendRequest(id: "req1", senderId: "mock4", senderName: "Burak Şen", senderUsername: "burak_s", avatarEmoji: "🐼")
    ]
    
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
        // Load initial mock state
        self.friends = mockFriends
        self.pendingRequests = mockRequests
    }
    
    // MARK: - Local Persistence Helpers
    
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
    
    public func loadProfileAndFriends() async {
        guard let user = AuthManager.shared.currentUser else { return }
        
        do {
            // Try fetching from real Supabase profiles table
            let profile: PublicProfile = try await client.database
                .from("profiles")
                .select()
                .eq("id", value: user.id)
                .single()
                .execute()
                .value
            self.myProfile = profile
            useMock = false
            saveLocalProfile(profile) // Cache locally
        } catch {
            print("Supabase profile error: \(error.localizedDescription). Falling back to mock/local.")
            useMock = true
            
            // Local fallback with persistence
            if let local = loadLocalProfile() {
                self.myProfile = local
            } else {
                let defaultProfile = PublicProfile(
                    id: user.id,
                    username: user.firstName.lowercased() + "_user",
                    displayName: user.firstName + " " + user.lastName,
                    currentLevel: ProgressManager.shared.progress.currentLevel.rawValue,
                    xp: 150,
                    avatarEmoji: "🚀"
                )
                self.myProfile = defaultProfile
                saveLocalProfile(defaultProfile)
            }
        }
        
        if useMock {
            self.friends = mockFriends
            self.pendingRequests = mockRequests
        } else {
            await fetchRealFriends()
            await fetchRealRequests()
        }
    }
    
    public func updateProfile(username: String, displayName: String, avatarEmoji: String) async throws {
        guard let profile = myProfile else { return }
        var updated = profile
        updated.username = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        updated.displayName = displayName.trimmingCharacters(in: .whitespaces)
        updated.avatarEmoji = avatarEmoji
        
        // Save locally first to guarantee immediate persistence
        saveLocalProfile(updated)
        self.myProfile = updated
        
        if useMock {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        
        do {
            try await client.database
                .from("profiles")
                .update(updated)
                .eq("id", value: profile.id)
                .execute()
        } catch {
            print("Failed to update real profile: \(error)")
        }
    }
    
    public func searchUserByUsername(username: String) async -> PublicProfile? {
        let query = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if useMock {
            if query == "burak" || query == "burak_s" {
                return PublicProfile(id: "mock4", username: "burak_s", displayName: "Burak Şen", currentLevel: "B2", xp: 1800, avatarEmoji: "🐼")
            }
            if query == "selin" {
                return PublicProfile(id: "mock5", username: "selin_g", displayName: "Selin Gök", currentLevel: "A1", xp: 120, avatarEmoji: "🐱")
            }
            return nil
        }
        
        do {
            let matches: [PublicProfile] = try await client.database
                .from("profiles")
                .select()
                .eq("username", value: query)
                .execute()
                .value
            return matches.first
        } catch {
            print("Search error: \(error)")
            return nil
        }
    }
    
    public func sendFriendRequest(receiverId: String) async throws {
        guard let profile = myProfile else { return }
        
        if useMock {
            return
        }
        
        let requestData = [
            "sender_id": profile.id,
            "receiver_id": receiverId,
            "status": "pending"
        ]
        
        try await client.database
            .from("friendships")
            .insert(requestData)
            .execute()
    }
    
    public func acceptFriendRequest(requestId: String) async {
        if useMock {
            if let reqIdx = pendingRequests.firstIndex(where: { $0.id == requestId }) {
                let req = pendingRequests[reqIdx]
                let newFriend = PublicProfile(
                    id: req.senderId,
                    username: req.senderUsername,
                    displayName: req.senderName,
                    currentLevel: "A1",
                    xp: 300,
                    avatarEmoji: req.avatarEmoji
                )
                friends.append(newFriend)
                mockFriends.append(newFriend)
                pendingRequests.remove(at: reqIdx)
                mockRequests = pendingRequests
            }
            return
        }
        
        do {
            try await client.database
                .from("friendships")
                .update(["status": "accepted"])
                .eq("id", value: requestId)
                .execute()
            
            await fetchRealRequests()
            await fetchRealFriends()
        } catch {
            print("Accept friend request error: \(error)")
        }
    }
    
    public func rejectFriendRequest(requestId: String) async {
        if useMock {
            pendingRequests.removeAll(where: { $0.id == requestId })
            mockRequests = pendingRequests
            return
        }
        
        do {
            try await client.database
                .from("friendships")
                .delete()
                .eq("id", value: requestId)
                .execute()
            await fetchRealRequests()
        } catch {
            print("Reject request error: \(error)")
        }
    }
    
    // MARK: - Supabase Real fetch helpers
    
    private func fetchRealFriends() async {
        guard let profile = myProfile else { return }
        do {
            let sent: [FriendshipWrapper] = try await client.database
                .from("friendships")
                .select("id, receiver_id, status")
                .eq("sender_id", value: profile.id)
                .eq("status", value: "accepted")
                .execute()
                .value
            
            let received: [FriendshipWrapper] = try await client.database
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
            
            let profiles: [PublicProfile] = try await client.database
                .from("profiles")
                .select()
                .in("id", values: friendIDs)
                .execute()
                .value
            
            self.friends = profiles
        } catch {
            print("Fetch friends error: \(error)")
        }
    }
    
    private func fetchRealRequests() async {
        guard let profile = myProfile else { return }
        do {
            let received: [FriendshipWithSender] = try await client.database
                .from("friendships")
                .select("id, sender_id, status, profiles:sender_id(id, username, display_name, avatar_emoji)")
                .eq("receiver_id", value: profile.id)
                .eq("status", value: "pending")
                .execute()
                .value
            
            self.pendingRequests = received.map { wrapper in
                FriendRequest(
                    id: wrapper.id,
                    senderId: wrapper.profiles.id,
                    senderName: wrapper.profiles.display_name,
                    senderUsername: wrapper.profiles.username,
                    avatarEmoji: wrapper.profiles.avatar_emoji
                )
            }
        } catch {
            print("Fetch requests error: \(error)")
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
