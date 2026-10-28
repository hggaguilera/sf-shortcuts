# sf-shortcuts — Salesforce CLI shortcuts for SFDX projects
#
# Naming: sf + verb + type   (d = deploy, r = retrieve)
# Org:    uses your default org (see `sfdefault`) unless you pass -o <alias>
# Tests:  deploy commands accept -t Test1 [Test2 ...] to run specific tests
# Extra:  anything after -- is passed straight to sf
#
# Run `sfhelp` for the full list.

# Settings (all optional):
#   SF_SOURCE_DIR   metadata folder; default: read from sfdx-project.json
#   SF_BASE_BRANCH  branch sfdbranch compares against; default: origin's HEAD, then main/master
#   SF_TEST_WAIT    minutes to wait for test results; default: 10

: ${SF_TEST_WAIT:=10}

# ---------- internals ----------

# Prints the metadata folder: $SF_SOURCE_DIR, else the default package directory
# from sfdx-project.json (plus /main/default when that layout is used)
_sf_source_dir() {
  if [[ -n $SF_SOURCE_DIR ]]; then
    print -r -- "$SF_SOURCE_DIR"
    return
  fi

  local pkg
  if (( $+commands[jq] )); then
    pkg=$(jq -r '(.packageDirectories | map(select(.default == true)) + .packageDirectories)[0].path // empty' sfdx-project.json 2>/dev/null)
  fi
  if [[ -z $pkg ]]; then
    # No jq: take the first "path" entry
    local json=${(j: :)${(f)"$(<sfdx-project.json)"}}
    [[ $json =~ '"path"[[:space:]]*:[[:space:]]*"([^"]+)"' ]] && pkg=$match[1]
  fi
  pkg=${${pkg:-force-app}%/}

  if [[ -d $pkg/main/default ]]; then
    print -r -- "$pkg/main/default"
  else
    print -r -- "$pkg"
  fi
}

# Prints the branch sfdbranch compares against
_sf_base_branch() {
  if [[ -n $SF_BASE_BRANCH ]]; then
    print -r -- "$SF_BASE_BRANCH"
    return
  fi

  local ref
  ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [[ -n $ref ]]; then
    print -r -- "$ref"
    return
  fi

  local b
  for b in main master; do
    if git rev-parse --verify --quiet "$b" >/dev/null; then
      print -r -- "$b"
      return
    fi
  done
  print -r -- main
}

# Splits "$@" into the caller's local arrays: items, org, tests, extra
_sf_parse() {
  items=() org=() tests=() extra=()
  local mode=items
  while (( $# )); do
    case $1 in
      -o|--target-org)
        if [[ -z $2 ]]; then
          print -u2 "sf-shortcuts: $1 needs an org alias"
          return 1
        fi
        org=(--target-org "$2")
        shift 2
        continue
        ;;
      -t|--tests)
        mode=tests
        shift
        continue
        ;;
      --)
        shift
        extra=("$@")
        break
        ;;
    esac
    if [[ $mode == tests ]]; then
      tests+=("$1")
    else
      items+=("$1")
    fi
    shift
  done
}

# Prints the command (dimmed), then runs it
_sf_run() {
  # No sf installed: run the CLI through npx instead
  if [[ $1 == sf ]] && (( ! $+commands[sf] && ! $+functions[sf] )); then
    if (( ! $+commands[npx] )); then
      print -u2 "sf-shortcuts: Salesforce CLI not found. Install it (brew install sf, or npm install -g @salesforce/cli) or install Node so npx can run it"
      return 127
    fi
    shift
    set -- npx -y @salesforce/cli "$@"
  fi
  print -r -- $'\e[2m'"→ ${(q-)@}"$'\e[0m'
  "$@"
}

_sf_require_project() {
  [[ -f sfdx-project.json ]] && return 0
  print -u2 "sf-shortcuts: run this from the project root (no sfdx-project.json here)"
  return 1
}

