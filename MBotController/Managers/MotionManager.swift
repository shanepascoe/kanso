import CoreMotion
import Combine

/// Wraps CMMotionManager and CMAltimeter, publishing all iPhone motion sensors.
final class MotionManager: ObservableObject {

    // MARK: - Attitude (radians)
    @Published var roll:  Double = 0
    @Published var pitch: Double = 0
    @Published var yaw:   Double = 0

    // MARK: - Accelerometer (g, gravity-free user acceleration)
    @Published var accelX: Double = 0
    @Published var accelY: Double = 0
    @Published var accelZ: Double = 0

    // MARK: - Raw accelerometer (g, includes gravity)
    @Published var rawAccelX: Double = 0
    @Published var rawAccelY: Double = 0
    @Published var rawAccelZ: Double = 0

    // MARK: - Gyroscope (rad/s)
    @Published var gyroX: Double = 0
    @Published var gyroY: Double = 0
    @Published var gyroZ: Double = 0

    // MARK: - Magnetometer (µT)
    @Published var magX: Double = 0
    @Published var magY: Double = 0
    @Published var magZ: Double = 0
    @Published var magAccuracy: CMMagneticFieldCalibrationAccuracy = .uncalibrated

    // MARK: - Heading (degrees, 0 = north)
    @Published var heading: Double = 0

    // MARK: - Barometer
    @Published var relativeAltitude: Double = 0  // metres since session start
    @Published var pressure: Double = 0           // kPa

    // MARK: - Availability flags
    var hasMotion:    Bool { motion.isDeviceMotionAvailable }
    var hasAltimeter: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    private let motion    = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let queue     = OperationQueue.main

    // MARK: - Lifecycle

    func start() {
        startDeviceMotion()
        startAltimeter()
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }

    // MARK: - Private

    private func startDeviceMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0   // 30 Hz
        motion.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: queue
        ) { [weak self] data, _ in
            guard let self, let data else { return }

            // Attitude
            self.roll  = data.attitude.roll
            self.pitch = data.attitude.pitch
            self.yaw   = data.attitude.yaw

            // Gravity-free user acceleration
            self.accelX = data.userAcceleration.x
            self.accelY = data.userAcceleration.y
            self.accelZ = data.userAcceleration.z

            // Raw accel = user accel + gravity vector
            self.rawAccelX = data.userAcceleration.x + data.gravity.x
            self.rawAccelY = data.userAcceleration.y + data.gravity.y
            self.rawAccelZ = data.userAcceleration.z + data.gravity.z

            // Gyroscope
            self.gyroX = data.rotationRate.x
            self.gyroY = data.rotationRate.y
            self.gyroZ = data.rotationRate.z

            // Magnetometer
            self.magX = data.magneticField.field.x
            self.magY = data.magneticField.field.y
            self.magZ = data.magneticField.field.z
            self.magAccuracy = data.magneticField.accuracy

            // Heading from true north (yaw in magnetic-north reference frame → degrees)
            let deg = -data.attitude.yaw * 180.0 / .pi
            self.heading = (deg + 360).truncatingRemainder(dividingBy: 360)
        }
    }

    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.relativeAltitude = data.relativeAltitude.doubleValue
            self.pressure         = data.pressure.doubleValue
        }
    }
}
