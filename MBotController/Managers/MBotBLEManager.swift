import Foundation
import CoreBluetooth

// MARK: - Sensor Definitions

enum MBotSensor: String {
    case ultrasonic   // Device 1, port 10
    case lineFollower // Device 17, port 9
    case light        // Device 3, port 8
    case battery      // Device 25, port 0
    case gyro         // Device 6, port 0 (Auriga onboard MPU6050)

    var device: UInt8 {
        switch self {
        case .ultrasonic:   return 0x01
        case .lineFollower: return 0x11
        case .light:        return 0x03
        case .battery:      return 0x19
        case .gyro:         return 0x06
        }
    }

    /// Default port for standard mBot Ranger (Auriga) wiring
    var port: UInt8 {
        switch self {
        case .ultrasonic:   return 0x0A  // port 10
        case .lineFollower: return 0x09  // port 9
        case .light:        return 0x08  // port 8
        case .battery:      return 0x00
        case .gyro:         return 0x00  // onboard
        }
    }

    var slot: UInt8 { 0x00 }
}

// MARK: - BLE Manager

/// Manages BLE connection to mBot Ranger and the Makeblock Serial Protocol.
/// Packet format: 0xFF 0x55 [len] [idx] [action] [device] [port] [slot] [data…]
/// Response:      0xFF 0x55 [idx] [type] [data…]  (type: 1=byte, 2=float, 3=short)
final class MBotBLEManager: NSObject, ObservableObject {

    // MARK: Published – connection

    @Published var isScanning = false
    @Published var isConnected = false
    @Published var connectionStatus = "Disconnected"
    @Published var discoveredDevices: [(peripheral: CBPeripheral, name: String, rssi: Int)] = []

    // MARK: Published – mBot sensors

    @Published var ultrasonicCM: Float = 0
    @Published var lineLeft = false
    @Published var lineRight = false
    @Published var lightLevel: Float = 0
    @Published var batteryVoltage: Float = 0
    @Published var robotPitch: Float = 0

    // MARK: Published – motors

    @Published var leftSpeed = 0
    @Published var rightSpeed = 0

    // MARK: Private – BLE

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txChar: CBCharacteristic?
    private var rxChar: CBCharacteristic?

    // Makeblock HM-11 module uses service FFE0, characteristic FFE1
    private let serviceUUID = CBUUID(string: "FFE0")
    private let charUUID    = CBUUID(string: "FFE1")

    // MARK: Private – protocol state

    private var packetIdx: UInt8 = 0
    private var pending: [UInt8: MBotSensor] = [:]
    private var rxBuffer = Data()
    private var pollTimer: Timer?

    // MARK: Init

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scanning

