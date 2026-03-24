import Foundation

// MARK: - Script Commands

indirect enum ScriptCommand {
    case forward(speed: Int, duration: Double)      // duration=0 → non-blocking
    case backward(speed: Int, duration: Double)
    case arcLeft(speed: Int, duration: Double)
    case arcRight(speed: Int, duration: Double)
    case spinLeft(speed: Int, duration: Double)
    case spinRight(speed: Int, duration: Double)
    case stop(pause: Double)
    case wait(duration: Double)
    case repeat_(count: Int, body: [ScriptCommand])
    case whileUltrasonic(op: String, cm: Double, body: [ScriptCommand])
    case ifUltrasonic(op: String, cm: Double, body: [ScriptCommand])
    case motors(left: Int, right: Int, duration: Double)
}

// MARK: - Parse Error

struct ScriptParseError: LocalizedError {
    let line: Int
    let message: String
    var errorDescription: String? { "Line \(line): \(message)" }
}

// MARK: - Parser
//
// Language syntax (one command per line):
//
//   forward  <speed> [<seconds>]    backward  <speed> [<seconds>]
//   left     <speed> [<seconds>]    right     <speed> [<seconds>]
//   spin_left  <speed> [<seconds>]  spin_right <speed> [<seconds>]
//   motors   <left> <right> [<seconds>]
//   stop  [<seconds>]
//   wait  <seconds>
//   repeat <N>:            # begin block
//     ...commands...
//   end
//   while ultrasonic <op> <cm>:    # op: < > <= >= ==
//     ...commands...
//   end
//   if ultrasonic <op> <cm>:
//     ...commands...
//   end
//   # comment

struct ScriptParser {

    func parse(_ source: String) throws -> [ScriptCommand] {
        let lines = source.components(separatedBy: "\n")
        var result: [ScriptCommand] = []
        var i = 0
        while i < lines.count {
            let (cmd, consumed) = try parseLine(lines: lines, at: i)
            if let cmd { result.append(cmd) }
            i += consumed
        }
        return result
    }

    // Returns (parsed command or nil, lines consumed)
    private func parseLine(lines: [String], at i: Int) throws -> (ScriptCommand?, Int) {
        let raw = lines[i].trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, !raw.hasPrefix("#") else { return (nil, 1) }

        let lineNum = i + 1
        var tokens = raw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let kw = tokens[0].lowercased()

        switch kw {

        // ── Simple motion ──────────────────────────────────────────────
        case "forward":
            let (s, d) = try speedOptDuration(tokens, line: lineNum)
            return (.forward(speed: s, duration: d), 1)

        case "backward", "back":
            let (s, d) = try speedOptDuration(tokens, line: lineNum)
            return (.backward(speed: s, duration: d), 1)

        case "left", "arc_left":
            let (s, d) = try speedOptDuration(tokens, line: lineNum)
            return (.arcLeft(speed: s, duration: d), 1)

        case "right", "arc_right":
            let (s, d) = try speedOptDuration(tokens, line: lineNum)
            return (.arcRight(speed: s, duration: d), 1)

        case "spin_left":
            let (s, d) = try speedOptDuration(tokens, line: lineNum)
            return (.spinLeft(speed: s, duration: d), 1)

        case "spin_right":
            let (s, d) = try speedOptDuration(tokens, line: lineNum)
            return (.spinRight(speed: s, duration: d), 1)

        case "motors":
            guard tokens.count >= 3,
                  let l = Int(tokens[1]), let r = Int(tokens[2]) else {
                throw ScriptParseError(line: lineNum, message: "motors <left> <right> [<seconds>]")
            }
            let d = tokens.count >= 4 ? (Double(tokens[3]) ?? 0) : 0
            return (.motors(left: l, right: r, duration: d), 1)

        case "stop":
            let pause = tokens.count >= 2 ? (Double(tokens[1].trimmingCharacters(in: CharacterSet(charactersIn: ":"))) ?? 0) : 0
            return (.stop(pause: pause), 1)

        case "wait":
            guard tokens.count >= 2, let d = Double(tokens[1]) else {
                throw ScriptParseError(line: lineNum, message: "wait <seconds>")
            }
            return (.wait(duration: d), 1)

        // ── Blocks ────────────────────────────────────────────────────
        case "repeat":
            let countStr = (tokens.count >= 2 ? tokens[1] : "")
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard let count = Int(countStr), count > 0 else {
                throw ScriptParseError(line: lineNum, message: "repeat <count>:")
            }
            let (body, consumed) = try parseBlock(lines: lines, from: i + 1)
            return (.repeat_(count: count, body: body), 1 + consumed)

        case "while":
            // while ultrasonic < 30:
            let stripped = raw.dropFirst(kw.count).trimmingCharacters(in: .whitespaces)
            let (sensor, op, value) = try parseSensorCondition(stripped, line: lineNum)
            _ = sensor
            let (body, consumed) = try parseBlock(lines: lines, from: i + 1)
            return (.whileUltrasonic(op: op, cm: value, body: body), 1 + consumed)

        case "if":
            let stripped = raw.dropFirst(kw.count).trimmingCharacters(in: .whitespaces)
            let (sensor, op, value) = try parseSensorCondition(stripped, line: lineNum)
            _ = sensor
            let (body, consumed) = try parseBlock(lines: lines, from: i + 1)
            return (.ifUltrasonic(op: op, cm: value, body: body), 1 + consumed)

        default:
            throw ScriptParseError(line: lineNum, message: "Unknown command '\(kw)'")
        }
    }

