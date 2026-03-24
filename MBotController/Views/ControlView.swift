import SwiftUI

// MARK: - Drive Mode

enum DriveMode: String, CaseIterable, Identifiable {
    case joystick    = "Joystick"
    case tilt        = "Tilt"
    case lineFollow  = "Line Follow"
    case avoidance   = "Avoid"
    var id: String { rawValue }
}

// MARK: - ControlView

struct ControlView: View {

    @EnvironmentObject var ble:    MBotBLEManager
    @EnvironmentObject var motion: MotionManager

    @State private var mode      = DriveMode.joystick
    @State private var joyX:     Double = 0
    @State private var joyY:     Double = 0
    @State private var maxSpeed: Double = 180
    @State private var tiltSens: Double = 1.0
    @State private var driveTimer: Timer?

    var body: some View {
        VStack(spacing: 16) {

            // Mode picker
            Picker("Mode", selection: $mode) {
                ForEach(DriveMode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            // Central control area
            Group {
                switch mode {
                case .joystick:   joystickPanel
                case .tilt:       tiltPanel
                case .lineFollow: lineFollowPanel
                case .avoidance:  avoidancePanel
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Speed slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Max speed: \(Int(maxSpeed))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $maxSpeed, in: 50...255, step: 5)
                    .tint(.blue)
            }
            .padding(.horizontal)

            // Motor bars
            HStack(spacing: 20) {
                MotorBar(label: "L", speed: ble.leftSpeed)
                MotorBar(label: "R", speed: ble.rightSpeed)
            }
            .padding(.horizontal)

            // Tilt sensitivity (only in tilt mode)
            if mode == .tilt {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tilt sensitivity: \(String(format: "%.1f", tiltSens))×")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Slider(value: $tiltSens, in: 0.5...3.0, step: 0.1)
                        .tint(.orange)
                }
                .padding(.horizontal)
            }

            // E-Stop
            Button {
                ble.stop()
                joyX = 0; joyY = 0
            } label: {
                Label("STOP", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.red)
                    .foregroundColor(.white)
                    .font(.headline)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("Control")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear  { startLoop() }
        .onDisappear { stopLoop(); ble.stop() }
    }

    // MARK: - Panels

    var joystickPanel: some View {
        VStack(spacing: 12) {
            Spacer()
            JoystickView(x: $joyX, y: $joyY)
            Text("Drag the stick to drive")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }

    var tiltPanel: some View {
        VStack(spacing: 12) {
            Spacer()
            TiltIndicator(pitch: motion.pitch, roll: motion.roll)
                .frame(width: 200, height: 200)
            HStack(spacing: 30) {
                VStack {
                    Text("Pitch").font(.caption2).foregroundColor(.secondary)
                    Text("\(Int(motion.pitch * 180 / .pi))°").font(.title3.bold())
                }
                VStack {
                    Text("Roll").font(.caption2).foregroundColor(.secondary)
                    Text("\(Int(motion.roll * 180 / .pi))°").font(.title3.bold())
                }
            }
            Text("Tilt phone to steer — phone can be flat on the robot")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }
    }

    var lineFollowPanel: some View {
        VStack(spacing: 16) {
            Spacer()
            HStack(spacing: 40) {
                SensorDot(label: "Left",  on: ble.lineLeft,  onColor: .yellow)
                SensorDot(label: "Right", on: ble.lineRight, onColor: .yellow)
            }
            Text(lineFollowStatus)
                .font(.headline)
            Text("Robot follows a dark line on a light surface.\nEnsure line follower sensor is connected to port 9.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }
    }

    var avoidancePanel: some View {
        VStack(spacing: 16) {
            Spacer()
            UltrasonicGauge(cm: ble.ultrasonicCM)
                .frame(width: 200, height: 200)
            Text("\(String(format: "%.0f", ble.ultrasonicCM)) cm")
                .font(.title2.bold())
            Text("Robot stops and turns when an obstacle is detected.\nUltrasonic sensor should be on port 10.")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }
    }

    var lineFollowStatus: String {
        switch (ble.lineLeft, ble.lineRight) {
        case (true,  true):  return "On line — straight ahead"
        case (true,  false): return "Veering right — correcting left"
        case (false, true):  return "Veering left — correcting right"
        case (false, false): return "Line lost — stopped"
        }
    }

    // MARK: - Drive loop

    func startLoop() {
        driveTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            updateMotors()
        }
    }

    func stopLoop() { driveTimer?.invalidate(); driveTimer = nil }

    func updateMotors() {
        guard ble.isConnected else { return }

        var fwd: Double = 0   // −1…1
        var trn: Double = 0   // −1…1

        switch mode {
        case .joystick:
            fwd = joyY; trn = joyX

        case .tilt:
            let scale = tiltSens
            // Pitch: lean forward → fwd, lean back → reverse
            fwd = (motion.pitch * scale).clamped(to: -1...1)
            // Roll: lean right → right turn
            trn = (motion.roll  * scale).clamped(to: -1...1)

        case .lineFollow:
            lineFollowMix(&fwd, &trn)

        case .avoidance:
            obstacleAvoidMix(&fwd, &trn)
        }

        let sp = maxSpeed
        let l = Int((fwd + trn) * sp).clamped(to: -255...255)
        let r = Int((fwd - trn) * sp).clamped(to: -255...255)
        ble.drive(left: l, right: r)
    }

    func lineFollowMix(_ fwd: inout Double, _ trn: inout Double) {
        switch (ble.lineLeft, ble.lineRight) {
        case (true,  true):  fwd = 0.6; trn =  0
        case (true,  false): fwd = 0.3; trn = -0.5   // steer left to re-centre
        case (false, true):  fwd = 0.3; trn =  0.5   // steer right to re-centre
        case (false, false): fwd = 0;   trn =  0
        }
    }

    func obstacleAvoidMix(_ fwd: inout Double, _ trn: inout Double) {
        let d = ble.ultrasonicCM
        if d > 0 && d < 15 {
            fwd = -0.4; trn = 0.6        // back up and turn
        } else if d < 35 {
            fwd =  0.2; trn = -0.4       // slow and turn away
        } else {
            fwd =  0.6; trn =  0         // clear – go
        }
    }
}

// MARK: - Joystick

struct JoystickView: View {
    @Binding var x: Double
    @Binding var y: Double

    private let radius: CGFloat = 90
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color.secondary.opacity(0.08))
                .frame(width: radius * 2, height: radius * 2)

            // Cross hairs
            Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: 1, height: radius * 2)
            Rectangle().fill(Color.secondary.opacity(0.15)).frame(width: radius * 2, height: 1)

            // Thumb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.blue.opacity(0.9), .blue],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .shadow(color: .blue.opacity(0.4), radius: 6)
                .frame(width: 54, height: 54)
                .offset(offset)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let dx = v.translation.width
                            let dy = v.translation.height
                            let dist = sqrt(dx*dx + dy*dy)
                            if dist <= radius {
                                offset = CGSize(width: dx, height: dy)
                            } else {
                                let angle = atan2(dy, dx)
                                offset = CGSize(
                                    width:  cos(angle) * radius,
                                    height: sin(angle) * radius
                                )
                            }
                            x =  Double(offset.width  / radius)
                            y = -Double(offset.height / radius)   // +y = forward
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.25)) {
                                offset = .zero
                            }
                            x = 0; y = 0
                        }
                )
        }
    }
}

