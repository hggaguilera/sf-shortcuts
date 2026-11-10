#!/usr/bin/env bash
# Sets the version in all three ports. Run it and commit before tagging a release.
# Usage: bash scripts/bump-version.sh 1.2.0

set -euo pipefail

version=${1:-}
version=${version#v}
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <version>   e.g. $0 1.2.0 (or v1.2.0)" >&2
  exit 1
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for file in "$root/sf-shortcuts.plugin.zsh" "$root/bash/sf-shortcuts.bash"; do
  sed -i.bak -E "s/^_SF_SHORTCUTS_VERSION=.*/_SF_SHORTCUTS_VERSION=$version/" "$file"
  rm "$file.bak"
done

psd1=$root/powershell/SfShortcuts.psd1
sed -i.bak -E "s/^( *ModuleVersion *= *)'[^']*'/\1'$version'/" "$psd1"
rm "$psd1.bak"

echo "Version set to $version. Commit this, then: git tag v$version && git push origin v$version"
