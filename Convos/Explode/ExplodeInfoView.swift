import SwiftUI

struct SoonLabel: View {
    var body: some View {
        Text("Soon")
            .font(.system(size: 14.0))
            .foregroundStyle(.colorTextSecondary)
            .padding(.vertical, DesignConstants.Spacing.stepX)
            .padding(.horizontal, DesignConstants.Spacing.step2x)
            .background(
                Capsule()
                    .fill(.colorFillMinimal)
            )
    }
}

struct ExplodeInfoView: View {
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
            Text("Real life is off the record.™")
                .font(.caption)
                .foregroundColor(.colorTextSecondary)
            Text("Exploding convos")
                .font(.system(.largeTitle))
                .fontWeight(.bold)
            Text("Messages and Members are destroyed forever, and there’s no record that the convo ever happened.")
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
        .padding([.leading, .top, .trailing], DesignConstants.Spacing.step10x)
    }
}

#Preview {
    @Previewable @State var presentingExplodeInfo: Bool = false
    VStack {
        Button {
            presentingExplodeInfo.toggle()
        } label: {
            Text("Toggle")
        }
    }
    .selfSizingSheet(isPresented: $presentingExplodeInfo) {
        ExplodeInfoView()
    }
}
