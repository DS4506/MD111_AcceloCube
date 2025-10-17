
import SwiftUI

@main
struct AcceloCubeProApp: App {
    @StateObject private var motion = MotionVM()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(motion)
        }
    }
}
