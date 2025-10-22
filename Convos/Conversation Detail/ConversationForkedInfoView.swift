import SwiftUI

struct ConversationForkedInfoView: View {
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.step4x) {
            Text("Problem")
                .font(.system(.largeTitle))
                .fontWeight(.bold)

            Text("This convo is buggy on your device.\nPlease delete it and ask the person who invited you for a new invitation.")
                .font(.body)
                .foregroundStyle(.colorTextPrimary)

            Text("For privacy, Convos tracks zero app activity, including errors. Please screenshot this and tag @convosmessenger on social to let us know.")
                .font(.body)
                .foregroundStyle(.colorTextSecondary)

            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button {
                    onDelete()
                } label: {
                    Text("Delete convo")
                }
                .convosButtonStyle(.rounded(fullWidth: true, backgroundColor: .colorCaution))
            }
            .padding(.top, DesignConstants.Spacing.step4x)

            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button {
                    dismiss()
                } label: {
                    Text("Ignore")
                }
                .convosButtonStyle(.text)
                .frame(maxWidth: .infinity)
            }
            .padding(.top, DesignConstants.Spacing.step4x)
        }
        .padding(DesignConstants.Spacing.step10x)
    }
}

#Preview {
    @Previewable @State var presenting: Bool = false
    VStack {
        Button {
            presenting.toggle()
        } label: {
            Text("Toggle")
        }
    }
    .selfSizingSheet(isPresented: $presenting) {
        ConversationForkedInfoView {
        }
    }
}
