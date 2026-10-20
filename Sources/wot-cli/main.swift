import Foundation
import WheelCore

// Headless driver for testing: wot-cli convert <file> <ext> | wot-cli tool <name> <files...> | wot-cli formats <file>
let args = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1) }

guard let command = args.first else { fail("usage: wot-cli convert|tool|formats ...") }
do {
    switch command {
    case "formats":
        print(Converter.formats(for: URL(fileURLWithPath: args[1])).joined(separator: " "))
    case "convert":
        for url in try Converter.convert(URL(fileURLWithPath: args[1]), to: args[2]) { print(url.path) }
    case "tool":
        guard let tool = Tool(rawValue: args[1]) else { fail("unknown tool \(args[1])") }
        let result = try Tools.run(tool, on: args.dropFirst(2).map { URL(fileURLWithPath: $0) })
        result.outputs.forEach { print($0.path) }
        if let text = result.text { print(text) }
    default: fail("unknown command")
    }
} catch {
    fail("error: \(error.localizedDescription)")
}
