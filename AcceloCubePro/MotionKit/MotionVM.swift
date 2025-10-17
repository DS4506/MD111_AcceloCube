
import Foundation
import CoreMotion
import simd
import Combine
import QuartzCore

// MARK: - Config
struct MotionConfig {
    var sampleHz: Double = 60
    var smoothing: Double = 0.2   // 0..1 (higher = smoother)
    var damping: Double = 0.02    // 0..0.2 per tick
    var maxSpeed: Float = 5.0     // m/s
    var maxRange: Float = 2.0     // m
    var loggingEnabled: Bool = false
}

@MainActor
final class MotionVM: ObservableObject {

    // Published state for UI/Scene
    @Published var cfg = MotionConfig()
    @Published var quat: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
    @Published var pos: SIMD3<Float> = .zero
    @Published var status: String = "Idle"
    @Published var sampleLatencyMs: Double = 0
    @Published var usingDeviceMotion: Bool = false

    // Lifecycle
    private let mgr = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "MotionVM.queue"
        q.qualityOfService = .userInteractive
        return q
    }()

    // Kinematics
    private var v: SIMD3<Float> = .zero
    private var lastTimestamp: Double?

    // Calibration (neutral orientation)
    private var neutralInv: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

    // Optional logger
    private var logger: CSVLogger? = nil

    // MARK: - Public controls

    func start() {
        guard CMMotionManager().isDeviceMotionAvailable else {
            status = "DeviceMotion unavailable"
            usingDeviceMotion = false
            return
        }

        stop() // clean start
        usingDeviceMotion = true
        mgr.deviceMotionUpdateInterval = 1.0 / max(1.0, cfg.sampleHz)

        lastTimestamp = nil
        v = .zero
        status = "Starting"

        if cfg.loggingEnabled {
            logger = CSVLogger(filename: "accelocube_log.csv")
            logger?.writeHeaderIfNeeded()
        } else {
            logger = nil
        }

        // Use a stable reference frame
        mgr.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] dm, err in
            guard let self = self else { return }
            if let err = err {
                Task { @MainActor in self.status = "Error: \(err.localizedDescription)" }
                return
            }
            guard let dm = dm else { return }

            let now = CACurrentMediaTime()
            let ts = dm.timestamp
            let dt: Double
            if let last = self.lastTimestamp { dt = max(0, ts - last) } else { dt = 0 }
            self.lastTimestamp = ts

            // Attitude → quaternion
            let aq = dm.attitude.quaternion
            var q = simd_quatf(ix: Float(aq.x), iy: Float(aq.y), iz: Float(aq.z), r: Float(aq.w))
            q = self.neutralInv * q   // apply neutral calibration

            // User acceleration (gravity already removed by CMDeviceMotion)
            let ua = SIMD3<Float>(Float(dm.userAcceleration.x),
                                  Float(dm.userAcceleration.y),
                                  Float(dm.userAcceleration.z))

            // World-ish transform: revert neutral then apply q
            let qWorld = self.neutralInv.inverse * q
            let aWorld = qWorld.act(ua)

            // Integrate with damping and clamps
            var vNew = self.v + aWorld * Float(dt)
            if !vNew.allFinite { vNew = .zero }
            let speed = length(vNew)
            if speed > self.cfg.maxSpeed {
                vNew = normalize(vNew) * self.cfg.maxSpeed
            }
            vNew *= max(0, 1.0 - Float(self.cfg.damping))

            var pNew = self.pos + vNew * Float(dt)
            pNew = simd_clamp(
                pNew,
                SIMD3<Float>(repeating: -self.cfg.maxRange),
                SIMD3<Float>(repeating:  self.cfg.maxRange)
            )

            // Low-pass slerp for attitude
            let alpha = Float(min(max(self.cfg.smoothing, 0.0), 0.98))
            let qSmoothed = simd_slerp(self.quat, q, 1 - alpha)

            Task { @MainActor in
                self.quat = qSmoothed
                self.v = vNew
                self.pos = pNew
                self.sampleLatencyMs = (CACurrentMediaTime() - now) * 1000.0
                self.status = "OK \(Int(self.cfg.sampleHz)) Hz | v=\(String(format: "%.2f", length(vNew))) m/s | pos=\(self.formatVec(pNew)) m"
            }

            if let logger = self.logger, dt > 0 {
                logger.writeRow(timestamp: ts, q: qSmoothed, userAccel: ua, pos: pNew)
            }
        }
    }

    func stop() {
        if mgr.isDeviceMotionActive { mgr.stopDeviceMotionUpdates() }
        usingDeviceMotion = false
        status = "Stopped"
    }

    func toggle() { usingDeviceMotion ? stop() : start() }

    func recenter() {
        v = .zero
        pos = .zero
    }

    func calibrateNeutral(currentAttitude: CMQuaternion?) {
        guard let cq = currentAttitude else { return }
        let q = simd_quatf(ix: Float(cq.x), iy: Float(cq.y), iz: Float(cq.z), r: Float(cq.w))
        neutralInv = q.inverse
    }

    func applySampleRate() {
        if usingDeviceMotion { start() }
    }

    // MARK: - Helpers
    private func formatVec(_ v: SIMD3<Float>) -> String {
        String(format: "%.2f, %.2f, %.2f", v.x, v.y, v.z)
    }
}

// MARK: - Finite guard
private extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

// MARK: - CSV Logger (Optional)
final class CSVLogger {
    private let url: URL
    private var wroteHeader = false
    private let fm = FileManager.default

    init?(filename: String) {
        do {
            let docs = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            url = docs.appendingPathComponent(filename)
        } catch { return nil }
    }

    func writeHeaderIfNeeded() {
        guard wroteHeader == false else { return }
        let header = "timestamp,qx,qy,qz,qw,ax,ay,az,px,py,pz\n"
        append(text: header)
        wroteHeader = true
    }

    func writeRow(timestamp: Double, q: simd_quatf, userAccel: SIMD3<Float>, pos: SIMD3<Float>) {
        let row = String(
            format: "%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
            timestamp, q.imag.x, q.imag.y, q.imag.z, q.real,
            userAccel.x, userAccel.y, userAccel.z,
            pos.x, pos.y, pos.z
        )
        append(text: row)
    }

    private func append(text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                // ignore logging errors
            }
        } else {
            do {
                try data.write(to: url)
            } catch {
                // ignore logging errors
            }
        }
    }
}
