import SwiftUI

struct WhatIsQuicknameView: View {
    let onManage: () -> Void
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
            Text("Real life is off the record.™")
                .font(.caption)
                .foregroundColor(.colorTextSecondary)
            Text("Quickname")
                .font(.system(.largeTitle))
                .fontWeight(.bold)
            Text("Quickly re-use your favorite name and pic in new convos you join.")
                .font(.body)
                .foregroundStyle(.colorTextPrimary)

            Text("You’re always anonymous by default, with the option to use your quickname.")
                .font(.body)
                .foregroundStyle(.colorTextSecondary)

            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                }
                .convosButtonStyle(.rounded(fullWidth: true))

                Button {
                    onManage()
                } label: {
                    Text("Manage")
                }
                .convosButtonStyle(.text)
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