    // Read all lines until "end" keyword; returns (commands, lines consumed including "end")
    private func parseBlock(lines: [String], from start: Int) throws -> ([ScriptCommand], Int) {
        var cmds: [ScriptCommand] = []
        var i = start
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces).lowercased()
            if line == "end" { return (cmds, i - start + 1) }
            let (cmd, consumed) = try parseLine(lines: lines, at: i)
            if let cmd { cmds.append(cmd) }
            i += consumed
        }
        throw ScriptParseError(line: start + 1, message: "Block is missing 'end'")
    }

    // Parse "ultrasonic < 30:" → ("ultrasonic", "<", 30.0)
    private func parseSensorCondition(_ text: String, line: Int) throws -> (String, String, Double) {
        let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let parts = stripped.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard parts.count >= 3,
              let value = Double(parts[2]) else {
            throw ScriptParseError(line: line, message: "Expected: while ultrasonic <op> <value>:")
        }
        return (parts[0], parts[1], value)
    }

    // Speed required, duration optional (defaults to 0 = non-blocking)
    private func speedOptDuration(_ tokens: [String], line: Int) throws -> (Int, Double) {
        guard tokens.count >= 2, let speed = Int(tokens[1]) else {
            throw ScriptParseError(line: line, message: "\(tokens[0]) requires a speed (0–255)")
        }
        let duration = tokens.count >= 3 ? (Double(tokens[2]) ?? 0) : 0
        return (speed, duration)
    }
}

// MARK: - Script Engine (executes parsed commands via BLE)

@MainActor
final class ScriptEngine: ObservableObject {

    // MARK: Published

    @Published var isRunning    = false
    @Published var log: [Entry] = []

    struct Entry: Identifiable {
        let id   = UUID()
        let text : String
        let kind : Kind
        enum Kind { case info, running, error, done }
    }

    // MARK: Private

    private var task: Task<Void, Never>?
    private weak var ble: MBotBLEManager?

    func attach(ble: MBotBLEManager) { self.ble = ble }

    // MARK: - Run / Stop

