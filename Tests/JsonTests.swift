import Testing
import Foundation
@testable import JsonLib

// MARK: - tokenize

@Suite("tokenize")
struct TokenizeTests {
    @Test func simplePath() {
        #expect(tokenize("name") == ["name"])
    }

    @Test func nestedPath() {
        #expect(tokenize("a.b.c") == ["a", "b", "c"])
    }

    @Test func arrayIndex() {
        #expect(tokenize("items[0]") == ["items[0]"])
    }

    @Test func mixedPath() {
        #expect(tokenize("users[0].name") == ["users[0]", "name"])
    }

    @Test func pureIndex() {
        #expect(tokenize("[2]") == ["[2]"])
    }

    @Test func nestedArrayPath() {
        #expect(tokenize("a.b[1].c[2].d") == ["a", "b[1]", "c[2]", "d"])
    }
}

// MARK: - parseArrayIndex

@Suite("parseArrayIndex")
struct ParseArrayIndexTests {
    @Test func validIndices() {
        #expect(parseArrayIndex("[0]") == 0)
        #expect(parseArrayIndex("[5]") == 5)
        #expect(parseArrayIndex("[42]") == 42)
    }

    @Test func nonIndices() {
        #expect(parseArrayIndex("name") == nil)
        #expect(parseArrayIndex("items[0]") == nil)
        #expect(parseArrayIndex("0") == nil)
    }

    @Test func invalidNumber() {
        #expect(parseArrayIndex("[abc]") == nil)
    }
}

// MARK: - queryPath

@Suite("queryPath")
struct QueryPathTests {
    let sample: [String: Any] = [
        "name": "test",
        "nested": ["key": "value"] as [String: Any],
        "items": [1, 2, 3] as [Any],
        "users": [
            ["name": "alice", "age": 30] as [String: Any],
            ["name": "bob", "age": 25] as [String: Any],
        ] as [Any],
    ]

    @Test func rootPath() {
        let result = queryPath(sample, path: ".")
        #expect(result != nil)
        #expect(result is [String: Any])
    }

    @Test func simpleKey() {
        let result = queryPath(sample, path: ".name")
        #expect(result as? String == "test")
    }

    @Test func nestedKey() {
        let result = queryPath(sample, path: ".nested.key")
        #expect(result as? String == "value")
    }

    @Test func arrayAccess() {
        let result = queryPath(sample, path: ".items[1]")
        #expect(result as? Int == 2)
    }

    @Test func combinedAccess() {
        let result = queryPath(sample, path: ".users[0].name")
        #expect(result as? String == "alice")
    }

    @Test func secondElement() {
        let result = queryPath(sample, path: ".users[1].age")
        #expect(result as? Int == 25)
    }

    @Test func missingKey() {
        let result = queryPath(sample, path: ".nonexistent")
        #expect(result == nil)
    }

    @Test func missingNestedKey() {
        let result = queryPath(sample, path: ".nested.missing")
        #expect(result == nil)
    }

    @Test func outOfBoundsIndex() {
        let result = queryPath(sample, path: ".items[10]")
        #expect(result == nil)
    }

    @Test func invalidPathNoLeadingDot() {
        let result = queryPath(sample, path: "name")
        #expect(result == nil)
    }

    @Test func pureArrayIndex() {
        let arr: [Any] = ["a", "b", "c"]
        let result = queryPath(arr, path: ".[1]")
        #expect(result as? String == "b")
    }
}

// MARK: - diffJSON

@Suite("diffJSON")
struct DiffJSONTests {
    @Test func identicalObjects() {
        let a: [String: Any] = ["x": 1, "y": "hello"]
        let b: [String: Any] = ["x": 1, "y": "hello"]
        let diffs = diffJSON(a, b)
        #expect(diffs.isEmpty)
    }

    @Test func addedKey() {
        let a: [String: Any] = ["x": 1]
        let b: [String: Any] = ["x": 1, "y": 2]
        let diffs = diffJSON(a, b)
        #expect(diffs.count == 1)
        #expect(diffs[0].kind == .added)
        #expect(diffs[0].path == ".y")
    }

    @Test func removedKey() {
        let a: [String: Any] = ["x": 1, "y": 2]
        let b: [String: Any] = ["x": 1]
        let diffs = diffJSON(a, b)
        #expect(diffs.count == 1)
        #expect(diffs[0].kind == .removed)
        #expect(diffs[0].path == ".y")
    }

