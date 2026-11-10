# sf-shortcuts — Salesforce CLI shortcuts for SFDX projects (PowerShell 7 version)
#
# Naming: sf + verb + type   (d = deploy, r = retrieve)
# Org:    uses your default org (see `sfdefault`) unless you pass -o <alias>
# Tests:  deploy commands accept -t Test1 [Test2 ...] to run specific tests
# Extra:  sf flags are passed straight to sf, starting at the first --flag
#         (PowerShell drops a bare -- before a function sees it; quote it as '--'
#         to pass short flags like -w)
#
# Run `sfhelp` for the full list.

# Settings (all optional, read from environment variables):
#   $env:SF_SOURCE_DIR   metadata folder; default: read from sfdx-project.json
#   $env:SF_BASE_BRANCH  branch sfdbranch compares against; default: origin's HEAD, then main/master
#   $env:SF_TEST_WAIT    minutes to wait for test results; default: 10
#   $env:SF_SHORTCUTS_NO_UPDATE_CHECK  set to 1 to turn off the update notice

# The version comes from the manifest; set it with scripts/bump-version.sh before tagging a release
$script:Version = (Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'SfShortcuts.psd1')).ModuleVersion
$script:ModuleDir = $PSScriptRoot
$script:RepoUrl = 'https://github.com/hggaguilera/sf-shortcuts'

# Set by sfdcheck/sfdpreview while they run a deploy command: start, dry-run or preview
$script:DeployMode = 'start'

$script:DeployCommands = @(
    'sfdobj', 'sfdfields', 'sfdcls', 'sfdtrg', 'sfdlwc', 'sfdaura', 'sfdvf', 'sfdflow',
    'sfdlayout', 'sfdperm', 'sfdmdt', 'sfdlabels', 'sfdmeta', 'sfdbranch'
)

# ---------- update notice ----------

function Get-SfUpdateCacheDir {
    $base = if ($env:XDG_CACHE_HOME) {
        $env:XDG_CACHE_HOME
    } elseif ($IsWindows) {
        $env:LOCALAPPDATA
    } else {
        Join-Path $HOME '.cache'
    }
    Join-Path $base 'sf-shortcuts'
}

# Returns how to update this install
function Get-SfUpdateHint([string]$Dir = $script:ModuleDir) {
    # Install-PSResource and Install-Module both leave this file in the module folder
    if (Test-Path -LiteralPath (Join-Path $Dir 'PSGetModuleInfo.xml')) {
        if (Get-Command Update-PSResource -ErrorAction Ignore) {
            return 'Update-PSResource SfShortcuts'
        }
        return 'Update-Module SfShortcuts'
    }
    if (Get-Command git -CommandType Application -ErrorAction Ignore) {
        $origin = git -C $Dir remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and "$origin" -like '*sf-shortcuts*') {
            return "git -C '$($Dir -replace "'", "''")' pull"
        }
    }
    "$script:RepoUrl#install"
}

# Returns the address the "latest release" page redirects to (.../releases/tag/vX.Y.Z).
# Follows the redirect and reads where it ended up: turning redirects off and reading the
# Location header doesn't work everywhere, as some setups follow the redirect anyway.
function Get-SfLatestLocation {
    $response = Invoke-WebRequest -Uri "$script:RepoUrl/releases/latest" -Method Head -TimeoutSec 10 -ErrorAction Stop
    "$($response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri)"
}

# Saves the latest released version. Keeps what's saved if the request fails or the
# response has no version in it.
function Invoke-SfUpdateFetch {
    try {
        $location = Get-SfLatestLocation
    } catch {
        return
    }
    if ($location -notmatch '/releases/tag/v(\d+\.\d+\.\d+)') {
        return
    }
    $latest = $Matches[1]
    $dir = Get-SfUpdateCacheDir
    New-Item -ItemType Directory -Force $dir | Out-Null
    $partial = Join-Path $dir "latest-version.$PID"
    Set-Content -LiteralPath $partial "$latest $([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    Move-Item -LiteralPath $partial -Destination (Join-Path $dir 'latest-version') -Force
}

