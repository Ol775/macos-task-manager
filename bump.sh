#!/bin/zsh
# Usage: ./bump.sh major|minor|patch "what changed"   – updates VERSION, the README version and the CHANGELOG.
set -e
cd "$(dirname "$0")"
kind="${1:-}"; note="${2:-}"
[ -z "$kind" ] || [ -z "$note" ] && { echo "usage: ./bump.sh major|minor|patch \"what changed\""; exit 1; }
IFS=. read -r maj min pat < VERSION
case "$kind" in
  major) maj=$((maj + 1)); min=0; pat=0 ;;
  minor) min=$((min + 1)); pat=0 ;;
  patch) pat=$((pat + 1)) ;;
  *) echo "kind must be major, minor or patch"; exit 1 ;;
esac
new="$maj.$min.$pat"
echo "$new" > VERSION
python3 - "$new" "$note" <<'PY'
import sys
from datetime import date
v, note = sys.argv[1], sys.argv[2]
s = open("CHANGELOG.md").read()
i = s.index("## ")
open("CHANGELOG.md", "w").write(s[:i] + f"## {v} ({date.today().isoformat()})\n- {note}\n\n" + s[i:])
PY
sed -i '' "s|<!--v-->.*<!--/v-->|<!--v-->v$new<!--/v-->|" README.md
echo "Version is now $new"
