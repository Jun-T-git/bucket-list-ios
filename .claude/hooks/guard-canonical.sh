#!/usr/bin/env bash
#
# PreToolUse hook — canonical guard.
# The `if` matcher in settings.json scopes this to docs/philosophy/** only
# (the non-negotiable principles / core concept). Editing those is high-signal:
# ask the user to confirm the change is intentional. Changing the principles
# themselves should start with an ADR (docs/decisions/), not a silent edit.

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"正典（哲学/設計原則）ファイルの変更です。設計原則を変えるなら、まず docs/decisions/ に ADR を起票してください。意図的な変更なら承認してください。"}}
JSON
exit 0
