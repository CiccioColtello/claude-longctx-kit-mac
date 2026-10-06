# longctx kit — macOS verification plan (manual)

> **STATUS: NOT EXECUTED on a real mac.**
> This plan was written from the Windows-verified implementation of the kit.
> The macOS path — the three `sh` adapters, the `pwsh` runtime, the settings
> merge against a real `~/.claude/settings.json` on macOS, and the behavior of
> the hooks under Claude Code on macOS — has **not** been run end-to-end.
> **Treat the mac path as BETA until someone executes this plan and files the
> results.** Every "expected" below is a claim read from the implementation
> (and, where noted, verified only on Windows), not an observation from macOS.

---

## 0. Scope and honesty statement

**Covered by this plan**

- `install.sh`, `uninstall.sh`, `verify.sh` — the three macOS adapters
  (missing-`pwsh` path, argument pass-through, delegation to the `.ps1` next to
  them).
- Installation through the shared `install.ps1`: file layout under the kit root,
  non-destructive settings merge, idempotence, backups.
- The five runtime behaviors of the kit under Claude Code on macOS:
  SessionStart injection, the exactly-once guard, the "no `.agent`" message,
  compaction archiving (+ digest fallback), and the deny rules / deny gate.
- Uninstall: settings cleaned, pre-existing user hooks and deny rules preserved.

**Not covered (do not claim it because this plan passes)**

- The internals of the PowerShell hooks: they have their own suites on the
  Windows side (`Test-Hooks.ps1`, `Test-HookFailures.ps1` in the source
  workspace). This plan only checks that they behave correctly *on macOS*,
  end to end.
- `install.ps1` / `uninstall.ps1` / `verify.ps1` internals (owned by the
  installer workstream); this plan treats them as a black box and records what
  they print.
- Performance with very large transcripts, Ollama digest *quality*, Windows/mac
  parity beyond what is listed here.
- The `sh` adapters were syntax-checked with `bash -n` (Git Bash) but **not
  executed**. `install.ps1` / `uninstall.ps1` / `verify.ps1` are present in this
  repo root (synced from the Windows repository at finalize time).

**Known gap to confirm during the run**

- `.agent`-missing message: when the kit layout resolves, the message prints the
  exact activation command
  (`pwsh -NoProfile -File "<kitroot>/bin/longctx.ps1" init`); the kit ships that
  CLI (`core/bin/longctx.ps1`, installed at `<kitroot>/bin/longctx.ps1`). The bare
  `longctx` name is deliberately **not** on `PATH`. Confirm the printed path
  matches your KitRoot and run it as printed; the manual workaround in check
  **B3** remains valid.

---

## 1. Prerequisites

Record all of these; they go in the report (section 7).

| What | Command | Record |
|---|---|---|
| macOS version | `sw_vers` | product + build |
| Hardware | `uname -m` | `arm64` or `x86_64` |
| Claude Code | `claude --version` | must be a recent 2.1.x |
| Homebrew | `brew --version` | version + prefix |
| PowerShell 7 | `command -v pwsh; pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'` | full path + version (7.x) |
| Kit copy | path where this repo was unzipped, plus `shasum -a 256 core/.claude/hooks/Invoke-SessionStart.ps1` | path + hash |

Install PowerShell 7 if needed — **this plan never installs it for you**:

```sh
brew install --cask powershell
```

The adapters themselves print this exact command and exit 2 if `pwsh` is
missing; they never run it.

Also prepare a **scratch project** so nothing here touches your real work:

```sh
mkdir -p "$HOME/longctx-lab"
```

Finally, snapshot the settings file you are about to let the installer touch.
The installer is expected to merge the **user-level** `~/.claude/settings.json`
(confirm which file it actually reports touching, and record it):

```sh
cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.pretest" 2>/dev/null || true
shasum -a 256 "$HOME/.claude/settings.json" 2>/dev/null
ls -la "$HOME/.claude/" | grep settings
```

> If you do not want the kit to touch your real settings during the first pass,
> run the install with `-SkipSettings` (files only) and do the settings part
> later on purpose. Say so in the report.