# Fetches in a separate hidden process, so the command never waits on the network
function Start-SfUpdateRefresh {
    $manifest = (Join-Path $script:ModuleDir 'SfShortcuts.psd1') -replace "'", "''"
    $exe = Join-Path $PSHOME ($IsWindows ? 'pwsh.exe' : 'pwsh')
    $info = [System.Diagnostics.ProcessStartInfo]::new($exe)
    foreach ($a in '-NoProfile', '-NonInteractive', '-Command',
        "Import-Module -LiteralPath '$manifest'; & (Get-Module SfShortcuts) { Invoke-SfUpdateFetch }") {
        $info.ArgumentList.Add($a)
    }
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $null = [System.Diagnostics.Process]::Start($info)
}

# Shows the notice (at most once a day) and refreshes the saved version (at most once a week).
# Only reads local files, so it adds no noticeable time to a command.
function Invoke-SfUpdateTick {
    if ($env:SF_SHORTCUTS_NO_UPDATE_CHECK) {
        return
    }
    $dir = Get-SfUpdateCacheDir
    $noticeFile = Join-Path $dir 'last-notice'
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $latest = $null
    $checked = 0L
    if ((Get-Content -LiteralPath (Join-Path $dir 'latest-version') -TotalCount 1 -ErrorAction Ignore) -match '^(\d+\.\d+\.\d+) (\d+)$') {
        $latest = $Matches[1]
        $checked = [long]$Matches[2]
    }
    $noticed = 0L
    $line = Get-Content -LiteralPath $noticeFile -TotalCount 1 -ErrorAction Ignore
    if ($line -match '^\d+$') {
        $noticed = [long]$line
    }

    if ($latest -and [version]$latest -gt [version]$script:Version -and ($now - $noticed) -ge 86400) {
        Write-Host "sf-shortcuts $latest is available (you have $script:Version). Update: $(Get-SfUpdateHint)"
        Set-Content -LiteralPath $noticeFile "$now" -ErrorAction Ignore
    }
    if (($now - $checked) -ge 604800) {
        Start-SfUpdateRefresh
    }
}

# ---------- internals ----------

# Writes a non-terminating error shown as "sf-shortcuts: <message>"
function Write-SfError([string]$Message) {
    Write-Error -Message $Message -Category InvalidArgument -CategoryActivity 'sf-shortcuts'
}

# Returns the metadata folder: $env:SF_SOURCE_DIR, else the default package directory
# from sfdx-project.json (plus /main/default when that layout is used)
function Get-SfSourceDir {
    if ($env:SF_SOURCE_DIR) {
        return $env:SF_SOURCE_DIR
    }

    $pkg = $null
    try {
        $dirs = @((Get-Content -Raw -LiteralPath sfdx-project.json | ConvertFrom-Json).packageDirectories)
        $pkg = (@($dirs | Where-Object default -EQ $true) + $dirs | Select-Object -First 1).path
    } catch {
        # Unreadable sfdx-project.json: fall back to force-app
    }
    if (-not $pkg) {
        $pkg = 'force-app'
    }
    $pkg = $pkg.TrimEnd('/', '\')

    if (Test-Path -LiteralPath "$pkg/main/default" -PathType Container) {
        "$pkg/main/default"
    } else {
        $pkg
    }
}

# Returns the branch sfdbranch compares against
function Get-SfBaseBranch {
    if ($env:SF_BASE_BRANCH) {
        return $env:SF_BASE_BRANCH
    }

    $ref = git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $ref) {
        return $ref
    }

    foreach ($b in 'main', 'master') {
        git rev-parse --verify --quiet $b *>$null
        if ($LASTEXITCODE -eq 0) {
            return $b
        }
    }
    'main'
}

# Splits the arguments into Items, Org, Tests and Extra (passed straight to sf).
# Extra starts at a quoted '--' or at the first other --flag. Returns $null on error.
function Split-SfArgs([string[]]$Arguments) {
    $p = @{ Items = @(); Org = @(); Tests = @(); Extra = @() }
    $mode = 'Items'
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $a = $Arguments[$i]
        if ($a -in '-o', '--target-org') {
            if ($i + 1 -ge $Arguments.Count -or -not $Arguments[$i + 1]) {
                Write-SfError "$a needs an org alias"
                return $null
            }
            $p.Org = @('--target-org', $Arguments[++$i])
        } elseif ($a -in '-t', '--tests') {
            $mode = 'Tests'
        } elseif ($a -eq '--') {
            $p.Extra = @($Arguments | Select-Object -Skip ($i + 1))
            break
        } elseif ($a.StartsWith('--')) {
            $p.Extra = @($Arguments | Select-Object -Skip $i)
            break
        } else {
            $p[$mode] += $a
        }
    }
    $p
}

