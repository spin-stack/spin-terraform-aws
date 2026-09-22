#!/usr/bin/env bash
# A security group's description, and each of its rules', is a string AWS takes only a small set
# of characters in: an apostrophe in one is a 400 at apply, halfway through an installation,
# with everything before it already made. Nothing else here reads these strings, and validate
# does not know the set, so this does.
set -euo pipefail

bad=$(awk '
  /^resource "aws_(security_group|vpc_security_group_(in|e)gress_rule)"/ { rule = 1 }
  /^}/ { rule = 0 }
  rule && $1 == "description" {
    text = $0
    sub(/^[^"]*"/, "", text)
    sub(/"[^"]*$/, "", text)
    if (text ~ /[^a-zA-Z0-9. _:\/()#,@[\]+=&;{}!$*-]/) printf "%s:%d: %s\n", FILENAME, FNR, text
  }
' "$@")

if [ -n "$bad" ]; then
  echo "$bad"
  echo 'a description above holds a character AWS refuses: it takes a-zA-Z0-9 and . _-:/()#,@[]+=&;{}!$*'
  exit 1
fi
echo "OK: every security group description is in the set AWS takes."
