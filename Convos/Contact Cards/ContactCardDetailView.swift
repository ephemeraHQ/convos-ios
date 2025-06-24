import SwiftUI

struct ContactCardDetailView: View {
    let contactCard: ContactCard

    var body: some View {
        NavigationStack {
            VStack {
                ContactCardView(contactCard: contactCard)
                    .padding(.horizontal, DesignConstants.Spacing.step4x)
                    .padding(.top, DesignConstants.Spacing.step2x)

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gear") {
                    }
                }
            }
        }
    }
}

#Preview {
    ContactCardDetailView(contactCard: .mock(type: .ephemeral([.mock()])))
}
