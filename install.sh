#!/bin/sh
# longctx kit - macOS adapter for install.ps1
#
# install.ps1, sitting next to this file, is the SHARED implementation of the
# installer: the same PowerShell script is used on Windows and on macOS. This
# wrapper is only the macOS entry point. It does exactly two things: check that
# PowerShell 7 (pwsh) is available, then hand every argument through to
# install.ps1 unchanged.
#
# Usage (macOS):
#   sh install.sh                              # dry run: print the plan, change nothing (default)
#   sh install.sh -Apply                       # real install
#   sh install.sh -Apply -WithSensor           # also enable the opt-in PreToolUse deny gate
#   sh install.sh -Apply -SkipSettings         # copy files, do not touch settings.json
#   sh install.sh -KitRoot "$HOME/.claude/longctx" -Apply
#
# Exit codes:
#   0   install.ps1 exited 0
#   2   pwsh (PowerShell 7) not found on PATH - nothing was executed
#   3   install.ps1 not found next to this wrapper (incomplete copy of the kit)
#   *   any other value is install.ps1's own exit code
#
# macOS prerequisite - printed, NEVER installed by this script:
#   brew install --cask powershell
#
# Deliberately POSIX sh: /bin/sh on macOS is bash 3.2 in POSIX mode. `set -u`
# is intentionally NOT used, because in bash 3.2 it turns the no-argument
# invocation `sh install.sh` (the primary way to run this) into an error.

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1

if ! command -v pwsh >/dev/null 2>&1; then
    {
        echo "FAIL: pwsh (PowerShell 7) not found on PATH."
        echo ""
        echo "The longctx kit is implemented in PowerShell and runs on macOS"
        echo "through PowerShell 7 (pwsh). Install it with Homebrew, then run"
        echo "this script again:"
        echo ""
        echo "    brew install --cask powershell"
        echo ""
        echo "(If Homebrew itself is missing, see https://brew.sh . This script"
        echo "installs nothing on its own.)"
    } >&2
    exit 2
fi

if [ ! -f "$script_dir/install.ps1" ]; then
    echo "FAIL: $script_dir/install.ps1 not found - this copy of the kit is incomplete." >&2
    exit 3
fi

# Soft version check: warn, never block. An unparseable version is not a reason
# to refuse an otherwise working install.
pwsh_major=$(pwsh -v 2>/dev/null | sed -n 's/^PowerShell \([0-9][0-9]*\).*/\1/p' | head -n 1)
case "$pwsh_major" in
    ''|*[!0-9]*) : ;;
    *)
        if [ "$pwsh_major" -lt 7 ]; then
            echo "WARNING: pwsh major version $pwsh_major found; the kit targets PowerShell 7+. Continuing anyway." >&2
        fi
        ;;
esac

exec pwsh -NoProfile -File "$script_dir/install.ps1" "$@"
