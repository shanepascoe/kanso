import SwiftUI

// MARK: - Code Editor View

struct CodeEditorView: View {

    @EnvironmentObject var ble:    MBotBLEManager
    @EnvironmentObject var engine: ScriptEngine

    @State private var code = Examples.starter
    @State private var showHelp  = false
    @State private var showSave  = false
    @State private var saveName  = ""
    @AppStorage("mbot_saved_scripts") private var savedJSON = "[]"

    private var savedScripts: [SavedScript] {
        (try? JSONDecoder().decode([SavedScript].self, from: Data(savedJSON.utf8))) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            editorAndConsole
        }
        .navigationTitle("Code")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHelp)  { HelpSheet() }
        .sheet(isPresented: $showSave)  { saveSheet }
        .onAppear { engine.attach(ble: ble) }
    }

    // MARK: - Toolbar

    var toolbar: some View {
        HStack(spacing: 10) {

            // Examples menu
            Menu {
                Section("Examples") {
                    ForEach(Examples.all) { ex in
                        Button(ex.name) { code = ex.code }
                    }
                }
                if !savedScripts.isEmpty {
                    Section("Saved") {
                        ForEach(savedScripts) { s in
                            Button(s.name) { code = s.code }
                        }
                    }
                }
            } label: {
                Label("Scripts", systemImage: "doc.text.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
            }

            Button { showSave = true } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.title3)
            }

            Button { showHelp = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(.title3)
            }

            Spacer()

            // BLE indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(ble.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(ble.isConnected ? "Connected" : "Not connected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Run / Stop
            Button {
                if engine.isRunning { engine.stop() }
                else                { engine.run(source: code) }
            } label: {
                Label(
                    engine.isRunning ? "Stop" : "Run",
                    systemImage: engine.isRunning ? "stop.circle.fill" : "play.circle.fill"
                )
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(engine.isRunning ? Color.red : Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                .font(.subheadline.bold())
            }
            .disabled(!ble.isConnected && !engine.isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Editor + Console

    var editorAndConsole: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // ── Editor ──────────────────────────────────
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $code)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .frame(height: geo.size.height * 0.58)
                        .overlay(
                            engine.isRunning
                                ? Color.black.opacity(0.03).allowsHitTesting(false)
                                : nil
                        )

                    if code.isEmpty {
                        Text("Write your mBot script here…")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                            .padding(.leading, 5)
                            .padding(.top, 9)
                            .allowsHitTesting(false)
                    }
                }

                Divider()

                // ── Console ──────────────────────────────────
                VStack(spacing: 0) {
                    consoleHeader
                    consoleLog
                }
                .frame(height: geo.size.height * 0.42)
            }
        }
    }

    var consoleHeader: some View {
        HStack {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Console")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            if engine.isRunning {
                ProgressView().scaleEffect(0.6)
            }
            Spacer()
            Button("Clear") { engine.log.removeAll() }
                .font(.caption)
                .foregroundColor(.blue)
                .disabled(engine.log.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
    }

    var consoleLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(engine.log) { entry in
                        Text(entry.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(entryColor(entry.kind))
                            .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .onChange(of: engine.log.count) { _ in
                withAnimation { proxy.scrollTo("bottom") }
            }
        }
        .background(Color(.systemBackground))
    }

    func entryColor(_ kind: ScriptEngine.Entry.Kind) -> Color {
        switch kind {
        case .info:    return .secondary
        case .running: return .primary
        case .error:   return .red
        case .done:    return .green
        }
    }

    // MARK: - Save sheet

    var saveSheet: some View {
        NavigationView {
            Form {
                Section("Script name") {
                    TextField("My Script", text: $saveName)
                }
                Section {
                    Button("Save") {
                        var scripts = savedScripts
                        scripts.append(SavedScript(name: saveName.isEmpty ? "Script \(scripts.count + 1)" : saveName, code: code))
                        if let data = try? JSONEncoder().encode(scripts) {
                            savedJSON = String(data: data, encoding: .utf8) ?? "[]"
                        }
                        showSave = false
                    }
                }
            }
            .navigationTitle("Save Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showSave = false }
                }
            }
        }
    }
}

// MARK: - Help Sheet

