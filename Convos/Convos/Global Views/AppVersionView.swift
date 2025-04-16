//
//  AppVersionView.swift
//  Convos
//
//  Created by Jarod Luebbert on 4/16/25.
//

import SwiftUI

enum AppVersionProvider {
    static func appVersion(in bundle: Bundle = .main) -> String {
        guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            fatalError("CFBundleShortVersionString should not be missing from info dictionary")
        }
        return version
    }
}

enum AppIconProvider {
    static func appIcon(in bundle: Bundle = .main) -> String {
        guard let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              let iconFileName = iconFiles.last else {
            fatalError("Could not find icons in bundle")
        }

        return iconFileName
    }
}

struct AppVersionView: View {
    let versionString: String
    let appIcon: String
    
    init(versionString: String = AppVersionProvider.appVersion(), appIcon: String = AppIconProvider.appIcon()) {
        self.versionString = versionString
        self.appIcon = appIcon
    }

    var body: some View {
        VStack(alignment: .center, spacing: DesignConstants.Spacing.step3x) {
            if let image = UIImage(named: appIcon) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DesignConstants.CornerRadius.small))
            }

            Group {
                Text("Convos ")
                    .bold() +
                Text("v\(versionString)")
            }
            .multilineTextAlignment(.center)
            .font(.caption)
            .foregroundColor(.primary)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("App version \(versionString)")
    }
}
