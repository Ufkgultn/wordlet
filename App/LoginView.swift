import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject private var authManager = AuthManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isRegistering = false
    @State private var username  = ""
    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var email     = ""
    @State private var password  = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Close button header
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    // Logo & App Name
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Theme.accent, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 72, height: 72)
                                .opacity(0.3)
                            
                            Image(systemName: "bolt.shield.fill")
                                .font(.system(size: 34))
                                .foregroundColor(Theme.accent)
                        }

                        Text("Wordlet")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(isRegistering ? "Yeni Bir Hesap Oluştur" : "Kelime Düellolarına Katıl")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 10)

                    // Quick OAuth Buttons (Google & Apple)
                    VStack(spacing: 12) {
                        // Google Sign-In Button
                        Button(action: handleGoogleSignIn) {
                            HStack(spacing: 12) {
                                Image(systemName: "g.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.red)
                                Text("Google ile Devam Et")
                                    .font(.headline)
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .cornerRadius(14)
                            .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 3)
                        }
                        
                        // Apple Sign-In Button
                        Button(action: handleAppleSignIn) {
                            HStack(spacing: 10) {
                                Image(systemName: "applelogo")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                Text("Apple ile Giriş Yap")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 24)

                    // Divider: "veya e-posta ile"
                    HStack {
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                        Text("veya e-posta ile")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 8)
                        Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
                    }
                    .padding(.horizontal, 24)

                    // Email/Password Form Card
                    VStack(spacing: 14) {
                        if isRegistering {
                            styledField("Kullanıcı Adı", text: $username, autoCapitalize: false)
                            HStack(spacing: 12) {
                                styledField("Ad", text: $firstName)
                                styledField("Soyad", text: $lastName)
                            }
                        }

                        styledField("E-posta", text: $email, keyboard: .emailAddress, autoCapitalize: false)
                        styledSecureField("Şifre (en az 6 karakter)", text: $password)

                        if let msg = errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(msg)
                                    .font(.caption)
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: submitEmailAuth) {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(isRegistering ? "Kayıt Ol" : "E-posta ile Giriş")
                                        .font(.headline.bold())
                                        .foregroundColor(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .cornerRadius(14)
                            .shadow(color: Theme.accent.opacity(0.25), radius: 8, x: 0, y: 4)
                        }
                        .disabled(isLoading)
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05)))
                    .padding(.horizontal, 24)

                    // Toggle register / login
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRegistering.toggle()
                            errorMessage = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(isRegistering ? "Zaten hesabın var mı?" : "Hesabın yok mu?")
                                .foregroundColor(.white.opacity(0.6))
                            Text(isRegistering ? "Giriş Yap" : "Kayıt Ol")
                                .fontWeight(.bold)
                                .foregroundColor(Theme.accent)
                        }
                        .font(.footnote)
                    }

                    // Continue as Guest Option
                    Button(action: {
                        authManager.continueAsGuest()
                        dismiss()
                    }) {
                        Text("Kayıt Olmadan Misafir Olarak Oyna")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.45))
                            .underline()
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 30)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>,
                             keyboard: UIKeyboardType = .default,
                             autoCapitalize: Bool = true) -> some View {
        TextField(placeholder, text: text)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            .foregroundColor(.white)
            .autocapitalization(autoCapitalize ? .words : .none)
            .keyboardType(keyboard)
    }

    @ViewBuilder
    private func styledSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            .foregroundColor(.white)
    }

    private func handleGoogleSignIn() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await authManager.signInWithGoogle()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func handleAppleSignIn() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await authManager.signInWithApple()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func submitEmailAuth() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                if isRegistering {
                    try await authManager.register(
                        username: username,
                        firstName: firstName,
                        lastName: lastName,
                        email: email,
                        password: password
                    )
                } else {
                    try await authManager.login(email: email, password: password)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
