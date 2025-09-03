import SwiftUI

struct DebugExportView: View {
    var body: some View {
        List {
            DebugViewSection()
        }
        .navigationTitle("Debug")
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { DebugExportView() }
}