# Prints the command (dimmed), then runs it
function Invoke-SfCommand([string[]]$Command) {
    $exe = $Command[0]
    $rest = @($Command | Select-Object -Skip 1)

    # No sf installed: run the CLI through npx instead
    if ($exe -eq 'sf' -and -not (Get-Command sf -ErrorAction Ignore)) {
        if (-not (Get-Command npx -CommandType Application -ErrorAction Ignore)) {
            Write-SfError 'Salesforce CLI not found. Install it (npm install -g @salesforce/cli, or the installer from https://developer.salesforce.com/tools/salesforcecli) or install Node so npx can run it'
            return
        }
        $exe = 'npx'
        $rest = @('-y', '@salesforce/cli') + $rest
    }

    # Only in a terminal, so scripts are never affected, and a failure here never stops the command
    if (-not [Console]::IsErrorRedirected) {
        try {
            $null = Invoke-SfUpdateTick
        } catch {
            Write-Debug "Update check failed: $_"
        }
    }

    $shown = (@($exe) + $rest | ForEach-Object {
            if ($_ -match '[\s''"]' -or $_ -eq '') { "'" + ($_ -replace "'", "''") + "'" } else { $_ }
        }) -join ' '
    Write-Host "`e[2m→ $shown`e[0m"
    & $exe @rest
}

function Test-SfProject {
    if (Test-Path -LiteralPath sfdx-project.json -PathType Leaf) {
        return $true
    }
    Write-SfError 'run this from the project root (no sfdx-project.json here)'
    $false
}

function Get-SfTestWait {
    if ($env:SF_TEST_WAIT) { $env:SF_TEST_WAIT } else { '10' }
}

# Runs a deploy with the given --source-dir/--metadata flags, using the parsed
# org, tests and extra flags. The mode comes from sfdcheck/sfdpreview.
function Invoke-SfDeploy([hashtable]$Parsed, [string[]]$Flags) {
    $cmd = switch ($script:DeployMode) {
        'preview' { 'sf', 'project', 'deploy', 'preview' }
        'dry-run' { 'sf', 'project', 'deploy', 'start', '--dry-run' }
        default { 'sf', 'project', 'deploy', 'start' }
    }
    $cmd += @($Flags | Where-Object { $_ }) + $Parsed.Org

    if ($Parsed.Tests.Count -and $script:DeployMode -ne 'preview') {
        $cmd += '--test-level', 'RunSpecifiedTests'
        foreach ($t in $Parsed.Tests) {
            $cmd += '--tests', $t
        }
    }

    Invoke-SfCommand ($cmd + $Parsed.Extra)
}

# Shared body for "deploy one or more components of a type"
function Invoke-SfDeployType([string]$Name, [string]$Dir, [string]$Suffix, [string[]]$Arguments) {
    $p = Split-SfArgs $Arguments
    if (-not $p -or -not (Test-SfProject)) { return }
    if (-not $p.Items.Count) {
        Write-SfError "Usage: $Name Name1 [Name2 ...] [-o org] [-t Test1 ...] [-- sf flags]"
        return
    }

    $root = Get-SfSourceDir
    $flags = foreach ($i in $p.Items) { '--source-dir', "$root/$Dir/$i$Suffix" }
    Invoke-SfDeploy $p $flags
}

# Shared body for "retrieve one or more components by metadata type"
function Invoke-SfRetrieveType([string]$Name, [string]$Type, [string[]]$Arguments) {
    $p = Split-SfArgs $Arguments
    if (-not $p -or -not (Test-SfProject)) { return }
    if (-not $p.Items.Count) {
        Write-SfError "Usage: $Name Name1 [Name2 ...] [-o org] [-- sf flags]"
        return
    }

    $flags = foreach ($i in $p.Items) { '--metadata', "${Type}:$i" }
    Invoke-SfCommand (@('sf', 'project', 'retrieve', 'start') + $flags + $p.Org + $p.Extra)
}