    func startScan() {
        guard central.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        isScanning = true
        // Scan without service filter so the user can see all nearby BLE devices
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(to device: CBPeripheral) {
        peripheral = device
        connectionStatus = "Connecting…"
        stopScan()
        central.connect(device, options: nil)
    }

    func disconnect() {
        guard let p = peripheral else { return }
        central.cancelPeripheralConnection(p)
    }

    // MARK: - Motor control

    /// Drive both encoded motors. Speed range: −255…255.
    func drive(left: Int, right: Int) {
        let l = left.clamped(to: -255...255)
        let r = right.clamped(to: -255...255)
        leftSpeed  = l
        rightSpeed = r
        sendEncodedMotor(port: 0x09, speed: l)  // M1 – left  (Auriga port 9)
        sendEncodedMotor(port: 0x0A, speed: r)  // M2 – right (Auriga port 10)
    }

    func stop() { drive(left: 0, right: 0) }

    // MARK: - Makeblock Serial Protocol helpers

    /// Encoded motor command: FF 55 06 idx 02 3E port speed_lo speed_hi
    private func sendEncodedMotor(port: UInt8, speed: Int) {
        let s = Int16(clamping: speed)
        let lo = UInt8(bitPattern: Int8(truncatingIfNeeded: Int(s) & 0xFF))
        let hi = UInt8(bitPattern: Int8(truncatingIfNeeded: (Int(s) >> 8) & 0xFF))
        send(Data([0xFF, 0x55, 0x06, nextIdx(), 0x02, 0x3E, port, lo, hi]))
    }

    /// Sensor read request: FF 55 04 idx 01 device port slot
    private func requestSensor(_ sensor: MBotSensor) {
        let idx = nextIdx()
        pending[idx] = sensor
        send(Data([0xFF, 0x55, 0x04, idx, 0x01, sensor.device, sensor.port, sensor.slot]))
    }

    private func send(_ data: Data) {
        guard isConnected, let p = peripheral, let ch = txChar else { return }
        p.writeValue(data, for: ch, type: .withoutResponse)
    }

    private func nextIdx() -> UInt8 {
        packetIdx &+= 1
        if packetIdx == 0 { packetIdx = 1 }
        return packetIdx
    }

    // MARK: - Sensor polling

    func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.pollAll()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollAll() {
        requestSensor(.ultrasonic)
        requestSensor(.lineFollower)
        requestSensor(.battery)
        requestSensor(.gyro)
    }

    // MARK: - Response parsing

    private func processData(_ data: Data) {
        rxBuffer.append(data)
        while rxBuffer.count >= 4 {
            guard rxBuffer[0] == 0xFF, rxBuffer[1] == 0x55 else {
                rxBuffer.removeFirst(); continue
            }
            let idx  = rxBuffer[2]
            let type = rxBuffer[3]
            guard let sensor = pending[idx] else {
                rxBuffer.removeFirst(2); continue
            }
            switch type {
            case 0x01: // byte
                guard rxBuffer.count >= 5 else { return }
                apply(sensor: sensor, byte: rxBuffer[4])
                pending.removeValue(forKey: idx)
                rxBuffer.removeFirst(5)
            case 0x02: // float
                guard rxBuffer.count >= 8 else { return }
                var f: Float = 0
                withUnsafeMutableBytes(of: &f) { rxBuffer[4..<8].copyBytes(to: $0) }
                apply(sensor: sensor, float: f)
                pending.removeValue(forKey: idx)
                rxBuffer.removeFirst(8)
            case 0x03: // short
                guard rxBuffer.count >= 6 else { return }
                let val = Float(Int16(rxBuffer[4]) | (Int16(rxBuffer[5]) << 8))
                apply(sensor: sensor, float: val)
                pending.removeValue(forKey: idx)
                rxBuffer.removeFirst(6)
            default:
                rxBuffer.removeFirst(2)
            }
        }
    }

    private func apply(sensor: MBotSensor, byte: UInt8) {
        if sensor == .lineFollower {
            lineLeft  = (byte & 0x02) != 0
            lineRight = (byte & 0x01) != 0
        }
    }

    private func apply(sensor: MBotSensor, float: Float) {
        switch sensor {
        case .ultrasonic: ultrasonicCM   = float
        case .light:      lightLevel     = float
        case .battery:    batteryVoltage = float
        case .gyro:       robotPitch     = float
        default: break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension MBotBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        connectionStatus = central.state == .poweredOn ? "Ready to scan" : "Bluetooth unavailable"
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Unknown"
        guard !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) else { return }
        discoveredDevices.append((peripheral, name, RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected     = true
        connectionStatus = "Connected to \(peripheral.name ?? "mBot")"
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        startPolling()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected      = false
        connectionStatus = "Disconnected"
        txChar = nil; rxChar = nil
        stopPolling()
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Connection failed"
    }
}

// MARK: - CBPeripheralDelegate

extension MBotBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        service.characteristics?.forEach { ch in
            if ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse) {
                txChar = ch
            }
            if ch.properties.contains(.notify) {
                rxChar = ch
                peripheral.setNotifyValue(true, for: ch)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        processData(data)
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
