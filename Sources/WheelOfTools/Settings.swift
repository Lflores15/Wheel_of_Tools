import SwiftUI
import ServiceManagement
import WheelCore

struct SettingsView: View {
    @State private var scale = Double(WheelView.scale)
    @State private var dragging = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    var onPreview: () -> Void
    @State private var deps = Dependencies.status()

    var body: some View {
        Form {
            Section("Wheel") {
                HStack {
                    Image(systemName: "circle").imageScale(.small)
                    Slider(value: $scale, in: 0.7...1.5) { editing in
                        dragging = editing
                        if !editing { onPreview() }
                    }
                    Image(systemName: "circle").imageScale(.large)
                }
                .onChange(of: scale) { _, value in
                    guard dragging else { return }   // only react to the user, not to layout
                    WheelView.scale = CGFloat(value)
                    UserDefaults.standard.set(value, forKey: "wheelScale")
                }
                Text("Size: \(Int(scale * 100))%").foregroundStyle(.secondary)
                Button("Preview Wheel", action: onPreview)
            }
            Section("Use") {
                Label("Drag a file in Finder, then hold ⇧ Shift to convert it", systemImage: "arrow.triangle.2.circlepath")
                Label("Hold ⌃ Control (or ⌥⇧) for tools: compress, crop, metadata…", systemImage: "wrench.and.screwdriver")
                Label("Drop the file on a button. The result appears beside the original.", systemImage: "square.and.arrow.down")
            }
            Section("Needed for some conversions") {
                ForEach(deps, id: \.name) { dep in
                    HStack {
                        Image(systemName: dep.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(dep.isInstalled ? .green : .orange)
                        VStack(alignment: .leading) {
                            Text(dep.name)
                            Text(dep.purpose).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let command = Dependencies.installCommand() {
                    Text(command).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    HStack {
                        Button("Copy Install Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(command, forType: .string)
                        }
                        Button("Check Again") { deps = Dependencies.status() }
                    }
                    Text("Pages, Numbers and Keynote are free in the App Store. Homebrew is from brew.sh.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Everything is installed.").foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
            }
        }
        .formStyle(.grouped)
        .onAppear { scale = Double(WheelView.scale) }   // a slider can clamp itself while the window lays out
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