# Runs a deploy command with $script:DeployMode set - Usage: Invoke-SfDeployMode <mode> <usage> <args>
function Invoke-SfDeployMode([string]$Mode, [string]$Usage, [string[]]$Arguments) {
    if (-not $Arguments.Count -or $Arguments[0] -notlike 'sfd*') {
        Write-SfError $Usage
        return
    }
    $rest = @($Arguments | Select-Object -Skip 1)
    $script:DeployMode = $Mode
    try {
        & $Arguments[0] @rest
    } finally {
        $script:DeployMode = 'start'
    }
}

# ---------- deploy ----------

function sfdobj    { Invoke-SfDeployType sfdobj    objects        ''                        $args }
function sfdfields { Invoke-SfDeployType sfdfields objects        '/fields'                 $args }
function sfdcls    { Invoke-SfDeployType sfdcls    classes        '.cls'                    $args }
function sfdtrg    { Invoke-SfDeployType sfdtrg    triggers       '.trigger'                $args }
function sfdlwc    { Invoke-SfDeployType sfdlwc    lwc            ''                        $args }
function sfdaura   { Invoke-SfDeployType sfdaura   aura           ''                        $args }
function sfdvf     { Invoke-SfDeployType sfdvf     pages          '.page'                   $args }
function sfdflow   { Invoke-SfDeployType sfdflow   flows          '.flow-meta.xml'          $args }
function sfdlayout { Invoke-SfDeployType sfdlayout layouts        '.layout-meta.xml'        $args }
function sfdperm   { Invoke-SfDeployType sfdperm   permissionsets '.permissionset-meta.xml' $args }
function sfdmdt    { Invoke-SfDeployType sfdmdt    customMetadata '.md-meta.xml'            $args }

# Deploy all custom labels - Usage: sfdlabels [-o org]
function sfdlabels {
    $p = Split-SfArgs $args
    if (-not $p -or -not (Test-SfProject)) { return }
    Invoke-SfDeploy $p @('--source-dir', "$(Get-SfSourceDir)/labels")
}

# Deploy by Type:Name - Usage: sfdmeta ApexClass:Foo [CustomObject:Bar ...] [-o org]
function sfdmeta {
    $p = Split-SfArgs $args
    if (-not $p -or -not (Test-SfProject)) { return }
    if (-not $p.Items.Count) {
        Write-SfError 'Usage: sfdmeta Type:Name1 [Type:Name2 ...] [-o org] [-t Test1 ...]'
        return
    }

    $flags = foreach ($i in $p.Items) { '--metadata', $i }
    Invoke-SfDeploy $p $flags
}

# Deploy everything changed on this branch (committed, uncommitted and untracked)
# since it split from the base branch. Deleted files are NOT removed from the org.
# Usage: sfdbranch [base-branch] [-o org] [-t Test1 ...]
function sfdbranch {
    $p = Split-SfArgs $args
    if (-not $p -or -not (Test-SfProject)) { return }

    $root = Get-SfSourceDir
    $base = if ($p.Items.Count) { $p.Items[0] } else { Get-SfBaseBranch }
    $mb = git merge-base $base HEAD
    if ($LASTEXITCODE -ne 0) { return }

    # git always prints paths with forward slashes
    $prefix = ($root -replace '\\', '/').TrimEnd('/') + '/'
    $files = @(
        @(git diff --name-only --diff-filter=ACMRT $mb) + @(git ls-files --others --exclude-standard) |
            Where-Object { $_ -and $_.StartsWith($prefix, [StringComparison]::Ordinal) } |
            Select-Object -Unique
    )

    if (-not $files.Count) {
        "No changes under $root since $base"
        return
    }

    "Changed since $base ($($files.Count) files):"
    $files | ForEach-Object { "  $_" }

    $flags = foreach ($f in $files) { '--source-dir', $f }
    Invoke-SfDeploy $p $flags
}

# Dry-run any sfd command - Usage: sfdcheck sfdcls MyClass -t MyClassTest
function sfdcheck {
    Invoke-SfDeployMode dry-run 'Usage: sfdcheck <sfd-command> [args ...]   e.g. sfdcheck sfdbranch -t MyTest' $args
}