### 1.1 macOS-specific check on the default kit root

The shared merge library resolves the default kit root through an OS-aware helper
(`Get-KitRootDefault`), not by naive home concatenation: on macOS/Linux `$env:HOME`
wins, with `$env:USERPROFILE` as the fallback; on Windows it is the other way round;
if both are empty it falls back to the system user-profile folder, and it never
returns a silent relative path (the old `USERPROFILE`-only behaviour was fixed on
2026-10-06; `-SelfTest` case 9c covers it). Confirm the environment anyway:

```sh
pwsh -NoProfile -Command '"USERPROFILE=[$env:USERPROFILE]"; "HOME=[$env:HOME]"'
```

- Expected on a normal mac: `USERPROFILE` is empty and `HOME` is `/Users/<you>`; the
  default kit root resolves to `/Users/<you>/.claude/longctx`.
- Record the two values. A default that is empty or relative would be a finding.
- Passing `-KitRoot "$HOME/.claude/longctx"` explicitly to the commands below stays
  the cleanest way to make the run unambiguous.

---

## 2. Install

### I0 — run everything from the kit repo

```sh
cd /path/to/longctx-kit-mac
ls -l install.sh install.ps1   # both must be present (install.ps1 is synced from the Windows repo at finalize time)
```

### I1 — adapter contract: `pwsh` missing -> FAIL, exit 2, nothing executed

Simulate a missing `pwsh` without uninstalling anything, by running with a
minimal PATH (on Apple Silicon Homebrew lives in `/opt/homebrew/bin`, on Intel
in `/usr/local/bin`; both are excluded):

```sh
env PATH=/usr/bin:/bin sh install.sh; echo "exit=$?"
```

**Expected:** a FAIL message on stderr naming PowerShell 7, containing the
exact command `brew install --cask powershell`; `exit=2`; nothing was created
or modified. Record the exact text.

### I2 — dry run (default): plan only

```sh
sh install.sh; echo "exit=$?"
sh install.sh -DryRun; echo "exit=$?"    # same thing: the plan-only mode is the default
```

**Expected:** a plan of what *would* be copied/merged; `exit=0`; nothing
changed. Verify:

```sh
shasum -a 256 "$HOME/.claude/settings.json"   # identical to the I0/§1 snapshot
ls "$HOME/.claude/longctx" 2>/dev/null        # should NOT exist yet (or be unchanged)
```

### I3 — real install

```sh
sh install.sh -Apply -KitRoot "$HOME/.claude/longctx"; echo "exit=$?"
```

**Expected (confirm and record each point):**

1. Files land under `$HOME/.claude/longctx/`, including
   `.claude/hooks/Invoke-SessionStart.ps1`, the other hook files,
   `templates/agent/`, `templates/settings-deny-fragment.json`, `lib/`.
   Record: `find "$HOME/.claude/longctx" -maxdepth 3 -type f | sort`
2. The settings file is merged: a **backup** `...settings.json.bak-<yyyyMMdd-HHmmss>`
   appears next to it (only if the file already existed).
3. The merged settings contain **4 hook events** — `SessionStart`,
   `PostToolUseFailure`, `PreCompact`, `PostCompact` — each with `command:
   "pwsh"` and args pointing at `$HOME/.claude/longctx/.claude/hooks/*.ps1`.
   `PreToolUse` is **absent** in a default install (it is opt-in).
4. `permissions.deny` gained the 11 kit rules (`.env`, `.env.*`, `*.pem`,
   `*.key`, `~/.ssh/**`, `~/.aws/**`, `.git-credentials`, `mcp.json`, `*.kdbx`,
   ...). Any rules you already had are still there, untouched.
5. Nothing else in the settings changed (diff against
   `settings.json.pretest`):
   `diff "$HOME/.claude/settings.json.pretest" "$HOME/.claude/settings.json"`

### I4 — idempotence

```sh
sh install.sh -Apply -KitRoot "$HOME/.claude/longctx"; echo "exit=$?"
shasum -a 256 "$HOME/.claude/settings.json"
```

