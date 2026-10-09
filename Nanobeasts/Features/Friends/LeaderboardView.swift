import AuthenticationServices
import SwiftUI

/// The friends leaderboard sheet: Sign in with Apple first, then this week's
/// and today's standings, invites, and account controls.
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
                CreatureArtworkView(stage: store.currentStage, maxPixel: 480)
                    .frame(width: 150, height: 150)
                    .padding(.top, 12)

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

    private var signedInContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Range", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text(scope == .week ? weekCaption : "Steps since midnight in each friend's time zone")
                    .font(NanoFont.aldrich(11))
                    .tracking(0.6)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 0) {
                    let ranking = scope == .week ? friends.weekRanking : friends.todayRanking
                    ForEach(Array(ranking.enumerated()), id: \.element.id) { index, entry in
                        row(entry, rank: index + 1)
                        if index < ranking.count - 1 || ranking.count < 3 { divider }
                    }
                    ForEach(0..<max(3 - ranking.count, 0), id: \.self) { slot in
                        inviteSlot(rank: ranking.count + slot + 1)
                        if ranking.count + slot + 1 < 3 { divider }
                    }
                }
                .background(NanoTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let winner = lastWeekWinner {
                    HStack(spacing: 10) {
                        Image(systemName: "crown.fill").foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.29))
                        Text("Last week: \(winner.isMe ? "you" : winner.displayName) won with \(winner.lastWeek.formatted()) steps")
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(NanoTheme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
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
                        Text("Invite friends")
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

    private var divider: some View {
        Rectangle()
            .fill(NanoTheme.border)
            .frame(height: 1)
            .padding(.leading, 70)
    }

    private func row(_ entry: LeaderboardEntry, rank: Int) -> some View {
        let steps = scope == .week ? entry.week : entry.today
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(NanoFont.spaceMono(15, bold: true))
                .foregroundStyle(rank == 1 && steps > 0 ? Color(red: 0.96, green: 0.78, blue: 0.29) : NanoTheme.secondaryText)
                .frame(width: 20)

            FriendAvatar(stage: stage(for: entry.avatarKey), size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if entry.isMe {
                        Text("YOU")
                            .font(NanoFont.aldrich(9))
                            .tracking(1)
                            .foregroundStyle(NanoTheme.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(NanoTheme.teal.opacity(0.14), in: Capsule())
                    }
                }
                Text(freshness(entry.lastSync))
                    .font(.system(size: 12))
                    .foregroundStyle(NanoTheme.secondaryText)
            }

            Spacer(minLength: 8)

            Text(steps.formatted())
                .font(NanoFont.spaceMono(17, bold: true))
                .monospacedDigit()
                .foregroundStyle(NanoTheme.text)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .contextMenu {
            if !entry.isMe {
                Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) {
                    removal = entry
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(rank), \(entry.isMe ? "you" : entry.displayName), \(steps.formatted()) steps")
    }

    @ViewBuilder
    private func inviteSlot(rank: Int) -> some View {
        if let me = friends.me {
            ShareLink(
                item: me.inviteURL,
                message: Text("Race me on Nanobeasts this week! My invite code is \(me.inviteCode).")
            ) {
                HStack(spacing: 12) {
                    Text("\(rank)")
                        .font(NanoFont.spaceMono(15, bold: true))
                        .foregroundStyle(NanoTheme.mutedText)
                        .frame(width: 20)
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .frame(width: 42, height: 42)
                        .overlay(Circle().strokeBorder(NanoTheme.secondaryText.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])))
                    Text("Invite someone")
                        .font(.system(size: 16))
                        .foregroundStyle(NanoTheme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 68)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACCOUNT")
                .font(NanoFont.aldrich(10))
                .tracking(1.4)
                .foregroundStyle(NanoTheme.secondaryText)
            Text("Signed in with Apple as \(friends.me?.displayName ?? displayName). Your name and creature update from your profile.")
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

    // MARK: - Helpers

    private var weekCaption: String {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date())
        let daysLeft = 7 - weekday
        switch daysLeft {
        case 0: return "Final day. Resets tonight at midnight"
        case 1: return "Resets Sunday · 1 day left"
        default: return "Resets Sunday · \(daysLeft) days left"
        }
    }

    private var lastWeekWinner: LeaderboardEntry? {
        guard friends.hasFriends else { return nil }
        return friends.board?.entries.filter { $0.lastWeek > 0 }.max { $0.lastWeek < $1.lastWeek }
    }

    private func stage(for key: String?) -> CreatureStage? {
        guard let key else { return nil }
        return store.catalog.families.lazy.flatMap(\.stages).first { $0.imageKey == key }
    }

    private func freshness(_ date: Date?) -> String {
        guard let date else { return "No steps synced yet" }
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 120 { return "Updated now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
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

/// Shown on Home once a week, on Sunday or Monday, with last week's top three.
struct WeeklyPodiumCard: View {
    let podium: [LeaderboardEntry]
    let stageForKey: (String?) -> CreatureStage?
    let onDismiss: () -> Void

    private let gold = Color(red: 0.96, green: 0.78, blue: 0.29)

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("LAST WEEK'S PODIUM")
                    .font(NanoFont.aldrich(12))
                    .tracking(1.6)
                    .foregroundStyle(NanoTheme.teal)
                Text(headline)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(NanoTheme.text)
                    .multilineTextAlignment(.center)
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(displayOrder, id: \.entry.id) { place, entry in
                    VStack(spacing: 8) {
                        FriendAvatar(stage: stageForKey(entry.avatarKey), size: place == 1 ? 64 : 50)
                            .overlay(alignment: .top) {
                                if place == 1 {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(gold)
                                        .offset(y: -16)
                                }
                            }
                        Text(entry.isMe ? "You" : entry.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(entry.lastWeek.formatted())
                            .font(NanoFont.spaceMono(12, bold: true))
                            .foregroundStyle(NanoTheme.secondaryText)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(place == 1 ? gold.opacity(0.85) : NanoTheme.elevated)
                            .frame(height: place == 1 ? 64 : place == 2 ? 44 : 30)
                            .overlay {
                                Text("\(place)")
                                    .font(NanoFont.spaceMono(16, bold: true))
                                    .foregroundStyle(place == 1 ? Color.black.opacity(0.75) : NanoTheme.text)
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Button(action: onDismiss) {
                Text("NEW WEEK, LET'S GO")
                    .font(NanoFont.aldrich(12))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(NanoTheme.teal))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(NanoTheme.surface.opacity(0.97))
                .stroke(NanoTheme.teal.opacity(0.62), lineWidth: 1)
                .shadow(color: NanoTheme.shadow.opacity(0.55), radius: 30, y: 14)
        )
    }

    private var headline: String {
        guard let winner = podium.first else { return "" }
        return winner.isMe ? "You won the week!" : "\(winner.displayName) won the week"
    }

    /// Second, first, third, so the winner stands in the middle.
    private var displayOrder: [(place: Int, entry: LeaderboardEntry)] {
        let placed = podium.enumerated().map { (place: $0.offset + 1, entry: $0.element) }
        guard placed.count >= 2 else { return placed }
        var order = [placed[1], placed[0]]
        if placed.count > 2 { order.append(placed[2]) }
        return order
    }
}
