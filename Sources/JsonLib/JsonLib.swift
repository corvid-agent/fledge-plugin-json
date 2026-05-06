import Foundation

// MARK: - Argument parsing helpers

public struct Args {
    public let raw: [String]
    public var positional: [String] = []
    public var flags: Set<String> = []
    public var options: [String: String] = [:]

    public init(_ args: [String]) {
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

    public func hasFlag(_ name: String) -> Bool { flags.contains(name) }
    public func option(_ name: String) -> String? { options[name] }
}

// MARK: - JSON serialization

public func serializeJSON(_ obj: Any, prettyPrint: Bool, sortKeys: Bool, indent: Int = 2) -> String {
    var opts: JSONSerialization.WritingOptions = [.fragmentsAllowed]
    if prettyPrint { opts.insert(.prettyPrinted) }
    if sortKeys { opts.insert(.sortedKeys) }
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: opts) else {
        return ""
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

// MARK: - JSON path query

public func queryPath(_ obj: Any, path: String) -> Any? {
    guard path.hasPrefix(".") else {
        return nil
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

public func tokenize(_ path: String) -> [String] {
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

public func parseArrayIndex(_ token: String) -> Int? {
    // Pure index like "[0]"
    if token.hasPrefix("[") && token.hasSuffix("]") {
        return Int(token.dropFirst().dropLast())
    }
    return nil
}

// MARK: - JSON diff

public struct DiffEntry {
    public enum Kind: String { case added, removed, changed }
    public let path: String
    public let kind: Kind
    public let oldValue: Any?
    public let newValue: Any?

    public init(path: String, kind: Kind, oldValue: Any?, newValue: Any?) {
        self.path = path
        self.kind = kind
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

public func diffJSON(_ a: Any, _ b: Any, path: String = "") -> [DiffEntry] {
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

public func isEqual(_ a: Any, _ b: Any) -> Bool {
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

public func valueToString(_ v: Any?) -> String {
    guard let v = v else { return "null" }
    if v is NSNull { return "null" }
    if let s = v as? String { return "\"\(s)\"" }
    if let data = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]),
       let s = String(data: data, encoding: .utf8) { return s }
    return "\(v)"
}

// MARK: - JSON type info

public func jsonTypeName(_ obj: Any) -> String {
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
