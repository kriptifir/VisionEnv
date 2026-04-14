import SwiftUI

@main
struct VisionEnvApp: App {
    @StateObject private var generator = EnvironmentGenerator()
    @StateObject private var promptHistory = PromptHistory()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(generator)
                .environmentObject(promptHistory)
        }

        ImmersiveSpace(id: PanoramaView.immersiveSpaceID) {
            PanoramaView()
                .environmentObject(generator)
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