# Show what any sfd command would deploy - Usage: sfdpreview sfdbranch
function sfdpreview {
    Invoke-SfDeployMode preview 'Usage: sfdpreview <sfd-command> [args ...]   e.g. sfdpreview sfdlwc myComp' $args
}

# ---------- retrieve ----------

function sfrcls { Invoke-SfRetrieveType sfrcls ApexClass                $args }
function sfrlwc { Invoke-SfRetrieveType sfrlwc LightningComponentBundle $args }

# Retrieve whole object(s) - Usage: sfrobj Account [Contact ...] [-o org]
function sfrobj {
    $p = Split-SfArgs $args
    if (-not $p -or -not (Test-SfProject)) { return }
    if (-not $p.Items.Count) {
        Write-SfError 'Usage: sfrobj Object1 [Object2 ...] [-o org]'
        return
    }

    $root = Get-SfSourceDir
    $flags = foreach ($i in $p.Items) { '--source-dir', "$root/objects/$i" }
    Invoke-SfCommand (@('sf', 'project', 'retrieve', 'start') + $flags + $p.Org + $p.Extra)
}

# Retrieve by Type:Name - Usage: sfrmeta ApexClass:Foo [Flow:Bar ...] [-o org]
function sfrmeta {
    $p = Split-SfArgs $args
    if (-not $p -or -not (Test-SfProject)) { return }
    if (-not $p.Items.Count) {
        Write-SfError 'Usage: sfrmeta Type:Name1 [Type:Name2 ...] [-o org]'
        return
    }

    $flags = foreach ($i in $p.Items) { '--metadata', $i }
    Invoke-SfCommand (@('sf', 'project', 'retrieve', 'start') + $flags + $p.Org + $p.Extra)
}

# ---------- tests ----------

# Run test class(es) with coverage - Usage: sftest MyTest [OtherTest ...] [-o org]
function sftest {
    $p = Split-SfArgs $args
    if (-not $p) { return }
    if (-not $p.Items.Count) {
        Write-SfError 'Usage: sftest TestClass1 [TestClass2 ...] [-o org]'
        return
    }

    $flags = foreach ($i in $p.Items) { '--class-names', $i }
    Invoke-SfCommand (@('sf', 'apex', 'run', 'test') + $flags +
        @('--result-format', 'human', '--code-coverage', '--wait', (Get-SfTestWait)) + $p.Org + $p.Extra)
}

# Run test method(s) - Usage: sftestm MyTest.testSomething [MyTest.other ...] [-o org]
function sftestm {
    $p = Split-SfArgs $args
    if (-not $p) { return }
    if (-not $p.Items.Count) {
        Write-SfError 'Usage: sftestm TestClass.method1 [TestClass.method2 ...] [-o org]'
        return
    }

    $flags = foreach ($i in $p.Items) { '--tests', $i }
    Invoke-SfCommand (@('sf', 'apex', 'run', 'test') + $flags +
        @('--result-format', 'human', '--code-coverage', '--wait', (Get-SfTestWait)) + $p.Org + $p.Extra)
}

# Run all local tests - Usage: sftestall [-o org]
function sftestall {
    $p = Split-SfArgs $args
    if (-not $p) { return }
    Invoke-SfCommand (@('sf', 'apex', 'run', 'test', '--test-level', 'RunLocalTests',
            '--result-format', 'human', '--code-coverage', '--wait', (Get-SfTestWait)) + $p.Org + $p.Extra)
}

# ---------- run / query ----------

# Run anonymous Apex from a file - Usage: sfapex script.apex [-o org]
function sfapex {
    $p = Split-SfArgs $args
    if (-not $p) { return }
    if (-not $p.Items.Count -or -not (Test-Path -LiteralPath $p.Items[0] -PathType Leaf)) {
        Write-SfError 'Usage: sfapex path/to/script.apex [-o org]'
        return
    }
    Invoke-SfCommand (@('sf', 'apex', 'run', '--file', $p.Items[0]) + $p.Org + $p.Extra)
}

