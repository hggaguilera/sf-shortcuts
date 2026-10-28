#!/usr/bin/env zsh
# Runs every shortcut against a fake `sf` that prints its arguments, inside a
# throwaway SFDX project, and checks the command each one would have run.
# Usage: zsh tests/run.zsh

PLUGIN=${0:A:h:h}/sf-shortcuts.plugin.zsh
TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT

unset SF_SOURCE_DIR SF_BASE_BRANCH SF_TEST_WAIT
source $PLUGIN

# Fake sf: prints the arguments it received
sf() { print -r -- "sf ${(j: :)@}" }

pass=0 fail=0
check() {
  local name=$1 expected=$2
  shift 2
  local actual
  actual=$("$@" 2>&1 | grep -v $'^\e\\[2m→')
  if [[ $actual == "$expected" ]]; then
    (( pass++ ))
  else
    (( fail++ ))
    print -r -- "FAIL: $name"
    print -r -- "  expected: $expected"
    print -r -- "  actual:   $actual"
  fi
}

# --- project with the standard layout ---
cd $TMP
git init -q -b main
git config user.email test@example.com
git config user.name test
print '{"packageDirectories":[{"path":"force-app","default":true}]}' > sfdx-project.json
mkdir -p force-app/main/default/classes
print a > force-app/main/default/classes/A.cls
git add . && git commit -qm init
git checkout -qb feature
print b > force-app/main/default/classes/B.cls
print a2 >> force-app/main/default/classes/A.cls
print x > README.md

S=force-app/main/default

check "deploy classes with tests" \
  "sf project deploy start --source-dir $S/classes/A.cls --source-dir $S/classes/B.cls --test-level RunSpecifiedTests --tests ATest --tests BTest" \
  sfdcls A B -t ATest BTest
check "deploy to a named org" \
  "sf project deploy start --source-dir $S/classes/A.cls --target-org uat" \
  sfdcls A -o uat
check "pass-through flags" \
  "sf project deploy start --source-dir $S/lwc/c1 --target-org uat --ignore-conflicts" \
  sfdlwc c1 -o uat -- --ignore-conflicts
check "object fields" \
  "sf project deploy start --source-dir $S/objects/Account/fields" \
  sfdfields Account
check "custom metadata" \
  "sf project deploy start --source-dir $S/customMetadata/T.R.md-meta.xml" \
  sfdmdt T.R
check "labels" \
  "sf project deploy start --source-dir $S/labels" \
  sfdlabels
check "deploy by type" \
  "sf project deploy start --metadata ApexClass:Foo --metadata Flow:Bar" \
  sfdmeta ApexClass:Foo Flow:Bar
check "dry run" \
  "sf project deploy start --dry-run --source-dir $S/triggers/T.trigger --test-level RunSpecifiedTests --tests TTest" \
  sfdcheck sfdtrg T -t TTest
check "preview drops tests" \
  "sf project deploy preview --source-dir $S/flows/F.flow-meta.xml" \
  sfdpreview sfdflow F -t Ignored
check "branch deploy (detects main, skips files outside the source folder)" \
  "Changed since main (2 files):
  $S/classes/A.cls
  $S/classes/B.cls
sf project deploy start --source-dir $S/classes/A.cls --source-dir $S/classes/B.cls" \
  sfdbranch
check "retrieve classes" \
  "sf project retrieve start --metadata ApexClass:Foo --metadata ApexClass:Bar --target-org uat" \
  sfrcls Foo Bar -o uat
check "retrieve object" \
  "sf project retrieve start --source-dir $S/objects/Account" \
  sfrobj Account
check "test classes" \
  "sf apex run test --class-names T1 --class-names T2 --result-format human --code-coverage --wait 10" \
  sftest T1 T2
check "test methods" \
  "sf apex run test --tests T1.m1 --result-format human --code-coverage --wait 10 --target-org uat" \
  sftestm T1.m1 -o uat
check "query" \
  "sf data query --query SELECT Id FROM Account --use-tooling-api" \
  sfq 'SELECT Id FROM Account' -- --use-tooling-api
check "set default org globally" \
  "sf config set target-org uat --global" \
  sfdefault uat -g
check "missing names shows usage" \
  "Usage: sfdcls Name1 [Name2 ...] [-o org] [-t Test1 ...] [-- sf flags]" \
  sfdcls
check "sfdcheck rejects other commands" \
  "Usage: sfdcheck <sfd-command> [args ...]   e.g. sfdcheck sfdbranch -t MyTest" \
  sfdcheck ls
check "-o needs a value" \
  "sf-shortcuts: -o needs an org alias" \
  sfopen -o

# --- settings and other layouts ---
with_custom_dir() { SF_SOURCE_DIR=custom sfdcls "$@" }
check "SF_SOURCE_DIR override" \
  "sf project deploy start --source-dir custom/classes/A.cls" \
  with_custom_dir A

print '{"packageDirectories":[{"path":"src"}]}' > sfdx-project.json
mkdir -p src/classes
check "flat layout without main/default" \
  "sf project deploy start --source-dir src/classes/A.cls" \
  sfdcls A

cd /
check "outside a project" \
  "sf-shortcuts: run this from the project root (no sfdx-project.json here)" \
  sfdcls A

# --- no sf installed ---
unfunction sf
mkdir -p $TMP/bin $TMP/empty
print -r -- '#!/bin/sh
echo "npx $*"' > $TMP/bin/npx
chmod +x $TMP/bin/npx
with_npx() { local -a path=($TMP/bin); sforgs }
without_npx() { local -a path=($TMP/empty); sforgs }
check "falls back to npx" \
  "npx -y @salesforce/cli org list" \
  with_npx
check "no sf and no npx" \
  "sf-shortcuts: Salesforce CLI not found. Install it (brew install sf, or npm install -g @salesforce/cli) or install Node so npx can run it" \
  without_npx

print "$pass passed, $fail failed"
(( fail == 0 ))