**Expected:** reports nothing to add ("unchanged"); **no new backup file**; the
settings hash is byte-identical to I3. (A second run must not rewrite the file.)

### I5 — optional deny gate

```sh
sh install.sh -Apply -WithSensor -KitRoot "$HOME/.claude/longctx"
```

**Expected:** a `PreToolUse` entry is added, *appended after* any pre-existing
`PreToolUse` entries (yours stay first and intact). Record the resulting
`PreToolUse` array.

### I6 — broken settings must not be overwritten

Only if you can do it safely on a copy: point a run at a throwaway settings file
containing invalid JSON and confirm the installer **refuses** and leaves the
file byte-identical (this is a designed fail-safe). Note: with the real
installer you may not have a flag for an alternate settings path — if so, mark
this check NOT RUN rather than editing your real settings.

---

## 3. Verification

### V1 — `verify.ps1` through the adapter

```sh
sh verify.sh; echo "exit=$?"
sh verify.sh -InvokeProbe; echo "exit=$?"
```

**Expected:** a PASS/FAIL report per item; `exit=0` when all checks pass,
non-zero when any fails (and the failing item is named). `-InvokeProbe`
additionally executes the hooks with synthetic input. The exact wording is the
installer workstream's contract — **record the real output**; this plan does not
pin it.

### V2 — Claude Code sees the hooks

In the scratch project:

```sh
cd "$HOME/longctx-lab" && claude
# then, inside the session:
/hooks
```

**Expected:** the 4 events (`SessionStart`, `PostToolUseFailure`, `PreCompact`,
`PostCompact`) are listed with their commands pointing into
`$HOME/.claude/longctx/.claude/hooks/`. If `/hooks` does not list `PostCompact`,
record your Claude Code version: the event may not exist in that build.

### V3 — GUI-launch PATH risk (macOS-specific)

Claude Code launched from the GUI (Dock/Finder) inherits a minimal PATH that
usually does **not** include `/opt/homebrew/bin`, so the hook command `pwsh` may
not resolve even though it works in your terminal. Check by launching Claude
Code from the GUI (not from the terminal) and watching for hook errors at
session start.

**Preferred fix (no changes to the system):** launch Claude Code from a terminal
that has Homebrew in its PATH.

**Optional, administrator-level alternative** — only if you need the GUI
launcher, and only on Apple Silicon (on Intel, Homebrew's prefix *is*
`/usr/local`, so nothing is needed). This is a human decision; no script in the
kit runs it:

```sh
sudo ln -s /opt/homebrew/bin/pwsh /usr/local/bin/pwsh   # Apple Silicon, optional
```

Record whether the GUI-launch worked, and the `pwsh` path found.

---

## 4. Behavior checks

Each check: setup, steps, expected observation, what to record. All expected
strings are quoted from the implementation as shipped (English).

### B1 — SessionStart injection at session start

**Setup:** in `$HOME/longctx-lab` create the agent state (workaround for the
missing `longctx` CLI — see §0):

```sh
mkdir -p .agent/archive
cp "$HOME/.claude/longctx/templates/agent/"*.md .agent/
# put a marker in the state so you can recognize it:
# edit .agent/STATE.md -> "## Next action" -> "MAC-B1-MARKER"
```

**Steps:** start a fresh session in that directory (`claude`), then ask the
model: *"Quote the first lines of the `[AGENT_CONTEXT]` block in your context
verbatim."* Optionally run `claude --debug` in another terminal to see hook
execution directly.

**Expected:** the injected context includes `[AGENT_CONTEXT]`, `root:`, the
`session: <source> | <timestamp>` line, a `## .agent/STATE.md` section with
your `MAC-B1-MARKER` shown under `## Next action (explicit excerpt)`, and the
`active hooks: ...` line. The whole block is capped at 6000 characters.
**Silence or a generic answer = FAIL:** record the session's `source` (startup
vs resume) and the exact injected text if you can get it.

### B2 — exactly-once guard (no double injection)

