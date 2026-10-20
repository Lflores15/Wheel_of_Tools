import Foundation

/// Appends a line to ~/Library/Logs/WheelOfTools.log (handy because the app has no console).
func log(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WheelOfTools.log")
    let line = "\(Date()) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}
