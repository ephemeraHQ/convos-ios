import SwiftUI

struct WhatIsQuicknameView: View {
    let onContinue: () -> Void
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
            Text("Infinite identities")
                .font(.caption)
                .foregroundColor(.colorTextSecondary)
            Text("Quickname")
                .font(.system(.largeTitle))
                .fontWeight(.bold)
            Text("You're a new you in every convo, and your Quickname lets you instantly reuse a favorite name and pic across convos.")
                .font(.body)
                .foregroundStyle(.colorTextPrimary)

            Text("You're always anonymous by default, with the option to use your quickname.")
                .font(.body)
                .foregroundStyle(.colorTextSecondary)

            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button {
                    onContinue()
                } label: {
                    Text("Continue")
                }
                .convosButtonStyle(.rounded(fullWidth: true))
            }
            .padding(.top, DesignConstants.Spacing.step4x)
        }
        .padding([.leading, .top, .trailing], DesignConstants.Spacing.step10x)
    }
}

#Preview {
    @Previewable @State var presentingLearnMore: Bool = false
    VStack {
        Button {
            presentingLearnMore.toggle()
        } label: {
            Text("Toggle")
        }
    }
    .selfSizingSheet(isPresented: $presentingLearnMore) {
        WhatIsQuicknameView {}
    }
}
