import Foundation
import JsonLib

// MARK: - Helpers

func printError(_ message: String) {
    let stderr = FileHandle.standardError
    stderr.write(Data("\(message)\n".utf8))
}

func exitWithError(_ message: String, code: Int32 = 1) -> Never {
    printError("error: \(message)")
    exit(code)
}

func readInput(filePath: String?) -> String {
    if let path = filePath {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            exitWithError("file not found: \(path)")
        }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            exitWithError("could not read file: \(path)")
        }
        return text
    } else {
        // Read from stdin
        var chunks: [Data] = []
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
        defer { buf.deallocate() }
        while true {
            let n = fread(buf, 1, 65536, stdin)
            if n == 0 { break }
            chunks.append(Data(bytes: buf, count: n))
        }
        let data = chunks.reduce(Data(), +)
        guard let text = String(data: data, encoding: .utf8) else {
            exitWithError("could not read stdin as UTF-8")
        }
        return text
    }
}

func parseJSON(_ text: String) -> Any {
    guard let data = text.data(using: .utf8) else {
        exitWithError("invalid UTF-8 input")
    }
    do {
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
        exitWithError("invalid JSON: \(error.localizedDescription)")
    }
}

// MARK: - Commands

func cmdFmt(_ args: Args) {
    if args.hasFlag("help") {
        print("""
        Usage: fledge json fmt [file] [options]

        Format/pretty-print JSON.

        Options:
          --indent N     Indentation width (default: 2)
          --in-place     Overwrite the file in place
          --sort-keys    Sort object keys alphabetically
          --help         Show this help
        """)
        return
    }

    let filePath = args.positional.first
    let indent = Int(args.option("indent") ?? "2") ?? 2
    let inPlace = args.hasFlag("in-place")
    let sortKeys = args.hasFlag("sort-keys")

    if inPlace && filePath == nil {
        exitWithError("--in-place requires a file argument")
    }

    let input = readInput(filePath: filePath)
    let obj = parseJSON(input)
    var output = serializeJSON(obj, prettyPrint: true, sortKeys: sortKeys, indent: indent)
    if !output.hasSuffix("\n") { output += "\n" }

    if inPlace, let path = filePath {
        do {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            exitWithError("could not write to \(path): \(error.localizedDescription)")
        }
    } else {
        print(output, terminator: "")
    }
}

func cmdMin(_ args: Args) {
    if args.hasFlag("help") {
        print("""
        Usage: fledge json min [file]

        Minify JSON (remove all whitespace).

        Options:
          --help    Show this help
        """)
        return
    }

    let filePath = args.positional.first
    let input = readInput(filePath: filePath)
    let obj = parseJSON(input)
    let output = serializeJSON(obj, prettyPrint: false, sortKeys: false)
    print(output)
}

func cmdValidate(_ args: Args) {
    if args.hasFlag("help") {
        print("""
        Usage: fledge json validate [file]

        Validate JSON and report result.
        Exit code 0 for valid, 1 for invalid.

        Options:
          --json    Output result as JSON
          --help    Show this help
        """)
        return
    }

    let filePath = args.positional.first
    let jsonOutput = args.hasFlag("json")
    let input = readInput(filePath: filePath)
    let label = filePath ?? "stdin"

    guard let data = input.data(using: .utf8) else {
        if jsonOutput {
            print("""
            {"valid":false,"file":"\(label)","error":"invalid UTF-8"}
            """)
        } else {
            printError("\(label): invalid (not valid UTF-8)")
        }
        exit(1)
    }

    do {
        _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if jsonOutput {
            print("{\"valid\":true,\"file\":\"\(label)\"}")
        } else {
            print("\(label): valid JSON")
        }
    } catch {
        if jsonOutput {
            let escaped = error.localizedDescription
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            print("{\"valid\":false,\"file\":\"\(label)\",\"error\":\"\(escaped)\"}")
        } else {
            printError("\(label): invalid (\(error.localizedDescription))")
        }
        exit(1)
    }
}

func cmdQuery(_ args: Args) {
    if args.hasFlag("help") {
        print("""
        Usage: fledge json query <path> [file]

        Query JSON with dot-path syntax.

        Paths: .key, .key.nested, .array[0], .array[0].name

        Options:
          --raw     Output raw string values without quotes
          --json    Output result as JSON
          --help    Show this help
        """)
        return
    }

    guard let queryPath_ = args.positional.first else {
        exitWithError("query requires a path argument (e.g. .key.nested)")
    }

    let filePath = args.positional.count > 1 ? args.positional[1] : nil
    let raw = args.hasFlag("raw")
    let input = readInput(filePath: filePath)
    let obj = parseJSON(input)

    guard let result = queryPath(obj, path: queryPath_) else {
        exitWithError("path '\(queryPath_)' not found")
    }

    if raw, let s = result as? String {
        print(s)
    } else {
        let output = serializeJSON(result, prettyPrint: true, sortKeys: false)
        print(output)
    }
}

