import ConvosCore
import SwiftUI

struct DebugExportView: View {
    let environment: AppEnvironment

    var body: some View {
        List {
            DebugViewSection(environment: environment)
        }
        .navigationTitle("Debug")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { DebugExportView(environment: .tests) }
}
