#!/usr/bin/env pwsh
# Runs every shortcut against a fake `sf` that prints its arguments, inside a
# throwaway SFDX project, and checks the command each one would have run.
# Usage: pwsh tests/run.ps1

# GitHub Actions runs pwsh with a global 'Stop', which would turn the expected usage errors into
# exceptions. Module functions read the global value, so setting it in this script isn't enough.
$global:ErrorActionPreference = 'Continue'

$module = Join-Path $PSScriptRoot '..' 'powershell' 'SfShortcuts.psd1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) "sf-shortcuts-$([guid]::NewGuid())"
New-Item -ItemType Directory $tmp | Out-Null

Remove-Item env:SF_SOURCE_DIR, env:SF_BASE_BRANCH, env:SF_TEST_WAIT, env:SF_SHORTCUTS_NO_UPDATE_CHECK -ErrorAction Ignore
$origCache = $env:XDG_CACHE_HOME
$env:XDG_CACHE_HOME = Join-Path $tmp 'cache'
Import-Module $module -Force
$sfModule = Get-Module SfShortcuts

# The background refresh becomes a visible marker, so nothing here reaches the network
& $sfModule { function script:Start-SfUpdateRefresh { 'refresh' } }

# Fake sf: prints the arguments it received
function global:sf { "sf $($args -join ' ')" }

$script:pass = 0
$script:fail = 0
# Runs the script block and compares its output and errors (not the dimmed command line)
function check([string]$Name, [string]$Expected, [scriptblock]$Command) {
    $actual = (& $Command 2>&1 6>$null | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
        }) -join "`n"
    if ($actual -ceq $Expected) {
        $script:pass++
    } else {
        $script:fail++
        "FAIL: $Name"
        "  expected: $Expected"
        "  actual:   $actual"
    }
}

# Completion results for the line as if TAB were pressed at its end
function complete([string]$Line) {
    (TabExpansion2 -inputScript $Line -cursorColumn $Line.Length).CompletionMatches.CompletionText -join "`n"
}

