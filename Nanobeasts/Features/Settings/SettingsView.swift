import AVFoundation
import SwiftUI
import StoreKit
import UIKit

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appTourFocus) private var tourFocus
    var isTourPreview = false
    var onExitReplay: (() -> Void)? = nil
    @State private var confirmsReset = false
    @State private var showsPaywall = false
    @State private var showsOnboardingPreview = false
    @State private var goalDraft = 10_000
    @State private var showsManageSubscriptions = false
    @StateObject private var notifications = NanoNotifications.shared
    @AppStorage("nanobeasts.notifications.setup-reminders") private var setupReminders = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var store = store

        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()

            ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    SettingsScreenHeader()

                    SettingsProfileHero(
                        name: store.playerName,
                        stageName: store.currentStage.name
                    )

                    SettingsProCard(isPremium: store.isPremium) {
                        if isTourPreview { showsPaywall = true }
                        else if store.isPremium { showsManageSubscriptions = true }
                        else { showsPaywall = true }
                    }

                    if let onExitReplay {
                        SettingsPanel(icon: "play.rectangle.fill", title: "ONBOARDING LAB",
                                      subtitle: "Return to your saved profile.") {
                            Button("End onboarding replay", action: onExitReplay)
                                .frame(minHeight: 48)
                        }
                    } else {
                        SettingsPanel(icon: "play.rectangle.fill", title: "ONBOARDING LAB",
                                      subtitle: "Compare paywalls at the first hatch or a later evolution. Steps and purchases are simulated.") {
                            Button { showsOnboardingPreview = true } label: {
                                settingsActionLabel("Test onboarding & paywall", symbol: "play.rectangle")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    notificationSettings

                    SettingsPanel(
                        icon: "paintpalette.fill",
                        title: "APPEARANCE",
                        subtitle: "Choose your interface signal color."
                    ) {
                        SettingsAccentPicker(
                            selection: $store.interfaceAccent,
                            hapticsEnabled: store.hapticsEnabled
                        )

                        SettingsDivider()

                        SettingsToggleRow(
                            title: "Reduce Motion",
                            subtitle: "Use calmer transitions and animations.",
                            isOn: $store.reduceMotion
                        )
                    }

                    SettingsPanel(
                        icon: "heart.fill",
                        title: "MOVEMENT & HEALTH",
                        subtitle: "Configure how activity is measured."
                    ) {
                        SettingsStatusRow(
                            title: "Apple Health Sync",
                            subtitle: store.healthState.title,
                            status: store.healthState == .connected ? "CONNECTED" : "ACTION",
                            active: store.healthState == .connected
                        ) {
                            Task {
                                if store.hasRequestedHealthAccess {
                                    await store.refreshHealthData()
                                } else {
                                    await store.requestHealthAccess()
                                }
                            }
                        }

                        SettingsDivider()

                        SettingsDistanceUnitRow(selection: $store.distanceUnit)

                        SettingsDivider()

                        SettingsToggleRow(
                            title: "Haptic Feedback",
                            subtitle: "Tactile responses for key actions.",
                            isOn: $store.hapticsEnabled
                        )
                    }

                    DailyObjectiveCard(goal: $goalDraft,
                                       todayGoal: store.dailyGoal,
                                       scheduledGoal: store.scheduledDailyGoal,
                                       minimum: min(store.dailyGoal, DailyGoalPolicy.manualMinimum)) {
                        store.scheduleDailyGoal(goalDraft)
                        goalDraft = store.upcomingDailyGoal
                        if store.hapticsEnabled {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }

                    .appTourTarget(.settingsGoal)
                    .id(AppTourTarget.settingsGoal)

                    SettingsPanel(
                        icon: "person.crop.circle.fill",
                        title: "PROFILE & DATA",
                        subtitle: "Your records remain private."
                    ) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    store.playerName.isEmpty
                                        ? "Researcher archive"
                                        : "\(store.playerName)'s archive"
                                )
                                .font(NanoFont.aldrich(13))
                                .foregroundStyle(.white)
                                Text("Stored locally on this device")
                                    .font(NanoFont.aldrich(10))
                                    .foregroundStyle(NanoTheme.secondaryText)
                            }
                            Spacer()
                            Circle()
                                .fill(NanoTheme.teal)
                                .frame(width: 9, height: 9)
                                .shadow(color: NanoTheme.teal, radius: 6)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(NanoTheme.background.opacity(0.45))
                                .stroke(NanoTheme.elevated, lineWidth: 1)
                        )
                    }

                    SettingsPanel(icon: "info.circle.fill", title: "HELP & LEGAL",
                                  subtitle: "Support and information, always within reach.") {
                        settingsLink("Privacy Policy", symbol: "hand.raised.fill", url: "https://nanobeasts.app/privacy")
                        SettingsDivider()
                        settingsLink("Terms of Service", symbol: "doc.text.fill", url: "https://nanobeasts.app/terms")
                        SettingsDivider()
                        settingsLink("Support", symbol: "questionmark.circle.fill", url: "https://nanobeasts.app/support")
                        SettingsDivider()
                        Button { if isTourPreview { showsPaywall = true } else { showsManageSubscriptions = true } } label: {
                            settingsActionLabel("Manage Subscription", symbol: "creditcard.fill")
                        }.buttonStyle(.plain)
                        SettingsDivider()
                        Text("Icons by [Solar / 480 Design](https://github.com/480-Design/Solar-Icon-Set), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Adapted with app colors and sizing.")
                            .font(.caption)
                            .foregroundStyle(NanoTheme.secondaryText)
                            .tint(NanoTheme.teal)
                            .padding(.vertical, 8)
                    }

                    ResetArchiveCard {
                        confirmsReset = true
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .task(id: tourFocus) {
                guard tourFocus == .settingsGoal else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                scroll.scrollTo(AppTourTarget.settingsGoal, anchor: .top)
            }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            goalDraft = store.upcomingDailyGoal
        }
        .task {
            guard !isTourPreview else { return }
            await store.refreshSubscriptionStatus()
            await notifications.refreshAuthorization()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !isTourPreview { Task { await notifications.refreshAuthorization() } }
        }
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        .onChange(of: showsManageSubscriptions) { wasPresented, isPresented in
            guard wasPresented, !isPresented, !isTourPreview else { return }
            Task { await store.refreshSubscriptionStatus(forceRefresh: true) }
        }
        .confirmationDialog(
            "Reset all Nanobeast progress?",
            isPresented: $confirmsReset,
            titleVisibility: .visible
        ) {
            Button("Reset progress", role: .destructive) {
                store.resetGameProgress()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Apple Health data is not affected.")
        }
        .fullScreenCover(isPresented: $showsPaywall) {
            RevenueCatPaywallScreen(playerName: store.playerName, selectedGoals: store.onboardingGoals, primaryGoal: store.onboardingPrimaryGoal, selectedBlockers: store.onboardingBlockers, isPreview: isTourPreview)
        }
        .fullScreenCover(isPresented: $showsOnboardingPreview) {
            OnboardingReplayView()
        }
    }

    private var notificationSettings: some View {
        SettingsPanel(icon: "bell.badge.fill", title: "NOTIFICATIONS",
                      subtitle: "Choose when Nanobeasts can give you a nudge.") {
            SettingsToggleRow(title: "Notifications",
                subtitle: "Hatch and evolution reminders, plus workout check-ins.",
                isOn: Binding(get: {
                    store.onboardingWantsReminders && (isTourPreview || notifications.authorized)
                }, set: { enabled in
                    if isTourPreview { store.onboardingWantsReminders = enabled }
                    else if !enabled { store.onboardingWantsReminders = false }
                    else {
                        Task {
                            store.onboardingWantsReminders = await notifications.requestAuthorizationIfNeeded()
                        }
                    }
                }))
                .disabled(notifications.isRequesting)
            if setupReminders && !isTourPreview {
                SettingsDivider()
                SettingsToggleRow(title: "Setup reminders",
                    subtitle: "Up to five nudges, two days apart. Stops when you subscribe or finish setup.",
                    isOn: Binding(get: { setupReminders }, set: { enabled in
                        NanoNotifications.shared.setSetupReminderPreference(enabled)
                        setupReminders = enabled
                    }))
            }
            if !isTourPreview, notifications.authorization == .denied {
                SettingsDivider()
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    settingsActionLabel("Allow in iPhone Settings", symbol: "arrow.up.forward.app")
                }.buttonStyle(.plain)
                Text("Notifications are disabled in iOS. Allow them there, then turn them on here.")
                    .font(NanoFont.aldrich(11)).foregroundStyle(NanoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingsLink(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) { settingsActionLabel(title, symbol: symbol) }
    }

    private func settingsActionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(NanoTheme.teal).frame(width: 22)
            Text(title).foregroundStyle(.white)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").foregroundStyle(NanoTheme.secondaryText)
        }
        .font(NanoFont.aldrich(13)).frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

private struct SettingsAccentPicker: View {
    @Binding var selection: NanoAccent
    let hapticsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("INTERFACE ACCENT")
                .font(NanoFont.aldrich(11))
                .tracking(1.1)
                .foregroundStyle(.white)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(NanoAccent.allCases) { accent in
                        swatch(accent)
                    }
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 3),
                    spacing: 8
                ) {
                    ForEach(NanoAccent.allCases) { accent in
                        swatch(accent)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func swatch(_ accent: NanoAccent) -> some View {
        let isSelected = selection == accent

        return Button {
            guard selection != accent else { return }
            selection = accent
            if hapticsEnabled {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        } label: {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(accent.color)
                .frame(width: 38, height: 38)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(
                            isSelected ? Color.white : Color.white.opacity(0.10),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .shadow(
                    color: isSelected ? accent.color.opacity(0.34) : .clear,
                    radius: 8,
                    y: 2
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SettingsAccentSwatchButtonStyle())
        .accessibilityLabel("\(accent.displayName) interface accent")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SettingsAccentSwatchButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

private struct SettingsProCard: View {
    let isPremium: Bool
    let upgrade: () -> Void

    var body: some View {
        Button {
            upgrade()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isPremium ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isPremium ? NanoTheme.teal : NanoTheme.background)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(isPremium ? NanoTheme.teal.opacity(0.10) : NanoTheme.teal)
                            .stroke(NanoTheme.teal.opacity(0.42), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(isPremium ? "NANOBEASTS PRO ACTIVE" : "UPGRADE TO PRO")
                        .font(NanoFont.aldrich(13))
                        .tracking(1.1)
                        .foregroundStyle(.white)
                    Text(
                        isPremium
                            ? "Manage your subscription."
                            : "Remove the daily evolution cap and keep growing."
                    )
                    .font(NanoFont.aldrich(10))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(NanoTheme.teal)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(NanoTheme.teal.opacity(isPremium ? 0.05 : 0.08))
                    .stroke(NanoTheme.teal.opacity(0.45), lineWidth: 1.2)
                    .shadow(
                        color: NanoTheme.teal.opacity(isPremium ? 0.06 : 0.16),
                        radius: 16
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            isPremium
                ? "Opens subscription management"
                : "Opens Nanobeasts Pro subscription options"
        )
    }
}

private struct SettingsScreenHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("SYSTEM SETTINGS")
                .font(NanoFont.aldrich(28))
                .tracking(1.8)
            Text("Tune your Nanobeasts experience.")
                .font(NanoFont.aldrich(13))
                .foregroundStyle(NanoTheme.secondaryText)
        }
    }
}

private struct SettingsProfileHero: View {
    let name: String
    let stageName: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 27))
                .foregroundStyle(NanoTheme.teal)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(NanoTheme.teal.opacity(0.09))
                        .stroke(NanoTheme.teal.opacity(0.38), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("ACTIVE RESEARCHER")
                    .font(NanoFont.aldrich(9))
                    .tracking(1.3)
                    .foregroundStyle(NanoTheme.teal)
                Text(name.isEmpty ? "RESEARCHER" : name.uppercased())
                    .font(NanoFont.aldrich(18))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("LINKED TO \(stageName.uppercased())")
                    .font(NanoFont.aldrich(9))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(NanoTheme.teal)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .fill(NanoTheme.teal.opacity(0.06))
                        .stroke(NanoTheme.teal.opacity(0.30), lineWidth: 1)
                )
        }
        .nanoHUDCard(radius: 24, padding: 15, illuminated: true)
    }
}

