#!/usr/bin/env bash
# Scans what is staged (or, with --all, every tracked file) for secrets before a push.
# Checks the literal values in ~/vexa-system/.secrets/env and common key patterns. Exit 1 on a hit.
set -u
cd "$(git rev-parse --show-toplevel)"
if [ "${1:-}" = "--all" ]; then files=$(git ls-files); else files=$(git diff --cached --name-only --diff-filter=ACM); fi
[ -z "$files" ] && { echo "secret-scan: nothing to scan"; exit 0; }
hits=0
pattern='sk-ant-[A-Za-z0-9_-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{20,}|xox[bp]-[A-Za-z0-9-]{10,}'
for f in $files; do
  [ -f "$f" ] || continue
  if grep -I -n -E "$pattern" "$f" >/dev/null 2>&1; then echo "secret-scan: key pattern in $f"; hits=1; fi
done
SECRETS="$HOME/vexa-system/.secrets/env"
if [ -f "$SECRETS" ]; then
  while IFS='=' read -r name value; do
    value="${value%\"}"; value="${value#\"}"
    [ ${#value} -lt 12 ] && continue
    for f in $files; do
      [ -f "$f" ] || continue
      if grep -I -F -q -- "$value" "$f" 2>/dev/null; then echo "secret-scan: value of $name found in $f"; hits=1; fi
    done
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$SECRETS")
fi
if git ls-files | grep -E '(^|/)Config\.toml$' >/dev/null; then echo "secret-scan: a Config.toml is tracked"; hits=1; fi
[ $hits -eq 0 ] && echo "secret-scan: clean ($(echo "$files" | wc -l | tr -d ' ') files)"
exit $hits