    @Test func changedValue() {
        let a: [String: Any] = ["x": 1]
        let b: [String: Any] = ["x": 2]
        let diffs = diffJSON(a, b)
        #expect(diffs.count == 1)
        #expect(diffs[0].kind == .changed)
        #expect(diffs[0].path == ".x")
    }

    @Test func nestedDiff() {
        let a: [String: Any] = ["outer": ["inner": 1] as [String: Any]]
        let b: [String: Any] = ["outer": ["inner": 2] as [String: Any]]
        let diffs = diffJSON(a, b)
        #expect(diffs.count == 1)
        #expect(diffs[0].path == ".outer.inner")
        #expect(diffs[0].kind == .changed)
    }

    @Test func arrayDiffChanged() {
        let a: [Any] = [1, 2, 3]
        let b: [Any] = [1, 9, 3]
        let diffs = diffJSON(a, b)
        #expect(diffs.count == 1)
        #expect(diffs[0].path == "[1]")
        #expect(diffs[0].kind == .changed)
    }

    @Test func arrayDiffAdded() {
        let a: [Any] = [1, 2]
        let b: [Any] = [1, 2, 3]
        let diffs = diffJSON(a, b)
        #expect(diffs.count == 1)
        #expect(diffs[0].path == "[2]")
        #expect(diffs[0].kind == .added)
    }

    @Test func arrayDiffRemoved() {
        let a: [Any] = [1, 2, 3]
        let b: [Any] = [1, 2]
        let diffs = diffJSON(a, b)
        #expect(diffs.count == 1)
        #expect(diffs[0].path == "[2]")
        #expect(diffs[0].kind == .removed)
    }

    @Test func scalarDiff() {
        let diffs = diffJSON("hello" as Any, "world" as Any)
        #expect(diffs.count == 1)
        #expect(diffs[0].kind == .changed)
        #expect(diffs[0].path == ".")
    }

    @Test func identicalScalars() {
        let diffs = diffJSON(42 as Any, 42 as Any)
        #expect(diffs.isEmpty)
    }
}

// MARK: - isEqual

@Suite("isEqual")
struct IsEqualTests {
    @Test func equalStrings() {
        #expect(isEqual("abc" as Any, "abc" as Any))
    }

    @Test func differentStrings() {
        #expect(!isEqual("abc" as Any, "xyz" as Any))
    }

    @Test func equalNumbers() {
        #expect(isEqual(42 as Any, 42 as Any))
    }

    @Test func differentNumbers() {
        #expect(!isEqual(1 as Any, 2 as Any))
    }

    @Test func equalNulls() {
        #expect(isEqual(NSNull() as Any, NSNull() as Any))
    }

    @Test func equalArrays() {
        #expect(isEqual([1, 2, 3] as Any, [1, 2, 3] as Any))
    }

    @Test func differentArrays() {
        #expect(!isEqual([1, 2] as Any, [1, 3] as Any))
    }

    @Test func differentArrayLengths() {
        #expect(!isEqual([1, 2] as Any, [1, 2, 3] as Any))
    }

    @Test func equalObjects() {
        let a: [String: Any] = ["x": 1, "y": "hello"]
        let b: [String: Any] = ["x": 1, "y": "hello"]
        #expect(isEqual(a as Any, b as Any))
    }

    @Test func differentObjects() {
        let a: [String: Any] = ["x": 1]
        let b: [String: Any] = ["x": 2]
        #expect(!isEqual(a as Any, b as Any))
    }

    @Test func differentTypes() {
        #expect(!isEqual("1" as Any, 1 as Any))
    }
}

// MARK: - valueToString

@Suite("valueToString")
struct ValueToStringTests {
    @Test func nullValue() {
        #expect(valueToString(nil) == "null")
    }

    @Test func nsNull() {
        #expect(valueToString(NSNull()) == "null")
    }

    @Test func stringValue() {
        #expect(valueToString("hello" as Any) == "\"hello\"")
    }

    @Test func numberValue() {
        #expect(valueToString(42 as Any) == "42")
    }

    @Test func arrayValue() {
        #expect(valueToString([1, 2, 3] as Any) == "[1,2,3]")
    }

    @Test func objectValue() {
        #expect(valueToString(["a": 1] as Any) == "{\"a\":1}")
    }
}

// MARK: - jsonTypeName

@Suite("jsonTypeName")
struct JsonTypeNameTests {
    @Test func objectType() {
        #expect(jsonTypeName(["key": "value"] as [String: Any]) == "object")
    }

    @Test func arrayType() {
        #expect(jsonTypeName([1, 2, 3] as [Any]) == "array")
    }

