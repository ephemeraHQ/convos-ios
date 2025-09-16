import SwiftUI

struct EarlyAccessInfoView: View {
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
            Text("Real life is off the record.™")
                .font(.caption)
                .foregroundColor(.colorTextSecondary)
            Text("Welcome to Convos")
                .font(.system(.largeTitle))
                .fontWeight(.bold)

            Text("Your convos, encrypted and ephemeral.")
                .font(.body)
                .foregroundStyle(.colorTextPrimary)

            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                }
                .convosButtonStyle(.rounded(fullWidth: true))
            }
            .padding(.top, DesignConstants.Spacing.step4x)
        }
        .padding(DesignConstants.Spacing.step10x)
    }
}

#Preview {
    @Previewable @State var presentingEarlyAccessInfo: Bool = false
    VStack {
        Button {
            presentingEarlyAccessInfo.toggle()
        } label: {
            Text("Toggle")
        }
    }
    .selfSizingSheet(isPresented: $presentingEarlyAccessInfo) {
        EarlyAccessInfoView()
    }
}
