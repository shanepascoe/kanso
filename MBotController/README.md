# MBot Controller — iPhone App for mBot Ranger

A SwiftUI iPhone app that uses every iPhone sensor to control and monitor your **mBot Ranger** (Auriga board) robot over BLE.

---

## Features

### Control modes
| Mode | How it works |
|------|-------------|
| **Joystick** | On-screen drag joystick — works while holding phone or while robot drives autonomously |
| **Tilt** | Tilt the phone (or the robot if the phone is mounted on it) to steer — pitch = forward/back, roll = left/right |
| **Line Follow** | Automatic — robot follows a dark line using its line-follower sensor |
| **Obstacle Avoid** | Automatic — robot detects and steers around obstacles using its ultrasonic sensor |

### Sensor dashboard
Displays live readings from every available sensor:

**iPhone sensors**
- Attitude — roll, pitch, yaw (degrees)
- Accelerometer — X/Y/Z in g (gravity-free user acceleration)
- Gyroscope — X/Y/Z in rad/s
- Magnetometer — X/Y/Z in µT + calibration status
- Heading — compass bearing from true north
- Barometer — pressure (kPa) + relative altitude (m)
- GPS — latitude, longitude, altitude, speed (km/h), course

**mBot Ranger sensors** (via BLE / Makeblock protocol)
- Ultrasonic distance — cm, with colour-coded bar
- Line follower — left/right sensor state
- Battery voltage
- Robot IMU — pitch from Auriga onboard MPU6050

### Camera view
Live front or back camera feed with a HUD overlay showing ultrasonic distance, line sensor state, battery, heading, pitch, and roll.

---

## Hardware setup

| Sensor | Auriga port (default) |
|--------|----------------------|
| Encoded motor — left  (M1) | 9  |
| Encoded motor — right (M2) | 10 |
| Ultrasonic sensor           | 10 |
| Line follower sensor        | 9  |
| Light sensor (optional)     | 8  |
| Onboard gyro / battery      | 0 (internal) |

> If your wiring differs, update the `port` values in `MBotSensor` inside `MBotBLEManager.swift`.

---

## Xcode project setup

### Requirements
- Xcode 15 or later
- iOS 17 deployment target (iOS 16 also works with minor tweaks)
- Physical iPhone (simulator does not have Bluetooth, CoreMotion, or GPS)

### Steps

1. **Create a new Xcode project**
   - Product name: `MBotController`
   - Interface: SwiftUI
   - Language: Swift

2. **Replace the generated files** with the ones in this folder:
   ```
   MBotControllerApp.swift
   ContentView.swift
   Views/ConnectView.swift
   Views/ControlView.swift
   Views/SensorDashboardView.swift
   Views/CameraView.swift
   Managers/MBotBLEManager.swift
   Managers/MotionManager.swift
   Managers/LocationManager.swift
   ```

3. **Merge `Info.plist` entries** into the project's Info.plist (or set them in the
   target's *Info* tab in Xcode):
   - Privacy – Bluetooth Always Usage Description
   - Privacy – Bluetooth Peripheral Usage Description
   - Privacy – Motion Usage Description
   - Privacy – Location When In Use Usage Description
   - Privacy – Camera Usage Description

4. **Add Bluetooth background mode**
   - Target → Signing & Capabilities → + Capability → Background Modes
   - Check *Uses Bluetooth LE accessories*

5. Build and run on a real device (⌘R with your iPhone selected).

---

## Connecting to the robot

1. Power on your mBot Ranger.
2. Open the app and tap the **Connect** tab.
3. Tap **Scan** — the robot's BLE module should appear as `Makeblock_XXXX` or similar.
4. Tap the device name to connect.
5. Switch to the **Control** tab to start driving.

> The app also scans automatically when you open the Connect tab.

---

## Protocol notes

The app implements the **Makeblock Serial Protocol** over BLE (service `FFE0`, characteristic `FFE1`).

Packet format:
```
TX: FF 55 [len] [idx] [action] [device] [port] [slot] [data…]
RX: FF 55 [idx] [type] [data…]
```

Motor command (encoded motor, `device = 0x3E`):
```
FF 55 06 idx 02 3E port speed_lo speed_hi
```
Speed is a signed 16-bit integer (−255…255), little-endian.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Robot not found during scan | Ensure BLE module is powered; robot must be on |
| Motors not responding | Check motor port numbers in `MBotSensor` |
| Tilt control feels inverted | Adjust the sign of `pitch`/`roll` in `ControlView.updateMotors()` |
| Sensor values stuck at 0 | Verify sensor port wiring and query period in `MBotBLEManager.startPolling()` |
| Camera black screen | Camera permission must be granted; test on device not simulator |