$origPath = $env:PATH
Push-Location $tmp
try {
    # --- project with the standard layout ---
    git init -q -b main
    git config user.email test@example.com
    git config user.name test
    git config core.autocrlf false
    Set-Content sfdx-project.json '{"packageDirectories":[{"path":"force-app","default":true}]}'
    New-Item -ItemType Directory force-app/main/default/classes | Out-Null
    Set-Content force-app/main/default/classes/A.cls a
    git add .
    git commit -qm init
    git checkout -qb feature
    Set-Content force-app/main/default/classes/B.cls b
    Add-Content force-app/main/default/classes/A.cls a2
    Set-Content README.md x

    $S = 'force-app/main/default'

    check 'deploy classes with tests' `
        "sf project deploy start --source-dir $S/classes/A.cls --source-dir $S/classes/B.cls --test-level RunSpecifiedTests --tests ATest --tests BTest" `
    { sfdcls A B -t ATest BTest }
    check 'deploy to a named org' `
        "sf project deploy start --source-dir $S/classes/A.cls --target-org uat" `
    { sfdcls A -o uat }
    check 'pass-through flags' `
        "sf project deploy start --source-dir $S/lwc/c1 --target-org uat --ignore-conflicts" `
    { sfdlwc c1 -o uat -- --ignore-conflicts }
    check 'pass-through flags without --' `
        "sf project deploy start --source-dir $S/lwc/c1 --target-org uat --ignore-conflicts" `
    { sfdlwc c1 -o uat --ignore-conflicts }
    check "quoted '--' passes short flags" `
        'sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait 10 -w 30' `
    { sftestall '--' -w 30 }
    check 'object fields' `
        "sf project deploy start --source-dir $S/objects/Account/fields" `
    { sfdfields Account }
    check 'custom metadata' `
        "sf project deploy start --source-dir $S/customMetadata/T.R.md-meta.xml" `
    { sfdmdt T.R }
    check 'labels' `
        "sf project deploy start --source-dir $S/labels" `
    { sfdlabels }
    check 'deploy by type' `
        'sf project deploy start --metadata ApexClass:Foo --metadata Flow:Bar' `
    { sfdmeta ApexClass:Foo Flow:Bar }
    check 'dry run' `
        "sf project deploy start --dry-run --source-dir $S/triggers/T.trigger --test-level RunSpecifiedTests --tests TTest" `
    { sfdcheck sfdtrg T -t TTest }
    check 'preview drops tests' `
        "sf project deploy preview --source-dir $S/flows/F.flow-meta.xml" `
    { sfdpreview sfdflow F -t Ignored }
    check 'mode resets after sfdcheck' `
        "sf project deploy start --source-dir $S/classes/A.cls" `
    { sfdcheck sfdcls A | Out-Null; sfdcls A }
    check 'branch deploy (detects main, skips files outside the source folder)' `
        "Changed since main (2 files):`n  $S/classes/A.cls`n  $S/classes/B.cls`nsf project deploy start --source-dir $S/classes/A.cls --source-dir $S/classes/B.cls" `
    { sfdbranch }
    check 'retrieve classes' `
        'sf project retrieve start --metadata ApexClass:Foo --metadata ApexClass:Bar --target-org uat' `
    { sfrcls Foo Bar -o uat }
    check 'retrieve object' `
        "sf project retrieve start --source-dir $S/objects/Account" `
    { sfrobj Account }
    check 'test classes' `
        'sf apex run test --class-names T1 --class-names T2 --result-format human --code-coverage --wait 10' `
    { sftest T1 T2 }
    check 'test methods' `
        'sf apex run test --tests T1.m1 --result-format human --code-coverage --wait 10 --target-org uat' `
    { sftestm T1.m1 -o uat }
    check 'query' `
        'sf data query --query SELECT Id FROM Account --use-tooling-api' `
    { sfq 'SELECT Id FROM Account' -- --use-tooling-api }
    check 'set default org globally' `
        'sf config set target-org uat --global' `
    { sfdefault uat -g }
    check 'missing names shows usage' `
        'Usage: sfdcls Name1 [Name2 ...] [-o org] [-t Test1 ...] [-- sf flags]' `
    { sfdcls }
    check 'sfdcheck rejects other commands' `
        'Usage: sfdcheck <sfd-command> [args ...]   e.g. sfdcheck sfdbranch -t MyTest' `
    { sfdcheck ls }
    check '-o needs a value' `
        '-o needs an org alias' `
    { sfopen -o }

    # --- completion ---
    check 'complete class names' "A`nB" { complete 'sfdcls ' }
    check 'complete a partial class name' 'B' { complete 'sfdcls A B' }
    check 'complete test classes after -t' 'B' { complete 'sfdcheck sfdlwc c1 -t B' }
    check 'complete test methods with a dot' 'A.' { complete 'sftestm A' }
    check 'complete the command for sfdcheck' 'sfdcls' { complete 'sfdcheck sfdc' }

    # --- settings and other layouts ---
    check 'SF_SOURCE_DIR override' `
        'sf project deploy start --source-dir custom/classes/A.cls' `
    { $env:SF_SOURCE_DIR = 'custom'; try { sfdcls A } finally { Remove-Item env:SF_SOURCE_DIR } }
    check 'SF_TEST_WAIT override' `
        'sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait 30' `
    { $env:SF_TEST_WAIT = '30'; try { sftestall } finally { Remove-Item env:SF_TEST_WAIT } }

    Set-Content sfdx-project.json '{"packageDirectories":[{"path":"src"}]}'
    New-Item -ItemType Directory src/classes | Out-Null
    check 'flat layout without main/default' `
        'sf project deploy start --source-dir src/classes/A.cls' `
    { sfdcls A }

    Push-Location ([IO.Path]::GetPathRoot($tmp))
    check 'outside a project' `
        'run this from the project root (no sfdx-project.json here)' `
    { sfdcls A }
    Pop-Location

    # --- update notice ---
    $install = 'https://github.com/hggaguilera/sf-shortcuts#install'
    $cache = Join-Path $env:XDG_CACHE_HOME 'sf-shortcuts'
    $latestFile = Join-Path $cache 'latest-version'
    $noticeFile = Join-Path $cache 'last-notice'
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $day = 86400
    $week = 604800
    $notOurs = New-Item -ItemType Directory (Join-Path $tmp 'notours')
    & $sfModule { param($dir) $script:Version = '3.9.0'; $script:ModuleDir = $dir } $notOurs.FullName

    # seed <latest-version> <seconds since checked> [<seconds since notice>]
    function seed([string]$Latest, [long]$Checked, $Notice) {
        Remove-Item -Recurse -Force $cache -ErrorAction Ignore
        New-Item -ItemType Directory -Force $cache | Out-Null
        Set-Content $latestFile "$Latest $($now - $Checked)"
        if ($null -ne $Notice) { Set-Content $noticeFile "$($now - $Notice)" }
    }
    function tick { & $sfModule { Invoke-SfUpdateTick } 6>&1 }
    function cachedVersion { ((Get-Content $latestFile) -split ' ')[0] }

    seed 3.10.0 0
    check 'notice when a newer version is known (numeric compare, 10 > 9)' `
        "sf-shortcuts 3.10.0 is available (you have 3.9.0). Update: $install" `
    { tick }
    check 'notice shows once a day' '' { tick }
    seed 3.10.0 0 ($day - 60)
    check 'no notice within a day of the last one' '' { tick }
    seed 3.10.0 0 ($day + 60)
    check 'notice returns after a day' `
        "sf-shortcuts 3.10.0 is available (you have 3.9.0). Update: $install" `
    { tick }
    seed 3.9.0 0
    check 'no notice on the latest version' '' { tick }
    seed 3.8.9 0
    check 'no notice when ahead of the latest version' '' { tick }
    seed 3.9.0 ($week - 60)
    check 'no refresh within a week' '' { tick }
    seed 3.9.0 ($week + 60)
    check 'refresh after a week' 'refresh' { tick }
    Remove-Item -Recurse -Force $cache
    check 'refresh when nothing is cached' 'refresh' { tick }
    seed 'not-a-version' 0
    check 'corrupt cache is ignored and refreshed' 'refresh' { tick }
    seed 3.10.0 ($week + 60)
    check 'stale cache notifies and refreshes' `
        "sf-shortcuts 3.10.0 is available (you have 3.9.0). Update: $install`nrefresh" `
    { tick }
    seed 3.10.0 ($week + 60)
    check 'opt-out skips the notice and the refresh' '' `
    { $env:SF_SHORTCUTS_NO_UPDATE_CHECK = '1'; try { tick } finally { Remove-Item env:SF_SHORTCUTS_NO_UPDATE_CHECK } }
    if ([Console]::IsErrorRedirected) {
        seed 3.10.0 ($week + 60)
        check 'redirected commands skip the notice' 'sf org list' { sforgs 6>&1 | Where-Object { "$_" -notmatch '→' } }
        check "redirected commands don't mark the notice as shown" 'False' { Test-Path $noticeFile }
    }

    # Install-specific instructions
    $clone = Join-Path $tmp 'clone'
    git init -q $clone
    git -C $clone remote add origin https://github.com/hggaguilera/sf-shortcuts.git
    $gallery = New-Item -ItemType Directory (Join-Path $tmp 'gallery')
    Set-Content (Join-Path $gallery 'PSGetModuleInfo.xml') '<x/>'
    function hint([string]$Dir) { & $sfModule { param($d) Get-SfUpdateHint $d } $Dir }
    check 'git installs get a pull command' "git -C '$clone' pull" { hint $clone }
    check 'other git repos get the install link' $install { hint $notOurs.FullName }
    $galleryHint = (Get-Command Update-PSResource -ErrorAction Ignore) ? 'Update-PSResource SfShortcuts' : 'Update-Module SfShortcuts'
    check 'gallery installs get the module update command' $galleryHint { hint $gallery.FullName }

    # Fetching the latest version
    & $sfModule { function script:Get-SfLatestLocation { $script:FakeLocation } }
    function fetch([string]$Location) {
        & $sfModule { param($l) $script:FakeLocation = $l; Invoke-SfUpdateFetch } $Location
    }
    Remove-Item -Recurse -Force $cache -ErrorAction Ignore
    fetch 'https://github.com/hggaguilera/sf-shortcuts/releases/tag/v3.11.2'
    check 'fetch saves the version from the redirect' '3.11.2' { cachedVersion }
    seed 3.5.0 0
    fetch 'https://github.com/login'
    check 'a response without a version keeps the cache' '3.5.0' { cachedVersion }
    fetch ''
    check 'a failed request keeps the cache' '3.5.0' { cachedVersion }

    # --- no sf installed ---
    # Unqualified on purpose: "function:global:sf" finds the global scope but then looks for a
    # function literally named "global:sf", so it silently removes nothing
    Remove-Item Function:\sf
    if (Get-Command sf -CommandType Function -ErrorAction Ignore) { throw 'Could not remove the fake sf function' }
    $bin = New-Item -ItemType Directory (Join-Path $tmp bin)
    $empty = New-Item -ItemType Directory (Join-Path $tmp empty)
    Set-Content (Join-Path $bin npx) "#!/bin/sh`necho `"npx `$*`""
    Set-Content (Join-Path $bin npx.cmd) '@echo npx %*'
    if (-not $IsWindows) { chmod +x (Join-Path $bin npx) }

    check 'falls back to npx' `
        'npx -y @salesforce/cli org list' `
    { $env:PATH = $bin; try { sforgs } finally { $env:PATH = $origPath } }
    check 'no sf and no npx' `
        'Salesforce CLI not found. Install it (npm install -g @salesforce/cli, or the installer from https://developer.salesforce.com/tools/salesforcecli) or install Node so npx can run it' `
    { $env:PATH = $empty; try { sforgs } finally { $env:PATH = $origPath } }
} finally {
    $env:PATH = $origPath
    $env:XDG_CACHE_HOME = $origCache
    Pop-Location
    Remove-Item -Recurse -Force $tmp -ErrorAction Ignore
}

"$script:pass passed, $script:fail failed"
exit ($script:fail -eq 0 ? 0 : 1)
