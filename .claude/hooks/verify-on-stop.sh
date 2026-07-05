#!/usr/bin/env bash
#
# Stop hook — completion gate.
# If any Swift files changed in this working tree, typecheck the whole app
# module and BLOCK completion (JSON {"decision":"block"}) when it fails, so a
# session never ends on code that doesn't compile.
# Doc-only sessions (no Swift change) are a no-op — the gate stays quiet.
#
# Tuning: if this feels too heavy, remove the "Stop" entry from
# .claude/settings.json and rely on the PostToolUse parse-check instead.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Any *.swift changed? (unstaged + staged + untracked)
changed="$( {
  git diff --name-only -- '*.swift'
  git diff --cached --name-only -- '*.swift'
  git ls-files --others --exclude-standard -- '*.swift'
} 2>/dev/null | sort -u )"

[ -z "$changed" ] && exit 0   # doc-only session → no-op

SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)" || exit 0
[ -z "$SDK" ] && exit 0

# Whole-module typecheck (must include Capture/ — hence `find`, not BucketList/*.swift).
files="$(find BucketList -name '*.swift')"
errors="$(xcrun --sdk iphoneos swiftc -typecheck -sdk "$SDK" \
  -target arm64-apple-ios17.0 $files 2>&1)"
status=$?

[ "$status" -eq 0 ] && exit 0   # compiles → allow stop

# Failed → block completion, hand the errors back to Claude.
tail_errors="$(printf '%s' "$errors" | grep -E 'error:' | head -n 20)"
[ -z "$tail_errors" ] && tail_errors="$(printf '%s' "$errors" | tail -n 20)"
python3 - "$tail_errors" <<'PY'
import json, sys
msg = ("Swift の型チェックに失敗しています。完了する前に修正してください。\n"
       "（コマンド: swiftc -typecheck $(find BucketList -name '*.swift')）\n\n"
       + sys.argv[1])
print(json.dumps({"decision": "block", "reason": msg}))
PY
exit 0
