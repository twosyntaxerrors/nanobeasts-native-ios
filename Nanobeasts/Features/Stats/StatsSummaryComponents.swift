import SwiftUI

struct StatsScreenHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ACTIVITY STATS")
                .font(NanoFont.aldrich(28))
                .tracking(1.8)
                .foregroundStyle(NanoTheme.text)
            Text("Your movement powers evolution.")
                .font(NanoFont.aldrich(13))
                .foregroundStyle(NanoTheme.secondaryText)
        }
    }
}