# Run a SOQL query - Usage: sfq "SELECT Id FROM Account LIMIT 5" [-o org] [--use-tooling-api]
function sfq {
    $p = Split-SfArgs $args
    if (-not $p) { return }
    if (-not $p.Items.Count -or -not $p.Items[0]) {
        Write-SfError 'Usage: sfq "SELECT ..." [-o org] [-- sf flags]'
        return
    }
    Invoke-SfCommand (@('sf', 'data', 'query', '--query', $p.Items[0]) + $p.Org + $p.Extra)
}

# ---------- org / debug ----------

# Tail debug logs - Usage: sflogs [-o org]
function sflogs {
    $p = Split-SfArgs $args
    if (-not $p) { return }
    Invoke-SfCommand (@('sf', 'apex', 'tail', 'log') + $p.Org + $p.Extra)
}

# Open org in browser - Usage: sfopen [-o org]
function sfopen {
    $p = Split-SfArgs $args
    if (-not $p) { return }
    Invoke-SfCommand (@('sf', 'org', 'open') + $p.Org + $p.Extra)
}

# Show org details - Usage: sfwho [-o org]
function sfwho {
    $p = Split-SfArgs $args
    if (-not $p) { return }
    Invoke-SfCommand (@('sf', 'org', 'display') + $p.Org + $p.Extra)
}

# List authenticated orgs - Usage: sforgs
function sforgs {
    Invoke-SfCommand (@('sf', 'org', 'list') + $args)
}

# Show or set the default org for this project (-g for all projects)
# Usage: sfdefault            -> show current default
#        sfdefault myorg [-g] -> set default
function sfdefault {
    if (-not $args.Count) {
        Invoke-SfCommand @('sf', 'config', 'get', 'target-org')
        return
    }
    if ($args[1] -eq '-g') {
        Invoke-SfCommand @('sf', 'config', 'set', 'target-org', $args[0], '--global')
    } else {
        Invoke-SfCommand @('sf', 'config', 'set', 'target-org', $args[0])
    }
}

# ---------- help ----------

function sfhelp {
    @'
sf-shortcuts — org is your default unless you pass -o <alias>; --flags at the end go to sf

Deploy (one or more names; add -t Test1 [Test2 ...] to run specific tests)
  sfdobj     Account [...]                 whole object folder
  sfdfields  Account [...]                 object fields folder only
  sfdcls     MyClass [...]                 Apex classes
  sfdtrg     MyTrigger [...]               Apex triggers
  sfdlwc     myComp [...]                  Lightning Web Components
  sfdaura    myAuraComp [...]              Aura components
  sfdvf      MyPage [...]                  Visualforce pages
  sfdflow    My_Flow [...]                 Flows
  sfdlayout  Account-Account_Layout [...]  Page layouts
  sfdperm    MyPermSet [...]               Permission sets
  sfdmdt     MyType.Record [...]           Custom metadata records
  sfdlabels                                All custom labels
  sfdmeta    ApexClass:Foo [...]           Any Type:Name
  sfdbranch  [base]                        Everything changed vs base (default: origin HEAD)
  sfdcheck   <sfd-command> ...             Dry-run any of the above
  sfdpreview <sfd-command> ...             Preview what any of the above would deploy

Retrieve
  sfrobj   Account [...]                   whole object folder
  sfrcls   MyClass [...]                   Apex classes (works for new ones too)
  sfrlwc   myComp [...]                    LWCs (works for new ones too)
  sfrmeta  Flow:My_Flow [...]              Any Type:Name

Tests
  sftest    MyTest [...]                   test classes, with coverage
  sftestm   MyTest.method [...]            single test methods
  sftestall                                all local tests

Run / query
  sfapex  script.apex                      anonymous Apex
  sfq     "SELECT Id FROM Account"         SOQL (--use-tooling-api for Tooling)

Org / debug
  sfdefault [alias [-g]]                   show / set default org
  sforgs                                   list orgs
  sfwho                                    org details
  sfopen                                   open org in browser
  sflogs                                   tail debug logs

sf flags: everything from the first --flag on is passed to sf (sfdlwc myComp --ignore-conflicts).
PowerShell drops a bare --, so quote it to pass short flags: sftestall '--' -w 30

Settings (env vars, all optional)
  $env:SF_SOURCE_DIR   metadata folder        (default: from sfdx-project.json)
  $env:SF_BASE_BRANCH  sfdbranch base branch  (default: origin HEAD, then main/master)
  $env:SF_TEST_WAIT    test wait in minutes   (default: 10)
  $env:SF_SHORTCUTS_NO_UPDATE_CHECK = 1       turn off the update notice
'@
}

