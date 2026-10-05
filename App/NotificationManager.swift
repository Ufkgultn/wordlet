import SwiftUI
import UserNotifications

@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var hasPermission = false
    @Published var showInAppBanner = false
    @Published var bannerTitle = ""
    @Published var bannerMessage = ""
    @Published var bannerEmoji = "🔔"
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Request Permission
    
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            self.hasPermission = granted
        } catch {
            print("Notification permission error: \(error)")
        }
    }
    
    func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.hasPermission = settings.authorizationStatus == .authorized
    }
    
    // MARK: - Send Local Notification
    
    func sendLocalNotification(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification send error: \(error)")
            }
        }
    }
    
    // MARK: - In-App Banner
    
    func showBanner(title: String, message: String, emoji: String = "🔔") {
        bannerTitle = title
        bannerMessage = message
        bannerEmoji = emoji
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showInAppBanner = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeOut(duration: 0.3)) {
                self.showInAppBanner = false
            }
        }
    }
    
    // MARK: - Foreground Notification Handling
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - In-App Banner View

struct InAppNotificationBanner: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    
    var body: some View {
        if notificationManager.showInAppBanner {
            VStack {
                HStack(spacing: 12) {
                    Text(notificationManager.bannerEmoji)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(notificationManager.bannerTitle)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text(notificationManager.bannerMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            notificationManager.showInAppBanner = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.6))
                            .padding(6)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(999)
        }
    }
}