The user-level SessionStart hook stays silent only on **positive evidence** that the
project's own copy is the injector: a running copy that is **outside** the project
exits without injecting only when `<project>/.claude/settings.json` **or**
`<project>/.claude/settings.local.json` mentions the
literal string `Invoke-SessionStart.ps1` (case-insensitive) **and** a project-local
copy exists at `<project>/.claude/hooks/Invoke-SessionStart.ps1`. A copy running from
**inside** the project always injects; anything else injects (fail-open).

The same guard shape (shared helper `Test-ProjectLocalInjector`) is applied by **all
four** event hooks — `SessionStart`, `PreCompact`, `PostCompact`,
`PostToolUseFailure` — so a project can register the whole kit project-level as well
without running any event twice. (An earlier revision guarded only the injector; the
setup below used to warn against registering the other three events project-level.)

**Setup (in `$HOME/longctx-lab`):**

```sh
mkdir -p .claude/hooks
cp "$HOME/.claude/longctx/.claude/hooks/"*.ps1 .claude/hooks/   # so the project-level hook can actually run
cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact|fork",
        "hooks": [ { "type": "command", "command": "pwsh",
                     "args": ["-NoProfile", "-NonInteractive", "-File",
                              "${CLAUDE_PROJECT_DIR}/.claude/hooks/Invoke-SessionStart.ps1"],
                     "timeout": 15 } ] } ]
  }
}
JSON
```

**Steps:** start a new session; ask the model to quote any `[AGENT_CONTEXT]`
block it can see.

**Expected (both halves matter):**

- The **user-level** hook ran but exited 0 silently: there is **no second**
  `[AGENT_CONTEXT]` block. If you see the block twice (or doubled sections), the
  guard failed — record it.
- The **project-level** hook injects exactly one block (its file exists there, so it
  is the single injector).
- Discriminator (this is the case that catches the old dead-lock): rename the project
  hook dir out of the way (`mv .claude/hooks .claude/hooks.b2`) but keep the string in
  `settings.json`. Restart: the user-level hook must now inject — the guard needs the
  project-local copy to exist, so you should see **exactly one** `[AGENT_CONTEXT]`
  block, **not zero**. Zero blocks here = FAIL (that was the old bare-mention
  behaviour). Record what you saw.

**Known limitations to record:**

- A registration the guard cannot recognize (renamed copy, or a path pointing at the
  user-level install) is treated as "not the injector", so both copies inject. Both
  `settings.json` and `settings.local.json` are scanned.
- A project that registers the **user-level** hook path without shipping a
  project-local copy receives the block twice — the declared fail-open residual edge
  (double waste is preferred over a dead feature).
- For the other three events the same rule applies per event: an unrecognized
  registration means the event runs twice (two archives per `/compact`, a failed tool
  call recorded twice). With the guard in place, a correctly wired project runs each
  event exactly once.

### B3 — `.agent` absent -> explicit message suggesting `longctx init`

**Setup:** a project directory with **no** `.agent/` (e.g. `mkdir -p "$HOME/longctx-lab-empty"`).

**Steps:** start a session there; ask the model to quote the injected
`[AGENT_CONTEXT]` block, or read it from `claude --debug`.

**Expected:** a short block containing, verbatim:

```
[AGENT_CONTEXT]
Agent state missing: <project>/.agent does not exist. Activate the kit in this project: pwsh -NoProfile -File "<kitroot>/bin/longctx.ps1" init
[/AGENT_CONTEXT]
```

If the kit layout does not resolve under the running hook, the fallback wording
is the generic hint: `Run 'longctx init' in this project to activate the kit
(see the kit README for the full invocation).` Either wording is a pass; record
which one you saw.

**Record:** the exact path and command shown. Do **not** expect a bare `longctx`
on `PATH` — that is deliberate: run the command exactly as printed.

### B4 — compaction archive appears in `.agent/archive/`

**Setup:** `$HOME/longctx-lab` with `.agent/` present (B1) and a few turns of
conversation. If you are continuing straight from B2, rename its project-level
wiring away (`mv .claude/settings.json .claude/settings.json.b2`): B2 registers only
`SessionStart`, so `PreCompact` still runs once. (With the guard applied by all four
event hooks, a whole-kit project-level registration should also still produce exactly
one archive per compaction — if you test that configuration and see two, that is a
finding: record it.) Record which configuration you tested.

