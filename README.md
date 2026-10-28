# sf-shortcuts

Short, predictable zsh commands for the Salesforce CLI (`sf`), with tab completion for your classes, components and orgs.

```zsh
sfdcls AccountService AccountServiceTest -t AccountServiceTest   # deploy two classes, run one test
sfdlwc accountCard -o uat                                         # deploy an LWC to the "uat" org
sfdbranch                                                         # deploy everything changed on this branch
sfdcheck sfdbranch                                                # ...or dry-run it first
```

Each command prints the full `sf` command before running it, so you always know what it did.

## Requirements

- zsh
- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`), or [Node.js](https://nodejs.org) — if `sf` isn't installed, the shortcuts run it through `npx -y @salesforce/cli` (slower, and the first run downloads the CLI)
- git (for `sfdbranch`)
- [jq](https://jqlang.github.io/jq/) (optional, used to read `sfdx-project.json` more reliably)

## Install

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

All optional. Set them in `~/.zshrc`, or for one command (`SF_TEST_WAIT=30 sftestall`).

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

```zsh
zsh tests/run.zsh
```

The tests replace `sf` with a function that prints its arguments, so nothing is sent to an org.

## License

[MIT](LICENSE)