private struct SettingsPanel<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NanoTheme.teal)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 13)
                            .fill(NanoTheme.teal.opacity(0.08))
                            .stroke(NanoTheme.teal.opacity(0.28), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NanoFont.aldrich(12))
                        .tracking(1.4)
                    Text(subtitle)
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }

            content
        }
        .nanoHUDCard(padding: 16)
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let subtitle: String
    let status: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NanoFont.aldrich(13))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
                Spacer()
                Text(status)
                    .font(NanoFont.aldrich(8))
                    .tracking(0.9)
                    .foregroundStyle(active ? NanoTheme.teal : NanoTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(active ? NanoTheme.teal.opacity(0.08) : NanoTheme.background.opacity(0.4))
                            .stroke(
                                active ? NanoTheme.teal.opacity(0.34) : NanoTheme.elevated,
                                lineWidth: 1
                            )
                    )
            }
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsDistanceUnitRow: View {
    @Binding var selection: DistanceUnitPreference

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Distance Unit")
                    .font(NanoFont.aldrich(13))
                    .foregroundStyle(.white)
                Text("Choose how distances and badges are displayed.")
                    .font(NanoFont.aldrich(9))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Picker("Distance Unit", selection: $selection) {
                Text("MI").tag(DistanceUnitPreference.miles)
                Text("KM").tag(DistanceUnitPreference.kilometers)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 126)
            .accessibilityHint("Changes distance displays throughout Nanobeasts")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(NanoFont.aldrich(13))
                Text(subtitle)
                    .font(NanoFont.aldrich(10))
                    .foregroundStyle(NanoTheme.secondaryText)
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .accessibilityHint(subtitle)
                .tint(NanoTheme.teal)
                .scaleEffect(0.86)
        }
        .frame(minHeight: 52)
    }
}

private struct SettingsActionRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(NanoFont.aldrich(13))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(NanoTheme.teal)
            }
            .frame(minHeight: 52)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(NanoTheme.elevated.opacity(0.75))
            .frame(height: 1)
    }
}

private struct DailyObjectiveCard: View {
    @Binding var goal: Int
    let todayGoal: Int
    let scheduledGoal: Int?
    let minimum: Int
    let save: () -> Void

    private var savedGoal: Int { scheduledGoal ?? todayGoal }
    private var hasChanges: Bool { goal != savedGoal }

