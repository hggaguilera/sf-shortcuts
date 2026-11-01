# sf-shortcuts

Short, predictable commands for the Salesforce CLI (`sf`), with tab completion for your classes, components and orgs. Works in **zsh** and **bash** on macOS and Linux, and in **PowerShell 7** on Windows (or anywhere `pwsh` runs).

```zsh
sfdcls AccountService AccountServiceTest -t AccountServiceTest   # deploy two classes, run one test
sfdlwc accountCard -o uat                                         # deploy an LWC to the "uat" org
sfdbranch                                                         # deploy everything changed on this branch
sfdcheck sfdbranch                                                # ...or dry-run it first
```

Each command prints the full `sf` command before running it, so you always know what it did.

## Requirements

- zsh, bash 3.2+ or PowerShell 7+
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`), or [Node.js](https://nodejs.org) — if `sf` isn't installed, the shortcuts run it through `npx -y @salesforce/cli` (slower, and the first run downloads the CLI)
- git (for `sfdbranch`)
- [jq](https://jqlang.github.io/jq/) (optional for zsh and bash, used to read `sfdx-project.json` more reliably; PowerShell doesn't need it)

## Install

### zsh

**Oh My Zsh**

```zsh
git clone https://github.com/hggaguilera/sf-shortcuts ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/sf-shortcuts
```

Then add `sf-shortcuts` to the `plugins=(...)` line in `~/.zshrc`.

**zinit**

```zsh
zinit light hggaguilera/sf-shortcuts
```

**antidote** — add this line to `~/.zsh_plugins.txt`:

```
hggaguilera/sf-shortcuts
```

**No plugin manager**

```zsh
git clone https://github.com/hggaguilera/sf-shortcuts ~/.zsh/sf-shortcuts
echo 'source ~/.zsh/sf-shortcuts/sf-shortcuts.plugin.zsh' >> ~/.zshrc
```

For tab completion, source the plugin after `compinit` runs. Oh My Zsh and most plugin managers already do this.

### bash

```bash
git clone https://github.com/hggaguilera/sf-shortcuts ~/.bash/sf-shortcuts
echo 'source ~/.bash/sf-shortcuts/bash/sf-shortcuts.bash' >> ~/.bashrc
```

On macOS, bash login shells read `~/.bash_profile` instead, so add the `source` line there if that's what your terminal opens.

### PowerShell 7

```powershell
git clone https://github.com/hggaguilera/sf-shortcuts "$HOME\sf-shortcuts"
New-Item -ItemType Directory -Force (Split-Path $PROFILE) | Out-Null
Add-Content $PROFILE "`nImport-Module `"$HOME\sf-shortcuts\powershell\SfShortcuts.psd1`""
```

Restart PowerShell (or run `. $PROFILE`). The module needs PowerShell 7 (`pwsh`); it doesn't load in Windows PowerShell 5.1.

PowerShell differs from zsh and bash in a few places:

- **sf flags:** PowerShell drops a bare `--` before the command sees it, so everything from the first `--flag` on goes to `sf`: `sfdlwc myComp --ignore-conflicts` (`sfdlwc myComp -- --ignore-conflicts` also works). To pass short flags, quote the separator: `sftestall '--' -w 30`.
- **Settings** are environment variables: `$env:SF_TEST_WAIT = 30`. Put them in `$PROFILE` to keep them.
- **Errors** (usage, missing project) are written to the error stream, so `$?` is `$false` afterwards.

## How it works

- **Naming:** `sf` + action + type. `d` = deploy, `r` = retrieve. So `sfdcls` deploys classes and `sfrcls` retrieves them.
- **Org:** commands use your default org. Pass `-o <alias>` to use a different one, or set the default with `sfdefault <alias>`.
- **Several at once:** deploy and retrieve commands take one or more names.
- **Tests:** any deploy command takes `-t Test1 Test2 ...` to run those tests during the deploy.
- **Anything else:** arguments after `--` go straight to `sf`, e.g. `sfdlwc myComp -- --ignore-conflicts`.
- Run commands from your project root (the folder with `sfdx-project.json`).

## Commands

Run `sfhelp` in your terminal for this list.

### Deploy

