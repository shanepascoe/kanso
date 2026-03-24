import SwiftUI
import CoreBluetooth

struct ConnectView: View {

    @EnvironmentObject var ble: MBotBLEManager

    var body: some View {
        List {
            // Status section
            Section {
                HStack {
                    Image(systemName: ble.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(ble.isConnected ? .green : .red)
                    Text(ble.connectionStatus)
                        .font(.body)
                    Spacer()
                    if ble.isConnected {
                        Button("Disconnect", role: .destructive) { ble.disconnect() }
                    }
                }
            } header: {
                Text("Status")
            }

            // Scan / Devices section
            Section {
                if ble.discoveredDevices.isEmpty && !ble.isScanning {
                    Text("Tap "Scan" to find nearby mBot devices.")
                        .foregroundColor(.secondary)
                        .font(.callout)
                } else if ble.discoveredDevices.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Scanning…").foregroundColor(.secondary)
                    }
                } else {
                    ForEach(ble.discoveredDevices, id: \.peripheral.identifier) { item in
                        Button {
                            ble.connect(to: item.peripheral)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .foregroundColor(.primary)
                                        .font(.body)
                                    Text(item.peripheral.identifier.uuidString)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(item.rssi) dBm")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .disabled(ble.isConnected)
                    }
                }
            } header: {
                HStack {
                    Text("Nearby Devices")
                    Spacer()
                    Button {
                        ble.isScanning ? ble.stopScan() : ble.startScan()
                    } label: {
                        Text(ble.isScanning ? "Stop" : "Scan")
                            .font(.caption.bold())
                    }
                }
            }

            // Help section
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Power on your mBot Ranger", systemImage: "power")
                    Label("Make sure Bluetooth is enabled on both devices", systemImage: "bluetooth")
                    Label("Tap Scan, then select your robot from the list", systemImage: "hand.tap")
                    Label("The robot's BLE module may appear as "Makeblock_XXXX"", systemImage: "info.circle")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("Tips")
            }
        }
        .navigationTitle("Connect")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { if !ble.isConnected { ble.startScan() } }
        .onDisappear { ble.stopScan() }
    }
}