func cmdDiff(_ args: Args) {
    if args.hasFlag("help") {
        print("""
        Usage: fledge json diff <file1> <file2>

        Compare two JSON files semantically.
        Shows added, removed, and changed keys.

        Options:
          --json    Output diff as JSON
          --help    Show this help
        """)
        return
    }

    guard args.positional.count >= 2 else {
        exitWithError("diff requires two file arguments")
    }

    let file1 = args.positional[0]
    let file2 = args.positional[1]
    let jsonOutput = args.hasFlag("json")

    let input1 = readInput(filePath: file1)
    let input2 = readInput(filePath: file2)
    let obj1 = parseJSON(input1)
    let obj2 = parseJSON(input2)

    let diffs = diffJSON(obj1, obj2)

    if diffs.isEmpty {
        if jsonOutput {
            print("{\"equal\":true,\"diffs\":[]}")
        } else {
            print("files are semantically equal")
        }
        return
    }

    if jsonOutput {
        var entries: [[String: Any]] = []
        for d in diffs {
            var entry: [String: Any] = ["path": d.path, "kind": d.kind.rawValue]
            if let old = d.oldValue { entry["old"] = old }
            if let new = d.newValue { entry["new"] = new }
            entries.append(entry)
        }
        let wrapper: [String: Any] = ["equal": false, "diffs": entries]
        let output = serializeJSON(wrapper, prettyPrint: true, sortKeys: true)
        print(output)
    } else {
        for d in diffs {
            switch d.kind {
            case .added:
                print("+ \(d.path): \(valueToString(d.newValue))")
            case .removed:
                print("- \(d.path): \(valueToString(d.oldValue))")
            case .changed:
                print("~ \(d.path): \(valueToString(d.oldValue)) -> \(valueToString(d.newValue))")
            }
        }
    }
}

func cmdType(_ args: Args) {
    if args.hasFlag("help") {
        print("""
        Usage: fledge json type [file]

        Show the top-level JSON type.
        For objects, shows key count. For arrays, shows length.

        Options:
          --json    Output as JSON
          --help    Show this help
        """)
        return
    }

    let filePath = args.positional.first
    let jsonOutput = args.hasFlag("json")
    let input = readInput(filePath: filePath)
    let obj = parseJSON(input)
    let typeName = jsonTypeName(obj)

    if jsonOutput {
        var info: [String: Any] = ["type": typeName]
        if let dict = obj as? [String: Any] { info["keys"] = dict.count }
        if let arr = obj as? [Any] { info["length"] = arr.count }
        let output = serializeJSON(info, prettyPrint: false, sortKeys: true)
        print(output)
    } else {
        var extra = ""
        if let dict = obj as? [String: Any] { extra = " (\(dict.count) keys)" }
        if let arr = obj as? [Any] { extra = " (length \(arr.count))" }
        print("\(typeName)\(extra)")
    }
}

func showHelp() {
    print("""
    fledge-json: JSON toolkit for fledge

    Usage: fledge json <command> [options]

    Commands:
      fmt       Format/pretty-print JSON
      min       Minify JSON (remove whitespace)
      validate  Validate JSON syntax
      query     Query JSON with dot-path syntax
      diff      Compare two JSON files semantically
      type      Show top-level JSON type

    Global options:
      --help    Show help for any command

    Examples:
      fledge json fmt data.json --indent 4
      fledge json min data.json
      fledge json validate config.json
      fledge json query .name data.json --raw
      fledge json diff a.json b.json --json
      cat data.json | fledge json type
    """)
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.isEmpty || arguments.first == "--help" || arguments.first == "-h" {
    showHelp()
    exit(0)
}

let command = arguments[0]
let rest = Array(arguments.dropFirst())
let args = Args(rest)

switch command {
case "fmt":
    cmdFmt(args)
case "min":
    cmdMin(args)
case "validate":
    cmdValidate(args)
case "query":
    cmdQuery(args)
case "diff":
    cmdDiff(args)
case "type":
    cmdType(args)
default:
    printError("unknown command: \(command)")
    showHelp()
    exit(1)
}