**Steps:** run `/compact` in the session (manual trigger).

**Expected:**

- A system message in the session: `Context archived: .agent/archive/<TS>-precompact.md`
  (or the "...without local digest (<reason>): ..." variant — see B5).
- Files created under `.agent/archive/`:
  `<yyyyMMdd-HHmmss>-precompact.md`, then
  `<yyyyMMdd-HHmmss>-compact-summary.md` (PostCompact), plus/updated `INDEX.md`
  with one row per archive.
- `.agent/STATE.md` gains `## Last compaction` and `## Updated` sections; if
  STATE.md was missing/empty it is recreated with a template whose
  `## Next action` points at the archive file.
- The session is **not blocked** by the hook; the compaction completes within
  the 60 s PreCompact timeout.

**Record:** the actual file names, and whether INDEX.md has a matching row.

### B5 — digest is optional: no Ollama -> explicit fallback, never a block

**Setup:** ensure Ollama is NOT running (`curl -s http://127.0.0.1:11434/api/tags`
should fail) and no `.agent/ollama.env` exists.

**Steps:** same as B4 (`/compact`).

**Expected:**

- The archive file contains a section `## Local digest NOT available (fallback)`
  followed by `reason: <reason>` (e.g. `transcript not available` or a
  connection error — record the actual reason).
- The session shows the "...without local digest (...): ..." system message.
- A row with cause `digest-local-fallback` is appended to `.agent/FAILURES.md`.
- **Nothing blocks**: `/compact` completes normally.
- With Ollama running (optional): the same archive instead contains the digest
  text and no fallback section.

### B6 — deny rules are active (default install)

**Setup:** the installed settings from I3 (deny rules merged).

**Steps:** in a project that contains a `.env` file, ask Claude to read it with
the Read tool (e.g. *"read .env"*).

**Expected:** the tool call is **denied** by Claude Code's permission engine
(the kit's deny rules are `Read(./.env)`, `Read(**/.env)`, `Read(./.env.*)`,
...). No file content appears in the transcript.

**Also check the negative control:** reading a normal file (e.g. `README.md`)
still works — the deny rules must not be over-broad.

### B7 — deny gate (only if installed with `-WithSensor`)

**Setup:** I5 done.

**Steps:** in the session, have Claude attempt a destructive shell command
(e.g. `rm -rf` on the lab dir) and separately a benign one (`ls -la`).

**Expected:** the destructive call is denied by the PreToolUse hook: the hook
emits `hookSpecificOutput.permissionDecision = "deny"` with a
`permissionDecisionReason`, the call does not run, and an audit line appears in
`.agent/denied-actions.log`. The benign call runs normally (no false positive).
Record the reason text.

### B8 — PostToolUseFailure row (the 4th event)

**Steps:** in a session with `.agent/`, have Claude run a command that fails
(e.g. `ls /definitely-not-here`) through the Bash tool.

**Expected:** one redacted row appears in `.agent/FAILURES.md` starting with
`| <yyyy-MM-dd HH:mm:ss> |` naming the tool and a truncated error; nothing is
written when there is no failure.

---

## 5. Uninstall

### U1 — dry run

```sh
sh uninstall.sh; echo "exit=$?"
```

**Expected:** prints what *would* be removed; changes nothing.

### U2 — real uninstall

```sh
sh uninstall.sh -Apply -KitRoot "$HOME/.claude/longctx"; echo "exit=$?"
```

**Expected:**

- The kit's hook entries are gone from the settings file; a fresh backup is
  written before the change.
- **Pre-existing user hooks are still present** — compare with
  `settings.json.pretest` if you had any. The merge engine is add-only on
  install and removes only its own entries on uninstall.
- By default the `permissions.deny` rules stay (use `-RemoveDenyRules` to drop
  them) — record which behavior you observed and whether it matched the flag.

### U3 — `/hooks` clean