    private var statusText: String {
        if hasChanges {
            return goal < DailyGoalPolicy.manualMinimum
                ? "Saving starts it tomorrow, then it rises 500 a week to \(DailyGoalPolicy.manualMinimum.formatted())."
                : "Saving starts it tomorrow. Today’s goal stays \(todayGoal.formatted())."
        }
        if let scheduledGoal {
            return "Today: \(todayGoal.formatted()). Your new goal of \(scheduledGoal.formatted()) starts tomorrow."
        }
        if todayGoal < DailyGoalPolicy.manualMinimum {
            return "Your goal rises 500 a week until it reaches \(DailyGoalPolicy.manualMinimum.formatted())."
        }
        return "Minimum objective: \(DailyGoalPolicy.manualMinimum.formatted()) steps. Changes start tomorrow."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NanoTheme.teal)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 13)
                            .fill(NanoTheme.teal.opacity(0.08))
                            .stroke(NanoTheme.teal.opacity(0.28), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("DAILY OBJECTIVE")
                        .font(NanoFont.aldrich(12))
                        .tracking(1.4)
                    Text("Set the pace for creature evolution.")
                        .font(NanoFont.aldrich(10))
                        .foregroundStyle(NanoTheme.secondaryText)
                }
            }

            VStack(spacing: 2) {
                Text(goal.formatted())
                    .font(NanoFont.aldrich(38))
                Text("STEPS / DAY")
                    .font(NanoFont.aldrich(9))
                    .tracking(2)
                    .foregroundStyle(NanoTheme.teal)
            }
            .frame(maxWidth: .infinity)

            HStack {
                objectiveButton(icon: "minus") {
                    goal = max(goal - 1_000, minimum)
                }
                .disabled(goal <= minimum)
                .opacity(goal <= minimum ? 0.35 : 1)
                Spacer()
                Text("ADJUST BY 1,000")
                    .font(NanoFont.aldrich(9))
                    .tracking(1.2)
                    .foregroundStyle(NanoTheme.secondaryText)
                Spacer()
                objectiveButton(icon: "plus") {
                    goal = min(goal + 1_000, DailyGoalPolicy.maximum)
                }
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(NanoTheme.background.opacity(0.45))
                    .stroke(NanoTheme.elevated, lineWidth: 1)
            )

            Text(statusText)
                .font(NanoFont.aldrich(9))
                .foregroundStyle(hasChanges || scheduledGoal != nil ? NanoTheme.teal : NanoTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Button(action: save) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text(hasChanges ? "SAVE FOR TOMORROW" : "SAVED")
                        .font(NanoFont.aldrich(11))
                        .tracking(1.2)
                }
                .foregroundStyle(NanoTheme.background)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NanoTheme.teal)
                        .shadow(color: NanoTheme.teal.opacity(0.32), radius: 10)
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasChanges)
            .opacity(hasChanges ? 1 : 0.45)
        }
        .nanoHUDCard(radius: 24, padding: 16, illuminated: true)
    }

    private func objectiveButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NanoTheme.teal)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(NanoTheme.teal.opacity(0.40), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ResetArchiveCard: View {
    let reset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NanoTheme.danger)
                Text("RESET ARCHIVE")
                    .font(NanoFont.aldrich(12))
                    .tracking(1.4)
                    .foregroundStyle(NanoTheme.danger)
            }

            Text("Erase progress, creatures, and settings, then restart setup.")
                .font(NanoFont.aldrich(10))
                .foregroundStyle(NanoTheme.secondaryText)
                .lineSpacing(4)

            Button(action: reset) {
                Text("START OVER")
                    .font(NanoFont.aldrich(10))
                    .tracking(1.2)
                    .foregroundStyle(NanoTheme.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(NanoTheme.danger, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(NanoTheme.danger.opacity(0.04))
                .stroke(NanoTheme.danger.opacity(0.38), lineWidth: 1)
        )
    }
}

struct EvolutionLifecycleExperience: View {
    private enum TransitionMedia {
        case transparentWebP(URL, duration: Duration)
        case video(URL, duration: Duration)

        var duration: Duration {
            switch self {
            case .transparentWebP(_, let duration), .video(_, let duration):
                duration
            }
        }
    }

    private enum Phase: Int, CaseIterable {
        case assigned
        case hatch
        case hatchDex
        case evolutionTarget
        case evolution
        case evolutionDex
        case evolution2Target
        case evolution2
        case evolution2Dex
        case maturity
        case selection
        case newAssignment

        var shortTitle: String {
            switch self {
            case .assigned: "EGG"
            case .hatch: "HATCH"
            case .hatchDex: "DEX"
            case .evolutionTarget: "TARGET"
            case .evolution: "EVOLVE"
            case .evolutionDex: "DEX"
            case .evolution2Target: "TARGET"
            case .evolution2: "EVOLVE"
            case .evolution2Dex: "DEX"
            case .maturity: "MATURE"
            case .selection: "CHOOSE"
            case .newAssignment: "ASSIGNED"
            }
        }

        var isEvolution: Bool {
            self == .evolution || self == .evolution2
        }

        var isDexUnlock: Bool {
            self == .hatchDex || self == .evolutionDex || self == .evolution2Dex
        }
    }

    let catalog: CreatureCatalog
    let event: CreatureDiscoveryEvent?
    let nextEggs: [CreatureStage]
    let allowsDismissal: Bool
    let onChooseEgg: ((CreatureStage) -> Bool)?
    let automaticallyAdvances: Bool
    let returnButtonTitle: String?
    let onCompleted: (() -> Void)?
    let workoutContext: Bool
    let playsPrelude: Bool
    let previewVideoStartTime: TimeInterval
    let previewVideoPauseTime: TimeInterval?
    let onPreviewVideoPause: (() -> Void)?
    @State private var webPReachedPreviewCutoff = false
    let previewFinishesAtReveal: Bool
    let previewEggSelectionDetail: String?
    let dismissesOnCompletion: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var phase: Phase
    @State private var selectedEgg: CreatureStage?
    @State private var revealed = false
    @State private var copyRevealed = false
    @State private var sweepOffset: CGFloat = -1
    @State private var transitionLoaded = false
    @State private var transitionFailed = false
    @State private var transitionFinished = false
    @State private var portalLineExpanded = false
    @State private var portalOpened = false
    @State private var evolutionPreludeStep = 0
    @State private var evolutionPlaybackStarted = false
    @State private var evolutionShakeOffset: CGFloat = 0
    @State private var evolutionEnergyBurst = false
    @State private var revealFlashOpacity = 0.0
    @State private var dexScanProgress: CGFloat = 0
    @State private var dexScanComplete = false
    @State private var cinematicPreludeVisible = false
    @State private var cinematicPreludeBeat = 0
    @State private var didComplete = false

    init(
        catalog: CreatureCatalog,
        event: CreatureDiscoveryEvent?,
        nextEggs: [CreatureStage],
        allowsDismissal: Bool,
        onChooseEgg: ((CreatureStage) -> Bool)?,
        automaticallyAdvances: Bool = false,
        returnButtonTitle: String? = nil,
        workoutContext: Bool = false,
        playsPrelude: Bool = true,
        previewVideoStartTime: TimeInterval = 0,
        previewVideoPauseTime: TimeInterval? = nil,
        onPreviewVideoPause: (() -> Void)? = nil,
        previewFinishesAtReveal: Bool = false,
        previewStartsAtDex: Bool = false,
        previewEggSelectionDetail: String? = nil,
        dismissesOnCompletion: Bool = true,
        onCompleted: (() -> Void)? = nil
    ) {
        self.catalog = catalog
        self.event = event
        self.nextEggs = nextEggs
        self.allowsDismissal = allowsDismissal
        self.onChooseEgg = onChooseEgg
        self.automaticallyAdvances = automaticallyAdvances
        self.returnButtonTitle = returnButtonTitle
        self.workoutContext = workoutContext
        self.playsPrelude = playsPrelude
        self.previewVideoStartTime = previewVideoStartTime
        self.previewVideoPauseTime = previewVideoPauseTime
        self.onPreviewVideoPause = onPreviewVideoPause
        self.previewFinishesAtReveal = previewFinishesAtReveal
        self.previewEggSelectionDetail = previewEggSelectionDetail
        self.dismissesOnCompletion = dismissesOnCompletion
        self.onCompleted = onCompleted

        let initialPhase: Phase
        switch event?.kind {
        case .hatch:
            initialPhase = previewStartsAtDex ? .hatchDex : .hatch
        case .evolution:
            initialPhase = (event?.creatureStage.stage ?? 2) >= 3 ? .evolution2 : .evolution
        case .maturity:
            initialPhase = .maturity
        case .eggAcquired:
            initialPhase = .assigned
        case nil:
            initialPhase = .assigned
        }
        _phase = State(initialValue: initialPhase)
    }

