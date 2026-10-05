import Foundation
import SwiftUI
import Supabase

import AuthenticationServices

public enum AuthError: LocalizedError {
    case invalidCredentials
    case emptyFields
    case invalidUsername
    case supabaseError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:   return "E-posta veya şifre hatalı."
        case .emptyFields:          return "Lütfen tüm alanları doldurun."
        case .invalidUsername:      return "Kullanıcı adı 4-8 karakter uzunluğunda olmalı ve en az bir büyük harf içermelidir."
        case .supabaseError(let msg): return msg
        }
    }
}

@MainActor
public class AuthManager: ObservableObject {
    public static let shared = AuthManager()

    @Published public var isAuthenticated: Bool = false
    @Published public var isGuest: Bool = false
    @Published public var currentUser: UserProfile?

    private let client = SupabaseManager.shared.client
    private let guestStorageKey = "wordlet_guest_user"

    private init() {
        Task {
            await restoreSession()
        }
    }

    public func signInWithGoogle() async throws {
        let callbackURL = URL(string: "com.ufuk.DailyWordWidget://login-callback")!
        do {
            try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: callbackURL
            ) { session in
                #if canImport(AuthenticationServices)
                session.presentationContextProvider = AppPresentationContextProvider.shared
                #endif
            }
            await restoreSession()
        } catch {
            throw AuthError.supabaseError("Google ile giriş hatası: \(error.localizedDescription)")
        }
    }

    public func signInWithApple() async throws {
        let callbackURL = URL(string: "com.ufuk.DailyWordWidget://login-callback")!
        do {
            try await client.auth.signInWithOAuth(
                provider: .apple,
                redirectTo: callbackURL
            ) { session in
                #if canImport(AuthenticationServices)
                session.presentationContextProvider = AppPresentationContextProvider.shared
                #endif
            }
            await restoreSession()
        } catch {
            throw AuthError.supabaseError("Apple ile giriş hatası: \(error.localizedDescription)")
        }
    }

    public func continueAsGuest() {
        if let saved = UserDefaults.standard.data(forKey: guestStorageKey),
           let guest = try? JSONDecoder().decode(UserProfile.self, from: saved) {
            self.currentUser = guest
        } else {
            let randomNum = Int.random(in: 1000...9999)
            let newGuest = UserProfile(
                id: "guest_\(UUID().uuidString.prefix(8))",
                firstName: "Misafir",
                lastName: "\(randomNum)",
                email: "guest\(randomNum)@wordlet.app"
            )
            if let encoded = try? JSONEncoder().encode(newGuest) {
                UserDefaults.standard.set(encoded, forKey: guestStorageKey)
            }
            self.currentUser = newGuest
        }
        self.isGuest = true
        self.isAuthenticated = true
        Task {
            await SocialManager.shared.loadProfileAndFriends()
        }
    }

    public func register(username: String, firstName: String, lastName: String, email: String, password: String) async throws {
        let trimEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let trimUsername = username.trimmingCharacters(in: .whitespaces)
        
        guard !trimUsername.isEmpty, !firstName.isEmpty, !lastName.isEmpty, !trimEmail.isEmpty, !password.isEmpty else {
            throw AuthError.emptyFields
        }
        
        let usernameRegex = "^(?=.*[A-Z]).{4,8}$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        guard usernamePredicate.evaluate(with: trimUsername) else {
            throw AuthError.invalidUsername
        }
        
        do {
            let response = try await client.auth.signUp(
                email: trimEmail,
                password: password,
                data: [
                    "username": .string(trimUsername),
                    "first_name": .string(firstName),
                    "last_name": .string(lastName),
                    "full_name": .string("\(firstName) \(lastName)")
                ]
            )
            let user = response.user
            self.currentUser = UserProfile(id: user.id.uuidString, firstName: firstName, lastName: lastName, email: trimEmail)
            self.isGuest = false
            self.isAuthenticated = true
            await SocialManager.shared.loadProfileAndFriends()
        } catch {
            throw AuthError.supabaseError("Kayıt hatası: \(error.localizedDescription)")
        }
    }

    public func login(email: String, password: String) async throws {
        let trimEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimEmail.isEmpty, !password.isEmpty else {
            throw AuthError.emptyFields
        }

        do {
            let session = try await client.auth.signIn(email: trimEmail, password: password)
            let user = session.user
            let name = user.userMetadata["full_name"]?.value as? String ?? user.userMetadata["first_name"]?.value as? String ?? "Kullanıcı"
            self.currentUser = UserProfile(id: user.id.uuidString, firstName: name, lastName: "", email: trimEmail)
            self.isGuest = false
            self.isAuthenticated = true
            await SocialManager.shared.loadProfileAndFriends()
        } catch {
            throw AuthError.supabaseError("Giriş hatası: \(error.localizedDescription)")
        }
    }

    public func logout() async {
        do {
            try await client.auth.signOut()
        } catch {
            // Ignore error
        }
        UserDefaults.standard.removeObject(forKey: guestStorageKey)
        self.isAuthenticated = false
        self.isGuest = false
        self.currentUser = nil
    }

    public func restoreSession() async {
        do {
            let session = try await client.auth.session
            let user = session.user
            let name = user.userMetadata["full_name"]?.value as? String ?? user.userMetadata["first_name"]?.value as? String ?? "Kullanıcı"
            self.currentUser = UserProfile(id: user.id.uuidString, firstName: name, lastName: "", email: user.email ?? "")
            self.isGuest = false
            self.isAuthenticated = true
            await SocialManager.shared.loadProfileAndFriends()
        } catch {
            // Check if active guest
            if let saved = UserDefaults.standard.data(forKey: guestStorageKey),
               let guest = try? JSONDecoder().decode(UserProfile.self, from: saved) {
                self.currentUser = guest
                self.isGuest = true
                self.isAuthenticated = true
                await SocialManager.shared.loadProfileAndFriends()
            } else {
                self.isAuthenticated = false
                self.isGuest = false
                self.currentUser = nil
            }
        }
    }
}

#if canImport(AuthenticationServices)
final class AppPresentationContextProvider: NSObject, @unchecked Sendable, ASWebAuthenticationPresentationContextProviding {
    static let shared = AppPresentationContextProvider()
    
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        return window ?? scenes.first?.windows.first ?? ASPresentationAnchor()
    }
}
#endif