Start a session in the lab project and run `/hooks`: no kit entries remain
(unless a project-level wiring exists — B2's files are yours to remove).

### U4 — full removal (optional)

```sh
sh uninstall.sh -Apply -RemoveDenyRules -RemoveFiles -KitRoot "$HOME/.claude/longctx"
```

**Expected:** deny rules removed too and the copied files under the kit root
removed. Record whether your own pre-existing deny rules survived.

---

## 6. Failure signatures

| Symptom | Likely cause | Fix |
|---|---|---|
| `sh install.sh` prints the pwsh FAIL message although `pwsh` works in your terminal | PATH seen by the shell differs (e.g. you ran with a stripped PATH); or Homebrew's bin dir is not in PATH | `eval "$(/opt/homebrew/bin/brew shellenv)"`, then re-run; the adapter never installs anything itself |
| Adapter exits 3: `install.ps1 not found` | You are running a partial copy of the repo (install.ps1 missing) | Run from the repo root where `install.ps1` exists (it is synced there at finalize time) |
| `sh: install.sh: command not found` or `\r`/`bad interpreter` errors | File has CRLF line endings (copied through Windows) | `tr -d '\r' < install.sh > install.sh.lf && mv install.sh.lf install.sh` (and same for the other `.sh` files) |
| Hooks listed by `/hooks` but never fire | Hook `command: pwsh` not resolvable by the Claude Code process (GUI launch PATH — see V3) | Symlink `pwsh` into `/usr/local/bin`, restart Claude Code |
| No injection, session says nothing about `.agent` | The hook is not registered, or the session's project dir is wrong, or `.agent/` does not exist; with the v2 guard, project wiring alone can no longer silence the user-level hook | Run `/hooks` and `sh verify.sh`; confirm `.agent/` exists in the project root |
| Injection appears twice | The project's registration is in a shape the guard does not recognize (renamed copy, or a path pointing at the user-level install), or the project-local copy is missing at the convention the guard looks for; the guard scans `settings.json` **and** `settings.local.json`, so a mention alone in either one is not enough | Keep exactly one registration, or ship the project-local copy at `<project>/.claude/hooks/Invoke-SessionStart.ps1` |
| Two archives per `/compact`, or a failed tool call logged twice | The project's registration for that event is in a shape the guard does not recognize (same conditions as above, per event) | Keep exactly one registration per event, or ship the project-local copy of that hook — all four event hooks carry the same guard |
| `Agent state missing` even though `.agent/` exists | `CLAUDE_PROJECT_DIR` not set when you invoked the hook manually; or `.agent` is in a different directory than the project root | In a real session Claude Code sets it automatically; for manual runs export `CLAUDE_PROJECT_DIR` |
| `longctx init` suggested but `command -v longctx` finds nothing | Expected by design: the bare `longctx` name is not on `PATH` | Run the exact command printed by the message, or `pwsh -NoProfile -File "$HOME/.claude/longctx/bin/longctx.ps1" init`; manual workaround: `mkdir -p .agent/archive && cp "$HOME/.claude/longctx/templates/agent/"*.md .agent/` |
| `/compact` produces no archive file | Hook not registered for `PreCompact`; or the session was never compacted; or the hook errored (check `.agent/FAILURES.md` and `claude --debug`) | Re-run I3; confirm `/hooks` shows `PreCompact`; file `PreCompact` failures from the debug output |
| Archive exists but digest section always says fallback | Ollama not running, or the transcript was rejected/empty (macOS path separators are handled, but record the `reason:` line) | Expected without Ollama; with Ollama: `curl http://127.0.0.1:11434/api/tags` and check `.agent/ollama.env` |
| Reading `.env` is allowed | Settings merge skipped (`-SkipSettings`) or the deny rules were removed; or the file is not matched by the rule (different name) | Re-run `sh install.sh -Apply`; inspect `permissions.deny` |
| Legitimate commands denied after `-WithSensor` | The deny gate is aggressive by design (fail-closed on scan budget); it was opt-in at install time | To turn just the gate off: `sh uninstall.sh -Apply` (removes the kit's hook entries, keeps the files), then `sh install.sh -Apply` again **without** `-WithSensor`. Record which command actually ran the destructive call so the false positive can be tuned |
| Installer refuses with "invalid JSON" | Your settings file is not valid JSON | Fix the JSON (a backup was NOT taken because nothing was written); the kit never overwrites unparseable settings |
| Second `-Apply` created another backup / changed the file | Idempotence broken (or the first run genuinely added things) | Compare both settings hashes and file `mtime`; file a finding with the diff |

---

## 7. Reporting results

Feed this back so the mac path can leave BETA. Capture:

1. **Versions:** macOS (`sw_vers`), `uname -m`, `claude --version`, `pwsh`
   version + path, Homebrew prefix, kit path + hash of
   `core/.claude/hooks/Invoke-SessionStart.ps1`.
2. **Per check:** ID (I1..I6, V1..V3, B1..B8, U1..U4), status
   (PASS / FAIL / NOT RUN / PARTIAL), the exact commands you ran, and the raw
   output — including exit codes (`echo $?`).
3. **Expected-vs-observed:** for every string in this plan that did not match,
   quote both. Small wording differences are acceptable; missing behavior is a
   finding.
4. **Settings evidence:** the `diff` of `settings.json.pretest` vs the merged
   file, the backup file name, and the hash before/after the second `-Apply`.
5. **Files produced:** `find "$HOME/.claude/longctx" -maxdepth 3 -type f`,
   and `ls -la .agent/archive/` after `/compact`.
6. **Environment facts:** did you launch Claude Code from the terminal or the
   GUI (V3)? Is Ollama installed? Did `command -v longctx` find a CLI?
7. **Deviations:** anything you had to work around, and anything this plan got
   wrong.

Do **not** paste secrets, tokens, or the contents of `.env` files into the
report. If a check touches a sensitive file, cite `[SENSITIVE_FILE] <name>`
only.

---

## Appendix A — expected strings, for literal comparison

| Where | String |
|---|---|
| SessionStart block | `[AGENT_CONTEXT]` ... `[/AGENT_CONTEXT]`, `root: <dir>`, `session: <source> \| <timestamp>`, `active hooks: session-start, pre-compact, post-compact, post-tool-failure` — and the suffix `, pre-tool-use(policy deny)` **only** when the PreToolUse sensor is registered. In the `## Project operating rules` section, the sensor line is either `- PreToolUse deny sensor: ACTIVE - destructive commands and sensitive files are blocked by the deny gate.` or `- PreToolUse deny sensor: not installed (opt-in, -WithSensor); the merged permissions.deny rules for sensitive files still apply.` |
| `.agent` missing | `Agent state missing: <dir>/.agent does not exist. Activate the kit in this project: pwsh -NoProfile -File "<kitroot>/bin/longctx.ps1" init` (fallback wording when the kit layout does not resolve: `Agent state missing: <dir>/.agent does not exist. Run 'longctx init' in this project to activate the kit (see the kit README for the full invocation).`) |
| PreCompact ok | `Context archived: .agent/archive/<TS>-precompact.md` |
| PreCompact fallback | `Context archived without local digest (<reason>): .agent/archive/<TS>-precompact.md` |
| Archive fallback section | `## Local digest NOT available (fallback)` + `reason: <reason>` |
| PostCompact ok | `Compaction recorded: .agent/archive/<TS>-compact-summary.md (STATE.md updated)` |
| Archive file names | `<yyyyMMdd-HHmmss>-precompact.md`, `<yyyyMMdd-HHmmss>-compact-summary.md`, `INDEX.md` (a `-2`, `-3`, ... suffix appears if two archives land in the same second) |
| Settings hook entries | 4 events by default; `command: "pwsh"`, args `-NoProfile -NonInteractive -File <kitroot>/.claude/hooks/<file>.ps1`; timeouts 15/15/60/15 s; `PreToolUse` only with `-WithSensor` |
| Deny rules added | 11 rules from `templates/settings-deny-fragment.json` |
| Backup file | `<settings>.bak-<yyyyMMdd-HHmmss>` |
| Failure row | one line starting with `| yyyy-MM-dd HH:mm:ss |` in `.agent/FAILURES.md` |