    private var isPreview: Bool {
        event == nil
    }

    private var previewFamily: CreatureFamily {
        catalog.families.first(where: { family in
            family.stages.contains(where: { $0.name.lowercased() == "ampaw" })
        })
            ?? catalog.families.first(where: { $0.stages.count >= 4 })
            ?? catalog.families.first(where: { $0.stages.count >= 2 })
            ?? CreatureCatalog.fallback.families[0]
    }

    private var eventFamily: CreatureFamily {
        guard let event else { return previewFamily }
        return catalog.families.first(where: { $0.id == event.familyID }) ?? previewFamily
    }

    private var activeFamily: CreatureFamily {
        isPreview ? previewFamily : eventFamily
    }

    private var displayStage: CreatureStage {
        if phase == .newAssignment, let selectedEgg {
            return selectedEgg
        }

        if !isPreview, let event, phase != .selection {
            return event.creatureStage
        }

        switch phase {
        case .assigned:
            return activeFamily.stages.first(where: \.isEgg) ?? activeFamily.stages[0]
        case .hatch, .hatchDex, .evolutionTarget:
            return activeFamily.stages.first(where: { $0.stage == 1 })
                ?? activeFamily.stages.last!
        case .evolution, .evolutionDex, .evolution2Target:
            return activeFamily.stages.first(where: { $0.stage == 2 })
                ?? activeFamily.stages.last!
        case .evolution2, .evolution2Dex, .maturity:
            return activeFamily.stages.last!
        case .selection, .newAssignment:
            return selectedEgg ?? eggCandidates.first
                ?? activeFamily.stages.first(where: \.isEgg)
                ?? activeFamily.stages[0]
        }
    }

    private var previousStage: CreatureStage? {
        let stages = activeFamily.stages.sorted { $0.stage < $1.stage }
        guard let index = stages.firstIndex(where: { $0.id == displayStage.id }), index > 0 else {
            return nil
        }
        return stages[index - 1]
    }

    private var transitionMedia: TransitionMedia? {
        guard !accessibilityReduceMotion else { return nil }

        switch phase {
        case .hatch:
            let name = displayStage.name.lowercased().filter(\.isLetter)
            if let clip = ExpandedRosterAssets.transition(named: name + "-hatch") {
                return .transparentWebP(clip.url, duration: clip.duration)
            }
            guard let url = R2TransitionManifest.hatchVideoURL(for: displayStage) else {
                return nil
            }
            return .video(url, duration: .seconds(4.2))
        case .evolution, .evolution2:
            guard let previousStage else { return nil }
            let from = previousStage.name.lowercased().filter(\.isLetter)
            let to = displayStage.name.lowercased().filter(\.isLetter)
            if let clip = ExpandedRosterAssets.transition(named: from + "-" + to + "-evolution") {
                return .transparentWebP(clip.url, duration: clip.duration)
            }
            if let url = R2TransitionManifest.evolutionVideoURL(
                from: previousStage,
                to: displayStage
            ) {
                return .video(url, duration: .seconds(4.8))
            }
            if let url = R2TransitionManifest.transparentEvolutionVideoURL(
                from: previousStage,
                to: displayStage
            ) {
                return .video(url, duration: .milliseconds(2_750))
            }
            guard let url = R2TransitionManifest.transparentEvolutionURL(
                from: previousStage,
                to: displayStage
            ) else {
                return nil
            }
            return .transparentWebP(url, duration: .milliseconds(2_750))
        case .assigned, .hatchDex, .evolutionTarget, .evolutionDex,
                .evolution2Target, .evolution2Dex, .maturity, .selection, .newAssignment:
            return nil
        }
    }

    private var eggCandidates: [CreatureStage] {
        if !nextEggs.isEmpty {
            return Array(nextEggs.prefix(3))
        }
        return catalog.families
            .filter { $0.id != activeFamily.id }
            .compactMap { $0.stages.first(where: \.isEgg) }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()
            LifecycleParticleField()
                .opacity(phase == .selection ? 0.18 : 0.55)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isPreview {
                    phaseRail
                }

                Group {
                    if phase == .selection {
                        eggSelection
                    } else if phase.isDexUnlock {
                        lifecycleDexUnlock
                    } else {
                        revealStage
                    }
                }
                .frame(maxHeight: .infinity)

                actionBar
            }

            if (phase == .maturity || (!isPreview && phase == .assigned)), revealed {
                MaturityConfettiBurst()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .zIndex(30)
            }

            if cinematicPreludeVisible {
                HatchEvolutionPreludeOverlay(beat: cinematicPreludeBeat)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(!allowsDismissal)
        .task(id: phase) {
            if previewVideoPauseTime != nil, accessibilityReduceMotion || transitionMedia == nil {
                // Preserve the gate without requiring motion to unlock the preview.
                onPreviewVideoPause?()
                return
            }
            await runReveal()
            guard !Task.isCancelled else { return }
            if previewFinishesAtReveal, phase == .hatch || phase.isEvolution {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                completeExperience()
                return
            }
            await automaticallyAdvanceAfterReveal()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    isPreview
                        ? "LIFECYCLE PREVIEW"
                        : phase == .assigned ? "RESEARCHER INITIATION" : "EVOLUTION SIGNAL"
                )
                    .font(NanoFont.aldrich(10))
                    .tracking(1.7)
                    .foregroundStyle(NanoTheme.teal)
                Text(phase.shortTitle)
                    .font(NanoFont.aldrich(20))
                    .tracking(1.1)
            }

            Spacer()

