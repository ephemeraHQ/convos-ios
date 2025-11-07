import SwiftUI

struct ConversationForkedInfoView: View {
    let onDelete: () -> Void
    @Environment(\.dismiss) var dismiss: DismissAction

    var body: some View {
        VStack(alignment: .leading, spacing: DesignConstants.Spacing.step6x) {
            VStack(alignment: .leading, spacing: DesignConstants.Spacing.step2x) {
                Text("Get a new room")
                    .font(.system(.largeTitle))
                    .fontWeight(.bold)
                    .padding(.bottom, DesignConstants.Spacing.step4x)

                Text("A key is out of date, so this convo can’t continue correctly. Please delete it and start a new one.")
                    .font(.body)
                    .foregroundStyle(.colorTextPrimary)

                Text("All data remains securely encrypted.")
                    .font(.body)
                    .foregroundStyle(.colorTextSecondary)
            }

            VStack(alignment: .leading, spacing: DesignConstants.Spacing.step2x) {
                Text("Current keys guarantee security")
                    .font(.body)
                    .foregroundStyle(.colorTextPrimary)

                // swiftlint:disable:next line_length
                Text("Convos constantly confirms that all participants hold up-to-date cryptographic keys. If a member’s keys aren’t current, they cannot decrypt new messages nor updates, so their experience is degraded.")
                    .font(.body)
                    .foregroundStyle(.colorTextSecondary)
            }

            VStack {
                Text("For privacy, Convos tracks zero app activity, including errors. Please let us know by screenshotting this and tag @convosmessenger on social.")
                    .font(.subheadline)
                    .foregroundStyle(.colorTextSecondary)
                    .padding(DesignConstants.Spacing.step4x)
            }
            .background(.colorFillMinimal)
            .mask(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.mediumLarge))

            VStack(spacing: DesignConstants.Spacing.step2x) {
                Button {
                    onDelete()
                } label: {
                    Text("Delete convo")
                }
                .convosButtonStyle(.rounded(fullWidth: true, backgroundColor: .colorBackgroundInverted))
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
        }
        .padding(DesignConstants.Spacing.step10x)
        .background(.colorBackgroundPrimary)
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
