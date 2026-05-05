import Foundation

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

func serializeJSON(_ obj: Any, prettyPrint: Bool, sortKeys: Bool, indent: Int = 2) -> String {
    var opts: JSONSerialization.WritingOptions = [.fragmentsAllowed]
    if prettyPrint { opts.insert(.prettyPrinted) }
    if sortKeys { opts.insert(.sortedKeys) }
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: opts) else {
        exitWithError("could not serialize JSON")
    }
    var result = String(data: data, encoding: .utf8) ?? ""
    // Re-indent if the requested indent differs from the system default.
    // Detect the system default by looking at the first indented line.
    if prettyPrint {
        let lines = result.components(separatedBy: "\n")
        var systemIndent = 2
        for line in lines {
            var leading = 0
            for ch in line {
                if ch == " " { leading += 1 } else { break }
            }
            if leading > 0 { systemIndent = leading; break }
        }
        if indent != systemIndent {
            let indentStr = String(repeating: " ", count: indent)
            let mapped = lines.map { line -> String in
                var leading = 0
                for ch in line {
                    if ch == " " { leading += 1 } else { break }
                }
                guard leading > 0 else { return line }
                let level = leading / systemIndent
                let remainder = leading % systemIndent
                let newLeading = String(repeating: indentStr, count: level) + String(repeating: " ", count: remainder)
                return newLeading + String(line.dropFirst(leading))
            }
            result = mapped.joined(separator: "\n")
        }
    }
    return result
}

// MARK: - Argument parsing helpers

struct Args {
    let raw: [String]
    var positional: [String] = []
    var flags: Set<String> = []
    var options: [String: String] = [:]

    init(_ args: [String]) {
        self.raw = args
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--" {
                positional.append(contentsOf: args[(i+1)...])
                break
            } else if arg.hasPrefix("--") {
                let name = String(arg.dropFirst(2))
                // Check if next arg is a value (not another flag)
                if i + 1 < args.count && !args[i+1].hasPrefix("--") {
                    // Could be a flag or an option with value
                    // Known value-taking options:
                    let valueOptions: Set<String> = ["indent"]
                    if valueOptions.contains(name) {
                        options[name] = args[i+1]
                        i += 2
                        continue
                    }
                }
                flags.insert(name)
            } else {
                positional.append(arg)
            }
            i += 1
        }
    }

    func hasFlag(_ name: String) -> Bool { flags.contains(name) }
    func option(_ name: String) -> String? { options[name] }
}

// MARK: - JSON path query

func queryPath(_ obj: Any, path: String) -> Any? {
    guard path.hasPrefix(".") else {
        exitWithError("query path must start with '.'")
    }
    let stripped = String(path.dropFirst()) // remove leading dot
    if stripped.isEmpty { return obj }

    var current: Any = obj
    // Tokenize: split on '.' but handle array indices like [0]
    let tokens = tokenize(stripped)
    for token in tokens {
        if let idx = parseArrayIndex(token) {
            guard let arr = current as? [Any] else {
                return nil
            }
            guard idx >= 0 && idx < arr.count else {
                return nil
            }
            current = arr[idx]
        } else if token.contains("[") {
            // e.g. "array[0]"
            let parts = token.split(separator: "[", maxSplits: 1)
            let key = String(parts[0])
            let idxStr = String(parts[1].dropLast()) // remove ']'
            guard let dict = current as? [String: Any], let next = dict[key] else {
                return nil
            }
            guard let arr = next as? [Any], let idx = Int(idxStr), idx >= 0, idx < arr.count else {
                return nil
            }
            current = arr[idx]
        } else {
            guard let dict = current as? [String: Any], let next = dict[token] else {
                return nil
            }
            current = next
        }
    }
    return current
}

func tokenize(_ path: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var bracketDepth = 0
    for ch in path {
        if ch == "[" { bracketDepth += 1; current.append(ch) }
        else if ch == "]" { bracketDepth -= 1; current.append(ch) }
        else if ch == "." && bracketDepth == 0 {
            if !current.isEmpty { tokens.append(current) }
            current = ""
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

func parseArrayIndex(_ token: String) -> Int? {
    // Pure index like "[0]"
    if token.hasPrefix("[") && token.hasSuffix("]") {
        return Int(token.dropFirst().dropLast())
    }
    return nil
}

// MARK: - JSON diff

struct DiffEntry {
    enum Kind: String { case added, removed, changed }
    let path: String
    let kind: Kind
    let oldValue: Any?
    let newValue: Any?
}

func diffJSON(_ a: Any, _ b: Any, path: String = "") -> [DiffEntry] {
    var results: [DiffEntry] = []

    if let dictA = a as? [String: Any], let dictB = b as? [String: Any] {
        let allKeys = Set(dictA.keys).union(dictB.keys).sorted()
        for key in allKeys {
            let childPath = path.isEmpty ? ".\(key)" : "\(path).\(key)"
            if let va = dictA[key], let vb = dictB[key] {
                results.append(contentsOf: diffJSON(va, vb, path: childPath))
            } else if let _ = dictA[key] {
                results.append(DiffEntry(path: childPath, kind: .removed, oldValue: dictA[key], newValue: nil))
            } else {
                results.append(DiffEntry(path: childPath, kind: .added, oldValue: nil, newValue: dictB[key]))
            }
        }
    } else if let arrA = a as? [Any], let arrB = b as? [Any] {
        let maxLen = max(arrA.count, arrB.count)
        for i in 0..<maxLen {
            let childPath = "\(path)[\(i)]"
            if i < arrA.count && i < arrB.count {
                results.append(contentsOf: diffJSON(arrA[i], arrB[i], path: childPath))
            } else if i < arrA.count {
                results.append(DiffEntry(path: childPath, kind: .removed, oldValue: arrA[i], newValue: nil))
            } else {
                results.append(DiffEntry(path: childPath, kind: .added, oldValue: nil, newValue: arrB[i]))
            }
        }
    } else {
        // Compare scalars
        if !isEqual(a, b) {
            results.append(DiffEntry(path: path.isEmpty ? "." : path, kind: .changed, oldValue: a, newValue: b))
        }
    }
    return results
}

func isEqual(_ a: Any, _ b: Any) -> Bool {
    switch (a, b) {
    case (let a as NSNumber, let b as NSNumber): return a == b
    case (let a as String, let b as String): return a == b
    case (is NSNull, is NSNull): return true
    case (let a as [Any], let b as [Any]):
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { isEqual($0, $1) }
    case (let a as [String: Any], let b as [String: Any]):
        guard a.count == b.count else { return false }
        return a.keys.allSatisfy { key in
            guard let va = a[key], let vb = b[key] else { return false }
            return isEqual(va, vb)
        }
    default: return false
    }
}

func valueToString(_ v: Any?) -> String {
    guard let v = v else { return "null" }
    if v is NSNull { return "null" }
    if let s = v as? String { return "\"\(s)\"" }
    if let data = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]),
       let s = String(data: data, encoding: .utf8) { return s }
    return "\(v)"
}

// MARK: - JSON type info

func jsonTypeName(_ obj: Any) -> String {
    switch obj {
    case is [String: Any]: return "object"
    case is [Any]: return "array"
    case is String: return "string"
    case is NSNull: return "null"
    case let n as NSNumber:
        if CFBooleanGetTypeID() == CFGetTypeID(n) { return "boolean" }
        return "number"
    default: return "unknown"
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