            if isPreview {
                Button {
                    withAnimation(.snappy(duration: 0.38)) {
                        selectedEgg = nil
                        phase = .assigned
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Restart lifecycle preview")
            }

            if allowsDismissal {
                Button {
                    // Progress is already committed when the event is queued.
                    // Closing its workout reveal must release the old companion
                    // just like Back to Workout, without requiring a Dex visit.
                    // Maturity remains pending until an egg is actually chosen.
                    if workoutContext, event?.kind == .hatch || event?.kind == .evolution {
                        onCompleted?()
                    }
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close lifecycle experience")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var phaseRail: some View {
        HStack(spacing: 5) {
            ForEach(Phase.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= phase.rawValue ? NanoTheme.teal : Color.white.opacity(0.10))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.35), value: phase)
    }

    private var revealStage: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(
                            index == 2 ? NanoTheme.cyan.opacity(0.22) : NanoTheme.teal.opacity(0.30),
                            lineWidth: index == 0 ? 2 : 1
                        )
                        .frame(
                            width: CGFloat(214 + index * 50),
                            height: CGFloat(214 + index * 50)
                        )
                        .scaleEffect(revealed ? 1 : 0.58)
                        .opacity(revealed ? 0.18 : 0.72)
                        .animation(
                            .easeOut(duration: 1.1)
                                .delay(Double(index) * 0.09),
                            value: revealed
                        )
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                NanoTheme.teal.opacity(revealed ? 0.16 : 0.38),
                                NanoTheme.cyan.opacity(0.04),
                                .clear
                            ],
                            center: .center,
                            startRadius: 12,
                            endRadius: 155
                        )
                    )
                    .frame(width: 310, height: 310)

                if phase.isEvolution {
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .stroke(
                                index == 0 ? NanoTheme.teal : NanoTheme.cyan,
                                lineWidth: index == 0 ? 2 : 1
                            )
                            .frame(
                                width: CGFloat(232 + index * 34),
                                height: CGFloat(232 + index * 34)
                            )
                            .scaleEffect(evolutionEnergyBurst ? 1.24 : 0.82)
                            .opacity(evolutionEnergyBurst ? 0 : 0.42)
                    }

                    Circle()
                        .fill(Color.white.opacity(revealFlashOpacity))
                        .frame(width: 278, height: 278)
                        .blur(radius: 18)
                }

                transitionArtwork
                    .frame(width: 286, height: 286)
                    .offset(x: evolutionShakeOffset)

                if transitionMedia == nil, !accessibilityReduceMotion {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.50), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 54, height: 280)
                        .rotationEffect(.degrees(16))
                        .offset(x: sweepOffset * 205)
                        .blendMode(.plusLighter)
                        .mask(Circle().frame(width: 280, height: 280))
                }
            }
            .frame(height: 330)

            Group {
                if transitionMedia != nil, !transitionFinished {
                    VStack(spacing: 8) {
                        Text(phase == .hatch ? "HATCHING SEQUENCE" : "EVOLUTION IN PROGRESS")
                            .font(NanoFont.aldrich(11))
                            .tracking(1.8)
                            .foregroundStyle(NanoTheme.teal)
                        ProgressView()
                            .tint(NanoTheme.teal)
                    }
                } else {
                    VStack(spacing: 8) {
                        Label(phaseKicker, systemImage: phaseSymbol)
                            .font(NanoFont.aldrich(10))
                            .tracking(1.5)
                            .foregroundStyle(phaseTint)

                        Text(revealTitle)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.75)

                        Text(revealCopy)
                            .font(NanoFont.aldrich(12))
                            .foregroundStyle(NanoTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: 330)
                    }
                    .opacity(copyRevealed ? 1 : 0)
                    .offset(y: copyRevealed ? 0 : 12)
                }
            }
            .frame(minHeight: 104)

            Spacer(minLength: 10)
        }
        .padding(.horizontal, 22)
    }

    private var lifecycleDexUnlock: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 18)

            VStack(spacing: 6) {
                Text("FIELD DEX UPLINK")
                    .font(NanoFont.aldrich(10))
                    .tracking(1.8)
                    .foregroundStyle(NanoTheme.teal)
                Text(dexScanComplete ? "Archive entry unlocked" : "Scanning new specimen…")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.opacity)
            }

            LifecycleDexScanner(
                stage: displayStage,
                progress: dexScanProgress,
                completed: dexScanComplete
            )
            .frame(maxWidth: 360)
            .frame(height: 360)

            Text(
                dexScanComplete
                    ? "\(displayStage.name) is now cataloged. Its live idle signal will remain visible whenever you revisit this Dex entry."
                    : "Decrypting silhouette, matching the biometric profile, and preparing the live specimen record."
            )
            .font(NanoFont.aldrich(11))
            .foregroundStyle(NanoTheme.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: 340)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var transitionArtwork: some View {
        if let transitionMedia {
            lifecyclePortal(transitionMedia)
        } else {
            PreloadingStaticCreatureArtworkView(stage: displayStage)
                .padding(18)
                .scaleEffect(revealed ? 1 : 0.92)
                .opacity(revealed ? 1 : 0)
                .blur(radius: revealed ? 0 : 8)
                .rotation3DEffect(
                    .degrees(revealed ? 0 : -12),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.7
                )
                .shadow(color: NanoTheme.teal.opacity(0.26), radius: revealed ? 18 : 2)
        }
    }

    private func lifecyclePortal(_ media: TransitionMedia) -> some View {
        ZStack {
            PreloadingStaticCreatureArtworkView(stage: displayStage)
            .padding(18)
            .opacity(transitionFinished ? 1 : 0)
            .scaleEffect(transitionFinished ? 1 : 0.96)

            transitionMediaView(media, shouldPlay: portalOpened && !transitionFinished)
                .opacity(transitionFinished ? 0 : 1)

            if portalOpened, !transitionLoaded, !transitionFailed {
                ProgressView()
                    .tint(NanoTheme.teal)
            }

            if portalOpened, transitionFailed {
                signalInterrupted
            }
        }
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [NanoTheme.teal, NanoTheme.cyan.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        }
        .scaleEffect(
            x: portalLineExpanded ? 1 : 0.06,
            y: portalOpened ? 1 : 0.012
        )
        .opacity(revealed ? 1 : 0)
        .shadow(color: NanoTheme.teal.opacity(0.38), radius: 20)
    }

    @ViewBuilder
    private func transitionMediaView(
        _ media: TransitionMedia,
        shouldPlay: Bool
    ) -> some View {
        switch media {
        case .transparentWebP(let url, _):
            RemoteAnimatedWebPView(
                url: url,
                isPlaying: shouldPlay && !webPReachedPreviewCutoff,
                loopCount: 1,
                freezesOnLastFrame: true,
                preloadsAllFrames: true
            ) { succeeded in
                if !succeeded, previewVideoPauseTime != nil {
                    onPreviewVideoPause?()
                    return
                }
                transitionLoaded = succeeded
                transitionFailed = !succeeded
            }
            .id(url)
            // WebP clips can't seek, so the preview gate freezes them on a timer,
            // stopping before the new form takes shape (like the video checkpoint).
            .task(id: shouldPlay && transitionLoaded && previewVideoPauseTime != nil) {
                guard shouldPlay, transitionLoaded, let pauseTime = previewVideoPauseTime,
                      !webPReachedPreviewCutoff else { return }
                try? await Task.sleep(for: .seconds(max(pauseTime - previewVideoStartTime, 0)))
                guard !Task.isCancelled else { return }
                webPReachedPreviewCutoff = true
                onPreviewVideoPause?()
            }
        case .video(let url, _):
            RemoteTransitionVideoView(
                url: url,
                shouldPlay: shouldPlay,
                startTime: previewVideoStartTime,
                pauseTime: previewVideoPauseTime,
                onPause: onPreviewVideoPause,
                onReady: { succeeded in
                    if !succeeded, previewVideoPauseTime != nil {
                        onPreviewVideoPause?()
                        return
                    }
                    transitionLoaded = succeeded
                    transitionFailed = !succeeded
                },
                onFinished: {
                    if previewVideoPauseTime != nil {
                        onPreviewVideoPause?()
                        return
                    }
                    withAnimation(.easeOut(duration: 0.36)) {
                        transitionFinished = true
                    }
                }
            )
            .opacity(previewVideoStartTime > 0 && !transitionLoaded ? 0 : 1)
            .id(url)
        }
    }

    private var signalInterrupted: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(NanoTheme.teal)
            Text("SIGNAL INTERRUPTED")
                .font(NanoFont.aldrich(10))
                .tracking(1.2)
        }
    }

    private var eggSelection: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Text("NEW FIELD ASSIGNMENT")
                    .font(NanoFont.aldrich(10))
                    .tracking(1.8)
                    .foregroundStyle(NanoTheme.teal)
                Text("Choose your next egg")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text(previewEggSelectionDetail ?? "Three specimens arrived at the lab. Their identities remain classified until they hatch.")
                    .font(NanoFont.aldrich(12))
                    .foregroundStyle(NanoTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 10) {
                ForEach(Array(eggCandidates.enumerated()), id: \.element.id) { index, egg in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                            selectedEgg = egg
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 9) {
                            AnimatedCreatureArtworkView(stage: egg)
                                .frame(height: 112)
                                .scaleEffect(selectedEgg?.id == egg.id ? 1.07 : 0.92)

                            Text("SPECIMEN \(["A", "B", "C"][min(index, 2)])")
                                .font(NanoFont.aldrich(9))
                                .tracking(0.8)
                                .foregroundStyle(
                                    selectedEgg?.id == egg.id
                                        ? NanoTheme.teal
                                        : NanoTheme.secondaryText
                                )

                            Image(systemName: selectedEgg?.id == egg.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    selectedEgg?.id == egg.id
                                        ? NanoTheme.teal
                                        : NanoTheme.mutedText
                                )
                        }
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(
                                    selectedEgg?.id == egg.id
                                        ? NanoTheme.teal.opacity(0.10)
                                        : NanoTheme.surface.opacity(0.94)
                                )
                                .stroke(
                                    selectedEgg?.id == egg.id
                                        ? NanoTheme.teal
                                        : NanoTheme.border,
                                    lineWidth: selectedEgg?.id == egg.id ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose specimen \(index + 1)")
                }
            }
            .padding(.horizontal, 16)

            Text("Your selection becomes the active egg only after confirmation.")
                .font(.caption)
                .foregroundStyle(NanoTheme.mutedText)

            Spacer(minLength: 12)
        }
        .opacity(copyRevealed ? 1 : 0)
        .offset(y: copyRevealed ? 0 : 14)
    }

    private var actionBar: some View {
        Button(action: advance) {
            HStack(spacing: 9) {
                Text(actionTitle)
                    .font(NanoFont.aldrich(13))
                    .tracking(0.8)
                Image(systemName: phase == .newAssignment ? "checkmark" : "arrow.right")
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [NanoTheme.teal, NanoTheme.cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(
            (phase == .selection && selectedEgg == nil)
                || (phase != .selection && !copyRevealed)
        )
        .opacity(
            (phase == .selection && selectedEgg == nil)
                || (phase != .selection && !copyRevealed)
                ? 0.38
                : 1
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var phaseKicker: String {
        switch phase {
        case .assigned:
            isPreview ? "FIELD SPECIMEN RECEIVED" : "FIRST EGG RECEIVED"
        case .hatch: "HATCH SIGNAL COMPLETE"
        case .hatchDex, .evolutionDex, .evolution2Dex: "DEX ENTRY UNLOCKED"
        case .evolutionTarget, .evolution2Target: "STEP TARGET REACHED"
        case .evolution, .evolution2: "EVOLUTION COMPLETE"
        case .maturity: "FULL MATURITY REACHED"
        case .newAssignment: "NEW ASSIGNMENT LOCKED"
        case .selection: ""
        }
    }

    private var phaseSymbol: String {
        switch phase {
        case .assigned, .newAssignment: "gift.fill"
        case .hatch: "sparkles"
        case .hatchDex, .evolutionDex, .evolution2Dex: "checkmark.seal.fill"
        case .evolutionTarget, .evolution2Target: "figure.walk.motion"
        case .evolution, .evolution2: "arrow.triangle.2.circlepath"
        case .maturity: "crown.fill"
        case .selection: "circle.grid.3x3.fill"
        }
    }

    private var phaseTint: Color {
        phase == .maturity ? Color.yellow : NanoTheme.teal
    }

    private var revealTitle: String {
        switch phase {
        case .assigned:
            return isPreview
                ? "Hatch target reached"
                : "Welcome, Nanobeast Researcher!"
        case .hatch:
            return "You hatched \(displayStage.name)!"
        case .hatchDex, .evolutionDex, .evolution2Dex:
            return "\(displayStage.name) joined the Dex"
        case .evolutionTarget, .evolution2Target:
            return "\(displayStage.name) is ready"
        case .evolution, .evolution2:
            return "\(previousStageName) evolved into \(displayStage.name)!"
        case .maturity:
            return "\(displayStage.name) reached full maturity"
        case .newAssignment:
            return "\(displayStage.name) is now active"
        case .selection:
            return ""
        }
    }

    private var revealCopy: String {
        switch phase {
        case .assigned:
            return isPreview
                ? "The final required step filled the egg’s energy meter. The hatch signal is ready to begin."
                : "Professor Nano has entrusted you with your first field specimen. Walk 250 steps to power its hatch signal."
        case .hatch:
            return "The egg’s stored movement energy formed a brand-new Nanobeast."
        case .hatchDex, .evolutionDex, .evolution2Dex:
            return "The scan is complete, and the animated specimen is now available in the Field Dex."
        case .evolutionTarget, .evolution2Target:
            return "You hit this stage’s movement target. Continue to trigger the full evolution reveal."
        case .evolution, .evolution2:
            return "Consistent movement unlocked a stronger stage and a new archive entry."
        case .maturity:
            return "Every step in this lineage is complete. It’s time to begin a new field assignment."
        case .newAssignment:
            return workoutContext
                ? "Your saved steps have been carried over. Keep walking to help your new egg grow."
                : "Your new egg is cataloged. Any saved steps now count toward its growth."
        case .selection:
            return ""
        }
    }

    private var previousStageName: String {
        previousStage?.name ?? "Your Nanobeast"
    }

    private var actionTitle: String {
        if previewFinishesAtReveal, phase == .hatch || phase.isEvolution {
            return "CONTINUE"
        }
        if phase == .selection {
            return "CONFIRM NEXT EGG"
        }
        if phase == .newAssignment {
            return isPreview ? "CLOSE PREVIEW" : (returnButtonTitle ?? "RETURN TO LAB")
        }
        if !isPreview, phase == .hatch || phase.isEvolution {
            return "UNLOCK DEX ENTRY"
        }
        if !isPreview, phase.isDexUnlock {
            return returnButtonTitle ?? "RETURN TO LAB"
        }
        if !isPreview, phase == .assigned {
            return "ENTER THE LAB"
        }
        return "CONTINUE"
    }

    @MainActor
    private func performEvolutionShake() async {
        let offsets: [CGFloat] = [4, -4, 3, -3, 2, -2, 0]
        for offset in offsets {
            withAnimation(.linear(duration: 0.05)) {
                evolutionShakeOffset = offset
            }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
        }
    }

    private func advance() {
        if previewFinishesAtReveal, phase == .hatch || phase.isEvolution {
            completeExperience()
            return
        }
        if phase == .selection {
            guard let selectedEgg else { return }
            if let onChooseEgg, !onChooseEgg(selectedEgg) {
                return
            }
            withAnimation(.snappy(duration: 0.46, extraBounce: 0.05)) {
                phase = .newAssignment
            }
            return
        }

        if phase == .newAssignment {
            completeExperience()
            return
        }

        if !isPreview {
            if phase == .maturity {
                withAnimation(.snappy(duration: 0.46, extraBounce: 0.05)) {
                    phase = .selection
                }
            } else if phase == .hatch {
                withAnimation(.snappy(duration: 0.46, extraBounce: 0.05)) {
                    phase = .hatchDex
                }
            } else if phase == .evolution {
                withAnimation(.snappy(duration: 0.46, extraBounce: 0.05)) {
                    phase = .evolutionDex
                }
            } else if phase == .evolution2 {
                withAnimation(.snappy(duration: 0.46, extraBounce: 0.05)) {
                    phase = .evolution2Dex
                }
            } else {
                completeExperience()
            }
            return
        }

        guard let next = Phase(rawValue: phase.rawValue + 1) else {
            dismiss()
            return
        }
        withAnimation(.snappy(duration: 0.46, extraBounce: 0.05)) {
            phase = next
        }
    }

    private func completeExperience() {
        guard !didComplete else { return }
        didComplete = true
        onCompleted?()
        if dismissesOnCompletion { dismiss() }
    }

    @MainActor
    private func automaticallyAdvanceAfterReveal() async {
        guard automaticallyAdvances else { return }
        try? await Task.sleep(for: .milliseconds(1_250))
        guard !Task.isCancelled else { return }

        if phase == .selection {
            guard let egg = eggCandidates.first else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                selectedEgg = egg
            }
            try? await Task.sleep(for: .milliseconds(1_000))
            guard !Task.isCancelled else { return }
        }

        advance()
    }

    @MainActor
    private func runReveal() async {
        revealed = accessibilityReduceMotion
        copyRevealed = accessibilityReduceMotion
        sweepOffset = -1
        transitionLoaded = false
        transitionFailed = false
        transitionFinished = false
        portalLineExpanded = false
        portalOpened = false
        evolutionPreludeStep = 0
        evolutionPlaybackStarted = false
        evolutionShakeOffset = 0
        evolutionEnergyBurst = false
        revealFlashOpacity = 0
        dexScanProgress = 0
        dexScanComplete = false
        cinematicPreludeVisible = false
        cinematicPreludeBeat = 0

        if accessibilityReduceMotion {
            transitionFinished = true
            dexScanProgress = 1
            dexScanComplete = true
            return
        }

        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }

        if playsPrelude, phase == .hatch || phase.isEvolution {
            await runCinematicPrelude()
            guard !Task.isCancelled else { return }
        }

        if phase.isDexUnlock {
            withAnimation(.easeOut(duration: 0.30)) {
                revealed = true
            }
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 1.65)) {
                dexScanProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(1_650))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.38, extraBounce: 0.08)) {
                dexScanComplete = true
                copyRevealed = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        } else if let transitionMedia, phase == .hatch || phase.isEvolution {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.24)) {
                revealed = true
                portalLineExpanded = true
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)

            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }

            withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.38)) {
                portalOpened = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.82)

            if phase.isEvolution {
                withAnimation(.easeOut(duration: 0.20)) {
                    revealFlashOpacity = 0.24
                    evolutionEnergyBurst = true
                    evolutionPlaybackStarted = true
                }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
                await performEvolutionShake()
                withAnimation(.easeOut(duration: 0.58)) {
                    revealFlashOpacity = 0
                }
            }

            var readinessCycles = 0
            while !transitionLoaded && !transitionFailed && readinessCycles < 100 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                readinessCycles += 1
            }

            if case .transparentWebP = transitionMedia, transitionLoaded {
                try? await Task.sleep(for: transitionMedia.duration)
                withAnimation(.easeOut(duration: 0.36)) {
                    transitionFinished = true
                }
            } else {
                while !transitionFinished && !transitionFailed {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                }
            }
        } else {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
                revealed = true
            }
            withAnimation(.easeInOut(duration: 1.05).delay(0.15)) {
                sweepOffset = 1
            }
            try? await Task.sleep(for: .milliseconds(420))
        }

        if phase != .selection {
            UINotificationFeedbackGenerator().notificationOccurred(
                phase == .maturity || phase.isEvolution || phase == .hatch
                    ? .success
                    : .warning
            )
        }

        try? await Task.sleep(for: .milliseconds(260))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.42)) {
            copyRevealed = true
        }
    }

    @MainActor
    private func runCinematicPrelude() async {
        cinematicPreludeBeat = 0
        withAnimation(.easeIn(duration: 0.20)) {
            cinematicPreludeVisible = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.62)

        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }

        withAnimation(.snappy(duration: 0.32, extraBounce: 0.04)) {
            cinematicPreludeBeat = 1
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.88)

        try? await Task.sleep(for: .milliseconds(1_150))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.28)) {
            cinematicPreludeVisible = false
        }
        try? await Task.sleep(for: .milliseconds(280))
    }
}

