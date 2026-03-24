import SwiftUI

struct ContentView: View {

    @EnvironmentObject var bleManager: MBotBLEManager
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationView { ControlView() }
                .tabItem { Label("Control", systemImage: "gamecontroller.fill") }
                .tag(0)

            NavigationView { SensorDashboardView() }
                .tabItem { Label("Sensors", systemImage: "waveform.path.ecg") }
                .tag(1)

            NavigationView { CameraView() }
                .tabItem { Label("Camera", systemImage: "camera.fill") }
                .tag(2)

            NavigationView { ConnectView() }
                .tabItem { Label("Connect", systemImage: "dot.radiowaves.left.and.right") }
                .tag(3)
        }
        // Persistent "not connected" banner on all non-connect tabs
        .overlay(alignment: .top) {
            if !bleManager.isConnected && tab != 3 {
                Button { tab = 3 } label: {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("mBot not connected — tap to connect")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 4)
                }
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: bleManager.isConnected)
            }
        }
    }
}
