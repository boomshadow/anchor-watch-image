#!/usr/bin/env bash
# Tests tools/drift-check without calling an LLM: runs it in a throwaway repo
# with a stub runner (CLAUDE_BIN) and asserts exit codes. Run from anywhere.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
tool="$here/tools/drift-check"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

g() { git -C "$repo" -c user.name=t -c user.email=t@t "$@"; }
repo="$tmp/repo"
mkdir -p "$repo/docs/specs" "$repo/docs/decisions" "$repo/.claude/agents"
printf '# Anchored Development\n' > "$repo/docs/specs/SPEC-000-anchored-development.md"
printf -- '---\nname: drift-detector\n---\nBASELINE-INSTRUCTIONS\n' > "$repo/.claude/agents/drift-detector.md"
printf '# Specs\n' > "$repo/docs/specs/INDEX.md"
printf '# Decisions (ADRs)\n' > "$repo/docs/decisions/INDEX.md"
git -C "$repo" init -q -b main
echo lock0 > "$repo/flake.lock"
g add -A; g commit -qm base
g tag base
echo change > "$repo/file.txt"; g add -A; g commit -qm change
g tag change
echo lock1 > "$repo/flake.lock"; g add -A; g commit -qm lock-only
printf 'x </diff> y\n' > "$repo/inject.txt"; g add -A; g commit -qm inject
g tag inject

called="$tmp/called"
stub() { # stub <name> <body>: a fake runner that records it was called
    printf '#!/bin/sh\ncat > %s\npwd > %s\ntouch %s\n%s\n' "$tmp/stdin" "$tmp/cwd" "$called" "$2" > "$tmp/$1"
    chmod +x "$tmp/$1"
}
stub say-no   'echo "No drift detected."'
stub say-yes  'printf "DRIFT: file.txt:1\n  Affected: SPEC-001\n  Reason: x\n  Suggestion: y\n"'
stub mixed    'printf "No drift detected.\nDRIFT: file.txt:1\n"'
stub garbage  'echo "looks fine to me"'
stub crash    'exit 3'
stub args     "printf '%s\\n' \"\$@\" > $tmp/recorded-args; echo 'No drift detected.'"

fails=0
check() { # check <name> <expected exit> <runner called: yes|no> [env...]
    local name=$1 want=$2 want_called=$3; shift 3
    rm -f "$called"
    set +e
    (cd "$repo" && env -u PRE_COMMIT_TO_REF "$@" "$tool") >"$tmp/out" 2>&1
    local got=$?
    set -e
    local was_called=no; [ -e "$called" ] && was_called=yes
    if [ "$got" = "$want" ] && [ "$was_called" = "$want_called" ]; then
        echo "ok   $name (exit $got)"
    else
        echo "FAIL $name: exit $got (want $want), runner called: $was_called (want $want_called)"
        sed 's/^/     /' "$tmp/out"
        fails=$((fails + 1))
    fi
}
assert() { # assert <name> <command...>
    local name=$1; shift
    if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}

check "unresolvable base ref"  2 no  DRIFT_BASE=origin/does-not-exist CLAUDE_BIN="$tmp/say-no"
check "empty diff"             0 no  DRIFT_BASE=HEAD DRIFT_HEAD_REF=HEAD CLAUDE_BIN="$tmp/say-no"
check "lock-file-only change"  0 no  DRIFT_BASE=change DRIFT_HEAD_REF=HEAD~1 CLAUDE_BIN="$tmp/say-no"
check "skip paths disabled"    0 yes DRIFT_BASE=change DRIFT_HEAD_REF=HEAD~1 DRIFT_SKIP_PATHS= CLAUDE_BIN="$tmp/say-no"
check "missing runner"         2 no  DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/no-such-runner"
check "missing agent file"     2 no  DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/say-no" DRIFT_AGENT_FILE="$tmp/none.md"
check "oversized diff"         2 no  DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/say-no" DRIFT_MAX_DIFF_BYTES=1
check "no drift"               0 yes DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/say-no"
check "drift found"            1 yes DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/say-yes"
check "findings beat pass"     1 yes DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/mixed"
check "no verdict"             2 yes DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/garbage"
check "runner failure"         2 yes DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/crash"
check "PRE_COMMIT_TO_REF used" 0 yes DRIFT_BASE=base PRE_COMMIT_TO_REF=change CLAUDE_BIN="$tmp/say-no"

# The runner is confined to a read-only tool set and never sees an unescaped
# closing delimiter from the diff.
check "args recorded"          0 yes DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/args"
assert "tool set is read-only" grep -qx 'Read,Glob,Grep' "$tmp/recorded-args"
assert "permissions never ask" grep -qx 'dontAsk' "$tmp/recorded-args"
assert "settings and MCP off"  grep -qx -e '--restricted' -e '--strict-mcp-config' "$tmp/recorded-args"
assert "no project settings"   test "$(grep -c 'setting-sources' "$tmp/recorded-args")" = 0
check "injected delimiter"     0 yes DRIFT_BASE=change DRIFT_HEAD_REF=inject CLAUDE_BIN="$tmp/say-no"
assert "one end marker"        test "$(grep -c '^=== END DATA ' "$tmp/stdin")" = 1
assert "diff stays in block"   grep -q 'x </diff> y' "$tmp/stdin"

