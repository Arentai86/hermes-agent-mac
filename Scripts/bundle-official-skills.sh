#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/HermesAgent/Resources/runtime/server"
SKILLS_DIR="$ROOT_DIR/HermesAgent/Resources/skills"

if [ ! -d "$SERVER_DIR/skills" ] && [ ! -d "$SERVER_DIR/optional-skills" ]; then
  echo "No Hermes Agent skills found in $SERVER_DIR" >&2
  exit 1
fi

rm -rf "$SKILLS_DIR"
mkdir -p "$SKILLS_DIR"

copy_skill_tree() {
  local source="$1"
  [ -d "$source" ] || return 0
  find "$source" -mindepth 1 -maxdepth 2 -name SKILL.md -print0 | while IFS= read -r -d '' skill; do
    local dir
    local name
    dir="$(dirname "$skill")"
    name="$(basename "$dir")"
    rm -rf "$SKILLS_DIR/$name"
    cp -R "$dir" "$SKILLS_DIR/$name"
  done
}

copy_skill_tree "$SERVER_DIR/skills"
copy_skill_tree "$SERVER_DIR/optional-skills"

COUNT="$(find "$SKILLS_DIR" -maxdepth 2 -type f -name SKILL.md | wc -l | tr -d ' ')"
if [ "$COUNT" = "0" ]; then
  echo "No Hermes Agent skills were bundled" >&2
  exit 1
fi

cat > "$SKILLS_DIR/version.json" <<JSON
{
  "source": "Hermes Agent bundled runtime",
  "count": $COUNT
}
JSON

echo "Bundled $COUNT Hermes Agent skills in $SKILLS_DIR"
