import Foundation
import SwiftUI
import Supabase

public enum AuthError: LocalizedError {
    case invalidCredentials
    case emptyFields
    case supabaseError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:   return "E-posta veya şifre hatalı."
        case .emptyFields:          return "Lütfen tüm alanları doldurun."
        case .supabaseError(let msg): return msg
        }
    }
}

@MainActor
public class AuthManager: ObservableObject {
    public static let shared = AuthManager()

    @Published public var isAuthenticated: Bool = false
    @Published public var currentUser: UserProfile?

    private let client = SupabaseManager.shared.client

    private init() {
        Task {
            await restoreSession()
        }
    }

    public func register(firstName: String, lastName: String, email: String, password: String) async throws {
        let trimEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !firstName.isEmpty, !lastName.isEmpty, !trimEmail.isEmpty, !password.isEmpty else {
            throw AuthError.emptyFields
        }
        
        do {
            let response = try await client.auth.signUp(email: trimEmail, password: password)
            let user = response.user
            self.currentUser = UserProfile(id: user.id.uuidString, firstName: firstName, lastName: lastName, email: trimEmail)
            self.isAuthenticated = true
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
            self.currentUser = UserProfile(id: user.id.uuidString, firstName: "Kullanıcı", lastName: "", email: trimEmail)
            self.isAuthenticated = true
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
        self.isAuthenticated = false
        self.currentUser = nil
    }

    public func restoreSession() async {
        do {
            let session = try await client.auth.session
            let user = session.user
            self.currentUser = UserProfile(id: user.id.uuidString, firstName: "Kullanıcı", lastName: "", email: user.email ?? "")
            self.isAuthenticated = true
        } catch {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }
}
