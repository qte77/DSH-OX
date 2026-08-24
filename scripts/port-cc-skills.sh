#!/usr/bin/env bash
# Port Claude Code plugin skills into DSH project skills.
#
# CC layout:  <repo>/plugins/<plugin>/skills/<skill>/SKILL.md
# DSH layout: <repo>/.dsh/skills/<skill>/SKILL.md        (discovery rank 100)
#
# Both use a <name>/SKILL.md bundle with YAML frontmatter carrying `name` and
# `description`, so the body ports unchanged. Only the CC-specific
# `compatibility:` line is rewritten.
#
# Usage:
#   scripts/port-cc-skills.sh [SRC_PLUGINS_DIR] [--dry-run]
#   scripts/port-cc-skills.sh ../claude-code-plugins/plugins

set -euo pipefail

SRC="${1:-../claude-code-plugins/plugins}"
DEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.dsh/skills"
DRY_RUN=0
for arg in "$@"; do [ "$arg" = "--dry-run" ] && DRY_RUN=1; done

if [ ! -d "$SRC" ]; then
  echo "error: source plugin dir not found: $SRC" >&2
  echo "pass it explicitly: scripts/port-cc-skills.sh /path/to/claude-code-plugins/plugins" >&2
  exit 1
fi

[ "$DRY_RUN" -eq 0 ] && mkdir -p "$DEST"

ported=0
skipped=0

for skill_dir in "$SRC"/*/skills/*/; do
  [ -d "$skill_dir" ] || continue
  [ -f "$skill_dir/SKILL.md" ] || continue

  skill_name="$(basename "$skill_dir")"
  plugin_name="$(basename "$(dirname "$(dirname "$skill_dir")")")"

  # DSH requires kebab-case skill names.
  if ! printf '%s' "$skill_name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    echo "skip (not kebab-case): $plugin_name/$skill_name"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would port: $plugin_name/$skill_name"
    ported=$((ported + 1))
    continue
  fi

  rm -rf "${DEST:?}/$skill_name"
  cp -R "$skill_dir" "$DEST/$skill_name"

  # Retarget the CC-only compatibility marker; leave all other frontmatter and
  # the whole body intact.
  sed -i 's/^compatibility: .*/compatibility: Ported from Claude Code; runs under DeepSeek Harness/' \
    "$DEST/$skill_name/SKILL.md"

  echo "ported: $plugin_name/$skill_name"
  ported=$((ported + 1))
done

echo
echo "ported=$ported skipped=$skipped -> $DEST"
[ "$DRY_RUN" -eq 1 ] && echo "(dry run — nothing written)"
echo "Skills carrying CC-only tooling (Task/subagents, CC hooks) need a manual pass."
