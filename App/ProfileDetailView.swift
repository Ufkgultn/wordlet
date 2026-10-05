import SwiftUI

struct ProfileDetailView: View {
    let profile: PublicProfile
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var socialManager = SocialManager.shared
    
    @State private var requestSent = false
    @State private var isSending = false
    
    private var isMe: Bool {
        profile.id == socialManager.myProfile?.id
    }
    
    private var isFriend: Bool {
        socialManager.friends.contains(where: { $0.id == profile.id })
    }
    
    private var winRate: Int {
        guard profile.matchesPlayed > 0 else { return 0 }
        return Int(Double(profile.matchesWon) / Double(profile.matchesPlayed) * 100)
    }
    
    var body: some View {
        ZStack {
            AppBackground()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Close Button
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(12)
                                .background(Circle().fill(Color.white.opacity(0.1)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Avatar & Name
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Theme.accent.opacity(0.3), Theme.accent.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 110, height: 110)
                                .overlay(Circle().stroke(Theme.accent.opacity(0.5), lineWidth: 2))
                            
                            Text(profile.avatarEmoji)
                                .font(.system(size: 52))
                        }
                        
                        VStack(spacing: 6) {
                            Text(profile.displayName)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                            
                            Text("@\(profile.username)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.5))
                            
                            HStack(spacing: 6) {
                                Text("Seviye")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                                Text(profile.currentLevel)
                                    .font(.caption.bold())
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Theme.accent))
                            }
                        }
                    }
                    
                    // Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        statCard(icon: "star.fill", title: "Toplam XP", value: "\(profile.xp)", color: .yellow)
                        statCard(icon: "trophy.fill", title: "Galibiyet", value: "\(profile.matchesWon)", color: .green)
                        statCard(icon: "gamecontroller.fill", title: "Toplam Maç", value: "\(profile.matchesPlayed)", color: .blue)
                        statCard(icon: "chart.line.uptrend.xyaxis", title: "Kazanma %", value: "%\(winRate)", color: .purple)
                    }
                    .padding(.horizontal, 20)
                    
                    // Action Buttons
                    if !isMe {
                        VStack(spacing: 12) {
                            if isFriend {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                    Text("Zaten Arkadaşsınız")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.green.opacity(0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.green.opacity(0.3), lineWidth: 1))
                            } else if requestSent {
                                HStack(spacing: 8) {
                                    Image(systemName: "paperplane.fill")
                                        .foregroundColor(.orange)
                                    Text("İstek Gönderildi!")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.12)))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                            } else {
                                Button(action: {
                                    isSending = true
                                    Task {
                                        try? await socialManager.sendFriendRequest(receiverId: profile.id)
                                        isSending = false
                                        requestSent = true
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        if isSending {
                                            ProgressView().tint(.black)
                                        } else {
                                            Image(systemName: "person.badge.plus")
                                            Text("Arkadaşlık İsteği Gönder")
                                        }
                                    }
                                    .font(.headline.bold())
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Theme.accent)
                                    .cornerRadius(16)
                                }
                                .disabled(isSending)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer(minLength: 40)
                }
            }
        }
    }
    
    private func statCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(color.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