struct HatchEvolutionPreludeOverlay: View {
    let beat: Int

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Text(beat == 0 ? "HUH?" : "Something’s happening?!")
                    .font(.system(size: beat == 0 ? 54 : 42, weight: .black, design: .rounded))
                    .tracking(beat == 0 ? 4 : 0)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: NanoTheme.teal.opacity(beat == 0 ? 0.18 : 0.55), radius: 24)
                    .id(beat)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.82).combined(with: .opacity),
                            removal: .scale(scale: 1.12).combined(with: .opacity)
                        )
                    )

                Capsule()
                    .fill(NanoTheme.teal)
                    .frame(width: beat == 0 ? 34 : 118, height: 3)
                    .shadow(color: NanoTheme.teal, radius: 10)
                    .animation(.snappy(duration: 0.36), value: beat)
            }
            .padding(.horizontal, 28)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(beat == 0 ? "Huh?" : "Something’s happening?!")
    }
}

struct MaturityConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var exploded = false
    @State private var visible = true

    private let colors: [Color] = [
        NanoTheme.teal,
        NanoTheme.cyan,
        .yellow,
        .orange,
        .white
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<48, id: \.self) { index in
                    MaturityConfettiParticle(
                        index: index,
                        color: colors[index % colors.count],
                        exploded: exploded,
                        visible: visible,
                        containerSize: proxy.size
                    )
                }
            }
        }
        .task {
            if reduceMotion {
                exploded = true
                try? await Task.sleep(for: .milliseconds(650))
                visible = false
                return
            }

            withAnimation(.timingCurve(0.17, 0.84, 0.32, 1, duration: 1.15)) {
                exploded = true
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.55)) {
                visible = false
            }
        }
        .accessibilityHidden(true)
    }

}