struct HelpSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpSection("Motion Commands", items: [
                        ("forward  <speed>  [<secs>]",   "Drive forward. Speed 0–255. Duration optional."),
                        ("backward <speed>  [<secs>]",   "Drive backward."),
                        ("left     <speed>  [<secs>]",   "Arc turn left (right wheel faster)."),
                        ("right    <speed>  [<secs>]",   "Arc turn right (left wheel faster)."),
                        ("spin_left  <speed>  [<secs>]", "Pivot left on the spot."),
                        ("spin_right <speed>  [<secs>]", "Pivot right on the spot."),
                        ("motors  <L> <R>  [<secs>]",    "Set left & right speeds independently."),
                        ("stop  [<secs>]",               "Stop motors. Optional pause after."),
                        ("wait  <secs>",                 "Stop motors and wait."),
                    ])

                    helpSection("Control Flow", items: [
                        ("repeat <N>:",              "Repeat the block N times."),
                        ("  ...commands...", ""),
                        ("end",              ""),
                        ("while ultrasonic <op> <cm>:", "Loop while ultrasonic sensor condition holds."),
                        ("  ...commands...", ""),
                        ("end",              ""),
                        ("if ultrasonic <op> <cm>:",     "Run block once if condition is true."),
                        ("  ...commands...", ""),
                        ("end",              ""),
                        ("# comment",        "Lines starting with # are ignored."),
                    ])

                    helpSection("Operators for conditions", items: [
                        ("<  >  <=  >=  ==", "Standard comparisons"),
                    ])

                    helpSection("Tips", items: [
                        ("Speed 0–255",          "Typical driving: 100–180"),
                        ("Duration 0 or omitted","Sets motors and continues immediately (useful inside while)"),
                        ("while + short forward", "Use forward without duration inside while loops to keep polling"),
                        ("Phone on robot",        "Place your phone on the robot, hit Run, it drives off!"),
                    ])

                    Group {
                        Text("Example — Square")
                            .font(.headline)
                        codeBlock("""
repeat 4:
  forward 150 2.0
  spin_right 100 0.85
end
stop""")

                        Text("Example — Avoid obstacle")
                            .font(.headline)
                        codeBlock("""
while ultrasonic > 20:
  forward 120
end
stop""")
                    }
                }
                .padding()
            }
            .navigationTitle("Script Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    func helpSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(items, id: \.0) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.0)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(minWidth: 120, alignment: .leading)
                    if !item.1.isEmpty {
                        Text(item.1)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    func codeBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
    }
}

// MARK: - Saved Script model

struct SavedScript: Codable, Identifiable {
    let id:   UUID
    let name: String
    let code: String
    init(name: String, code: String) {
        self.id   = UUID()
        self.name = name
        self.code = code
    }
}

// MARK: - Built-in examples

struct Examples {
    struct Example: Identifiable {
        let id   = UUID()
        let name : String
        let code : String
    }

    static let starter = """
# mBot Ranger Script
# Place phone on robot, tap Run, it drives off!
# Use ? button for command reference.

forward 150 2.0
spin_right 100 0.85
forward 150 2.0
spin_right 100 0.85
forward 150 2.0
spin_right 100 0.85
forward 150 2.0
spin_right 100 0.85
stop
"""

    static let all: [Example] = [
        Example(name: "Square", code: """
# Drive in a square
repeat 4:
  forward 150 2.0
  spin_right 100 0.85
end
stop
"""),
        Example(name: "Figure 8", code: """
# Figure 8
repeat 2:
  left 150 3.2
  right 150 3.2
end
stop
"""),
        Example(name: "Obstacle Avoid", code: """
# Drive forward, stop when obstacle < 20 cm
while ultrasonic > 20:
  forward 150
end
stop
"""),
        Example(name: "Obstacle & Turn", code: """
# Drive until obstacle, then turn and continue
forward 150

if ultrasonic < 25:
  stop
  spin_right 120 1.0
end

forward 150 1.5
stop
"""),
        Example(name: "Zigzag", code: """
# Zigzag pattern
repeat 6:
  forward 150 0.7
  spin_left 120 0.35
  forward 150 0.7
  spin_right 120 0.35
end
stop
"""),
        Example(name: "Circle", code: """
# Draw a circle (approx.)
left 140 6.5
stop
"""),
        Example(name: "Spiral", code: """
# Expanding spiral (increase speed each loop)
motors 80 120 1.0
motors 100 150 1.2
motors 120 180 1.4
motors 140 200 1.6
stop
"""),
        Example(name: "Dance", code: """
# Robot dance
spin_right 200 0.4
spin_left  200 0.4
spin_right 200 0.4
spin_left  200 0.4
forward 150 0.5
backward 150 0.5
stop
"""),
    ]
}
