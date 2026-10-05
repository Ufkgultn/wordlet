import SwiftUI

struct DuelsView: View {
    @StateObject private var socialManager = SocialManager.shared
    @StateObject private var matchManager = MatchManager.shared
    @StateObject private var authManager = AuthManager.shared
    
    // Main Section Selection (0: ⚡️ 1v1 Arenası, 1: 🏆 Puan Durumu, 2: 👥 Arkadaşlar)
    @State private var mainSection = 0
    
    // Leaderboard Filter (0: Arkadaşlarım, 1: Genel Sıralama)
    @State private var leaderboardTab = 0
    
    // Friend Search State
    @State private var searchUsername = ""
    @State private var searchedProfile: PublicProfile? = nil
    @State private var searchError = ""
    @State private var isSearchingUser = false
    
    // Robot Duel State
    @State private var showRobotDuel = false
    @State private var selectedRobotLevel = 1
    @State private var selectedAITargetLevel: CEFRLevel = .a1
    
    private var currentRobotLevelStorage: Int {
        let val = UserDefaults.standard.integer(forKey: "robotDuelLevel_\(selectedAITargetLevel.rawValue)")
        return val == 0 ? 1 : val
    }
    
    // Friend Duel State
    @State private var showFriendDuel = false
    @State private var selectedFriendOpponent: PublicProfile? = nil
    @State private var showFriendDuelActionDialog = false
    
    @State private var showModeRoom = false
    
    private let gameModes = [
        (0, "Eşleştirme Odası", "rectangle.split.2x2.fill", "Kelime ve anlamını hızlıca eşleştir. Klasik mod!", Color.blue),
        (1, "Yazma Yarışı Odası", "keyboard.fill", "Türkçe kelimeyi gör, İngilizcesini hızla yaz.", Color.green),
        (2, "Hızlı Seçim Odası", "timer", "4 şıktan doğru anlamı seç. Yanlışta -2 saniye!", Color.orange),
        (3, "Doğru / Yanlış Odası", "checkmark.circle.fill", "Gösterilen eşleşme doğru mu? Anında karar ver!", Color.purple),
        (4, "Harf Avı Odası", "textformat.abc", "Karışık harfleri sıraya diz, kelimeyi oluştur.", Color.pink)
    ]
    
    @AppStorage("selectedMinigame") private var selectedMinigame: Int = 0
    
    // Login Sheet
    @State private var showLoginSheet = false
    
    // Join Private Room Sheet
    @State private var showJoinRoomSheet = false
    @State private var inputRoomCode = ""
    
    // Matchmaking pulse animation
    @State private var radarPulse = false
    
    // Profile Viewing
    @State private var selectedProfileForViewing: PublicProfile? = nil
    