| Command | Deploys | Example |
|---|---|---|
| `sfdobj` | whole object folder | `sfdobj Account Invoice__c` |
| `sfdfields` | an object's fields only | `sfdfields Account` |
| `sfdcls` | Apex classes | `sfdcls MyClass -t MyClassTest` |
| `sfdtrg` | Apex triggers | `sfdtrg AccountTrigger` |
| `sfdlwc` | Lightning Web Components | `sfdlwc accountCard` |
| `sfdaura` | Aura components | `sfdaura legacyCmp` |
| `sfdvf` | Visualforce pages | `sfdvf InvoicePdf` |
| `sfdflow` | Flows | `sfdflow New_Account_Flow` |
| `sfdlayout` | Page layouts | `sfdlayout Account-Account_Layout` |
| `sfdperm` | Permission sets | `sfdperm Sales_Admin` |
| `sfdmdt` | Custom metadata records | `sfdmdt Setting.Default` |
| `sfdlabels` | All custom labels | `sfdlabels` |
| `sfdmeta` | Any `Type:Name` | `sfdmeta ApexClass:Foo Flow:Bar` |
| `sfdbranch` | Everything changed on your branch | `sfdbranch` or `sfdbranch develop` |
| `sfdcheck` | Dry run of any deploy command | `sfdcheck sfdcls MyClass -t MyClassTest` |
| `sfdpreview` | Shows what a deploy command would send | `sfdpreview sfdbranch` |

`sfdbranch` includes committed, uncommitted and new files under your source folder. It does **not** remove deleted files from the org; use a destructive deploy for that.

### Retrieve

| Command | Retrieves | Example |
|---|---|---|
| `sfrobj` | whole object folder | `sfrobj Account` |
| `sfrcls` | Apex classes (also ones you don't have locally) | `sfrcls MyClass` |
| `sfrlwc` | LWCs (also ones you don't have locally) | `sfrlwc accountCard` |
| `sfrmeta` | Any `Type:Name` | `sfrmeta Flow:New_Account_Flow` |

### Tests

| Command | Runs | Example |
|---|---|---|
| `sftest` | test classes, with coverage | `sftest MyClassTest OtherTest` |
| `sftestm` | single test methods | `sftestm MyClassTest.testInsert` |
| `sftestall` | all local tests | `sftestall -o uat` |

### Run and query

| Command | Does | Example |
|---|---|---|
| `sfapex` | runs anonymous Apex from a file | `sfapex scripts/fix-data.apex` |
| `sfq` | runs a SOQL query | `sfq "SELECT Id, Name FROM Account LIMIT 5"` |

Add `-- --use-tooling-api` to `sfq` to query the Tooling API.

### Org and debugging

| Command | Does |
|---|---|
| `sfdefault` | shows the default org; `sfdefault uat` sets it for this project, `sfdefault uat -g` for all projects |
| `sforgs` | lists your orgs |
| `sfwho` | shows org details |
| `sfopen` | opens the org in your browser |
| `sflogs` | streams debug logs |

## Settings

All optional. Set them in `~/.zshrc` / `~/.bashrc`, or for one command (`SF_TEST_WAIT=30 sftestall`). In PowerShell, set `$env:SF_TEST_WAIT = 30` (in `$PROFILE` to keep it).

| Variable | What it does | Default |
|---|---|---|
| `SF_SOURCE_DIR` | folder that holds your metadata | the default package in `sfdx-project.json`, plus `/main/default` if that folder exists |
| `SF_BASE_BRANCH` | branch `sfdbranch` compares against | your remote's default branch, then `main`, then `master` |
| `SF_TEST_WAIT` | minutes to wait for test results | `10` |

## Tab completion

- Names of classes, triggers, LWCs, Aura components, objects, flows, layouts, permission sets and custom metadata records, read from your project.
- Org aliases after `-o` and for `sfdefault`.
- Test classes after `-t`.
- `sfdcheck` and `sfdpreview` complete the deploy command, then its arguments.

## Development

| Shell | Code | Tests |
|---|---|---|
| zsh | `sf-shortcuts.plugin.zsh` | `zsh tests/run.zsh` |
| bash | `bash/sf-shortcuts.bash` | `bash tests/run.bash` |
| PowerShell 7 | `powershell/SfShortcuts.psm1` (+ `.psd1` manifest) | `pwsh tests/run.ps1` |

The three versions provide the same commands and should stay in sync. The tests replace `sf` with a function that prints its arguments, so nothing is sent to an org. CI runs zsh and bash on Linux and macOS, and PowerShell on Linux, macOS and Windows.

## License

[MIT](LICENSE)
