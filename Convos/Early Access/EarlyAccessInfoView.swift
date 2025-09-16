import SwiftUI

struct EarlyAccessInfoView: View {
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
            Text("Real life is off the record.™")
                .font(.caption)
                .foregroundColor(.colorTextSecondary)

            Text("Convos aren't forever")
                .font(.system(.largeTitle))
                .fontWeight(.bold)

            Text("You can explode a convo as soon you're done with it.")
                .font(.body)
                .foregroundStyle(.colorTextPrimary)

            Text("All convos will explode 30 days after they're created.")
                .font(.body)
                .foregroundStyle(.colorTextSecondary)

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
