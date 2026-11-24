import SwiftUI

struct ContentView: View {
    @State private var appleHealth = HealthKitEHRService()
    @State private var direct = DirectFHIRService()
    @State private var selection = Tab.connections

    private enum Tab: Hashable {
        case connections, appleHealth, direct
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ConnectionsView(appleHealth: appleHealth, direct: direct)
            }
            .tabItem { Label("Connections", systemImage: "person.badge.key.fill") }
            .tag(Tab.connections)

            NavigationStack {
                AppleHealthRecordsView(service: appleHealth) { selection = .connections }
            }
            .tabItem { Label("Apple Health", systemImage: "heart.text.square.fill") }
            .tag(Tab.appleHealth)

            NavigationStack {
                DirectFHIRRecordsView(service: direct) { selection = .connections }
            }
            .tabItem { Label("Direct EHR", systemImage: "network") }
            .tag(Tab.direct)
        }
        .task { direct.restoreSession() }
    }
}
