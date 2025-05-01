import SwiftUI

struct RequestsHeader: View {
    let requestCount: Int
    let amount: Double?
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // Chat bubble with shield icon
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 52, height: 52)

                    Image(systemName: "bubble.left.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 26))

                    Image(systemName: "shield.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 16))
                        .offset(x: 10, y: 10)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Requests")
                        .font(.system(size: 17, weight: .bold))
                    Text("\(requestCount) new contacts")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Amount pill
                if let amount = amount {
                    Text("$\(Int(amount))")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.black)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    RequestsHeader(
        requestCount: 5,
        amount: 50.0,
        onTap: {}
    )
}
