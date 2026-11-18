import SwiftUI

struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.green, in: .capsule)
    }
}

struct Badge_Previews: PreviewProvider {
    static var previews: some View {
        Badge(text: "New").previewLayout(.sizeThatFits).previewDisplayName("New")
        Badge(text: "Beta").previewLayout(.sizeThatFits).previewDisplayName("Beta")
    }
}
