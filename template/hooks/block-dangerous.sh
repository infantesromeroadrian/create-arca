#!/bin/bash
set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

[[ -z "$COMMAND" ]] && exit 0

# For `git commit`, scan a copy with the -m/--message body removed. Dangerous-
# looking text inside a commit message (a described destructive op, a $HOME path,
# a DROP TABLE in a migration note) is data — never executed — and must not trip
# the guards below. Only the quoted message body is removed; a chained `&& ...`
# lives outside the quotes and is still scanned. Python runs only on commits.
SCAN_CMD="$COMMAND"
if printf '%s' "$COMMAND" | grep -qE '\bgit[[:space:]]+commit\b'; then
  STRIPPED=$(printf '%s' "$COMMAND" | python3 -c "import sys,re
c=sys.stdin.read()
c=re.sub(\"(?:--message|-m)\\\\s+\\\"[^\\\"]*\\\"\",\" \",c)
c=re.sub(\"(?:--message|-m)\\\\s+\\x27[^\\x27]*\\x27\",\" \",c)
sys.stdout.write(c)" 2>/dev/null) && [[ -n "$STRIPPED" ]] && SCAN_CMD="$STRIPPED"
fi

# Destructive filesystem — rm -rf on root or critical system paths.
# Flags can appear in any order/position (-rf, -fr, -r -f, --no-preserve-root).
if echo "$SCAN_CMD" | grep -qE '(sudo\s+)?rm\s+(-[a-zA-Z]*[rR][a-zA-Z]*\s+|-[a-zA-Z]*f[a-zA-Z]*\s+|--force\s+|--recursive\s+|--no-preserve-root\s+)*/(|home|etc|usr|var|boot|sys|proc|bin|lib|opt)(\s|$|/|\*)'; then
  echo "BLOCKED: rm on critical filesystem path" >&2; exit 2
fi

# Destructive filesystem — home-directory wipes (rm -rf ~, $HOME, or with --no-preserve-root anywhere)
if echo "$SCAN_CMD" | grep -qE 'rm\s+.*-[a-zA-Z]*[rR]' && echo "$SCAN_CMD" | grep -qE '(\s|=)(~|\$HOME|\$\{HOME\})(/|\s|$)'; then
  echo "BLOCKED: rm targeting home directory" >&2; exit 2
fi
if echo "$SCAN_CMD" | grep -qE 'rm\s+.*--no-preserve-root'; then
  echo "BLOCKED: rm --no-preserve-root" >&2; exit 2
fi

# Pipe remote script to shell (direct pipe or download-then-execute)
if echo "$SCAN_CMD" | grep -qE '(curl|wget).*\|\s*(sh|bash|zsh|source)'; then
  echo "BLOCKED: piping remote script to shell" >&2; exit 2
fi

# Force push to main/master. Split the command on shell separators (; && || |)
# and inspect each git-push segment INDEPENDENTLY: block only when, WITHIN ONE
# segment, the push targets main/master via either
#   (a) a force flag (-f / --force / --force-with-lease) AND a main/master ref, or
#   (b) a leading-plus force-refspec whose destination is main/master
#       (`+main`, `+HEAD:main`, `+feature:main` — force without a -f/--force flag).
# Per-segment correlation avoids the cross-token false positive where a force on
# one push and `main` on another wrongly combine (e.g.
# `git push origin main && git push --force origin feature` must pass).
# The git-push matcher tolerates global options between `git` and `push`
# (`git -c x=y push`, `git --no-pager push`, `git -C /repo push`). Backslash-
# newline line continuations are flattened first so a push split across physical
# lines is treated as one segment. `< <(...)` keeps the loop in the current shell
# so `exit 2` aborts the hook (a `| while` subshell could not).
SCAN_CMD_FLAT=$(printf '%s' "$SCAN_CMD" | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }')
while IFS= read -r seg; do
  printf '%s' "$seg" | grep -qE '\bgit[[:space:]]([^[:space:]]+[[:space:]]+)*push([[:space:]]|$)' || continue
  # (a) explicit force flag + a main/master ref in this segment
  if printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-f|--force|--force-with-lease)([[:space:]]|=|$)' \
     && printf '%s' "$seg" | grep -qE '\b(main|master)\b'; then
    echo "BLOCKED: force push to main/master" >&2; exit 2
  fi
  # (b) leading-plus force refspec whose destination is main/master. Covers
  # `+main`, `+HEAD:main`, `+feature:main`, the fully-qualified `+refs/heads/main`,
  # and the empty-source `+:main` (a FORCE-DELETE of the remote branch). The
  # source part is `[^:]*` (zero-or-more) so `+:main` matches; `(refs/heads/)?`
  # covers the fully-qualified destination. `+main:feature` / `+feature` stay
  # allowed (destination is not main/master).
  if printf '%s' "$seg" | grep -qE '(^|[[:space:]])\+([^[:space:]:]*:)?(refs/heads/)?(main|master)([[:space:]]|$)'; then
    echo "BLOCKED: force push to main/master (+refspec)" >&2; exit 2
  fi
done < <(printf '%s\n' "$SCAN_CMD_FLAT" | tr ';&|' '\n')   # trailing \n so `read` sees the last/only segment

# DROP/TRUNCATE database
if echo "$SCAN_CMD" | grep -qiE '(DROP\s+(TABLE|DATABASE)|TRUNCATE\s+TABLE)'; then
  echo "BLOCKED: destructive database operation" >&2; exit 2
fi

# Dangerous permissions (777 or a+rwx)
if echo "$SCAN_CMD" | grep -qE 'chmod\s+(777|a\+rwx)'; then
  echo "BLOCKED: dangerous permissions change" >&2; exit 2
fi

# Disk destruction
if echo "$SCAN_CMD" | grep -qE 'mkfs\.|dd\s+if=.*/dev/|wipefs\s+'; then
  echo "BLOCKED: disk destruction command" >&2; exit 2
fi

# Fork bomb
if echo "$SCAN_CMD" | grep -qE ':\(\)\{.*\|.*&'; then
  echo "BLOCKED: fork bomb pattern" >&2; exit 2
fi

# Mass process kill (kill -9 -1 signals all processes owned by user; killall -9 without target is a typo waiting to happen)
if echo "$SCAN_CMD" | grep -qE 'kill\s+-9\s+-1(\s|$)|killall\s+-9\s*$'; then
  echo "BLOCKED: mass process kill detected" >&2; exit 2
fi

# Credential-file exfiltration via Bash. The Read tool is already denied for these
# paths in settings.json; this closes the parallel Bash vector — dumping/copying/
# archiving the CONTENT of a secret store (`cat ~/.ssh/id_ed25519`, `cp ~/.aws/credentials …`,
# `tar czf out ~/.gnupg`, `base64 ~/.ssh/id_*`, `scp ~/.ssh/id_* host:`).
# Only DUMP/COPY/EXFIL readers are listed. `ssh`, `git`, `docker`, `aws`, `kubectl`,
# `gpg`, `ls`, `chmod` are deliberately NOT here — they USE the key (never cat it out),
# so normal pushes/connections/deploys keep working. This Bash rule does not flag public
# files (authorized_keys, known_hosts) — but the settings.json Read-deny on **/.ssh/**
# still blocks the Read tool from ALL of ~/.ssh (config/known_hosts/authorized_keys too),
# intentional fail-closed; read those in a plain terminal if ever needed. Dir paths require
# a following /, space, quote or end-of-token so siblings like `.aws-helper` don't match.
# Known defense-in-depth gaps (covered by the Read-tool deny, out of scope for this Bash
# layer): pure redirection `<key`, `$(<key)`, builtins read/mapfile, interpreters
# python3 -c/perl/node, editors vim/nano. To be folded into /harness-audit (ADR-105).
SENS_READER='(cat|bat|tac|nl|less|more|head|tail|od|xxd|hexdump|strings|base64|base32|grep|egrep|fgrep|awk|sed|cut|cp|install|dd|tar|cpio|zip|gzip|bzip2|xz|rsync|openssl|scp|sftp)'
SENS_PATH='(\.ssh(/|"|'"'"'|[[:space:]]|$)|(^|/)id_rsa|(^|/)id_ed25519|(^|/)id_ecdsa|\.aws(/|"|'"'"'|[[:space:]]|$)|\.gnupg(/|"|'"'"'|[[:space:]]|$)|\.kube(/|"|'"'"'|[[:space:]]|$)|\.config/gcloud|\.azure(/|"|'"'"'|[[:space:]]|$)|\.kaggle/kaggle\.json|\.docker/config\.json|\.netrc(/|"|'"'"'|[[:space:]]|$|\.))'
if echo "$SCAN_CMD" | grep -qE "(^|[|;&[:space:]])${SENS_READER}[[:space:]][^|;&]*${SENS_PATH}"; then
  echo "BLOCKED: reading/copying a credential file (use the key via ssh/git/docker, do not dump its contents)" >&2; exit 2
fi

exit 0
