import SwiftUI
import WidgetKit

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
    @State private var editUsername = ""
    @State private var editDisplayName = ""
    @State private var editAvatarEmoji = "🚀"
    @State private var showSaveProfileSuccess = false
    
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
                            .foregroundColor(.white)
                        Text("Profilini düzenle, tema seç ve düello yap.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
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
                    .foregroundColor(Theme.accent)
                    .frame(width: 24)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
        }
    }
    
    // MARK: - Section Content: Profile
    
    private var profileSectionContent: some View {
        VStack(spacing: 16) {
            // Profile Card Preview
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Text(editAvatarEmoji)
                        .font(.system(size: 32))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(editDisplayName.isEmpty ? "Profil İsmi" : editDisplayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("@\(editUsername.isEmpty ? "kullanici" : editUsername)")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
            
            // Input Fields
            VStack(alignment: .leading, spacing: 6) {
                Text("Kullanıcı Adı")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.5))
                TextField("kullanici_adi", text: $editUsername)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Görünen İsim")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.5))
                TextField("Ad Soyad", text: $editDisplayName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Profil Emojisi Seç")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.5))
                
                HStack(spacing: 10) {
                    ForEach(["🚀", "🦁", "🦊", "🐼", "🐨", "🐱", "🦉", "🦄"], id: \.self) { emoji in
                        Button(action: {
                            editAvatarEmoji = emoji
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }) {
                            Text(emoji)
                                .font(.title3)
                                .padding(8)
                                .background(Circle().fill(editAvatarEmoji == emoji ? Theme.accent.opacity(0.25) : Color.white.opacity(0.04)))
                                .overlay(
                                    Circle()
                                        .stroke(editAvatarEmoji == emoji ? Theme.accent : Color.clear, lineWidth: 1.5)
                                )
                        }
                    }
                }
            }
            
            // Save Profile Button
            Button(action: {
                Task {
                    try? await socialManager.updateProfile(
                        username: editUsername,
                        displayName: editDisplayName,
                        avatarEmoji: editAvatarEmoji
                    )
                    withAnimation {
                        showSaveProfileSuccess = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showSaveProfileSuccess = false
                    }
                }
            }) {
                HStack {
                    if showSaveProfileSuccess {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Güncellendi!")
                    } else {
                        Text("Profili Güncelle")
                    }
                }
                .font(.subheadline.bold())
                .foregroundColor(.black)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(showSaveProfileSuccess ? Color.green : Theme.accent))
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Log Out Button
            Button(action: {
                Task {
                    await authManager.logout()
                }
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Oturumu Kapat")
                }
                .font(.subheadline.bold())
                .foregroundColor(.red)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.12)))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
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
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
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
                            .foregroundColor(selectedInterval == interval.minutes ? Theme.accent : .white.opacity(0.7))
                        
                        Text(interval.label)
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if selectedInterval == interval.minutes {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.accent)
                                .transition(.scale)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(selectedInterval == interval.minutes ? Color.white.opacity(0.04) : Color.clear)
                }
                
                if interval.minutes != intervals.last?.minutes {
                    Divider()
                        .background(Color.white.opacity(0.1))
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
                .foregroundColor(.black)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(showSaveSuccess ? Color.green : Theme.accent))
                .padding(14)
            }
            .disabled(showSaveSuccess)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
    }
    
    // MARK: - Actions
    
    private func loadInitialSocialData() {
        Task {
            await socialManager.loadProfileAndFriends()
            if let myP = socialManager.myProfile {
                editUsername = myP.username
                editDisplayName = myP.displayName
                editAvatarEmoji = myP.avatarEmoji
            }
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