# Runs a deploy with the given --source-dir/--metadata flags.
# Reads org, tests and extra from the caller; mode comes from sfdcheck/sfdpreview.
_sf_deploy() {
  local -a cmd
  case ${_SF_DEPLOY_MODE:-start} in
    preview) cmd=(sf project deploy preview "$@" "${org[@]}") ;;
    dry-run) cmd=(sf project deploy start --dry-run "$@" "${org[@]}") ;;
    *)       cmd=(sf project deploy start "$@" "${org[@]}") ;;
  esac

  if (( ${#tests} )) && [[ $_SF_DEPLOY_MODE != preview ]]; then
    cmd+=(--test-level RunSpecifiedTests)
    local t
    for t in "${tests[@]}"; do
      cmd+=(--tests "$t")
    done
  fi

  _sf_run "${cmd[@]}" "${extra[@]}"
}

# Shared body for "deploy one or more components of a type"
# Usage: _sf_deploy_type <command-name> <dir> <suffix> "$@"
_sf_deploy_type() {
  local name=$1 dir=$2 suffix=$3
  shift 3
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_require_project || return 1
  if (( ! ${#items} )); then
    print -u2 "Usage: $name Name1 [Name2 ...] [-o org] [-t Test1 ...] [-- sf flags]"
    return 1
  fi

  local root=$(_sf_source_dir)
  local -a flags
  local i
  for i in "${items[@]}"; do
    flags+=(--source-dir "$root/$dir/$i$suffix")
  done
  _sf_deploy "${flags[@]}"
}

# Shared body for "retrieve one or more components by metadata type"
# Usage: _sf_retrieve_type <command-name> <MetadataType> "$@"
_sf_retrieve_type() {
  local name=$1 type=$2
  shift 2
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_require_project || return 1
  if (( ! ${#items} )); then
    print -u2 "Usage: $name Name1 [Name2 ...] [-o org] [-- sf flags]"
    return 1
  fi

  local -a flags
  local i
  for i in "${items[@]}"; do
    flags+=(--metadata "$type:$i")
  done
  _sf_run sf project retrieve start "${flags[@]}" "${org[@]}" "${extra[@]}"
}

# ---------- deploy ----------

sfdobj()    { _sf_deploy_type sfdobj    objects        ""                        "$@" }
sfdfields() { _sf_deploy_type sfdfields objects        "/fields"                 "$@" }
sfdcls()    { _sf_deploy_type sfdcls    classes        ".cls"                    "$@" }
sfdtrg()    { _sf_deploy_type sfdtrg    triggers       ".trigger"                "$@" }
sfdlwc()    { _sf_deploy_type sfdlwc    lwc            ""                        "$@" }
sfdaura()   { _sf_deploy_type sfdaura   aura           ""                        "$@" }
sfdvf()     { _sf_deploy_type sfdvf     pages          ".page"                   "$@" }
sfdflow()   { _sf_deploy_type sfdflow   flows          ".flow-meta.xml"          "$@" }
sfdlayout() { _sf_deploy_type sfdlayout layouts        ".layout-meta.xml"        "$@" }
sfdperm()   { _sf_deploy_type sfdperm   permissionsets ".permissionset-meta.xml" "$@" }
sfdmdt()    { _sf_deploy_type sfdmdt    customMetadata ".md-meta.xml"            "$@" }

# Deploy all custom labels - Usage: sfdlabels [-o org]
sfdlabels() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_require_project || return 1
  _sf_deploy --source-dir "$(_sf_source_dir)/labels"
}

# Deploy by Type:Name - Usage: sfdmeta ApexClass:Foo [CustomObject:Bar ...] [-o org]
sfdmeta() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_require_project || return 1
  if (( ! ${#items} )); then
    print -u2 "Usage: sfdmeta Type:Name1 [Type:Name2 ...] [-o org] [-t Test1 ...]"
    return 1
  fi

  local -a flags
  local i
  for i in "${items[@]}"; do
    flags+=(--metadata "$i")
  done
  _sf_deploy "${flags[@]}"
}

# Deploy everything changed on this branch (committed, uncommitted and untracked)
# since it split from the base branch. Deleted files are NOT removed from the org.
# Usage: sfdbranch [base-branch] [-o org] [-t Test1 ...]
sfdbranch() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_require_project || return 1

  local root=$(_sf_source_dir)
  local base=${items[1]:-$(_sf_base_branch)}
  local mb
  mb=$(git merge-base "$base" HEAD) || return 1

  local -a files
  files=(${(fu)"$(
    git diff --name-only --diff-filter=ACMRT "$mb"
    git ls-files --others --exclude-standard
  )"})
  files=(${(M)files:#${(b)root}/*})

  if (( ! ${#files} )); then
    print "No changes under $root since $base"
    return 0
  fi

  print "Changed since $base (${#files} files):"
  print -l -- "  "${^files}

  local -a flags
  local f
  for f in "${files[@]}"; do
    flags+=(--source-dir "$f")
  done
  _sf_deploy "${flags[@]}"
}

# Dry-run any sfd command - Usage: sfdcheck sfdcls MyClass -t MyClassTest
sfdcheck() {
  if [[ $1 != sfd* ]]; then
    print -u2 "Usage: sfdcheck <sfd-command> [args ...]   e.g. sfdcheck sfdbranch -t MyTest"
    return 1
  fi
  _SF_DEPLOY_MODE=dry-run "$@"
}

# Show what any sfd command would deploy - Usage: sfdpreview sfdbranch
sfdpreview() {
  if [[ $1 != sfd* ]]; then
    print -u2 "Usage: sfdpreview <sfd-command> [args ...]   e.g. sfdpreview sfdlwc myComp"
    return 1
  fi
  _SF_DEPLOY_MODE=preview "$@"
}

# ---------- retrieve ----------

sfrcls()  { _sf_retrieve_type sfrcls  ApexClass               "$@" }
sfrlwc()  { _sf_retrieve_type sfrlwc  LightningComponentBundle "$@" }

# Retrieve whole object(s) - Usage: sfrobj Account [Contact ...] [-o org]
sfrobj() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_require_project || return 1
  if (( ! ${#items} )); then
    print -u2 "Usage: sfrobj Object1 [Object2 ...] [-o org]"
    return 1
  fi

  local root=$(_sf_source_dir)
  local -a flags
  local i
  for i in "${items[@]}"; do
    flags+=(--source-dir "$root/objects/$i")
  done
  _sf_run sf project retrieve start "${flags[@]}" "${org[@]}" "${extra[@]}"
}

# Retrieve by Type:Name - Usage: sfrmeta ApexClass:Foo [Flow:Bar ...] [-o org]
sfrmeta() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_require_project || return 1
  if (( ! ${#items} )); then
    print -u2 "Usage: sfrmeta Type:Name1 [Type:Name2 ...] [-o org]"
    return 1
  fi

  local -a flags
  local i
  for i in "${items[@]}"; do
    flags+=(--metadata "$i")
  done
  _sf_run sf project retrieve start "${flags[@]}" "${org[@]}" "${extra[@]}"
}

# ---------- tests ----------

# Run test class(es) with coverage - Usage: sftest MyTest [OtherTest ...] [-o org]
sftest() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  if (( ! ${#items} )); then
    print -u2 "Usage: sftest TestClass1 [TestClass2 ...] [-o org]"
    return 1
  fi

  local -a flags
  local i
  for i in "${items[@]}"; do
    flags+=(--class-names "$i")
  done
  _sf_run sf apex run test "${flags[@]}" --result-format human --code-coverage --wait "$SF_TEST_WAIT" "${org[@]}" "${extra[@]}"
}

# Run test method(s) - Usage: sftestm MyTest.testSomething [MyTest.other ...] [-o org]
sftestm() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  if (( ! ${#items} )); then
    print -u2 "Usage: sftestm TestClass.method1 [TestClass.method2 ...] [-o org]"
    return 1
  fi

  local -a flags
  local i
  for i in "${items[@]}"; do
    flags+=(--tests "$i")
  done
  _sf_run sf apex run test "${flags[@]}" --result-format human --code-coverage --wait "$SF_TEST_WAIT" "${org[@]}" "${extra[@]}"
}

# Run all local tests - Usage: sftestall [-o org]
sftestall() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_run sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait "$SF_TEST_WAIT" "${org[@]}" "${extra[@]}"
}

# ---------- run / query ----------

# Run anonymous Apex from a file - Usage: sfapex script.apex [-o org]
sfapex() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  if [[ ! -f ${items[1]} ]]; then
    print -u2 "Usage: sfapex path/to/script.apex [-o org]"
    return 1
  fi
  _sf_run sf apex run --file "${items[1]}" "${org[@]}" "${extra[@]}"
}

# Run a SOQL query - Usage: sfq "SELECT Id FROM Account LIMIT 5" [-o org] [-- --use-tooling-api]
sfq() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  if [[ -z ${items[1]} ]]; then
    print -u2 "Usage: sfq \"SELECT ...\" [-o org] [-- sf flags]"
    return 1
  fi
  _sf_run sf data query --query "${items[1]}" "${org[@]}" "${extra[@]}"
}

# ---------- org / debug ----------

# Tail debug logs - Usage: sflogs [-o org]
sflogs() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_run sf apex tail log "${org[@]}" "${extra[@]}"
}

# Open org in browser - Usage: sfopen [-o org]
sfopen() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_run sf org open "${org[@]}" "${extra[@]}"
}

# Show org details - Usage: sfwho [-o org]
sfwho() {
  local -a items org tests extra
  _sf_parse "$@" || return 1
  _sf_run sf org display "${org[@]}" "${extra[@]}"
}

# List authenticated orgs - Usage: sforgs
sforgs() {
  _sf_run sf org list "$@"
}

# Show or set the default org for this project (-g for all projects)
# Usage: sfdefault            -> show current default
#        sfdefault myorg [-g] -> set default
sfdefault() {
  if (( ! $# )); then
    _sf_run sf config get target-org
    return
  fi
  local alias=$1
  shift
  if [[ $1 == -g ]]; then
    _sf_run sf config set target-org "$alias" --global
  else
    _sf_run sf config set target-org "$alias"
  fi
}

# ---------- help ----------

sfhelp() {
  cat <<'EOF'
sf-shortcuts — org is your default unless you pass -o <alias>; anything after -- goes to sf

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
  sfq     "SELECT Id FROM Account"         SOQL (-- --use-tooling-api for Tooling)

Org / debug
  sfdefault [alias [-g]]                   show / set default org
  sforgs                                   list orgs
  sfwho                                    org details
  sfopen                                   open org in browser
  sflogs                                   tail debug logs

Settings (env vars, all optional)
  SF_SOURCE_DIR   metadata folder        (default: from sfdx-project.json)
  SF_BASE_BRANCH  sfdbranch base branch  (default: origin HEAD, then main/master)
  SF_TEST_WAIT    test wait in minutes   (default: 10)
EOF
}

# ---------- completion ----------

# Completes component names of a type from the local project
# Usage: _sf_complete_names <dir> [<file-suffix> [compadd options]]   (no suffix = folder names)
_sf_complete_names() {
  [[ -f sfdx-project.json ]] || return 1
  local base="$(_sf_source_dir)/$1" suffix=$2
  shift 2 2>/dev/null || shift
  local -a names
  if [[ -n $suffix ]]; then
    names=(${base}/*${suffix}(N:t))
    names=(${names%$suffix})
  else
    names=(${base}/*(N/:t))
  fi
  compadd "$@" -a names
}

# Completes org aliases from the sf CLI alias file
_sf_complete_orgs() {
  local file=~/.sfdx/alias.json
  [[ -f $file ]] || return 1
  local json=${(j: :)${(f)"$(<$file)"}}
  json=${json#*\"orgs\"*\{}
  json=${json%%\}*}
  local -a aliases
  local pair
  for pair in ${(s:,:)json}; do
    [[ $pair =~ '"([^"]+)"[[:space:]]*:' ]] && aliases+=($match[1])
  done
  compadd -a aliases
}

_sf_shortcuts_complete() {
  local cmd=$words[1]

  if [[ $cmd == (sfdcheck|sfdpreview) ]]; then
    if (( CURRENT == 2 )); then
      compadd sfdobj sfdfields sfdcls sfdtrg sfdlwc sfdaura sfdvf sfdflow \
        sfdlayout sfdperm sfdmdt sfdlabels sfdmeta sfdbranch
      return
    fi
    shift words
    (( CURRENT-- ))
    cmd=$words[1]
  fi

  if [[ $words[CURRENT-1] == (-o|--target-org) ]]; then
    _sf_complete_orgs
    return
  fi
  if [[ $PREFIX == -* ]]; then
    compadd -- -o -t
    return
  fi
  # Anything after -t is a test class
  local t=${words[(I)(-t|--tests)]}
  if (( t && t < CURRENT )); then
    _sf_complete_names classes .cls
    return
  fi

  case $cmd in
    sfdobj|sfdfields|sfrobj) _sf_complete_names objects ;;
    sfdcls|sfrcls|sftest)    _sf_complete_names classes .cls ;;
    sftestm)                 _sf_complete_names classes .cls -S . -q ;;
    sfdtrg)                  _sf_complete_names triggers .trigger ;;
    sfdlwc|sfrlwc)           _sf_complete_names lwc ;;
    sfdaura)                 _sf_complete_names aura ;;
    sfdvf)                   _sf_complete_names pages .page ;;
    sfdflow)                 _sf_complete_names flows .flow-meta.xml ;;
    sfdlayout)               _sf_complete_names layouts .layout-meta.xml ;;
    sfdperm)                 _sf_complete_names permissionsets .permissionset-meta.xml ;;
    sfdmdt)                  _sf_complete_names customMetadata .md-meta.xml ;;
    sfapex)                  _files -g '*.apex' ;;
    sfdefault)               _sf_complete_orgs ;;
  esac
}

# compdef exists once compinit has run (Oh My Zsh and most plugin managers do this first)
if (( $+functions[compdef] )); then
  compdef _sf_shortcuts_complete \
    sfdobj sfdfields sfdcls sfdtrg sfdlwc sfdaura sfdvf sfdflow sfdlayout sfdperm sfdmdt \
    sfdlabels sfdmeta sfdbranch sfdcheck sfdpreview \
    sfrobj sfrcls sfrlwc sfrmeta \
    sftest sftestm sftestall sfapex sfq sflogs sfopen sfwho sfdefault
fi