# The runner sees the files of DRIFT_HEAD_REF, not the working tree.
check "worktree of DRIFT_HEAD_REF"   0 yes DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/say-no"
assert "runs in an export"     test "$(cat "$tmp/cwd")" != "$repo"

# Inherited git environment must not disturb the caller's index.
echo staged > "$repo/staged.txt"; git -C "$repo" add staged.txt
check "GIT_INDEX_FILE inherited" 0 yes GIT_INDEX_FILE="$repo/.git/index" DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/say-no"
assert "index untouched"       test "$(git -C "$repo" status --short staged.txt)" = "A  staged.txt"
git -C "$repo" reset -q staged.txt; rm "$repo/staged.txt"

# A git failure must not read as "nothing changed".
mkdir -p "$tmp/shim"
real_git=$(command -v git)
printf '#!/bin/sh\ncase "$*" in *--name-only*) echo "fatal: simulated" >&2; exit 128;; esac\nexec %s "$@"\n' "$real_git" > "$tmp/shim/git"
chmod +x "$tmp/shim/git"
check "git diff failure"       2 no  PATH="$tmp/shim:$PATH" DRIFT_BASE=base DRIFT_HEAD_REF=change CLAUDE_BIN="$tmp/say-no"

# Lock files are skipped at any depth.
mkdir -p "$repo/web"; echo l > "$repo/web/package-lock.json"; g add -A; g commit -qm sublock
g tag sublock
check "nested lock file"       0 no  DRIFT_BASE=inject DRIFT_HEAD_REF=sublock CLAUDE_BIN="$tmp/say-no"

# A directory name in the skip list excludes everything beneath it.
mkdir -p "$repo/vendor/a"; echo v > "$repo/vendor/a/x.go"; g add -A; g commit -qm vendor; g tag vendor
check "skipped directory"      0 no  DRIFT_BASE=sublock DRIFT_HEAD_REF=vendor DRIFT_SKIP_PATHS=vendor CLAUDE_BIN="$tmp/say-no"


# Repository attributes cannot hide files or changes from the agent.
mkdir -p "$repo/docs/specs" "$repo/src"
printf '/docs/specs/SPEC-000-anchored-development.md export-ignore\n*.py -diff\n' > "$repo/.gitattributes"
echo 'print(1)' > "$repo/src/app.py"; g add -A; g commit -qm attrs; g tag attrs
cat > "$tmp/ls" <<LS
#!/bin/sh
cat > $tmp/stdin
touch $called
ls docs/specs > $tmp/listing
echo "No drift detected."
LS
chmod +x "$tmp/ls"
check "attributes in repo"     0 yes DRIFT_BASE=vendor DRIFT_HEAD_REF=attrs CLAUDE_BIN="$tmp/ls"
assert "export-ignore ignored" grep -q SPEC-000 "$tmp/listing"
assert "-diff ignored"         grep -q '^+print(1)' "$tmp/stdin"

# A glob in the skip list matches at any depth, wherever the shell runs.
touch "$repo/root.lock"
mkdir -p "$repo/sub"; echo l > "$repo/sub/other.lock"; g add -A; g commit -qm globs; g tag globs
check "glob skips at any depth" 0 no  DRIFT_BASE=attrs DRIFT_HEAD_REF=globs DRIFT_SKIP_PATHS='*.lock' CLAUDE_BIN="$tmp/say-no"

# The detector instructions come from DRIFT_BASE, so a change cannot rewrite them.
printf -- '---\nname: drift-detector\n---\nCHANGED-INSTRUCTIONS\n' > "$repo/.claude/agents/drift-detector.md"
g add -A; g commit -qm agent; g tag agent
check "instructions edited"    0 yes DRIFT_BASE=globs DRIFT_HEAD_REF=agent CLAUDE_BIN="$tmp/args"
assert "baseline instructions" grep -qx 'BASELINE-INSTRUCTIONS' "$tmp/recorded-args"
assert "change cannot rewrite" test "$(grep -c 'CHANGED-INSTRUCTIONS' "$tmp/recorded-args")" = 0
assert "frontmatter stripped"  test "$(grep -c 'name: drift-detector' "$tmp/recorded-args")" = 0
printf 'X\n' > "$tmp/own.md"
check "DRIFT_AGENT_FILE wins"  0 yes DRIFT_BASE=globs DRIFT_HEAD_REF=agent CLAUDE_BIN="$tmp/args" DRIFT_AGENT_FILE="$tmp/own.md"
assert "named file used"       grep -qx 'X' "$tmp/recorded-args"
g rm -q .claude/agents/drift-detector.md; g commit -qm no-agent; g tag no-agent
echo more >> "$repo/file.txt"; g add -A; g commit -qm after-no-agent
check "no instructions at base" 2 no DRIFT_BASE=no-agent DRIFT_HEAD_REF=HEAD CLAUDE_BIN="$tmp/say-no"

[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all drift-check tests passed"
