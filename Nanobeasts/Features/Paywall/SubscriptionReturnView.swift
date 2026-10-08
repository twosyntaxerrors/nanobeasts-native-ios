import RevenueCat
import StoreKit
import SwiftUI

struct SubscriptionReturnView: View {
    @Environment(AppStore.self) private var store
    let reviewPlans: () -> Void
    var isPreview = false
    @State private var restoring = false
    @State private var message: String?
    @State private var managesSubscription = false

    var body: some View {
        ZStack {
            NanoTheme.background.ignoresSafeArea()
            LabGridBackground().ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    CreatureArtworkView(stage: store.currentStage)
                        .frame(width: 180, height: 180)
                    Text("Your journey is saved.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Your creatures, stats, and recorded routes are still here. Nanobeasts Pro lets you keep exploring.")
                        .foregroundStyle(NanoTheme.secondaryText)
                    Button(action: reviewPlans) {
                        Text("Explore my options").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent).tint(NanoTheme.teal).foregroundStyle(.black)
                    Button(restoring ? "Restoring…" : "Restore purchases") {
                        Task { await restore() }
                    }
                    .disabled(restoring).frame(minHeight: 44)
                    Button("Manage subscription") {
                        if isPreview { message = "Subscription management is simulated in this replay." }
                        else { managesSubscription = true }
                    }.frame(minHeight: 44)
                    if let message { Text(message).font(.footnote).foregroundStyle(NanoTheme.secondaryText) }
                    Toggle("Notifications", isOn: Binding(get: { store.onboardingWantsReminders },
                        set: { enabled in
                            if isPreview { store.onboardingWantsReminders = enabled }
                            else if !enabled { store.onboardingWantsReminders = false }
                            else { Task { store.onboardingWantsReminders = await NanoNotifications.shared.requestAuthorizationIfNeeded() } }
                        }))
                        .tint(NanoTheme.teal)
                    HStack(spacing: 22) {
                        Link("Privacy", destination: URL(string: "https://nanobeasts.app/privacy")!)
                        Link("Terms", destination: URL(string: "https://nanobeasts.app/terms")!)
                        Link("Support", destination: URL(string: "https://nanobeasts.app/support")!)
                    }.font(.footnote).frame(minHeight: 44)
                }
                .multilineTextAlignment(.center)
                .padding(24)
            }
        }
        .manageSubscriptionsSheet(isPresented: $managesSubscription)
        .onChange(of: managesSubscription) { wasPresented, isPresented in
            guard wasPresented, !isPresented, !isPreview else { return }
            message = nil
            Task { await store.refreshSubscriptionStatus(forceRefresh: true) }
        }
    }

    private func restore() async {
        guard !isPreview else { message = "No purchase to restore for this fresh replay profile."; return }
        guard Purchases.isConfigured else { message = "Please reconnect and try again."; return }
        restoring = true
        defer { restoring = false }
        do {
            await store.applyRevenueCatCustomerInfo(try await Purchases.shared.restorePurchases())
            if !store.isPremium { message = "No Nanobeasts Pro purchase was found for this Apple Account." }
        } catch { message = "Couldn’t restore right now. Check your connection and try again." }
    }
}
