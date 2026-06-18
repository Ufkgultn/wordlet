import SwiftUI

struct DuelsView: View {
    @StateObject private var socialManager = SocialManager.shared
    
    // Social Tab State (0 = Arkadaşlarım & İstekler, 1 = Arkadaş Ekle)
    @State private var socialTab = 0
    @State private var searchUsername = ""
    @State private var searchedProfile: PublicProfile? = nil
    @State private var searchError = ""
    @State private var isSearching = false
    @State private var showRequestSentSuccess = false
    
    // Robot Duel State
    @AppStorage("robotDuelLevel") private var robotDuelLevelStorage: Int = 1
    @State private var showRobotDuel = false
    @State private var selectedRobotLevel = 1
    
    // Friend Duel State
    @State private var showFriendDuel = false
    @State private var selectedFriendOpponent: PublicProfile? = nil
    
    var body: some View {
        ZStack {
            AppBackground()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Title Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kelime Düelloları")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Yapay zeka robotlarına meydan oku veya arkadaşlarınla hız yarışı yap!")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // PART 1: Robot Duels Grid
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("🤖 YAPAY ZEKA ROBOT DÜELLOSU")
                                .font(.caption.bold())
                                .foregroundColor(Theme.accent)
                            Spacer()
                            Text("Seviye \(robotDuelLevelStorage)/30")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                        
                        Text("Her seviye robotu yenerek bir sonrakini aç. Seviye yükseldikçe kelime sayısı artar ve robot hızlanır!")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.bottom, 6)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 14) {
                            ForEach(1...30, id: \.self) { levelNum in
                                let isUnlocked = levelNum <= robotDuelLevelStorage
                                let isCurrent = levelNum == robotDuelLevelStorage
                                
                                Button(action: {
                                    guard isUnlocked else { return }
                                    selectedRobotLevel = levelNum
                                    showRobotDuel = true
                                }) {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle()
                                                .fill(isUnlocked ? (isCurrent ? Color.orange.opacity(0.2) : Color.white.opacity(0.08)) : Color.white.opacity(0.03))
                                                .frame(width: 48, height: 48)
                                                .overlay(
                                                    Circle()
                                                        .stroke(isCurrent ? Color.orange : (isUnlocked ? Color.white.opacity(0.18) : Color.clear), lineWidth: 1.5)
                                                )
                                            
                                            if isUnlocked {
                                                Text("\(levelNum)")
                                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                                    .foregroundColor(.white)
                                            } else {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 13))
                                                    .foregroundColor(.white.opacity(0.25))
                                            }
                                        }
                                        
                                        Text("Seviye \(levelNum)")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundColor(isUnlocked ? .white.opacity(0.6) : .white.opacity(0.25))
                                    }
                                }
                                .disabled(!isUnlocked)
                            }
                        }
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.04)))
                    .padding(.horizontal, 20)
                    
                    // PART 2: Real Friends Multiplayer
                    VStack(alignment: .leading, spacing: 16) {
                        Text("👥 GERÇEK OYUNCULAR & SOSYAL")
                            .font(.caption.bold())
                            .foregroundColor(Theme.accent)
                        
                        Picker("Sosyal Sekme", selection: $socialTab) {
                            Text("Arkadaşlarım").tag(0)
                            Text("Arkadaş Ekle").tag(1)
                        }
                        .pickerStyle(.segmented)
                        
                        if socialTab == 0 {
                            // Friends & Requests
                            VStack(alignment: .leading, spacing: 12) {
                                // Incoming Requests
                                if !socialManager.pendingRequests.isEmpty {
                                    Text("GELEN İSTEKLER")
                                        .font(.caption2.bold())
                                        .foregroundColor(.orange)
                                    
                                    ForEach(socialManager.pendingRequests) { req in
                                        HStack {
                                            Text(req.avatarEmoji)
                                                .font(.title3)
                                            VStack(alignment: .leading) {
                                                Text(req.senderName)
                                                    .font(.caption.bold())
                                                    .foregroundColor(.white)
                                                Text("@\(req.senderUsername)")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.white.opacity(0.6))
                                            }
                                            Spacer()
                                            
                                            Button(action: {
                                                Task {
                                                    await socialManager.acceptFriendRequest(requestId: req.id)
                                                }
                                            }) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.title3)
                                            }
                                            
                                            Button(action: {
                                                Task {
                                                    await socialManager.rejectFriendRequest(requestId: req.id)
                                                }
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .font(.title3)
                                            }
                                        }
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                                    }
                                }
                                
                                Text("ARKADAŞ LİSTEM")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(.top, 4)
                                
                                if socialManager.friends.isEmpty {
                                    Text("Henüz arkadaş eklenmedi.")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.45))
                                        .padding(.vertical, 12)
                                } else {
                                    ForEach(socialManager.friends) { friend in
                                        HStack {
                                            Text(friend.avatarEmoji)
                                                .font(.title2)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(friend.displayName)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.white)
                                                Text("@\(friend.username) • Seviye: \(friend.currentLevel)")
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                selectedFriendOpponent = friend
                                                showFriendDuel = true
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "bolt.fill")
                                                    Text("Düello")
                                                }
                                                .font(.caption.bold())
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(Capsule().fill(Color.orange))
                                            }
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                                    }
                                }
                            }
                        } else {
                            // Add Friends Search
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    TextField("Kullanıcı adını yazın...", text: $searchUsername)
                                        .textFieldStyle(.plain)
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                                        .foregroundColor(.white)
                                        .autocapitalization(.none)
                                    
                                    Button(action: {
                                        searchUser()
                                    }) {
                                        if isSearching {
                                            ProgressView()
                                        } else {
                                            Text("Ara")
                                                .font(.caption.bold())
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 12)
                                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))
                                        }
                                    }
                                }
                                
                                if !searchError.isEmpty {
                                    Text(searchError)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                
                                if let found = searchedProfile {
                                    HStack {
                                        Text(found.avatarEmoji)
                                            .font(.title)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(found.displayName)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                            Text("@\(found.username)")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                        Spacer()
                                        
                                        Button(action: {
                                            sendRequest(to: found.id)
                                        }) {
                                            Text("Ekle")
                                                .font(.caption.bold())
                                                .foregroundColor(.black)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(Capsule().fill(Theme.accent))
                                        }
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                                }
                                
                                if showRequestSentSuccess {
                                    Text("Arkadaşlık isteği gönderildi! 🚀")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    .padding(20)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.04)))
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .onAppear {
            Task {
                await socialManager.loadProfileAndFriends()
            }
        }
        .sheet(isPresented: $showRobotDuel) {
            WordMatchBattleView(opponentName: "Yapay Zeka", isRobot: true, robotLevel: selectedRobotLevel)
        }
        .sheet(isPresented: $showFriendDuel) {
            if let friend = selectedFriendOpponent {
                WordMatchBattleView(opponentName: friend.displayName, isRobot: false)
            }
        }
    }
    
    private func searchUser() {
        guard !searchUsername.isEmpty else { return }
        isSearching = true
        searchError = ""
        searchedProfile = nil
        
        Task {
            if let match = await socialManager.searchUserByUsername(username: searchUsername) {
                searchedProfile = match
            } else {
                searchError = "Kullanıcı bulunamadı."
            }
            isSearching = false
        }
    }
    
    private func sendRequest(to id: String) {
        Task {
            try? await socialManager.sendFriendRequest(receiverId: id)
            withAnimation {
                showRequestSentSuccess = true
                searchedProfile = nil
                searchUsername = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showRequestSentSuccess = false
            }
        }
    }
}
