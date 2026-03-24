import SwiftUI
import CoreMotion

/// Displays all iPhone sensors and mBot Ranger sensors in a scrollable card grid.
struct SensorDashboardView: View {

    @EnvironmentObject var motion:   MotionManager
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var ble:      MBotBLEManager

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                sectionHeader("iPhone — Motion")
                LazyVGrid(columns: columns, spacing: 12) {
                    attitudeCard
                    accelerometerCard
                    gyroscopeCard
                    magnetometerCard
                }

                sectionHeader("iPhone — Environment")
                LazyVGrid(columns: columns, spacing: 12) {
                    barometerCard
                    headingCard
                }

                sectionHeader("iPhone — Location (GPS)")
                LazyVGrid(columns: columns, spacing: 12) {
                    gpsCard
                    speedCourseCard
                }

                sectionHeader("mBot Ranger")
                LazyVGrid(columns: columns, spacing: 12) {
                    ultrasonicCard
                    lineFollowerCard
                    batteryCard
                    robotGyroCard
                }
            }
            .padding()
        }
        .navigationTitle("Sensors")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Section header

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }

    // MARK: - iPhone Motion cards

    var attitudeCard: some View {
        SensorCard(title: "Attitude", icon: "arrow.3.trianglepath") {
            SensorRow(label: "Roll",  value: "\(fmtDeg(motion.roll))")
            SensorRow(label: "Pitch", value: "\(fmtDeg(motion.pitch))")
            SensorRow(label: "Yaw",   value: "\(fmtDeg(motion.yaw))")
        }
    }

    var accelerometerCard: some View {
        SensorCard(title: "Accelerometer", icon: "move.3d") {
            SensorRow(label: "X", value: "\(fmt2(motion.accelX)) g")
            SensorRow(label: "Y", value: "\(fmt2(motion.accelY)) g")
            SensorRow(label: "Z", value: "\(fmt2(motion.accelZ)) g")
        }
    }

    var gyroscopeCard: some View {
        SensorCard(title: "Gyroscope", icon: "rotate.3d") {
            SensorRow(label: "X", value: "\(fmt2(motion.gyroX)) r/s")
            SensorRow(label: "Y", value: "\(fmt2(motion.gyroY)) r/s")
            SensorRow(label: "Z", value: "\(fmt2(motion.gyroZ)) r/s")
        }
    }

    var magnetometerCard: some View {
        SensorCard(title: "Magnetometer", icon: "location.north.line.fill") {
            SensorRow(label: "X", value: "\(fmt1(motion.magX)) µT")
            SensorRow(label: "Y", value: "\(fmt1(motion.magY)) µT")
            SensorRow(label: "Z", value: "\(fmt1(motion.magZ)) µT")
            SensorRow(label: "Cal", value: calibrationLabel(motion.magAccuracy))
        }
    }

    // MARK: - iPhone Environment cards

    var barometerCard: some View {
        SensorCard(title: "Barometer", icon: "barometer") {
            SensorRow(label: "Pressure", value: "\(fmt2(motion.pressure)) kPa")
            SensorRow(label: "Rel. Alt", value: "\(fmt1(motion.relativeAltitude)) m")
        }
    }

    var headingCard: some View {
        SensorCard(title: "Heading", icon: "safari") {
            SensorRow(label: "Bearing", value: "\(fmtHeading(motion.heading))")
            SensorRow(label: "Degrees", value: "\(fmt1(motion.heading))°")
        }
    }

    // MARK: - GPS cards

    var gpsCard: some View {
        SensorCard(title: "Position", icon: "mappin.and.ellipse") {
            SensorRow(label: "Lat",  value: "\(fmt5(location.latitude))°")
            SensorRow(label: "Lon",  value: "\(fmt5(location.longitude))°")
            SensorRow(label: "Alt",  value: "\(fmt1(location.altitude)) m")
            SensorRow(label: "Acc",  value: "±\(fmt1(location.horizontalAccuracy)) m")
        }
    }

    var speedCourseCard: some View {
        SensorCard(title: "Speed & Course", icon: "speedometer") {
            let kmh = location.speed >= 0 ? location.speed * 3.6 : 0
            SensorRow(label: "Speed",  value: "\(fmt1(kmh)) km/h")
            SensorRow(label: "Course", value: "\(fmt1(location.course))°")
        }
    }

    // MARK: - mBot cards

    var ultrasonicCard: some View {
        SensorCard(title: "Ultrasonic", icon: "sensor.tag.radiowaves.forward") {
            let d = ble.ultrasonicCM
            SensorRow(label: "Distance", value: d > 0 ? "\(Int(d)) cm" : "—")
            // Simple bar
            GeometryReader { geo in
                let frac = d > 0 ? min(CGFloat(d) / 200, 1) : 0
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(d < 15 ? Color.red : d < 35 ? Color.orange : Color.green)
                        .frame(width: geo.size.width * frac)
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.2), value: ble.ultrasonicCM)
        }
    }

    var lineFollowerCard: some View {
        SensorCard(title: "Line Follower", icon: "road.lanes") {
            HStack(spacing: 20) {
                VStack {
                    Circle()
                        .fill(ble.lineLeft ? Color.yellow : Color.secondary.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Text("L").font(.caption2).foregroundColor(.secondary)
                }
                VStack {
                    Circle()
                        .fill(ble.lineRight ? Color.yellow : Color.secondary.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Text("R").font(.caption2).foregroundColor(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.1), value: ble.lineLeft)
        }
    }

    var batteryCard: some View {
        SensorCard(title: "mBot Battery", icon: "battery.75") {
            let v = ble.batteryVoltage
            SensorRow(label: "Voltage", value: v > 0 ? "\(fmt2(Double(v))) V" : "—")
            if v > 0 {
                // Rough 4S NiMH: 4.8V empty, 6.0V full
                let frac = min(max((Double(v) - 4.8) / 1.2, 0), 1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(frac < 0.2 ? Color.red : frac < 0.5 ? Color.orange : Color.green)
                            .frame(width: geo.size.width * CGFloat(frac))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    var robotGyroCard: some View {
        SensorCard(title: "Robot IMU", icon: "gyroscope") {
            SensorRow(label: "Pitch", value: "\(fmt1(Double(ble.robotPitch)))°")
            Text("Auriga onboard MPU6050")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Formatters

    func fmt1(_ v: Double)  -> String { String(format: "%.1f", v) }
    func fmt2(_ v: Double)  -> String { String(format: "%.2f", v) }
    func fmt5(_ v: Double)  -> String { String(format: "%.5f", v) }
    func fmtDeg(_ r: Double) -> String { String(format: "%.1f°", r * 180 / .pi) }
    func fmtHeading(_ d: Double) -> String {
        let dirs = ["N","NE","E","SE","S","SW","W","NW"]
        let idx  = Int((d / 45.0).rounded()) % 8
        return dirs[idx]
    }
    func calibrationLabel(_ acc: CMMagneticFieldCalibrationAccuracy) -> String {
        switch acc {
        case .uncalibrated: return "Uncal"
        case .low:          return "Low"
        case .medium:       return "Medium"
        case .high:         return "High"
        @unknown default:   return "?"
        }
    }
}

// MARK: - Sensor Card component

struct SensorCard<Content: View>: View {
    let title:   String
    let icon:    String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title   = title
        self.icon    = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .lineLimit(1)
            content
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

// MARK: - Sensor Row component

struct SensorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }
}
