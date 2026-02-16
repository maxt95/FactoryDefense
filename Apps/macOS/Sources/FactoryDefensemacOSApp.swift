import SwiftUI

@main
struct FactoryDefensemacOSApp: App {
    var body: some Scene {
        WindowGroup {
            FactoryDefensemacOSRootView()
                .frame(minWidth: 1024, minHeight: 640)
        }
        .windowResizability(.contentSize)
    }
}
