#!/usr/bin/env bash
#
# PostToolUse hook — instant syntax feedback after editing a Swift file.
# Parses ONLY the file that was just edited (fast: syntax, not whole-module
# type resolution). On a syntax error, exit 2 so the message is fed back to
# Claude immediately. Deeper type errors are caught later by the Stop gate.
#
# Reads the hook JSON on stdin and pulls tool_input.file_path.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

file="$(python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("file_path", ""))
except Exception:
    print("")
' 2>/dev/null)"

# Only Swift files (the `if` matcher should already ensure this).
case "$file" in
  *.swift) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)" || exit 0
[ -z "$SDK" ] && exit 0

errors="$(xcrun --sdk iphoneos swiftc -parse -sdk "$SDK" \
  -target arm64-apple-ios17.0 "$file" 2>&1)"
status=$?
[ "$status" -eq 0 ] && exit 0

# Syntax error → surface to Claude (exit 2 feeds stderr back).
{
  echo "Swift 構文エラー（${file}）— 修正してください:"
  printf '%s\n' "$errors" | grep -E 'error:' | head -n 15
} >&2
exit 2
