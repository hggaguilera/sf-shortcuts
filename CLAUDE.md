# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Shell shortcuts that wrap the Salesforce CLI (`sf`) in short commands named `sf` + verb + type (`d` = deploy, `r` = retrieve), e.g. `sfdcls`, `sfrlwc`. No build step. The same commands exist in three ports that must stay in sync:

- `sf-shortcuts.plugin.zsh` — zsh plugin (the original; architecture notes below describe it)
- `bash/sf-shortcuts.bash` — bash port, must work on bash 3.2 (macOS default): no associative arrays, `mapfile`, `${x,,}` or `local -n`; completion via `complete -F`
- `powershell/SfShortcuts.psm1` + `SfShortcuts.psd1` — PowerShell 7 module (Core only)

## Commands

```zsh
zsh tests/run.zsh                 # zsh test suite
zsh -n sf-shortcuts.plugin.zsh    # zsh syntax check
bash tests/run.bash               # bash test suite
pwsh tests/run.ps1                # PowerShell test suite
```

CI (`.github/workflows/`) runs zsh and bash on ubuntu-latest and macos-latest (macOS has bash 3.2), and PowerShell on ubuntu, macos and windows-latest.

There is no single-test selector. To exercise one command by hand without touching an org, source the plugin in a zsh with a fake `sf` defined, from a directory containing `sfdx-project.json`:

```zsh
zsh -c 'source ./sf-shortcuts.plugin.zsh; sf() { print -r -- "sf $*" }; cd /path/to/sfdx-project && sfdcls Foo -t FooTest'
```

## Architecture

**Argument parsing via dynamic scoping.** Every public command declares `local -a items org tests extra` and calls `_sf_parse "$@"`, which fills those caller-scoped arrays (`-o/--target-org` → `org`, words after `-t/--tests` → `tests`, everything after `--` → `extra`, the rest → `items`). Helpers like `_sf_deploy` then read `org`, `tests` and `extra` from the caller's scope rather than taking them as arguments. Any new command must declare those four locals before calling `_sf_parse`/`_sf_deploy`.

**Deploy pipeline.** `_sf_deploy_type <name> <dir> <suffix>` builds `--source-dir $(_sf_source_dir)/<dir>/<name><suffix>` flags and hands off to `_sf_deploy`, which picks the `sf project deploy` subcommand from `$_SF_DEPLOY_MODE` (`start` default, `dry-run`, `preview`) and appends `--test-level RunSpecifiedTests --tests …` when tests were given (skipped for preview). `sfdcheck`/`sfdpreview` work by running any `sfd*` command with `_SF_DEPLOY_MODE` set as an env prefix — so every deploy command must go through `_sf_deploy` to support them.

**Execution.** All `sf` invocations go through `_sf_run`, which prints the command dimmed (`\e[2m→ …`) then runs it, falling back to `npx -y @salesforce/cli` when no `sf` command or function exists. The test harness strips those dimmed lines and defines `sf` as a function, which is why the fallback check includes `$+functions[sf]`.

**Update notice.** `_sf_run` calls `_sf_update_tick` only when stderr is a terminal. The tick reads `latest-version` (`<version> <epoch>`) and `last-notice` from `${XDG_CACHE_HOME:-~/.cache}/sf-shortcuts`, prints the notice at most once a day, and when the check is over a week old calls `_sf_update_refresh`, which runs `_sf_update_fetch` in a detached process. Tests call the tick directly because their stderr is a pipe, and replace the refresh with a marker.

**Source dir resolution.** `_sf_source_dir` uses `$SF_SOURCE_DIR`, else the default package path from `sfdx-project.json` (jq if available, regex fallback otherwise), appending `/main/default` when that directory exists.

**Completion.** `_sf_shortcuts_complete` is one dispatcher for all commands: it unwraps `sfdcheck`/`sfdpreview` to complete the inner command, completes org aliases (parsed from `~/.sfdx/alias.json`) after `-o`, test classes after `-t`, and otherwise component names from local project folders via `_sf_complete_names`. `compdef` is only registered if `compinit` already ran.

## Releases

Run `bash scripts/bump-version.sh X.Y.Z --tag` (or without `--tag`, then commit and tag yourself): it refuses a dirty tree or an existing tag, then sets `_SF_SHORTCUTS_VERSION` in zsh and bash and `ModuleVersion` in the `.psd1`. These must live in the repo because git installs get the repo files directly.

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`: it calls `ci.yml` (via `workflow_call`), runs `scripts/package.sh <tag>` to build `dist/sf-shortcuts-{zsh,bash,powershell}.zip` + `SHA256SUMS` (asset names are unversioned so `releases/latest/download/…` links keep working), creates the GitHub release, then publishes `dist/SfShortcuts` to the PowerShell Gallery if the `PSGALLERY_API_KEY` secret exists. `package.sh` fails if any port doesn't declare the tag's version. A new file a shell needs at runtime must be added to that shell's `pack` line in `package.sh`.

## PowerShell port differences

- No dynamic scoping: `Split-SfArgs` returns a hashtable (`Items`, `Org`, `Tests`, `Extra`) that is passed explicitly to `Invoke-SfDeploy`.
- PowerShell strips a bare `--` before a function sees `$args`, so `Extra` starts at a quoted `'--'` **or the first other `--flag`**.
- `sfdcheck`/`sfdpreview` set `$script:DeployMode` in try/finally instead of an env prefix.
- Errors go through `Write-SfError` (`Write-Error` with `-CategoryActivity sf-shortcuts`, so ConciseView prints `sf-shortcuts: …`); messages therefore omit the `sf-shortcuts:` prefix the shell versions print.
- The dimmed command line is `Write-Host` (information stream); tests drop it with `6>$null`.
- Completion is one `Register-ArgumentCompleter -Native` script block calling `Get-SfCompletions`; returning nothing falls back to file-name completion (used for `sfapex`).
- Exported commands are listed in both `FunctionsToExport` in the `.psd1` and the completer's `-CommandName` list.

## Adding a command

A new command touches several places that must stay in sync, in each of the three ports (zsh steps listed; bash and PowerShell have the same pieces — function, completion `case`/`switch`, `complete`/`Register-ArgumentCompleter` list, `sfhelp`, and for PowerShell `FunctionsToExport` in the `.psd1`):
1. The function itself (deploy types are usually a one-line `_sf_deploy_type` wrapper).
2. The `case $cmd` block in `_sf_shortcuts_complete`, and for deploy commands the `compadd` list used by `sfdcheck`/`sfdpreview`.
3. The `compdef` list at the bottom of the file.
4. The `sfhelp` heredoc.
5. The command tables in `README.md` (and the Settings table if adding an env var — env vars are also documented in the plugin's header comment and `sfhelp`).
6. A `check` line in `tests/run.zsh`, `tests/run.bash` and `tests/run.ps1` (the PowerShell one takes a script block: `check '<name>' '<expected>' { sfdcls A }`). Tests run inside a throwaway git repo in `mktemp -d` with a `feature` branch off `main`, so `sfdbranch` expectations depend on the files that setup creates.
