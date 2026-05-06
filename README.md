# fledge-plugin-json

JSON toolkit plugin for [fledge](https://github.com/CorvidLabs/fledge) -- format, minify, validate, query, diff, and inspect JSON from the terminal.

## Install

```bash
fledge plugins install corvid-agent/fledge-plugin-json
```

## Commands

### fmt -- Format / pretty-print

```bash
# Pretty-print a file with default 2-space indent
fledge json fmt data.json

# Custom indent width
fledge json fmt data.json --indent 4

# Sort keys alphabetically
fledge json fmt data.json --sort-keys

# Format in place (overwrites the file)
fledge json fmt data.json --in-place

# Read from stdin
cat data.json | fledge json fmt
```

### min -- Minify

```bash
# Remove all whitespace
fledge json min data.json

# From stdin
cat data.json | fledge json min
```

### validate -- Validate syntax

Exits with code 0 for valid JSON, 1 for invalid.

```bash
# Human-readable output
fledge json validate config.json
# => config.json: valid JSON

# Machine-readable output
fledge json validate config.json --json
# => {"valid":true,"file":"config.json"}

# From stdin
echo '{"ok": true}' | fledge json validate
```

### query -- Dot-path query

Extract values using dot-path syntax: `.key`, `.nested.key`, `.array[0]`, `.array[0].name`.

```bash
# Query a nested key
fledge json query .name data.json
# => "alice"

# Raw string output (no quotes)
fledge json query .name data.json --raw
# => alice

# Array access
fledge json query .items[0] data.json

# Combined access
fledge json query .users[1].email data.json
```

### diff -- Semantic diff

Compare two JSON files semantically (ignoring formatting). Shows added, removed, and changed keys.

```bash
# Human-readable diff
fledge json diff a.json b.json
# + .newKey: "value"
# - .removedKey: 42
# ~ .changedKey: "old" -> "new"

# Machine-readable output
fledge json diff a.json b.json --json
```

### type -- Show top-level type

```bash
fledge json type data.json
# => object (3 keys)

fledge json type list.json
# => array (length 5)

# Machine-readable output
echo '42' | fledge json type --json
# => {"type":"number"}
```

## Development

Requires Swift 6.0+.

```bash
swift build
swift test
```

## Architecture

The codebase is split into two targets:

- **JsonLib** (`Sources/JsonLib/`) -- pure functions for JSON serialization, querying, diffing, type inspection, and argument parsing. No I/O or process exit calls.
- **fledge-json** (`Sources/main.swift`) -- CLI entry point, I/O helpers, and command dispatch. Imports JsonLib.

Tests in `Tests/JsonTests.swift` cover all public functions in JsonLib.

## License

MIT
