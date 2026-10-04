import SwiftUI

struct WatchWorkoutSettingsView: View {
    @Environment(\.watchAccent) private var accent
    @ObservedObject var recorder: WatchWorkoutRecorder
    @AppStorage("saveWorkoutsToHealth") private var savesToHealth = true
    @AppStorage("recordGPSRoute") private var recordsRoute = true
    @AppStorage("workoutAutoPause") private var autoPause = true
    @AppStorage("workoutMilestones") private var milestones = true

    var body: some View {
        Form {
            Section {
                Toggle("GPS routes", isOn: $recordsRoute)
                if recordsRoute {
                    Text(recorder.locationAccess.settingsDescription).font(.footnote).foregroundStyle(.secondary)
                    if recorder.locationAccess.needsAuthorization {
                        Button("Enable Location") { recorder.enableLocationFromSettings() }
                    }
                }
            } footer: {
                Text("Saved for future outdoor workouts, including with your wrist down. Turn this off only when you don't want a route.")
            }
            Section {
                Toggle("Auto-pause", isOn: $autoPause)
            } footer: {
                Text("Pauses after about 15 seconds of detected stillness. Resumes after walking or running is detected for 3 seconds. Manual pauses stay paused.")
            }
            Section {
                Toggle("Milestone alerts", isOn: $milestones)
            } footer: {
                Text("A haptic and creature celebration every 1,000 workout steps and every mile, with your mile split.")
            }
            Section {
                Toggle("Save to Health", isOn: $savesToHealth)
            } footer: {
                Text("Save completed workouts and recorded routes to Apple Health. Settings apply to your next workout.")
            }
        }
        .tint(accent)
        .navigationTitle("Settings")
        .onAppear { recorder.refreshLocationStatus() }
        .onChange(of: recordsRoute) { _, enabled in
            if enabled { recorder.enableLocationFromSettings() }
        }
    }

}
