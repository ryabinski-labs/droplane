#!/bin/bash
# Builds and runs the mutation fuzzer for the parsers that read phone data.
# Usage: ./scripts/fuzz.sh [seconds]
set -euo pipefail
cd "$(dirname "$0")/.."

SECONDS_TO_RUN="${1:-60}"
OUT="${FUZZ_OUT:-.build/fuzz-droplane}"
mkdir -p "$(dirname "$OUT")"

swiftc -O -g -sanitize=address -parse-as-library \
    Sources/TransferCore/*.swift Fuzz/JPEGDimensionsFuzz.swift Fuzz/FuzzMain.swift \
    -o "$OUT"

"$OUT" "$SECONDS_TO_RUN"