# ---------- completion ----------

# Returns component names of a type from the local project
# Usage: Get-SfComponentNames <dir> [<file-suffix> [<append>]]   (no suffix = folder names)
function Get-SfComponentNames([string]$Dir, [string]$Suffix, [string]$Append) {
    if (-not (Test-Path -LiteralPath sfdx-project.json -PathType Leaf)) { return }
    $base = "$(Get-SfSourceDir)/$Dir"
    if ($Suffix) {
        Get-ChildItem -LiteralPath $base -File -ErrorAction Ignore |
            Where-Object { $_.Name.EndsWith($Suffix, [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { $_.Name.Substring(0, $_.Name.Length - $Suffix.Length) + $Append }
    } else {
        Get-ChildItem -LiteralPath $base -Directory -ErrorAction Ignore | ForEach-Object Name
    }
}

# Returns org aliases from the sf CLI alias file
function Get-SfOrgAliases {
    $file = Join-Path $HOME '.sfdx' 'alias.json'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return }
    try {
        (Get-Content -Raw -LiteralPath $file | ConvertFrom-Json).orgs.PSObject.Properties.Name
    } catch {
        # Unreadable alias file: no completions
    }
}

# Returns completion candidates given the words before the cursor and the word being completed
function Get-SfCompletions([string[]]$Words, [string]$Current) {
    $cmd = $Words[0]

    if ($cmd -in 'sfdcheck', 'sfdpreview') {
        if ($Words.Count -eq 1) {
            return $script:DeployCommands
        }
        $Words = @($Words | Select-Object -Skip 1)
        $cmd = $Words[0]
    }

    if ($Words[-1] -in '-o', '--target-org') {
        return Get-SfOrgAliases
    }
    if ($Current.StartsWith('-')) {
        return '-o', '-t'
    }
    # Anything after -t is a test class
    if (@($Words | Select-Object -Skip 1) -contains '-t' -or @($Words | Select-Object -Skip 1) -contains '--tests') {
        return Get-SfComponentNames classes '.cls'
    }

    switch ($cmd) {
        { $_ -in 'sfdobj', 'sfdfields', 'sfrobj' } { Get-SfComponentNames objects }
        { $_ -in 'sfdcls', 'sfrcls', 'sftest' } { Get-SfComponentNames classes '.cls' }
        'sftestm' { Get-SfComponentNames classes '.cls' '.' }
        'sfdtrg' { Get-SfComponentNames triggers '.trigger' }
        { $_ -in 'sfdlwc', 'sfrlwc' } { Get-SfComponentNames lwc }
        'sfdaura' { Get-SfComponentNames aura }
        'sfdvf' { Get-SfComponentNames pages '.page' }
        'sfdflow' { Get-SfComponentNames flows '.flow-meta.xml' }
        'sfdlayout' { Get-SfComponentNames layouts '.layout-meta.xml' }
        'sfdperm' { Get-SfComponentNames permissionsets '.permissionset-meta.xml' }
        'sfdmdt' { Get-SfComponentNames customMetadata '.md-meta.xml' }
        'sfdefault' { Get-SfOrgAliases }
        # sfapex and anything else: no results, so PowerShell completes file names
    }
}

Register-ArgumentCompleter -Native -CommandName @(
    $script:DeployCommands + @('sfdcheck', 'sfdpreview', 'sfrobj', 'sfrcls', 'sfrlwc', 'sfrmeta',
        'sftest', 'sftestm', 'sftestall', 'sfapex', 'sfq', 'sflogs', 'sfopen', 'sfwho', 'sfdefault')
) -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # Words before the cursor, without the one being completed
    $words = @($commandAst.CommandElements |
            Where-Object { $_.Extent.StartOffset -lt $cursorPosition } |
            ForEach-Object { $_.Extent.Text })
    if ($wordToComplete) {
        $words = @($words | Select-Object -SkipLast 1)
    }

    Get-SfCompletions $words $wordToComplete |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
