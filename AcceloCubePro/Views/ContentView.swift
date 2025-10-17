
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: MotionVM

    var body: some View {
        VStack(spacing: 0) {
            // Scene
            AcceloSceneView()
                .environmentObject(vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    Text("AcceloCube 2.0")
                        .font(.headline)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding()
                }

            Divider()

            // Controls
            ControlPanel()
                .environmentObject(vm)
                .background(Color(UIColor.secondarySystemBackground))
        }
        .onAppear {
            // Start manually with the button, or uncomment to auto-start
            // vm.start()
        }
    }
}