    @Test func stringType() {
        #expect(jsonTypeName("hello" as Any) == "string")
    }

    @Test func numberType() {
        #expect(jsonTypeName(42 as Any) == "number")
    }

    @Test func booleanType() {
        #expect(jsonTypeName(kCFBooleanTrue as Any) == "boolean")
    }

    @Test func nullType() {
        #expect(jsonTypeName(NSNull() as Any) == "null")
    }
}

// MARK: - serializeJSON

@Suite("serializeJSON")
struct SerializeJSONTests {
    @Test func prettyPrint() {
        let obj: [String: Any] = ["name": "test"]
        let result = serializeJSON(obj, prettyPrint: true, sortKeys: false)
        #expect(result.contains("\n"))
        #expect(result.contains("name"))
        #expect(result.contains("test"))
    }

    @Test func minified() {
        let obj: [String: Any] = ["name": "test"]
        let result = serializeJSON(obj, prettyPrint: false, sortKeys: false)
        #expect(!result.contains("\n"))
        #expect(result.contains("name"))
    }

    @Test func sortedKeys() {
        let obj: [String: Any] = ["z": 1, "a": 2, "m": 3]
        let result = serializeJSON(obj, prettyPrint: false, sortKeys: true)
        // Keys should appear in order: a, m, z
        if let aPos = result.range(of: "\"a\""),
           let mPos = result.range(of: "\"m\""),
           let zPos = result.range(of: "\"z\"") {
            #expect(aPos.lowerBound < mPos.lowerBound)
            #expect(mPos.lowerBound < zPos.lowerBound)
        } else {
            Issue.record("Missing keys in output: \(result)")
        }
    }

    @Test func customIndent() {
        let obj: [String: Any] = ["key": "value"]
        let result = serializeJSON(obj, prettyPrint: true, sortKeys: false, indent: 4)
        #expect(result.contains("    "))
    }

    @Test func defaultIndent() {
        let obj: [String: Any] = ["key": "value"]
        let result = serializeJSON(obj, prettyPrint: true, sortKeys: false, indent: 2)
        let lines = result.components(separatedBy: "\n")
        let indentedLines = lines.filter { $0.hasPrefix(" ") }
        for line in indentedLines {
            var leading = 0
            for ch in line {
                if ch == " " { leading += 1 } else { break }
            }
            #expect(leading % 2 == 0, "Indentation should be multiples of 2, got \(leading)")
        }
    }

    @Test func stringFragment() {
        let result = serializeJSON("hello" as Any, prettyPrint: false, sortKeys: false)
        #expect(result == "\"hello\"")
    }

    @Test func numberFragment() {
        let result = serializeJSON(42 as Any, prettyPrint: false, sortKeys: false)
        #expect(result == "42")
    }
}

// MARK: - Args

@Suite("Args")
struct ArgsTests {
    @Test func flagParsing() {
        let args = Args(["--sort-keys", "--help"])
        #expect(args.hasFlag("sort-keys"))
        #expect(args.hasFlag("help"))
        #expect(!args.hasFlag("verbose"))
        #expect(args.positional.isEmpty)
    }

    @Test func optionParsing() {
        let args = Args(["--indent", "4", "file.json"])
        #expect(args.option("indent") == "4")
        #expect(args.positional == ["file.json"])
    }

    @Test func positionalArgs() {
        let args = Args(["file1.json", "file2.json"])
        #expect(args.positional == ["file1.json", "file2.json"])
        #expect(args.flags.isEmpty)
    }

    @Test func mixedArgs() {
        let args = Args(["--sort-keys", "--indent", "4", "file.json", "--help"])
        #expect(args.hasFlag("sort-keys"))
        #expect(args.hasFlag("help"))
        #expect(args.option("indent") == "4")
        #expect(args.positional == ["file.json"])
    }

    @Test func doubleDashSeparator() {
        let args = Args(["--sort-keys", "--", "--not-a-flag", "file.json"])
        #expect(args.hasFlag("sort-keys"))
        #expect(!args.hasFlag("not-a-flag"))
        #expect(args.positional == ["--not-a-flag", "file.json"])
    }

    @Test func emptyArgs() {
        let args = Args([])
        #expect(args.positional.isEmpty)
        #expect(args.flags.isEmpty)
        #expect(args.options.isEmpty)
    }

    @Test func unknownOptionTreatedAsFlag() {
        let args = Args(["--verbose", "file.json"])
        #expect(args.hasFlag("verbose"))
        #expect(args.positional == ["file.json"])
    }
}
