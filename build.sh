#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release 2>/dev/null
mkdir -p bin
cp "$(swift build -c release --show-bin-path)/fledge-json" bin/fledge-json