    var body: some View {
        ZStack {
            AppBackground()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // MARK: - Header Profile Stats Banner
                    profileHeaderBanner
                    
                    // MARK: - Segmented Navigation Bar
                    Picker("Bölüm", selection: $mainSection) {
                        Text("⚡️ 1v1 Arena").tag(0)
                        Text("🏆 Sıralama").tag(1)
                        Text("👥 Arkadaşlar").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    
                    // MARK: - Section Content
                    if mainSection == 0 {
                        arenaSectionContent
                    } else if mainSection == 1 {
                        leaderboardSectionContent
                    } else {
                        friendsSectionContent
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 10)
            }
            .blur(radius: (matchManager.isSearching || showJoinRoomSheet || selectedProfileForViewing != nil) ? 5 : 0)
            
            // Custom Pop-ups
            if matchManager.isSearching {
                matchmakingRadarModal
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(100)
            }
            
            if showJoinRoomSheet {
                joinRoomModal
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(100)
            }
            
            if let profile = selectedProfileForViewing {
                profileModal(profile: profile)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(100)
            }
            
            // In-app Notification
            if socialManager.showInAppNotification {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                        Text(socialManager.inAppNotificationMessage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.orange.opacity(0.9)))
                    .shadow(radius: 10)
                    .padding(.horizontal, 20)
                    .padding(.top, 50)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(200)
            }
        }
        .onAppear {
            Task {
                await socialManager.loadProfileAndFriends()
            }
        }
        // Popups and full screens
        .fullScreenCover(isPresented: $matchManager.showBattleArena) {
            if let opp = matchManager.currentOpponent {
                gameView(opponentName: opp.displayName, opponentProfile: opp, isRobot: false, robotLevel: 1)
            }
        }
        // Friend Duel Sheet
        .fullScreenCover(isPresented: $showFriendDuel) {
            if let friend = selectedFriendOpponent {
                gameView(opponentName: friend.displayName, opponentProfile: friend, isRobot: false, robotLevel: 1)
            }
        }
        // Robot Duel Sheet
        .fullScreenCover(isPresented: $showRobotDuel) {
            gameView(opponentName: "Yapay Zeka Robotu", opponentProfile: nil, isRobot: true, robotLevel: selectedRobotLevel, targetCEFRLevel: selectedAITargetLevel)
        }
        // Mode Room Sheet
        .fullScreenCover(isPresented: $showModeRoom) {
            let mode = gameModes.first(where: { $0.0 == selectedMinigame }) ?? gameModes[0]
            ModeRoomView(
                modeId: mode.0,
                modeTitle: mode.1,
                modeDescription: mode.3,
                modeIcon: mode.2,
                modeColor: mode.4
            )
        }
        // Login Sheet
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
        .confirmationDialog(
            "Arkadaşla Düello",
            isPresented: $showFriendDuelActionDialog,
            presenting: selectedFriendOpponent
        ) { friend in
            Button("⚔️ Canlı Düello Daveti Gönder") {
                Task {
                    await matchManager.sendDirectInvite(to: friend, gameMode: selectedMinigame)
                }
            }
            Button("🤖 Çevrimdışı Oyna") {
                showFriendDuel = true
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { friend in
            Text("\(friend.displayName) kullanıcısına anlık düello daveti gönderebilirsin.")
        }
    }
    
    private func getGameMode(isRobot: Bool) -> Int {
        if !isRobot, let active = matchManager.activeMatch {
            if active.mode.contains("_") {
                return Int(active.mode.split(separator: "_").last ?? "0") ?? 0
            }
        }
        return selectedMinigame
    }
    
    @ViewBuilder
    private func gameView(opponentName: String, opponentProfile: PublicProfile?, isRobot: Bool, robotLevel: Int, targetCEFRLevel: CEFRLevel? = nil) -> some View {
        switch getGameMode(isRobot: isRobot) {
        case 1:
            TypingBattleView(opponentName: opponentName, opponentProfile: opponentProfile, isRobot: isRobot, robotLevel: robotLevel, targetCEFRLevel: targetCEFRLevel)
        case 2:
            SpeedQuizBattleView(opponentName: opponentName, opponentProfile: opponentProfile, isRobot: isRobot, robotLevel: robotLevel, targetCEFRLevel: targetCEFRLevel)
        case 3:
            TrueFalseBattleView(opponentName: opponentName, opponentProfile: opponentProfile, isRobot: isRobot, robotLevel: robotLevel, targetCEFRLevel: targetCEFRLevel)
        case 4:
            JumbleBattleView(opponentName: opponentName, opponentProfile: opponentProfile, isRobot: isRobot, robotLevel: robotLevel, targetCEFRLevel: targetCEFRLevel)
        default:
            WordMatchBattleView(opponentName: opponentName, opponentProfile: opponentProfile, isRobot: isRobot, robotLevel: robotLevel, targetCEFRLevel: targetCEFRLevel)
        }
    }
    
    // MARK: - 1. Profile Header Banner
    
    private var profileHeaderBanner: some View {
        let profile = socialManager.myProfile
        let isAuth = authManager.isAuthenticated
        let isGuest = authManager.isGuest
        
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Avatar with UserAvatarView
                UserAvatarView(emoji: profile?.avatarEmoji ?? "🚀", size: 58)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile?.displayName ?? "Misafir Oyuncu")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(profile?.currentLevel ?? "A1")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                    }
                    
