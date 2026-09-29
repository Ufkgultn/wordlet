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
    @State private var showRequestSentSuccess = false
    
    // Robot Duel State
    @AppStorage("robotDuelLevel") private var robotDuelLevelStorage: Int = 1
    @State private var showRobotDuel = false
    @State private var selectedRobotLevel = 1
    
    // Friend Duel State
    @State private var showFriendDuel = false
    @State private var selectedFriendOpponent: PublicProfile? = nil
    @State private var showFriendDuelActionDialog = false
    
    // Login Sheet
    @State private var showLoginSheet = false
    
    // Join Private Room Sheet
    @State private var showJoinRoomSheet = false
    @State private var inputRoomCode = ""
    
    // Matchmaking pulse animation
    @State private var radarPulse = false
    
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
        }
        .onAppear {
            Task {
                await socialManager.loadProfileAndFriends()
                await socialManager.fetchLeaderboards()
            }
        }
        // Matchmaking Radar Sheet
        .sheet(isPresented: $matchManager.isSearching) {
            matchmakingRadarModal
                .presentationDetents([.fraction(0.55)])
                .presentationDragIndicator(.visible)
        }
        // Battle Arena Sheet (Random / Online match)
        .sheet(isPresented: $matchManager.showBattleArena) {
            if let opp = matchManager.currentOpponent {
                WordMatchBattleView(opponentName: opp.displayName, opponentProfile: opp, isRobot: false)
            }
        }
        // Friend Duel Sheet
        .sheet(isPresented: $showFriendDuel) {
            if let friend = selectedFriendOpponent {
                WordMatchBattleView(opponentName: friend.displayName, opponentProfile: friend, isRobot: false)
            }
        }
        // Robot Duel Sheet
        .sheet(isPresented: $showRobotDuel) {
            WordMatchBattleView(opponentName: "Yapay Zeka Robotu", isRobot: true, robotLevel: selectedRobotLevel)
        }
        // Login Sheet
        .sheet(isPresented: $showLoginSheet) {
            LoginView()
        }
        // Join Room Sheet
        .sheet(isPresented: $showJoinRoomSheet) {
            joinRoomModal
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Arkadaşla Düello",
            isPresented: $showFriendDuelActionDialog,
            presenting: selectedFriendOpponent
        ) { friend in
            Button("⚡️ Canlı Özel Oda Kur") {
                Task {
                    await matchManager.createPrivateRoom()
                }
            }
            Button("🎯 Hızlı Alıştırma Düellosu") {
                showFriendDuel = true
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { friend in
            Text("\(friend.displayName) ile canlı oda kurup oda kodunu paylaşabilir veya hemen alıştırma maçı yapabilirsin.")
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
    
    private var arenaSectionContent: some View {
        VStack(spacing: 20) {
            // HERO: Random 1v1 Matchmaking Card
            randomMatchHeroCard
            
            // Friends Quick Challenge Bar
            friendsQuickChallengeSection
            
            // AI Robot Arena Grid
            aiRobotArenaSection
        }
    }
    
    private var randomMatchHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("⚡️ RASTGELE 1V1 MAÇ")
                            .font(.caption.bold())
                            .foregroundColor(Theme.accent)
                        
                        Text("CANLI")
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                    
                    Text("Gerçek Bir Rakiple Yarış!")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 52, height: 52)
                    
                    Image(systemName: "bolt.shield.fill")
                        .font(.title2)
                        .foregroundColor(Theme.accent)
                }
            }
            
            Text("Aynı seviyedeki diğer kullanıcılarla hızlı kelime eşleştirme yarışı yap. Hızlı ol, maçı kazan ve +50 XP topla!")
                .font(.caption)
                .foregroundColor(.white.opacity(0.65))
                .lineSpacing(2)
            
            VStack(spacing: 10) {
                Button(action: {
                    Task {
                        await matchManager.startRandomMatchmaking()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.headline)
                        Text("Rastgele Canlı Maç Bul")
                            .font(.headline.bold())
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Theme.accent, Color(red: 0.35, green: 0.85, blue: 0.70)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 10, x: 0, y: 4)
                }
                
                HStack(spacing: 10) {
                    Button(action: {
                        Task {
                            await matchManager.createPrivateRoom()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Özel Oda Kur")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    }
                    
                    Button(action: {
                        showJoinRoomSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "number.square.fill")
                            Text("Koda Katıl")
                        }
                        .font(.caption.bold())
                        .foregroundColor(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.12)))
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Theme.accent.opacity(0.35), lineWidth: 1.2)
                )
        )
        .padding(.horizontal, 20)
    }
    
    private var friendsQuickChallengeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("👥 ARKADAŞLA DÜELLO")
                    .font(.caption.bold())
                    .foregroundColor(Theme.accent)
                Spacer()
                if !socialManager.friends.isEmpty {
                    Text("\(socialManager.friends.count) Arkadaş")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 20)
            
            if socialManager.friends.isEmpty {
                HStack {
                    Text("Henüz arkadaş eklemedin. 'Arkadaşlar' sekmesinden ekle!")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
                .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(socialManager.friends) { friend in
                            Button(action: {
                                selectedFriendOpponent = friend
                                showFriendDuelActionDialog = true
                            }) {
                                VStack(spacing: 8) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.white.opacity(0.08))
                                            .frame(width: 52, height: 52)
                                        Text(friend.avatarEmoji)
                                            .font(.title2)
                                    }
                                    
                                    VStack(spacing: 2) {
                                        Text(friend.displayName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text("\(friend.xp) XP")
                                            .font(.system(size: 10))
                                            .foregroundColor(Theme.accent)
                                    }
                                    
                                    Text("Düello ⚔️")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(Color.orange))
                                }
                                .padding(12)
                                .frame(width: 110)
                                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
    
    private var aiRobotArenaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("🤖 YAPAY ZEKA ARENASI")
                    .font(.caption.bold())
                    .foregroundColor(Theme.accent)
                Spacer()
                Text("Seviye \(robotDuelLevelStorage)/30")
                    .font(.caption.bold())
                    .foregroundColor(.orange)
            }
            
            Text("Robotları yenerek seviyeleri aç. Seviye yükseldikçe robot hızlanır ve kelime sayısı artar!")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.55))
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
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
        
        return VStack(spacing: 8) {
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
        .frame(maxWidth: .infinity)
    }
    
    private func leaderboardRow(rank: Int, player: PublicProfile) -> some View {
        let isMe = player.id == socialManager.myProfile?.id
        
        return HStack(spacing: 12) {
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
            
            Spacer()
            
            // Stats (XP & Duels Won)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.xp) XP")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("\(player.matchesWon) Galibiyet")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
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
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                }
                
                if showRequestSentSuccess {
                    Text("Arkadaşlık isteği iletildi! 🚀")
                        .font(.caption)
                        .foregroundColor(.green)
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
            Theme.background.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)
                
                Spacer()
                
                // Animated Radar Wave
                ZStack {
                    Circle()
                        .stroke(Theme.accent.opacity(0.2), lineWidth: 2)
                        .frame(width: 180, height: 180)
                        .scaleEffect(radarPulse ? 1.3 : 0.8)
                        .opacity(radarPulse ? 0 : 0.8)
                    
                    Circle()
                        .stroke(Theme.accent.opacity(0.35), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(radarPulse ? 1.2 : 0.9)
                    
                    Circle()
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Theme.accent)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        radarPulse = true
                    }
                }
                
                VStack(spacing: 10) {
                    Text(matchManager.roomCode != nil ? "Özel Lobi Bekleniyor" : "1v1 Düello Aranıyor")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    if let code = matchManager.roomCode {
                        VStack(spacing: 4) {
                            Text("ODA KODU")
                                .font(.caption.bold())
                                .foregroundColor(Theme.accent)
                            
                            Text(code)
                                .font(.system(size: 42, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.4), lineWidth: 1.5))
                            
                            Text("Arkadaşının bu kodu girmesini bekle...")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 6)
                    }
                    
                    Text(matchManager.searchStatus)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    if let err = matchManager.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    matchManager.cancelSearch()
                }) {
                    Text("İptal Et")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                        .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - Join Room Modal
    
    private var joinRoomModal: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 40, height: 4)
                    .padding(.top, 12)
                
                VStack(spacing: 6) {
                    Text("Özel Odaya Katıl")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text("Arkadaşının paylaştığı 4 haneli oda kodunu gir.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, 10)
                
                TextField("Örn: 4821", text: $inputRoomCode)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                    .foregroundColor(Theme.accent)
                    .keyboardType(.numberPad)
                    .padding(.horizontal, 40)
                
                if let err = matchManager.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
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
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .cornerRadius(14)
                        .padding(.horizontal, 40)
                }
                .disabled(inputRoomCode.trimmingCharacters(in: .whitespaces).isEmpty)
                
                Spacer()
            }
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
