import SwiftUI
import WidgetKit
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var socialManager = SocialManager.shared
    
    // Tema Modu
    @AppStorage("themeMode") private var themeMode: String = "dark"
    
    // Yenileme Sıklığı
    @State private var selectedInterval: Int = AppSettingsManager.shared.settings.widgetUpdateIntervalMinutes
    @State private var showSaveSuccess = false
    
    // Accordion Expand/Collapse States
    @State private var isProfileExpanded = true
    @State private var isThemeExpanded = false
    @State private var isIntervalExpanded = false
    
    // Profile Edit Mode
    @State private var editFirstName = ""
    @State private var editLastName = ""
    @State private var editUsername = ""
    @State private var editAvatarEmoji = "🚀"
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
    @State private var avatarPickerMode = 0 // 0: Avatar Emojisi, 1: Galeri Fotoğrafı
    @State private var showSaveProfileSuccess = false
    @State private var profileSaveError: String? = nil
    @State private var showLoginSheet = false
    @State private var showDeleteAccountAlert = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String? = nil
    
    let intervals = [
        (label: "5 Dakika", minutes: 5, icon: "timer"),
        (label: "30 Dakika", minutes: 30, icon: "timer"),
        (label: "1 Saat", minutes: 60, icon: "clock"),
        (label: "3 Saat", minutes: 180, icon: "clock.fill"),
        (label: "5 Saat", minutes: 300, icon: "hourglass")
    ]
    
    var body: some View {
        ZStack {
            AppBackground()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    // Başlık
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ayarlar")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.fg)
                        Text("Profilini düzenle, tema seç ve düello yap.")
                            .font(.subheadline)
                            .foregroundColor(Theme.fg.opacity(0.6))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // 1. PROFİL AYARLARI (Accordion)
                    VStack(alignment: .leading, spacing: 12) {
                        accordionHeader(title: "Profil Ayarları", icon: "person.circle.fill", isExpanded: $isProfileExpanded)
                        
                        if isProfileExpanded {
                            profileSectionContent
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // 2. EKRAN TEMA MODU (Accordion)
                    VStack(alignment: .leading, spacing: 12) {
                        accordionHeader(title: "Ekran Tema Modu", icon: "paintpalette.fill", isExpanded: $isThemeExpanded)
                        
                        if isThemeExpanded {
                            themeSectionContent
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // 3. WIDGET YENİLENME SIKLIĞI (Accordion)
                    VStack(alignment: .leading, spacing: 12) {
                        accordionHeader(title: "Widget Yenileme Sıklığı", icon: "clock.fill", isExpanded: $isIntervalExpanded)
                        
                        if isIntervalExpanded {
                            intervalSectionContent
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            loadInitialSocialData()
        }
        .onChange(of: socialManager.myProfile?.id) { _ in
            syncEditFields()
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
        .alert("Hata", isPresented: Binding(
            get: { profileSaveError != nil },
            set: { if !$0 { profileSaveError = nil } }
        )) {
            Button("Tamam", role: .cancel) { }
        } message: {
            Text(profileSaveError ?? "")
        }
    }
    
    // MARK: - Accordion Header
    
    private func accordionHeader(title: String, icon: String, isExpanded: Binding<Bool>) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isExpanded.wrappedValue.toggle()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(Theme.accentText)
                    .frame(width: 24)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(Theme.fg)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.fg.opacity(0.4))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.fg.opacity(0.06)))
        }
    }
    
    // MARK: - Section Content: Profile
    
    private var fullNamePreview: String {
        let full = "\(editFirstName) \(editLastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "Profil İsmi" : full
    }
    
    private var profileSectionContent: some View {
        VStack(spacing: 20) {
            // Guest or Not Logged In Warning Banner
            if !authManager.isAuthenticated || authManager.isGuest {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title2)
                            .foregroundColor(Theme.accentText)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(authManager.isGuest ? "Misafir Hesabı Kullanıyorsun" : "Giriş Yapılmadı")
                                .font(.subheadline.bold())
                                .foregroundColor(Theme.fg)
                            Text("Puanlarını kaydetmek ve arkadaşlarınla yarışmak için oturum aç.")
                                .font(.caption2)
                                .foregroundColor(Theme.fg.opacity(0.6))
                        }
                    }
                    Button(action: { showLoginSheet = true }) {
                        Text("Giriş Yap / Hesap Oluştur (Google / Apple)")
                            .font(.caption.bold())
                            .foregroundColor(Theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.accent.opacity(0.12)))
            }

            // Profil düzenleme sadece giriş yapılmış (sunucuda profili olan) kullanıcıya gösterilir;
            // çıkış ya da hesap silme sonrası eski profil ekranda kalmasın
            if socialManager.myProfile != nil {
                VStack(spacing: 20) {
                    // 1. Live Profile Card Preview
                    HStack(spacing: 16) {
                        UserAvatarView(
                            emoji: editAvatarEmoji,
                            size: 74,
                            customPhotoData: selectedPhotoData
                        )
                
                        VStack(alignment: .leading, spacing: 6) {
                            Text(fullNamePreview)
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.fg)
                                .lineLimit(1)
                    
                            Text("@\(editUsername.isEmpty ? "kullanici" : editUsername)")
                                .font(.subheadline)
                                .foregroundColor(Theme.accentText)
                                .lineLimit(1)
                    
                            HStack(spacing: 6) {
                                Text(socialManager.myProfile?.currentLevel ?? "A1")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Theme.onAccent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.accent))
                        
                                Text("\(socialManager.myProfile?.xp ?? 0) XP")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Theme.fg.opacity(0.6))
                            }
                        }
                
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Theme.fg.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Theme.fg.opacity(0.1), lineWidth: 1)
                            )
                    )
            
                    // 2. Avatar & Photo Mode Selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PROFİL GÖRSELİ")
                            .font(.caption.bold())
                            .foregroundColor(Theme.accentText)
                
                        Picker("", selection: $avatarPickerMode) {
                            Text("🎭 Hazır Avatar").tag(0)
                            Text("📸 Özel Fotoğraf").tag(1)
                        }
                        .pickerStyle(.segmented)
                
                        if avatarPickerMode == 0 {
                            // 16 Modern Emoji Avatars in a 4-column Grid
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                                ForEach([
                                    "🚀", "🦁", "🦊", "🐼", 
                                    "🐨", "🐱", "🦉", "🦄", 
                                    "⚡️", "👑", "🎯", "💎", 
                                    "🐉", "🥷", "🐺", "🏆"
                                ], id: \.self) { emoji in
                                    Button(action: {
                                        editAvatarEmoji = emoji
                                        selectedPhotoData = nil
                                        UserDefaults.standard.removeObject(forKey: "user_profile_photo_data")
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }) {
                                        Text(emoji)
                                            .font(.title2)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 52)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .fill((editAvatarEmoji == emoji && selectedPhotoData == nil) ? Theme.accent.opacity(0.25) : Theme.fg.opacity(0.05))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke((editAvatarEmoji == emoji && selectedPhotoData == nil) ? Theme.accent : Theme.fg.opacity(0.08), lineWidth: 1.5)
                                            )
                                    }
                                }
                            }
                            .padding(.top, 4)
                        } else {
                            // Custom Photo Selection via PhotosPicker
                            VStack(spacing: 12) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.headline)
                                        Text(selectedPhotoData != nil ? "Fotoğrafı Değiştir" : "Galeriden Fotoğraf Seç")
                                            .font(.subheadline.bold())
                                    }
                                    .foregroundColor(Theme.onAccent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Theme.accent)
                                    .cornerRadius(14)
                                }
                        
                                if selectedPhotoData != nil {
                                    Button(action: {
                                        selectedPhotoData = nil
                                        selectedPhotoItem = nil
                                        UserDefaults.standard.removeObject(forKey: "user_profile_photo_data")
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "trash")
                                            Text("Fotoğrafı Kaldır")
                                        }
                                        .font(.caption.bold())
                                        .foregroundColor(.red.opacity(0.9))
                                    }
                                }
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.fg.opacity(0.04)))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.fg.opacity(0.04)))
            
                    // 3. Name, Surname & Username Fields
                    VStack(alignment: .leading, spacing: 14) {
                        Text("KİŞİSEL BİLGİLER")
                            .font(.caption.bold())
                            .foregroundColor(Theme.accentText)
                
                        // First Name and Last Name side by side
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Ad")
                                    .font(.caption2.bold())
                                    .foregroundColor(Theme.fg.opacity(0.6))
                                TextField("Adınız", text: $editFirstName)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.fg.opacity(0.08)))
                                    .foregroundColor(Theme.fg)
                            }
                    
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Soyad")
                                    .font(.caption2.bold())
                                    .foregroundColor(Theme.fg.opacity(0.6))
                                TextField("Soyadınız", text: $editLastName)
                                    .textFieldStyle(.plain)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.fg.opacity(0.08)))
                                    .foregroundColor(Theme.fg)
                            }
                        }
                
                        // Username field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Kullanıcı Adı")
                                .font(.caption2.bold())
                                .foregroundColor(Theme.fg.opacity(0.6))
                    
                            HStack(spacing: 4) {
                                Text("@")
                                    .foregroundColor(Theme.accentText)
                                    .font(.headline.bold())
                        
                                TextField("kullanici_adi", text: $editUsername)
                                    .textFieldStyle(.plain)
                                    .foregroundColor(Theme.fg)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.fg.opacity(0.08)))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.fg.opacity(0.04)))
            
                    // 4. Save Changes Button
                    Button(action: {
                        Task {
                            let combinedName = "\(editFirstName) \(editLastName)".trimmingCharacters(in: .whitespaces)
                            do {
                                try await socialManager.updateProfile(
                                    username: editUsername,
                                    displayName: combinedName.isEmpty ? "Kullanıcı" : combinedName,
                                    avatarEmoji: editAvatarEmoji
                                )
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                withAnimation {
                                    showSaveProfileSuccess = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation {
                                        showSaveProfileSuccess = false
                                    }
                                }
                            } catch {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                                profileSaveError = error.localizedDescription
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            if showSaveProfileSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.headline)
                                Text("Başarıyla Kaydedildi!")
                                    .font(.headline.bold())
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.subheadline)
                                Text("Değişiklikleri Kaydet")
                                    .font(.headline.bold())
                            }
                        }
                        .foregroundColor(Theme.onAccent)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(showSaveProfileSuccess ? Color.green : Theme.accent)
                        )
                        .shadow(color: (showSaveProfileSuccess ? Color.green : Theme.accent).opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                }
            }

            if authManager.isAuthenticated {
                Divider().background(Theme.fg.opacity(0.1))
            
                // 5. Account Security: Log Out & App Store Compliant Delete Account
                VStack(spacing: 10) {
                    Button(action: {
                        Task {
                            await authManager.logout()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Oturumu Kapat")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(Theme.fg.opacity(0.8))
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.fg.opacity(0.08)))
                    }
                
                    Button(action: {
                        showDeleteAccountAlert = true
                    }) {
                        HStack(spacing: 6) {
                            if isDeletingAccount {
                                ProgressView().tint(.red)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text(isDeletingAccount ? "Hesabın siliniyor..." : "Hesabımı ve Verilerimi Sil")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.fg.opacity(0.03)))
        .alert("Hesabını Silmek İstiyor musun?", isPresented: $showDeleteAccountAlert) {
            Button("Vazgeç", role: .cancel) {}
            Button("Hesabımı Sil", role: .destructive) {
                Task {
                    isDeletingAccount = true
                    defer { isDeletingAccount = false }
                    do {
                        try await authManager.deleteAccount()
                    } catch {
                        deleteAccountError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("Bu işlem geri alınamaz. Profiliniz, skorlarınız ve arkadaşlık bilgileriniz silinecektir.")
        }
        .alert("Hesap Silinemedi", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(deleteAccountError ?? "")
        }
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        self.selectedPhotoData = data
                        UserDefaults.standard.set(data, forKey: "user_profile_photo_data")
                        self.avatarPickerMode = 1
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            }
        }
    }
    
    // MARK: - Section Content: Theme Selection
    
    private var themeSectionContent: some View {
        VStack(spacing: 12) {
            Picker("Tema Modu", selection: $themeMode) {
                Text("Sistem").tag("system")
                Text("Karanlık").tag("dark")
                Text("Aydınlık").tag("light")
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.fg.opacity(0.04)))
    }
    
    // MARK: - Section Content: Intervals
    
    private var intervalSectionContent: some View {
        VStack(spacing: 0) {
            ForEach(intervals, id: \.minutes) { interval in
                Button(action: {
                    withAnimation(.spring()) {
                        selectedInterval = interval.minutes
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    HStack {
                        Image(systemName: interval.icon)
                            .frame(width: 24)
                            .foregroundColor(selectedInterval == interval.minutes ? Theme.accentText : Theme.fg.opacity(0.7))
                        
                        Text(interval.label)
                            .foregroundColor(Theme.fg)
                        
                        Spacer()
                        
                        if selectedInterval == interval.minutes {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.accentText)
                                .transition(.scale)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(selectedInterval == interval.minutes ? Theme.fg.opacity(0.04) : Color.clear)
                }
                
                if interval.minutes != intervals.last?.minutes {
                    Divider()
                        .background(Theme.fg.opacity(0.1))
                        .padding(.leading, 50)
                }
            }
            
            // Save Settings Trigger Button
            Button(action: {
                saveSettings()
            }) {
                HStack {
                    Spacer()
                    if showSaveSuccess {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Kaydedildi!")
                    } else {
                        Text("Sıklık Ayarını Kaydet")
                    }
                    Spacer()
                }
                .font(.subheadline.bold())
                .foregroundColor(Theme.onAccent)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(showSaveSuccess ? Color.green : Theme.accent))
                .padding(14)
            }
            .disabled(showSaveSuccess)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.fg.opacity(0.04)))
    }
    
    // MARK: - Actions
    
    private func loadInitialSocialData() {
        Task {
            await socialManager.loadProfileAndFriends()
            syncEditFields()
        }
    }

    /// Düzenleme alanlarını mevcut profille eşitle; profil yoksa (çıkış / hesap silme) temizle
    private func syncEditFields() {
        guard let myP = socialManager.myProfile else {
            editUsername = ""
            editFirstName = ""
            editLastName = ""
            editAvatarEmoji = "🚀"
            selectedPhotoData = nil
            avatarPickerMode = 0
            return
        }
        editUsername = myP.username
        let parts = myP.displayName.components(separatedBy: " ")
        editFirstName = parts.first ?? ""
        editLastName = parts.dropFirst().joined(separator: " ")
        editAvatarEmoji = myP.avatarEmoji
        if let data = UserDefaults.standard.data(forKey: "user_profile_photo_data") {
            selectedPhotoData = data
            avatarPickerMode = 1
        }
    }
    

    
    private func saveSettings() {
        var settings = AppSettingsManager.shared.settings
        settings.widgetUpdateIntervalMinutes = selectedInterval
        AppSettingsManager.shared.settings = settings
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        withAnimation(.spring()) {
            showSaveSuccess = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring()) {
                showSaveSuccess = false
            }
        }
        
        WidgetCenter.shared.reloadAllTimelines()
    }
}