                    Text("@\(profile?.username ?? "kullanici")")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                }
                
                Spacer()
                
                if !isAuth || isGuest {
                    Button(action: {
                        showLoginSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Giriş Yap")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent))
                    }
                }
            }
            
            // Stats Row: Total XP, Matches Won, Win Rate
            HStack(spacing: 12) {
                statPill(title: "Toplam XP", value: "\(profile?.xp ?? 0)", icon: "sparkles", color: .yellow)
                statPill(title: "Galibiyet", value: "\(profile?.matchesWon ?? 0)", icon: "trophy.fill", color: .orange)
                let played = profile?.matchesPlayed ?? 0
                let won = profile?.matchesWon ?? 0
                let winRate = played > 0 ? Int((Double(won) / Double(played)) * 100) : 0
                statPill(title: "Kazanma", value: "%\(winRate)", icon: "chart.line.uptrend.xyaxis", color: Theme.accent)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
    
    private func statPill(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 2. Arena Section Content (Random Match, Friends, AI)
    
    private var incomingInvitesBanner: some View {
        VStack(spacing: 12) {
            ForEach(socialManager.incomingMatchInvites) { invite in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text(invite.player1Avatar)
                            .font(.title2)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(invite.player1Name) Seni Davet Ediyor!")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        Text("Mod: \(invite.mode.replacingOccurrences(of: "friend_", with: "Mod "))")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Button(action: {
                            Task {
                                await matchManager.declineDirectInvite(matchId: invite.id)
                                socialManager.incomingMatchInvites.removeAll(where: { $0.id == invite.id })
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.red.opacity(0.8)))
                        }
                        
                        Button(action: {
                            Task {
                                await matchManager.acceptDirectInvite(match: invite)
                                socialManager.incomingMatchInvites.removeAll(where: { $0.id == invite.id })
                            }
                        }) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.green.opacity(0.8)))
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.accent.opacity(0.4))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.accent.opacity(0.6), lineWidth: 1.5))
                )
                .shadow(color: Theme.accent.opacity(0.3), radius: 10)
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var arenaSectionContent: some View {
        VStack(spacing: 20) {
            
            if !socialManager.incomingMatchInvites.isEmpty {
                incomingInvitesBanner
                    .padding(.top, 10)
            }
            
            // Minigame Rooms - Vertical Large Buttons
            VStack(alignment: .leading, spacing: 14) {
                Text("🎮 OYUN ODALARI")
                    .font(.caption.bold())
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 20)
                
                VStack(spacing: 12) {
                    ForEach(gameModes, id: \.0) { mode in
                        Button(action: {
                            selectedMinigame = mode.0
                            showModeRoom = true
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(mode.4.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                    Image(systemName: mode.2)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(mode.4)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.1)
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)
                                    Text(mode.3)
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Spacer(minLength: 0)
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(mode.4.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.top, socialManager.incomingMatchInvites.isEmpty ? 10 : 0)
            
            // AI Robot Arena Grid
            aiRobotArenaSection
        }
    }
    

    
    private var aiRobotArenaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("🤖 YAPAY ZEKA ARENASI")
                    .font(.caption.bold())
                    .foregroundColor(Theme.accent)
                Spacer()
                Text("Seviye \(currentRobotLevelStorage)/30")
                    .font(.caption.bold())
                    .foregroundColor(.orange)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CEFRLevel.allCases, id: \.self) { level in
                        Button(action: {
                            selectedAITargetLevel = level
                        }) {
                            Text(level.rawValue)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(selectedAITargetLevel == level ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(selectedAITargetLevel == level ? Theme.accent : Color.white.opacity(0.1)))
                        }
                    }
                }
            }
            
            Text("Robotları yenerek seviyeleri aç. Seviye yükseldikçe robot hızlanır ve kelime sayısı artar!")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
                ForEach(1...30, id: \.self) { levelNum in
                    let isUnlocked = levelNum <= currentRobotLevelStorage
                    let isCurrent = levelNum == currentRobotLevelStorage
                    
                    Button(action: {
                        guard isUnlocked else { return }
                        selectedRobotLevel = levelNum
                        showRobotDuel = true
                    }) {
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(isUnlocked ? (isCurrent ? Color.orange.opacity(0.25) : Color.white.opacity(0.08)) : Color.white.opacity(0.02))
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
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.04)))
        .padding(.horizontal, 20)
    }
    
    // MARK: - 3. Leaderboard Section (Puan Durumu / Sıralama)
    
    private var leaderboardSectionContent: some View {
        let list = leaderboardTab == 0 ? socialManager.friendsLeaderboard : socialManager.globalLeaderboard
        
        return VStack(spacing: 20) {
            // Filter Picker (Arkadaşlarım vs Genel)
            Picker("Sıralama Türü", selection: $leaderboardTab) {
                Text("👥 Arkadaşlarım").tag(0)
                Text("🌍 Genel Sıralama").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            
            // Top 3 Podium
            if list.count >= 3 {
                leaderboardPodium(top3: Array(list.prefix(3)))
            }
            
            // Ranked Table
            VStack(spacing: 8) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, player in
                    leaderboardRow(rank: index + 1, player: player)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func leaderboardPodium(top3: [PublicProfile]) -> some View {
        HStack(alignment: .bottom, spacing: 14) {
            // 2nd Place (Silver)
            if top3.count > 1 {
                podiumItem(player: top3[1], rank: 2, medal: "🥈", color: Color(white: 0.75), height: 110)
            }
            
            // 1st Place (Gold)
            if top3.count > 0 {
                podiumItem(player: top3[0], rank: 1, medal: "🥇", color: Color.yellow, height: 140)
            }
            
            // 3rd Place (Bronze)
            if top3.count > 2 {
                podiumItem(player: top3[2], rank: 3, medal: "🥉", color: Color(red: 0.80, green: 0.50, blue: 0.30), height: 90)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
    
    private func podiumItem(player: PublicProfile, rank: Int, medal: String, color: Color, height: CGFloat) -> some View {
        let isMe = player.id == socialManager.myProfile?.id
        
        return Button(action: {
            selectedProfileForViewing = player
        }) {
            VStack(spacing: 8) {
                // Crown / Medal Icon
                Text(medal)
                    .font(.system(size: 24))
            
            // Avatar with glowing ring
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: rank == 1 ? 62 : 52, height: rank == 1 ? 62 : 52)
                    .overlay(Circle().stroke(color, lineWidth: 2))
                
                Text(player.avatarEmoji)
                    .font(.system(size: rank == 1 ? 30 : 24))
            }
            
            Text(player.displayName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isMe ? Theme.accent : .white)
                .lineLimit(1)
            
            Text("\(player.xp) XP")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            
            // Podium base bar
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.35), color.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: height)
                .overlay(
                    Text("\(rank)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(color.opacity(0.6))
                        .padding(.top, 10),
                    alignment: .top
                )
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
    
    private func leaderboardRow(rank: Int, player: PublicProfile) -> some View {
        let isMe = player.id == socialManager.myProfile?.id
        let isFriend = socialManager.friends.contains(where: { $0.id == player.id })
        
        return HStack(spacing: 12) {
            Button(action: {
                selectedProfileForViewing = player
            }) {
                HStack(spacing: 12) {
                    // Rank Number
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(rank <= 3 ? .yellow : .white.opacity(0.4))
                        .frame(width: 24, alignment: .leading)
                    
                    // Avatar
                    ZStack {
                        Circle()
                            .fill(isMe ? Theme.accent.opacity(0.2) : Color.white.opacity(0.06))
                            .frame(width: 40, height: 40)
                        Text(player.avatarEmoji)
                            .font(.title3)
                    }
                    
                    // Name & Level
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(player.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isMe ? Theme.accent : .white)
                                .lineLimit(1)
                            
                            if isMe {
                                Text("(Sen)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        
                        Text("@\(player.username) • \(player.currentLevel)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.45))
                    }
                    
                    Spacer(minLength: 4)
                }
            }
            .buttonStyle(.plain)
            
            // Stats & Add Friend Action
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(player.xp) XP")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(player.matchesWon) Win")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }
                
                if !isMe && !isFriend {
                    if socialManager.sentRequestReceiverIds.contains(player.id) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.orange))
                    } else {
                        Button(action: {
                            sendRequest(to: player.id)
                        }) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Theme.accent.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isMe ? Theme.accent.opacity(0.12) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isMe ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
    }
    
    // MARK: - 4. Friends & Requests Section
    
    private var friendsSectionContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Add Friend Search Box
            VStack(alignment: .leading, spacing: 10) {
                Text("YENİ ARKADAŞ EKLE")
                    .font(.caption.bold())
                    .foregroundColor(Theme.accent)
                
                HStack(spacing: 10) {
                    TextField("Kullanıcı adı yazın (örn: selin_g)...", text: $searchUsername)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                        .foregroundColor(.white)
                        .autocapitalization(.none)
                    
                    Button(action: searchUser) {
                        if isSearchingUser {
                            ProgressView()
                                .tint(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                        } else {
                            Text("Ara")
                                .font(.subheadline.bold())
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
                        }
                    }
                }
                
                if !searchError.isEmpty {
                    Text(searchError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if let found = searchedProfile {
                    HStack(spacing: 12) {
                        Text(found.avatarEmoji)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(found.displayName)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            Text("@\(found.username) • \(found.xp) XP")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        if socialManager.sentRequestReceiverIds.contains(found.id) {
                            Text("İstek Gönderildi")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.orange))
                        } else {
                            Button(action: {
                                sendRequest(to: found.id)
                            }) {
                                Text("İstek Gönder")
                                    .font(.caption.bold())
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Theme.accent))
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.04)))
            .padding(.horizontal, 20)
            
            // Incoming Requests
            if !socialManager.pendingRequests.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GELEN İSTEKLER")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    
                    ForEach(socialManager.pendingRequests) { req in
                        HStack(spacing: 12) {
                            Text(req.avatarEmoji)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(req.senderName)
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                Text("@\(req.senderUsername)")
                                    .font(.caption2)
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
                                    .font(.title2)
                            }
                            
                            Button(action: {
                                Task {
                                    await socialManager.rejectFriendRequest(requestId: req.id)
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                    }
                }
                .padding(.horizontal, 20)
            }
            
            // Friends List
            VStack(alignment: .leading, spacing: 10) {
                Text("ARKADAŞLARIM (\(socialManager.friends.count))")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.5))
                
                if socialManager.friends.isEmpty {
                    Text("Henüz listenizde arkadaşınız yok. Yukarıdaki arama kutusundan arkadaşlarınızı davet edebilirsiniz.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.vertical, 10)
                } else {
                    ForEach(socialManager.friends) { friend in
                        HStack(spacing: 12) {
                            Text(friend.avatarEmoji)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("@\(friend.username) • Seviye: \(friend.currentLevel) • \(friend.xp) XP")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                selectedFriendOpponent = friend
                                showFriendDuelActionDialog = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                    Text("Düello")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Color.orange))
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Matchmaking Radar Modal
    
    private var matchmakingRadarModal: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Animated Radar Wave
                ZStack {
                    Circle()
                        .stroke(Theme.accent.opacity(0.2), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(radarPulse ? 1.3 : 0.8)
                        .opacity(radarPulse ? 0 : 0.8)
                    
                    Circle()
                        .stroke(Theme.accent.opacity(0.35), lineWidth: 2)
                        .frame(width: 100, height: 100)
                        .scaleEffect(radarPulse ? 1.2 : 0.9)
                    
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.accent)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        radarPulse = true
                    }
                }
                .padding(.top, 10)
                
                VStack(spacing: 12) {
                    Text(matchManager.roomCode != nil ? "Özel Lobi Bekleniyor" : "1v1 Düello Aranıyor")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    
                    if let code = matchManager.roomCode {
                        VStack(spacing: 6) {
                            Text("ODA KODU")
                                .font(.caption2.bold())
                                .foregroundColor(Theme.accent)
                            
                            Text(code)
                                .font(.system(size: 38, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.4), lineWidth: 1.5))
                            
                            Text("Arkadaşının bu kodu girmesini bekle...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                    }
                    
                    Text(matchManager.searchStatus)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                    
                    if let err = matchManager.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Button(action: {
                    matchManager.cancelSearch()
                }) {
                    Text("İptal Et")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.1)))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Theme.background)
                    .shadow(color: Theme.accent.opacity(0.2), radius: 25)
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
            .padding(.horizontal, 30)
        }
    }
    
    // MARK: - Join Room Modal
    
    private var joinRoomModal: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { showJoinRoomSheet = false }
            
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Özel Odaya Katıl")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Text("Arkadaşının paylaştığı kodu gir.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 10)
                
                TextField("Örn: 4821", text: $inputRoomCode)
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                    .foregroundColor(Theme.accent)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 20)
                
                if let err = matchManager.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await matchManager.joinPrivateRoom(code: inputRoomCode)
                            if matchManager.showBattleArena {
                                showJoinRoomSheet = false
                                inputRoomCode = ""
                            }
                        }
                    }) {
                        Text("Odaya Bağlan")
                            .font(.headline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .cornerRadius(14)
                    }
                    .disabled(inputRoomCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    Button(action: {
                        showJoinRoomSheet = false
                    }) {
                        Text("Vazgeç")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Theme.background)
                    .shadow(color: Theme.accent.opacity(0.2), radius: 25)
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
            .padding(.horizontal, 30)
        }
    }
    
    // MARK: - Profile Modal
    
    private func profileModal(profile: PublicProfile) -> some View {
        let isFriend = socialManager.friends.contains(where: { $0.id == profile.id })
        let isMe = profile.id == socialManager.myProfile?.id
        
        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { selectedProfileForViewing = nil }
            
            VStack(spacing: 24) {
                // Header
                ZStack(alignment: .topTrailing) {
                    Button(action: { selectedProfileForViewing = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.top, -10)
                    .padding(.trailing, -10)
                    
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Theme.accent.opacity(0.2))
                                .frame(width: 80, height: 80)
                                .overlay(Circle().stroke(Theme.accent, lineWidth: 2))
                            Text(profile.avatarEmoji)
                                .font(.system(size: 40))
                        }
                        
                        VStack(spacing: 4) {
                            Text(profile.displayName)
                                .font(.title3.bold())
                                .foregroundColor(.white)
                            Text("@\(profile.username)")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Stats Grid
                HStack(spacing: 16) {
                    statPill(title: "XP", value: "\(profile.xp)", icon: "star.fill", color: .yellow)
                    statPill(title: "Seviye", value: "\(profile.currentLevel)", icon: "rosette", color: .orange)
                }
                
                HStack(spacing: 16) {
                    statPill(title: "Oynanan", value: "\(profile.matchesPlayed)", icon: "gamecontroller.fill", color: .blue)
                    statPill(title: "Kazanılan", value: "\(profile.matchesWon)", icon: "trophy.fill", color: .green)
                }
                
                // Add Friend Action
                if !isMe {
                    if isFriend {
                        Text("Sizinle arkadaş")
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.top, 10)
                    } else if socialManager.sentRequestReceiverIds.contains(profile.id) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                            Text("İstek Gönderildi")
                        }
                        .font(.headline.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange)
                        .cornerRadius(14)
                        .padding(.top, 10)
                    } else {
                        Button(action: {
                            sendRequest(to: profile.id)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                Text("Arkadaş Ekle")
                            }
                            .font(.headline.bold())
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .cornerRadius(14)
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 30)
                    .fill(Theme.background)
                    .shadow(color: Theme.accent.opacity(0.2), radius: 25)
                    .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
            .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Actions
    
    private func searchUser() {
        guard !searchUsername.isEmpty else { return }
        isSearchingUser = true
        searchError = ""
        searchedProfile = nil
        
        Task {
            if let match = await socialManager.searchUserByUsername(username: searchUsername) {
                searchedProfile = match
            } else {
                searchError = "Kullanıcı bulunamadı. Kullanıcı adını kontrol edin."
            }
            isSearchingUser = false
        }
    }
    
    private func sendRequest(to id: String) {
        Task {
            try? await socialManager.sendFriendRequest(receiverId: id)
            withAnimation {
                searchedProfile = nil
                searchUsername = ""
            }
        }
    }
}
import SwiftUI

struct ModeRoomView: View {
    let modeId: Int
    let modeTitle: String
    let modeDescription: String
    let modeIcon: String
    let modeColor: Color
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject var matchManager = MatchManager.shared
    @ObservedObject var socialManager = SocialManager.shared
    
    @State private var showInvitingRadar = false
    @State private var invitedFriendName = ""
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    Spacer()
                    Text(modeTitle)
                        .font(.title3.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Hero Icon
                        ZStack {
                            Circle()
                                .fill(modeColor.opacity(0.15))
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: modeIcon)
                                .font(.system(size: 50))
                                .foregroundColor(modeColor)
                        }
                        .padding(.top, 20)
                        
                        Text(modeDescription)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        
                        // Random Match Button
                        Button(action: {
                            Task {
                                await matchManager.startRandomMatchmaking(gameMode: modeId)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .font(.headline)
                                Text("Rastgele Eşleşme Bul")
                                    .font(.headline.bold())
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [modeColor, modeColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: modeColor.opacity(0.4), radius: 10, x: 0, y: 4)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        
                        // Invite Friends Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Arkadaşlarını Davet Et")
                                .font(.headline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                            
                            if socialManager.friends.isEmpty {
                                Text("Henüz arkadaş eklemedin.")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(socialManager.friends) { friend in
                                        HStack(spacing: 12) {
                                            ZStack {
                                                Circle()
                                                    .fill(Color.white.opacity(0.08))
                                                    .frame(width: 44, height: 44)
                                                Text(friend.avatarEmoji)
                                                    .font(.title3)
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(friend.displayName)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(.white)
                                                Text("\(friend.xp) XP")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(modeColor)
                                            }
                                            
                                            Spacer()
                                            
                                            Button(action: {
                                                invitedFriendName = friend.displayName
                                                withAnimation { showInvitingRadar = true }
                                                Task {
                                                    await matchManager.sendDirectInvite(to: friend, gameMode: modeId)
                                                }
                                            }) {
                                                Text("Davet Et")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 8)
                                                    .background(Capsule().fill(modeColor))
                                            }
                                        }
                                        .padding(12)
                                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                        .padding(.top, 10)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            
            // Inviting Radar Overlay
            if showInvitingRadar || matchManager.isSearching {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    
                    VStack(spacing: 24) {
                        ZStack {
                            Circle().stroke(modeColor.opacity(0.3), lineWidth: 2).frame(width: 140, height: 140)
                            Circle().fill(modeColor.opacity(0.2)).frame(width: 80, height: 80)
                            Image(systemName: "paperplane.fill").font(.system(size: 32)).foregroundColor(modeColor)
                        }
                        
                        Text(matchManager.searchStatus.isEmpty ? "\(invitedFriendName) bekleniyor..." : matchManager.searchStatus)
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        Button("İptal Et") {
                            withAnimation { showInvitingRadar = false }
                            matchManager.cancelSearch()
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                        .padding(.top, 20)
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onChange(of: matchManager.showBattleArena) { show in
            if show {
                dismiss()
            }
        }
    }
}
