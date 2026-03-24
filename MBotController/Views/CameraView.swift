import SwiftUI
import AVFoundation

/// Live camera feed with a sensor overlay showing key mBot + iPhone data.
struct CameraView: View {

    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var ble:    MBotBLEManager

    @State private var cameraPosition: AVCaptureDevice.Position = .back
    @State private var showOverlay = true

    var body: some View {
        ZStack {
            // Camera feed
            CameraPreview(position: $cameraPosition)
                .ignoresSafeArea()
                .background(Color.black)

            // HUD overlay
            if showOverlay {
                VStack {
                    Spacer()
                    hudOverlay
                        .padding(.bottom, 90)   // above tab bar
                }
            }

            // Controls
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        iconButton(symbol: "arrow.triangle.2.circlepath.camera") {
                            cameraPosition = cameraPosition == .back ? .front : .back
                        }
                        iconButton(symbol: showOverlay ? "eye.fill" : "eye.slash.fill") {
                            withAnimation { showOverlay.toggle() }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
        .navigationTitle("Camera")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - HUD

    var hudOverlay: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // mBot data
            hudBox {
                HudRow(icon: "sensor.tag.radiowaves.forward",
                       label: ble.ultrasonicCM > 0 ? "\(Int(ble.ultrasonicCM)) cm" : "— cm")
                HudRow(icon: "road.lanes",
                       label: lineLabel)
                HudRow(icon: "battery.75",
                       label: ble.batteryVoltage > 0 ? String(format: "%.1fV", ble.batteryVoltage) : "—")
            }

            Spacer()

            // iPhone motion
            hudBox {
                HudRow(icon: "safari",
                       label: String(format: "%.0f°", motion.heading))
                HudRow(icon: "arrow.up.and.down",
                       label: String(format: "P %.0f°", motion.pitch * 180 / .pi))
                HudRow(icon: "arrow.left.and.right",
                       label: String(format: "R %.0f°", motion.roll  * 180 / .pi))
            }
        }
        .padding(.horizontal, 12)
    }

    var lineLabel: String {
        switch (ble.lineLeft, ble.lineRight) {
        case (true,  true):  return "L● R●"
        case (true,  false): return "L● R○"
        case (false, true):  return "L○ R●"
        case (false, false): return "L○ R○"
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    func hudBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(8)
        .background(.black.opacity(0.55))
        .cornerRadius(10)
    }

    func iconButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.55))
                .clipShape(Circle())
        }
    }
}

// MARK: - HUD Row

struct HudRow: View {
    let icon:  String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 16)
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)
        }
    }
}

// MARK: - Camera preview (UIViewRepresentable)

struct CameraPreview: UIViewRepresentable {
    @Binding var position: AVCaptureDevice.Position

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.setup(position: position)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.switchTo(position: position)
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    private var session: AVCaptureSession?
    private var activeInput: AVCaptureDeviceInput?

    func setup(position: AVCaptureDevice.Position) {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        if let input = makeInput(position: position) {
            session.addInput(input)
            activeInput = input
        }
        previewLayer.session      = session
        previewLayer.videoGravity = .resizeAspectFill
        self.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    func switchTo(position: AVCaptureDevice.Position) {
        guard let session = session,
              let current = activeInput,
              current.device.position != position else { return }

        session.beginConfiguration()
        session.removeInput(current)
        if let newInput = makeInput(position: position) {
            session.addInput(newInput)
            activeInput = newInput
        }
        session.commitConfiguration()
    }

    private func makeInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input  = try? AVCaptureDeviceInput(device: device) else { return nil }
        return input
    }
}
