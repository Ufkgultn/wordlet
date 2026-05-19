import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var isRegistering = false
    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var email     = ""
    @State private var password  = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            // Soft background blob
            Circle()
                .fill(Theme.accentLight)
                .frame(width: 400, height: 400)
                .blur(radius: 80)
                .offset(x: 100, y: -200)

            ScrollView {
                VStack(spacing: 36) {

                    // Logo
                    VStack(spacing: 12) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Theme.accent)

                        Text("Vocab Daily")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundColor(Theme.textPrimary)

                        Text(isRegistering ? "Hesap Oluştur" : "Tekrar Hoş Geldin")
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.top, 70)

                    // Form card
                    VStack(spacing: 16) {

                        if isRegistering {
                            HStack(spacing: 12) {
                                styledField("Ad", text: $firstName)
                                styledField("Soyad", text: $lastName)
                            }
                        }

                        styledField("E-posta", text: $email,
                                    keyboard: .emailAddress, autoCapitalize: false)

                        styledSecureField("Şifre", text: $password)

                        // Error message
                        if let msg = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(msg)
                                    .font(.footnote)
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Action button
                        Button(action: submit) {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(isRegistering ? "Kayıt Ol" : "Giriş Yap")
                                        .font(.headline).fontWeight(.bold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(color: Theme.accent.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(isLoading)
                    }
                    .padding(28)
                    .neumorphism()
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
                                .foregroundColor(Theme.textSecondary)
                            Text(isRegistering ? "Giriş Yap" : "Kayıt Ol")
                                .fontWeight(.bold)
                                .foregroundColor(Theme.accent)
                        }
                        .font(.footnote)
                    }

                    Spacer(minLength: 40)
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
            .padding()
            .background(Theme.cardBackground)
            .cornerRadius(12)
            .foregroundColor(Theme.textPrimary)
            .autocapitalization(autoCapitalize ? .words : .none)
            .keyboardType(keyboard)
            .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
    }

    @ViewBuilder
    private func styledSecureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .padding()
            .background(Theme.cardBackground)
            .cornerRadius(12)
            .foregroundColor(Theme.textPrimary)
            .shadow(color: Color.black.opacity(0.02), radius: 5, x: 0, y: 2)
    }

    private func submit() {
        errorMessage = nil
        isLoading = true

        Task {
            do {
                if isRegistering {
                    try await authManager.register(firstName: firstName, lastName: lastName,
                                             email: email, password: password)
                } else {
                    try await authManager.login(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
