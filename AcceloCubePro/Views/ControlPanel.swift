
import SwiftUI
import CoreMotion

struct ControlPanel: View {
    @EnvironmentObject var vm: MotionVM

    private let hzOptions: [Double] = [30, 60, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(vm.usingDeviceMotion ? "Stop" : "Start") {
                    vm.toggle()
                }
                .buttonStyle(.borderedProminent)

                Button("Re-Center") { vm.recenter() }
                    .buttonStyle(.bordered)

                Button("Calibrate") {
                    if let att = currentAttitude() {
                        vm.calibrateNeutral(currentAttitude: att)
                    }
                }
                .buttonStyle(.bordered)
            }

            // Sample rate
            HStack {
                Text("Sample Hz")
                Spacer()
                Picker("", selection: $vm.cfg.sampleHz) {
                    ForEach(hzOptions, id: \.self) { hz in
                        Text("\(Int(hz))").tag(hz)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.cfg.sampleHz) { _ in vm.applySampleRate() }
                .frame(maxWidth: 220)
            }

            // Smoothing
            VStack(alignment: .leading) {
                HStack {
                    Text("Smoothing")
                    Spacer()
                    Text(String(format: "%.2f", vm.cfg.smoothing)).monospacedDigit()
                }
                Slider(value: $vm.cfg.smoothing, in: 0...0.98)
            }

            // Damping
            VStack(alignment: .leading) {
                HStack {
                    Text("Damping")
                    Spacer()
                    Text(String(format: "%.2f", vm.cfg.damping)).monospacedDigit()
                }
                Slider(value: $vm.cfg.damping, in: 0...0.2)
            }

            Toggle("CSV Logging", isOn: $vm.cfg.loggingEnabled)
                .onChange(of: vm.cfg.loggingEnabled) { _ in
                    if vm.usingDeviceMotion { vm.start() }
                }

            // HUD
            VStack(alignment: .leading, spacing: 6) {
                Text("Status: \(vm.status)")
                Text("Latency: \(Int(vm.sampleLatencyMs)) ms")
                // FIXED string interpolation (no escaped quotes)
                Text("Position: \(String(format: "%.2f, %.2f, %.2f", vm.pos.x, vm.pos.y, vm.pos.z)) m")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func currentAttitude() -> CMQuaternion? {
        // Fetch current attitude from motion manager for calibration
        (Mirror(reflecting: vm).children.first { $0.label == "mgr" }?.value as? CMMotionManager)?
            .deviceMotion?
            .attitude
            .quaternion
    }
}
