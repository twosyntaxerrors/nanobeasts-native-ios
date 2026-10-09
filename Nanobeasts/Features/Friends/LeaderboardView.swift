import AuthenticationServices
import SwiftUI

/// The friends leaderboard sheet: Sign in with Apple first, then a live podium,
/// the race to the next spot, the rest of the standings, and invites.
struct LeaderboardView: View {
    @Environment(FriendsStore.self) private var friends
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Scope: String, CaseIterable, Identifiable {
        case week = "This week"
        case today = "Today"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .week
    @State private var showsCodeEntry = false
    @State private var enteredCode = ""
    @State private var confirmsDelete = false
    @State private var removal: LeaderboardEntry?
    @State private var showsLastWeek = false
    @Namespace private var scopeSelection

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if friends.isSignedIn {
                signedInContent
            } else {
                signInContent
            }
        }
        .background(NanoTheme.background.ignoresSafeArea())
        .task { await friends.refresh() }
        .fullScreenCover(isPresented: $showsLastWeek) {
            WeeklyResultsView { showsLastWeek = false }
        }
        .alert("Enter invite code", isPresented: $showsCodeEntry) {
            TextField("Invite code", text: $enteredCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Add friend") {
                let code = enteredCode
                enteredCode = ""
                Task { await friends.addFriend(code: code) }
            }
            Button("Cancel", role: .cancel) { enteredCode = "" }
        } message: {
            Text("Ask your friend for the code on their invite link.")
        }
        .alert(
            "Couldn't finish that",
            isPresented: Binding(
                get: { friends.errorMessage != nil },
                set: { if !$0 { friends.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(friends.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete your friends account?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await friends.deleteAccount() }
            }
        } message: {
            Text("This removes your leaderboard profile, friends, and uploaded step totals. Your creatures and progress on this iPhone stay.")
        }
        .confirmationDialog(
            "Remove \(removal?.displayName ?? "friend")?",
            isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove friend", role: .destructive) {
                if let removal { Task { await friends.removeFriend(removal) } }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("Leaderboard")
                .font(.custom("Aldrich-Regular", size: 20, relativeTo: .title2))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NanoTheme.text.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(NanoTheme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close leaderboard")
        }
        .foregroundStyle(NanoTheme.text)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Signed out

    private var signInContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                LeaderboardPodium(
                    places: [],
                    value: \.week,
                    stageForKey: stage(for:),
                    placeholderCreature: store.currentStage
                )
                .padding(.top, 8)

                VStack(spacing: 10) {
                    Text("Race your friends")
                        .font(NanoFont.aldrich(26))
                        .multilineTextAlignment(.center)
                    Text("See who walks the most each week. The leaderboard resets every Sunday.")
                        .font(.system(size: 15))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                if friends.pendingInviteCode != nil {
                    Label("You've been invited. Sign in to join their leaderboard.", systemImage: "person.2.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NanoTheme.teal)
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(NanoTheme.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 14) {
                    promise("trophy.fill", "Weekly standings with friends you invite")
                    promise("lock.fill", "Only your friends see your daily step totals")
                    promise("person.crop.circle", "You appear as \(displayName) with your current creature")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                SignInWithAppleButton(.continue) { request in
                    friends.prepare(request)
                } onCompletion: { result in
                    Task { await friends.complete(result) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(friends.isWorking)
                .overlay {
                    if friends.isWorking { ProgressView().tint(NanoTheme.background) }
                }

                Text("No email or Apple name is shared. Delete your account anytime.")
                    .font(.system(size: 12))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .background(NanoTheme.background)
        }
    }

    private var displayName: String {
        let name = store.playerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Researcher" : name
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NanoTheme.teal)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(NanoTheme.text)
        }
    }

    // MARK: - Signed in

    private var ranking: [LeaderboardEntry] {
        scope == .week ? friends.weekRanking : friends.todayRanking
    }

    private var value: KeyPath<LeaderboardEntry, Int> {
        scope == .week ? \.week : \.today
    }

    private var signedInContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                RaceHeader(
                    weekNumber: friends.weekNumber,
                    dates: friends.thisWeekLabel,
                    raceDay: friends.raceDay
                )
                scopePicker

                TimingTower(
                    ranking: ranking,
                    value: value,
                    movement: scope == .week ? friends.weeklyMovement : [:],
                    bestDayID: scope == .week ? friends.bestDayOfWeek?.entry.id : nil,
                    stageForKey: stage(for:),
                    inviteURL: friends.me?.inviteURL,
                    onRemove: { removal = $0 }
                )

                if scope == .week, let best = friends.bestDayOfWeek {
                    BestDayCard(holder: best.entry, day: best.day)
                }

                if friends.hasLastWeekResults {
                    lastWeekButton
                }

                Button {
                    showsCodeEntry = true
                } label: {
                    Label("Enter invite code", systemImage: "keyboard")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NanoTheme.text)

                account
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .animation(.smooth(duration: 0.3), value: scope)
        }
        .scrollIndicators(.hidden)
        .refreshable { await friends.refresh() }
        .safeAreaInset(edge: .bottom) {
            if let me = friends.me {
                ShareLink(
                    item: me.inviteURL,
                    subject: Text("Race me on Nanobeasts"),
                    message: Text("Race me on Nanobeasts this week! My invite code is \(me.inviteCode).")
                ) {
                    HStack {
                        Text(friends.hasFriends ? "Invite more friends" : "Invite friends")
                            .font(.custom("Aldrich-Regular", size: 16, relativeTo: .headline))
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(NanoTheme.background)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(NanoTheme.teal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(NanoTheme.background)
            }
        }
    }

    /// A pill segmented control in the app's own type, rather than the system picker.
    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(Scope.allCases) { option in
                Button {
                    scope = option
                } label: {
                    Text(option.rawValue.uppercased())
                        .font(NanoFont.aldrich(12))
                        .tracking(1.2)
                        .foregroundStyle(scope == option ? NanoTheme.background : NanoTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if scope == option {
                                Capsule()
                                    .fill(NanoTheme.teal)
                                    .matchedGeometryEffect(id: "scope", in: scopeSelection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(NanoTheme.surface, in: Capsule())
        .sensoryFeedback(.selection, trigger: scope)
    }

    private var lastWeekButton: some View {
        Button {
            showsLastWeek = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(LeaderboardMedal.gold)
                    .frame(width: 36, height: 36)
                    .background(LeaderboardMedal.gold.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last week's results")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NanoTheme.text)
                    Text(friends.lastWeekLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
            .padding(14)
            .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .font(NanoFont.aldrich(10))
                .tracking(1.4)
                .foregroundStyle(NanoTheme.secondaryText)
            Text("Signed in with Apple as \(friends.me?.displayName ?? displayName). Your name and creature update from your profile. Press and hold a friend to remove them.")
                .font(.system(size: 13))
                .foregroundStyle(NanoTheme.secondaryText)
            HStack(spacing: 12) {
                Button("Sign out") { Task { await friends.signOut() } }
                    .foregroundStyle(NanoTheme.text)
                Spacer()
                Button("Delete account", role: .destructive) { confirmsDelete = true }
                    .foregroundStyle(NanoTheme.danger)
            }
            .font(.system(size: 14, weight: .medium))
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NanoTheme.border))
        .padding(.top, 12)
    }

    private func stage(for key: String?) -> CreatureStage? {
        store.catalog.stage(forImageKey: key)
    }
}

// MARK: - Shared pieces

enum LeaderboardMedal {
    static let gold = Color(red: 0.96, green: 0.78, blue: 0.29)
    static let silver = Color(red: 0.78, green: 0.81, blue: 0.87)
    static let bronze = Color(red: 0.84, green: 0.55, blue: 0.34)

    static func color(for rank: Int) -> Color? {
        switch rank {
        case 1: gold
        case 2: silver
        case 3: bronze
        default: nil
        }
    }
}

extension CreatureCatalog {
    func stage(forImageKey key: String?) -> CreatureStage? {
        guard let key else { return nil }
        return families.lazy.flatMap(\.stages).first { $0.imageKey == key }
    }
}

/// Second, first and third on pedestals, with each player's creature standing on top.
/// Empty places invite friends, or show the player's own creature before sign-in.
struct LeaderboardPodium: View {
    static func places(from ranking: [LeaderboardEntry], value: KeyPath<LeaderboardEntry, Int>) -> [LeaderboardEntry] {
        Array(ranking.prefix(3).prefix { $0[keyPath: value] > 0 })
    }

    let places: [LeaderboardEntry]
    let value: KeyPath<LeaderboardEntry, Int>
    let stageForKey: (String?) -> CreatureStage?
    var inviteURL: URL? = nil
    var placeholderCreature: CreatureStage? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            column(rank: 2)
            column(rank: 1)
            column(rank: 3)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func column(rank: Int) -> some View {
        let entry = places.indices.contains(rank - 1) ? places[rank - 1] : nil
        let medal = LeaderboardMedal.color(for: rank) ?? NanoTheme.teal
        let creatureSize: CGFloat = rank == 1 ? 96 : 72

        VStack(spacing: 6) {
            ZStack {
                if rank == 1, entry != nil {
                    Circle()
                        .fill(medal.opacity(0.22))
                        .frame(width: creatureSize * 1.25, height: creatureSize * 1.25)
                        .blur(radius: 22)
                }
                if let entry {
                    if let stage = stageForKey(entry.avatarKey) {
                        CreatureArtworkView(stage: stage, maxPixel: Int(creatureSize * 3))
                            .frame(width: creatureSize, height: creatureSize)
                    } else {
                        FriendAvatar(stage: nil, size: creatureSize * 0.8)
                    }
                } else if rank == 1, let placeholderCreature {
                    CreatureArtworkView(stage: placeholderCreature, maxPixel: Int(creatureSize * 3))
                        .frame(width: creatureSize, height: creatureSize)
                } else {
                    emptySeat(size: creatureSize * 0.7)
                }
            }
            .frame(height: creatureSize)
            .overlay(alignment: .top) {
                if rank == 1, entry != nil || placeholderCreature != nil {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(LeaderboardMedal.gold)
                        .shadow(color: LeaderboardMedal.gold.opacity(0.6), radius: 8)
                        .offset(y: -22)
                }
            }

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.map { $0.isMe ? "You" : $0.displayName } ?? (inviteURL == nil ? " " : "Who's next?"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(entry == nil ? NanoTheme.secondaryText : NanoTheme.text)
                        .lineLimit(1)
                }
                Text(entry.map { $0[keyPath: value].formatted() } ?? (inviteURL == nil ? " " : "Invite"))
                    .font(entry == nil ? NanoFont.aldrich(11) : NanoFont.spaceMono(13, bold: true))
                    .monospacedDigit()
                    .foregroundStyle(entry == nil ? NanoTheme.teal : NanoTheme.secondaryText)
            }

            pedestal(rank: rank, medal: medal, isEmpty: entry == nil, isMe: entry?.isMe == true)
        }
        .frame(maxWidth: .infinity)
        .overlay {
            if entry == nil, let inviteURL {
                ShareLink(
                    item: inviteURL,
                    message: Text("Race me on Nanobeasts this week!")
                ) {
                    Color.clear.contentShape(Rectangle())
                }
                .accessibilityLabel("Invite a friend")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func emptySeat(size: CGFloat) -> some View {
        Circle()
            .strokeBorder(NanoTheme.secondaryText.opacity(0.5), style: StrokeStyle(lineWidth: 1.4, dash: [5, 5]))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: inviteURL == nil ? "questionmark" : "plus")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
    }

    private func pedestal(rank: Int, medal: Color, isEmpty: Bool, isMe: Bool) -> some View {
        let height: CGFloat = rank == 1 ? 86 : rank == 2 ? 64 : 48
        return UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [medal.opacity(isEmpty ? 0.08 : 0.30), medal.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                    .stroke(medal.opacity(isEmpty ? 0.25 : 0.85), lineWidth: isMe ? 2 : 1)
                    .mask(alignment: .top) { Rectangle().frame(height: 18) }
            }
            .overlay {
                Text("\(rank)")
                    .font(NanoFont.spaceMono(rank == 1 ? 28 : 22, bold: true))
                    .foregroundStyle(medal.opacity(isEmpty ? 0.4 : 1))
            }
            .frame(height: height)
    }
}

/// One row below the podium, or in last week's full results.
struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let rank: Int
    let steps: Int
    let stage: CreatureStage?
    var showsFreshness = true

    var body: some View {
        HStack(spacing: 12) {
            rankBadge
            FriendAvatar(stage: stage, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if entry.isMe {
                        Text("YOU")
                            .font(NanoFont.aldrich(9))
                            .tracking(1)
                            .foregroundStyle(NanoTheme.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(NanoTheme.teal, in: Capsule())
                    }
                }
                if showsFreshness {
                    Text(freshness(entry.lastSync))
                        .font(.system(size: 12))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(steps.formatted())
                    .font(NanoFont.spaceMono(17, bold: true))
                    .monospacedDigit()
                    .foregroundStyle(NanoTheme.text)
                Text("STEPS")
                    .font(NanoFont.aldrich(8))
                    .tracking(1.2)
                    .foregroundStyle(NanoTheme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 70)
        .background {
            if entry.isMe {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(NanoTheme.teal.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(NanoTheme.teal.opacity(0.5), lineWidth: 1)
                    )
                    .padding(3)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            steps == 0
                ? "\(entry.isMe ? "You" : entry.displayName), no steps yet"
                : "Rank \(rank), \(entry.isMe ? "you" : entry.displayName), \(steps.formatted()) steps"
        )
    }

    @ViewBuilder
    private var rankBadge: some View {
        if steps == 0 {
            Text("–")
                .font(NanoFont.spaceMono(15, bold: true))
                .foregroundStyle(NanoTheme.mutedText)
                .frame(width: 26)
        } else if let medal = LeaderboardMedal.color(for: rank) {
            Text("\(rank)")
                .font(NanoFont.spaceMono(13, bold: true))
                .foregroundStyle(Color.black.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(medal, in: Circle())
        } else {
            Text("\(rank)")
                .font(NanoFont.spaceMono(15, bold: true))
                .foregroundStyle(NanoTheme.secondaryText)
                .frame(width: 26)
        }
    }

    private func freshness(_ date: Date?) -> String {
        guard let date else { return "No steps synced yet" }
        if Date().timeIntervalSince(date) < 120 { return "Updated now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

/// A friend's current creature in a small circle.
struct FriendAvatar: View {
    let stage: CreatureStage?
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().fill(NanoTheme.elevated)
            if let stage {
                CreatureArtworkView(stage: stage, maxPixel: Int(size * 3))
                    .padding(size * 0.1)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Weekly results

/// Last week's final standings. Opens on Home on Sunday and Monday, and anytime
/// from the leaderboard.
struct WeeklyResultsView: View {
    @Environment(FriendsStore.self) private var friends
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onDone: () -> Void

    @State private var revealed = false

    private var ranking: [LeaderboardEntry] { friends.lastWeekRanking }
    private var myIndex: Int? { ranking.firstIndex(where: \.isMe) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NanoTheme.text.opacity(0.8))
                        .frame(width: 40, height: 40)
                        .background(NanoTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close results")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Text("WEEK OF \(friends.lastWeekLabel.uppercased())")
                            .font(NanoFont.aldrich(11))
                            .tracking(1.6)
                            .foregroundStyle(NanoTheme.teal)
                        Text(headline)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(NanoTheme.text)
                            .multilineTextAlignment(.center)
                        Text(subheadline)
                            .font(.system(size: 15))
                            .foregroundStyle(NanoTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)

                    LeaderboardPodium(
                        places: LeaderboardPodium.places(from: ranking, value: \.lastWeek),
                        value: \.lastWeek,
                        stageForKey: store.catalog.stage(forImageKey:)
                    )
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.9, anchor: .bottom)
                    .opacity(revealed || reduceMotion ? 1 : 0)

                    VStack(spacing: 0) {
                        ForEach(Array(ranking.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(
                                entry: entry,
                                rank: index + 1,
                                steps: entry.lastWeek,
                                stage: store.catalog.stage(forImageKey: entry.avatarKey),
                                showsFreshness: false
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            Button(action: onDone) {
                Text("NEW WEEK, LET'S GO")
                    .font(NanoFont.aldrich(13))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(NanoTheme.teal))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background {
            ZStack(alignment: .top) {
                NanoTheme.background
                Circle()
                    .fill(LeaderboardMedal.gold.opacity(0.16))
                    .frame(width: 420, height: 420)
                    .blur(radius: 90)
                    .offset(y: -140)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: revealed) { _, isRevealed in
            isRevealed && store.hapticsEnabled && (myIndex ?? 3) < 3
        }
        .task {
            guard !revealed else { return }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(duration: 0.6, bounce: 0.3)) { revealed = true }
        }
    }

    private var headline: String {
        guard let myIndex, ranking[myIndex].lastWeek > 0 else {
            return "\(ranking.first?.displayName ?? "A friend") won the week"
        }
        return myIndex == 0 ? "You won the week!" : "You finished #\(myIndex + 1)"
    }

    private var subheadline: String {
        guard let myIndex, ranking[myIndex].lastWeek > 0 else {
            return "You didn't log steps on the board last week. This week is a fresh start."
        }
        let steps = ranking[myIndex].lastWeek.formatted()
        if myIndex == 0 {
            return "\(steps) steps. Defend the crown this week."
        }
        let gap = ranking[myIndex - 1].lastWeek - ranking[myIndex].lastWeek
        return "\(steps) steps, \(gap.formatted()) short of #\(myIndex). The board just reset."
    }
}