private struct MaturityConfettiParticle: View {
    let index: Int
    let color: Color
    let exploded: Bool
    let visible: Bool
    let containerSize: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: particleWidth, height: particleHeight)
            .rotationEffect(.degrees(exploded ? Double(index * 83) : 0))
            .scaleEffect(exploded ? 1 : 0.2)
            .position(x: containerSize.width / 2, y: containerSize.height * 0.37)
            .offset(exploded ? finalOffset : .zero)
            .opacity(visible ? 1 : 0)
            .shadow(color: color.opacity(0.42), radius: 3)
    }

    private var particleWidth: CGFloat {
        index.isMultiple(of: 3) ? 7 : 5
    }

    private var particleHeight: CGFloat {
        index.isMultiple(of: 3) ? 16 : 11
    }

    private var finalOffset: CGSize {
        let angle = angle(for: index)
        let distance = distance(for: index, in: containerSize)
        return CGSize(
            width: cos(angle) * distance,
            height: sin(angle) * distance + 76
        )
    }

    private func angle(for index: Int) -> CGFloat {
        let evenAngle = (CGFloat(index) / 48) * (.pi * 2)
        let deterministicJitter = CGFloat((index * 37) % 13 - 6) * 0.018
        return evenAngle + deterministicJitter
    }

    private func distance(for index: Int, in size: CGSize) -> CGFloat {
        let base = min(size.width, size.height) * 0.29
        return base + CGFloat((index * 29) % 72)
    }
}

private struct LifecycleDexScanner: View {
    let stage: CreatureStage
    let progress: CGFloat
    let completed: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(NanoTheme.surface.opacity(0.88))

                LabGridBackground()
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                if completed {
                    AnimatedCreatureArtworkView(stage: stage)
                        .padding(30)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else {
                    CreatureArtworkView(stage: stage)
                        .padding(30)
                        .saturation(0)
                        .colorMultiply(NanoTheme.teal)
                        .opacity(0.28)

                    CreatureArtworkView(stage: stage)
                        .padding(30)
                        .mask(alignment: .top) {
                            VStack(spacing: 0) {
                                Rectangle()
                                    .frame(height: proxy.size.height * progress)
                                Spacer(minLength: 0)
                            }
                        }

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, NanoTheme.teal, .white, NanoTheme.teal, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 3)
                        .shadow(color: NanoTheme.teal, radius: 12)
                        .offset(y: -proxy.size.height / 2 + proxy.size.height * progress)
                }

