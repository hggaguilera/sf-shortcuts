#!/usr/bin/env bash
# Sets the version in all three ports. Run it and commit before tagging a release,
# or pass --tag to commit the change and create the vX.Y.Z tag in one step.
# Usage: bash scripts/bump-version.sh 1.2.0 [--tag]

set -euo pipefail

usage() {
  echo "Usage: $0 <version> [--tag]   e.g. $0 1.2.0 (or v1.2.0)" >&2
  exit 1
}

version='' tag=0
for arg in "$@"; do
  case $arg in
    --tag) tag=1 ;;
    -*) usage ;;
    *) [[ -z $version ]] || usage; version=${arg#v} ;;
  esac
done
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
files=("$root/sf-shortcuts.plugin.zsh" "$root/bash/sf-shortcuts.bash" "$root/powershell/SfShortcuts.psd1")

if ((tag)); then
  cd "$root"
  if [[ -n $(git status --porcelain) ]]; then
    echo "Working tree has uncommitted changes; commit or stash them before using --tag." >&2
    exit 1
  fi
  if git rev-parse -q --verify "refs/tags/v$version" >/dev/null; then
    echo "Tag v$version already exists." >&2
    exit 1
  fi
fi

for file in "${files[@]:0:2}"; do
  sed -i.bak -E "s/^_SF_SHORTCUTS_VERSION=.*/_SF_SHORTCUTS_VERSION=$version/" "$file"
  rm "$file.bak"
done

psd1=${files[2]}
sed -i.bak -E "s/^( *ModuleVersion *= *)'[^']*'/\1'$version'/" "$psd1"
rm "$psd1.bak"

if ((tag)); then
  done_msg="already set to $version"
  if ! git diff --quiet -- "${files[@]}"; then
    git commit -q -m "chore: release $version" -- "${files[@]}"
    done_msg="set to $version and committed"
  fi
  git tag "v$version"
  echo "Version $done_msg; tagged v$version. Push with: git push origin HEAD v$version"
else
  echo "Version set to $version. Commit this, then: git tag v$version && git push origin v$version"
  echo "(Or run with --tag to commit and tag in one step.)"
fi
