import SwiftUI
import UIKit

class UserTitleCollectionCell: UICollectionViewCell {
    override func prepareForReuse() {
        super.prepareForReuse()
        self.contentConfiguration = nil
    }

    func setup(name: String) {
        contentConfiguration = UIHostingConfiguration {
            UserTitleView(name: name)
                .frame(maxWidth: .infinity,
                       alignment: .leading)
        }
        .margins(.horizontal, 20.0)
        .margins(.top, 8.0)
        .margins(.bottom, 0.0)
    }
}

struct UserTitleView: View {
    let name: String
    var body: some View {
        if !name.isEmpty {
            Text(name)
                .lineLimit(1)
                .font(.caption2)
                .foregroundStyle(Color.gray)
        } else {
            EmptyView()
        }
    }
}

#Preview {
    let cell = UserTitleCollectionCell()
    cell.setup(name: "John Doe")
    return cell
}