                VStack {
                    HStack {
                        Spacer()
                        Text(completed ? "LIVE" : "\(Int(progress * 100))%")
                            .font(NanoFont.aldrich(9))
                            .tracking(1)
                            .foregroundStyle(NanoTheme.teal)
                            .contentTransition(.numericText())
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(
                                Capsule()
                                    .fill(NanoTheme.background.opacity(0.92))
                                    .stroke(NanoTheme.teal.opacity(0.55), lineWidth: 1)
                            )
                    }
                    Spacer()
                    Label(
                        completed ? "ANIMATED PROFILE VERIFIED" : "BIOMETRIC SCAN IN PROGRESS",
                        systemImage: completed ? "checkmark.seal.fill" : "viewfinder"
                    )
                    .font(NanoFont.aldrich(8))
                    .tracking(1)
                    .foregroundStyle(NanoTheme.teal)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(
                        Capsule()
                            .fill(NanoTheme.background.opacity(0.92))
                            .stroke(NanoTheme.teal.opacity(0.45), lineWidth: 1)
                    )
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(NanoTheme.teal.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: NanoTheme.teal.opacity(completed ? 0.18 : 0.30), radius: 22)
        }
    }
}

private struct RemoteTransitionVideoView: UIViewRepresentable {
    let url: URL
    let shouldPlay: Bool
    var startTime: TimeInterval = 0
    var pauseTime: TimeInterval? = nil
    var onPause: (() -> Void)? = nil
    let onReady: (Bool) -> Void
    let onFinished: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TransitionPlayerView {
        let view = TransitionPlayerView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.playerLayer.backgroundColor = UIColor.clear.cgColor
        view.playerLayer.isOpaque = false
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = context.coordinator.player
        context.coordinator.load(
            url: url,
            shouldPlay: shouldPlay,
            startTime: startTime,
            pauseTime: pauseTime,
            onPause: onPause,
            onReady: onReady,
            onFinished: onFinished
        )
        return view
    }

    func updateUIView(_ view: TransitionPlayerView, context: Context) {
        context.coordinator.onReady = onReady
        context.coordinator.onFinished = onFinished
        context.coordinator.onPause = onPause
        if context.coordinator.url != url {
            context.coordinator.load(
                url: url,
                shouldPlay: shouldPlay,
                startTime: startTime,
                pauseTime: pauseTime,
                onPause: onPause,
                onReady: onReady,
                onFinished: onFinished
            )
        } else {
            context.coordinator.setShouldPlay(shouldPlay)
        }
    }

    static func dismantleUIView(_ view: TransitionPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        view.playerLayer.player = nil
    }

    final class Coordinator {
        let player = AVPlayer()
        var url: URL?
        var onReady: (Bool) -> Void = { _ in }
        var onFinished: () -> Void = {}
        var onPause: (() -> Void)?
        private var startTime: TimeInterval = 0
        private var pauseTime: TimeInterval?
        private var hasPausedAtCheckpoint = false
        private var boundaryObserver: Any?
        private var shouldPlay = false
        private var isReady = false
        private var hasStarted = false
        private var statusObservation: NSKeyValueObservation?
        private var endObserver: NSObjectProtocol?
        private var cacheTask: Task<Void, Never>?

        init() {
            player.isMuted = true
            player.volume = 0
            player.automaticallyWaitsToMinimizeStalling = true
            player.actionAtItemEnd = .pause
            player.preventsDisplaySleepDuringVideoPlayback = false
        }

        func load(
            url: URL,
            shouldPlay: Bool,
            startTime: TimeInterval = 0,
            pauseTime: TimeInterval? = nil,
            onPause: (() -> Void)? = nil,
            onReady: @escaping (Bool) -> Void,
            onFinished: @escaping () -> Void
        ) {
            self.url = url
            self.shouldPlay = shouldPlay
            self.onReady = onReady
            self.onFinished = onFinished
            self.startTime = max(startTime, 0)
            self.pauseTime = pauseTime
            self.onPause = onPause
            hasPausedAtCheckpoint = false
            removeBoundaryObserver()
            isReady = false
            hasStarted = false
            statusObservation?.invalidate()
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            cacheTask?.cancel()
            cacheTask = nil
            player.cancelPendingPrerolls()
            player.pause()
            player.replaceCurrentItem(with: nil)

            cacheTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let localURL = try await R2TransitionVideoCache.shared.localURL(for: url)
                    guard !Task.isCancelled, self.url == url else { return }
                    self.preparePlayer(with: localURL)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, self.url == url else { return }
                    self.onReady(false)
                }
            }
        }

        private func preparePlayer(with localURL: URL) {
            let item = AVPlayerItem(asset: AVURLAsset(url: localURL))
            item.preferredForwardBufferDuration = 0
            if let pauseTime {
                // Bound playback in the media timeline so a busy UI cannot expose later frames.
                item.forwardPlaybackEndTime = CMTime(seconds: pauseTime, preferredTimescale: 600)
            }
            player.replaceCurrentItem(with: item)
            if let pauseTime {
                boundaryObserver = player.addBoundaryTimeObserver(
                    forTimes: [NSValue(time: CMTime(seconds: pauseTime, preferredTimescale: 600))],
                    queue: .main
                ) { [weak self] in self?.pauseAtCheckpoint() }
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.hasStarted else { return }
                if self.pauseTime != nil { self.pauseAtCheckpoint() }
                else { self.onFinished() }
            }
            statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    switch item.status {
                    case .readyToPlay:
                        let start = CMTime(seconds: self.startTime, preferredTimescale: 600)
                        self.player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] sought in
                            DispatchQueue.main.async {
                                guard let self,
                                      let item,
                                      self.player.currentItem === item else {
                                    return
                                }
                                guard sought else { self.onReady(false); return }
                                self.player.preroll(atRate: 1) { [weak self, weak item] succeeded in
                                    DispatchQueue.main.async {
                                        guard let self, let item,
                                              self.player.currentItem === item else { return }
                                        self.isReady = succeeded
                                        self.onReady(succeeded)
                                        if succeeded { self.setShouldPlay(self.shouldPlay) }
                                    }
                                }
                            }
                        }
                    case .failed:
                        self.isReady = false
                        self.onReady(false)
                    case .unknown:
                        break
                    @unknown default:
                        self.onReady(false)
                    }
                }
            }
        }

        func setShouldPlay(_ shouldPlay: Bool) {
            self.shouldPlay = shouldPlay
            guard isReady else { return }

            if shouldPlay, !hasPausedAtCheckpoint {
                hasStarted = true
                player.play()
            } else {
                player.pause()
            }
        }

        private func pauseAtCheckpoint() {
            guard hasStarted, pauseTime != nil, !hasPausedAtCheckpoint else { return }
            hasPausedAtCheckpoint = true
            player.pause()
            onPause?()
        }

        private func removeBoundaryObserver() {
            if let boundaryObserver {
                player.removeTimeObserver(boundaryObserver)
                self.boundaryObserver = nil
            }
        }

        func stop() {
            removeBoundaryObserver()
            statusObservation?.invalidate()
            statusObservation = nil
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
                self.endObserver = nil
            }
            cacheTask?.cancel()
            cacheTask = nil
            isReady = false
            hasStarted = false
            player.cancelPendingPrerolls()
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }
}

private final class TransitionPlayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private struct LifecycleParticleField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<28 {
                    let seed = Double(index + 1)
                    let x = (sin(seed * 12.9898) * 43_758.5453).truncatingRemainder(dividingBy: 1)
                    let normalizedX = abs(x)
                    let speed = 5.0 + (seed.truncatingRemainder(dividingBy: 5))
                    let y = (time * speed + seed * 47).truncatingRemainder(dividingBy: max(size.height, 1))
                    let radius = 0.7 + seed.truncatingRemainder(dividingBy: 2.2)
                    let point = CGPoint(x: normalizedX * size.width, y: size.height - y)
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: point.x - radius,
                            y: point.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )),
                        with: .color(NanoTheme.teal.opacity(0.18 + seed.truncatingRemainder(dividingBy: 0.34)))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
