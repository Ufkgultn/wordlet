import SwiftUI
import WidgetKit

struct SettingsView: View {
    @State private var selectedInterval: Int = AppSettingsManager.shared.settings.widgetUpdateIntervalMinutes
    @State private var showSaveSuccess = false
    
    let intervals = [
        (label: "5 Dakika", minutes: 5, icon: "timer"),
        (label: "30 Dakika", minutes: 30, icon: "timer"),
        (label: "1 Saat", minutes: 60, icon: "clock"),
        (label: "3 Saat", minutes: 180, icon: "clock.fill"),
        (label: "5 Saat", minutes: 300, icon: "hourglass")
    ]
    
    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    // Başlık
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ayarlar")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Widget deneyimini kişiselleştir.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Yenilenme Sıklığı Bölümü
                    VStack(alignment: .leading, spacing: 16) {
                        Text("WIDGET YENİLENME SIKLIĞI")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 24)
                        
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
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 20)
                                    .background(selectedInterval == interval.minutes ? Color.white.opacity(0.05) : Color.clear)
                                }
                                
                                if interval.minutes != intervals.last?.minutes {
                                    Divider()
                                        .background(Color.white.opacity(0.1))
                                        .padding(.leading, 60)
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                        .padding(.horizontal, 20)
                        
                        Text("Seçilen süre sonunda widget otomatik olarak bir sonraki kelimeye geçecektir.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                            .padding(.horizontal, 24)
                    }

                    // Kaydet Butonu
                    Button(action: {
                        saveSettings()
                    }) {
                        HStack {
                            Spacer()
                            if showSaveSuccess {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Kaydedildi!")
                                    .font(.headline.bold())
                            } else {
                                Text("Ayarları Kaydet")
                                    .font(.headline.bold())
                            }
                            Spacer()
                        }
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(showSaveSuccess ? Color.green : Theme.accent)
                                .shadow(color: (showSaveSuccess ? Color.green : Theme.accent).opacity(0.3), radius: 10, x: 0, y: 5)
                        )
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)
                    .disabled(showSaveSuccess)

                    Spacer(minLength: 40)
                }
            }
        }
    }
    
    private func saveSettings() {
        var settings = AppSettingsManager.shared.settings
        settings.widgetUpdateIntervalMinutes = selectedInterval
        AppSettingsManager.shared.settings = settings
        
        // Haptic feedback
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        
        // Başarı mesajı göster
        withAnimation(.spring()) {
            showSaveSuccess = true
        }
        
        // Mesajı 2 saniye sonra gizle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring()) {
                showSaveSuccess = false
            }
        }
        
        // Widget'ı hemen güncellemeye zorla
        WidgetCenter.shared.reloadAllTimelines()
    }
}