    func run(source: String) {
        guard !isRunning else { return }
        log.removeAll()

        let parser = ScriptParser()
        let commands: [ScriptCommand]
        do {
            commands = try parser.parse(source)
        } catch let e as ScriptParseError {
            emit(e.errorDescription ?? e.message, kind: .error); return
        } catch {
            emit(error.localizedDescription, kind: .error); return
        }

        if commands.isEmpty { emit("Nothing to run.", kind: .info); return }
        emit("▶ Starting (\(commands.count) top-level commands)…", kind: .info)
        isRunning = true

        task = Task {
            await executeAll(commands)
            ble?.stop()
            if !Task.isCancelled { emit("✓ Finished.", kind: .done) }
            isRunning = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        ble?.stop()
        isRunning = false
        emit("⏹ Stopped by user.", kind: .info)
    }

    // MARK: - Execution

    private func executeAll(_ cmds: [ScriptCommand]) async {
        for cmd in cmds {
            guard !Task.isCancelled else { return }
            await execute(cmd)
        }
    }

    private func execute(_ cmd: ScriptCommand) async {
        guard !Task.isCancelled else { return }
        switch cmd {

        case .forward(let s, let d):
            emit("→ forward  \(s)  \(dStr(d))", kind: .running)
            ble?.drive(left: s, right: s)
            await pause(d)

        case .backward(let s, let d):
            emit("← backward  \(s)  \(dStr(d))", kind: .running)
            ble?.drive(left: -s, right: -s)
            await pause(d)

        case .arcLeft(let s, let d):
            emit("↖ arc-left  \(s)  \(dStr(d))", kind: .running)
            ble?.drive(left: s / 2, right: s)  // right faster → curves left
            await pause(d)

        case .arcRight(let s, let d):
            emit("↗ arc-right  \(s)  \(dStr(d))", kind: .running)
            ble?.drive(left: s, right: s / 2)
            await pause(d)

        case .spinLeft(let s, let d):
            emit("↺ spin-left  \(s)  \(dStr(d))", kind: .running)
            ble?.drive(left: -s, right: s)
            await pause(d)

        case .spinRight(let s, let d):
            emit("↻ spin-right  \(s)  \(dStr(d))", kind: .running)
            ble?.drive(left: s, right: -s)
            await pause(d)

        case .motors(let l, let r, let d):
            emit("⚙ motors L=\(l) R=\(r)  \(dStr(d))", kind: .running)
            ble?.drive(left: l, right: r)
            await pause(d)

        case .stop(let p):
            emit("⏹ stop\(p > 0 ? " \(p)s" : "")", kind: .running)
            ble?.stop()
            if p > 0 { await pause(p) }

        case .wait(let d):
            emit("⏳ wait  \(d)s", kind: .running)
            ble?.stop()
            await pause(d)

        case .repeat_(let count, let body):
            for i in 1...count {
                guard !Task.isCancelled else { return }
                emit("🔁 repeat \(i)/\(count)", kind: .running)
                await executeAll(body)
            }

        case .whileUltrasonic(let op, let cm, let body):
            emit("🔄 while ultrasonic \(op) \(cm)cm", kind: .running)
            var iters = 0
            while !Task.isCancelled {
                let dist = Double(ble?.ultrasonicCM ?? 0)
                guard dist > 0, compare(dist, op: op, rhs: cm) else { break }
                iters += 1
                if iters > 2000 { emit("⚠ while: safety limit (2000 iters)", kind: .error); break }
                await executeAll(body)
            }

        case .ifUltrasonic(let op, let cm, let body):
            let dist = Double(ble?.ultrasonicCM ?? 0)
            emit("? if ultrasonic \(op) \(cm)cm → \(compare(dist, op: op, rhs: cm) ? "true" : "false")", kind: .running)
            if compare(dist, op: op, rhs: cm) { await executeAll(body) }
        }
    }

    // MARK: - Helpers

    private func compare(_ lhs: Double, op: String, rhs: Double) -> Bool {
        switch op {
        case "<":  return lhs < rhs
        case ">":  return lhs > rhs
        case "<=": return lhs <= rhs
        case ">=": return lhs >= rhs
        case "==": return abs(lhs - rhs) < 1
        default:   return false
        }
    }

    private func pause(_ seconds: Double) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func dStr(_ d: Double) -> String {
        d > 0 ? "\(d)s" : ""
    }

    private func emit(_ text: String, kind: Entry.Kind) {
        log.append(Entry(text: text, kind: kind))
    }
}
