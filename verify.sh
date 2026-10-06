#!/bin/sh
# longctx kit - macOS adapter for verify.ps1
#
# verify.ps1, sitting next to this file, is the SHARED implementation of the
# verification report: the same PowerShell script is used on Windows and on
# macOS. This wrapper is only the macOS entry point. It does exactly two
# things: check that PowerShell 7 (pwsh) is available, then hand every argument
# through to verify.ps1 unchanged.
#
# Usage (macOS):
#   sh verify.sh                               # report only (no hook is executed)
#   sh verify.sh -InvokeProbe                  # additionally execute the hooks with synthetic input
#   sh verify.sh -KitRoot "$HOME/.claude/longctx"
#
# Exit codes:
#   0   verify.ps1 exited 0 (all checks passed)
#   2   pwsh (PowerShell 7) not found on PATH - nothing was executed
#   3   verify.ps1 not found next to this wrapper (incomplete copy of the kit)
#   *   any other value is verify.ps1's own exit code (non-zero = at least one check failed)
#
# Deliberately POSIX sh: /bin/sh on macOS is bash 3.2 in POSIX mode. `set -u`
# is intentionally NOT used, because in bash 3.2 it turns the no-argument
# invocation `sh verify.sh` (the primary way to run this) into an error.

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

if [ ! -f "$script_dir/verify.ps1" ]; then
    echo "FAIL: $script_dir/verify.ps1 not found - this copy of the kit is incomplete." >&2
    exit 3
fi

exec pwsh -NoProfile -File "$script_dir/verify.ps1" "$@"