// MARK: - Tilt Indicator

struct TiltIndicator: View {
    let pitch: Double   // radians
    let roll:  Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            Circle()
                .fill(Color.secondary.opacity(0.06))

            // Horizon line
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
                .rotationEffect(.radians(roll))

            // Bubble
            Circle()
                .fill(Color.orange.opacity(0.85))
                .shadow(color: .orange.opacity(0.4), radius: 4)
                .frame(width: 30, height: 30)
                // pitch forward → bubble moves up (negative dy), roll right → bubble right
                .offset(
                    x: CGFloat(sin(roll) * 70),
                    y: CGFloat(-sin(pitch) * 70)
                )

            // Centre cross
            Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 8, height: 1)
            Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 1, height: 8)
        }
    }
}

// MARK: - Ultrasonic Gauge

struct UltrasonicGauge: View {
    let cm: Float

    private var fraction: Double {
        cm <= 0 ? 0 : Double(min(cm, 200)) / 200.0
    }

    private var color: Color {
        switch cm {
        case ..<15:  return .red
        case ..<35:  return .orange
        default:     return .green
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 14)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: fraction)
            VStack(spacing: 2) {
                Image(systemName: "sensor.tag.radiowaves.forward")
                    .font(.title2)
                    .foregroundColor(color)
                Text(cm > 0 ? "\(Int(cm))" : "—")
                    .font(.title.bold())
                Text("cm").font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Motor Bar

struct MotorBar: View {
    let label: String
    let speed: Int

    private var fraction: Double { Double(abs(speed)) / 255.0 }
    private var color: Color    { speed >= 0 ? .blue : .orange }

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption.bold()).foregroundColor(.secondary)
            ZStack(alignment: speed >= 0 ? .bottom : .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 22, height: 80)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: 22, height: CGFloat(fraction) * 80)
                    .animation(.easeOut(duration: 0.08), value: fraction)
            }
            Text("\(speed)").font(.caption2).foregroundColor(.secondary)
        }
    }
}

// MARK: - Sensor Dot

struct SensorDot: View {
    let label:   String
    let on:      Bool
    let onColor: Color

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(on ? onColor : Color.secondary.opacity(0.2))
                .frame(width: 48, height: 48)
                .shadow(color: on ? onColor.opacity(0.5) : .clear, radius: 8)
                .animation(.easeInOut(duration: 0.1), value: on)
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
