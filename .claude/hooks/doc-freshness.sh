#!/usr/bin/env bash
#
# Stop hook — doc-freshness nudge.
# When code in an area that a *canonical architecture doc* describes has changed,
# but that doc was NOT touched in the same session, remind Claude to review it
# (and sync via /sync-docs or the doc-scribe agent) before finishing.
#
# This is a NUDGE, not a gate: it fires at most ONCE per distinct changeset
# (a stamp keyed on the changed-file set prevents loops). If the docs are still
# accurate, Claude can judge "no change needed" and stop — the second Stop
# passes because the changeset signature is unchanged. Updating the mapped doc
# also clears the reminder. Compile correctness is a separate gate
# (verify-on-stop.sh); this one never blocks on code, only flags doc drift.
#
# Map: code path (prefix match) -> canonical doc to review.
#   BucketList/Models.swift           -> architecture/data-model.md (+ overview.md: persistence)
#   BucketList/Capture/**             -> architecture/capture-pipeline.md
#   ShareExtension/ShareComposeView   -> architecture/capture-pipeline.md
# UI (Theme/Components/*View) is intentionally NOT mapped here: its "doc" is the
# philosophy, already guarded by .claude/rules/ui.md + design-guardian.
#
# Tuning: if this feels noisy, remove the second "Stop" entry from
# .claude/settings.json — the .claude/rules/* injections still cover the
# edit-time reminder.

set -uo pipefail
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# All changed files (unstaged + staged + untracked), any type.
changed="$( {
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} 2>/dev/null | sort -u )"

[ -z "$changed" ] && exit 0   # nothing changed → no-op

changed_has() { printf '%s\n' "$changed" | grep -qE "$1"; }

reminders=""
add_reminder() { reminders="${reminders}  - $1\n"; }

# --- mapping rules ---------------------------------------------------------
if changed_has '^BucketList/Models\.swift$' \
   && ! changed_has '^docs/architecture/data-model\.md$'; then
  add_reminder "Models.swift を変更 → docs/architecture/data-model.md（3軸モデル/型）と、永続化に触れたなら overview.md が実態と合うか確認"
fi

if { changed_has '^BucketList/Capture/' || changed_has '^ShareExtension/ShareComposeView\.swift$'; } \
   && ! changed_has '^docs/architecture/capture-pipeline\.md$'; then
  add_reminder "取り込み（Capture/）を変更 → docs/architecture/capture-pipeline.md（URL→候補パイプライン）が実態と合うか確認"
fi
# ---------------------------------------------------------------------------

[ -z "$reminders" ] && exit 0   # no doc-mapped drift → allow stop

# Loop guard: block at most once per distinct changeset.
stamp_file=".claude/.doc-freshness-stamp"    # gitignored (.claude/* not whitelisted)
sig="$(printf '%s' "$changed" | cksum | awk '{print $1}')"
if [ -f "$stamp_file" ] && [ "$(cat "$stamp_file" 2>/dev/null)" = "$sig" ]; then
  exit 0   # already nudged for this exact state → don't loop
fi
printf '%s' "$sig" > "$stamp_file" 2>/dev/null || true

msg="$(printf 'コード変更に対し、対応する常設ドキュメントが未更新です。乖離がないか確認し、必要なら同期してください（/sync-docs または doc-scribe エージェント）。ドキュメントが既に正確なら「更新不要」と判断してそのまま完了して構いません。\n\n%b' "$reminders")"
python3 - "$msg" <<'PY'
import json, sys
print(json.dumps({"decision": "block", "reason": sys.argv[1]}))
PY
exit 0
