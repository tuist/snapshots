import SwiftUI
import TuistSnapshots

struct ProfileCard: View {
    let name: String
    let role: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.indigo.gradient)
                .frame(width: 44, height: 44)
                .overlay(Text(String(name.prefix(1))).font(.headline).foregroundStyle(.white))
            VStack(alignment: .leading) {
                Text(name).font(.headline)
                Text(role).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .padding()
    }
}

#Preview("Light", traits: .sizeThatFitsLayout) {
    ProfileCard(name: "Ada Lovelace", role: "Analyst")
}

#Preview("Dark", traits: .sizeThatFitsLayout) {
    ProfileCard(name: "Grace Hopper", role: "Rear admiral")
        .preferredColorScheme(.dark)
}

#Preview("Gradient", traits: .sizeThatFitsLayout) {
    ProfileCard(name: "Katherine Johnson", role: "Mathematician")
        .snapshotDiffThreshold(0.02)
}

#Preview("Screen", traits: .landscapeLeft) {
    NavigationStack {
        List(["Ada", "Grace", "Katherine"], id: \.self) { ProfileCard(name: $0, role: "Engineer") }
            .navigationTitle("People")
    }
}
