#!/usr/bin/env bash
# Builds one zip per shell for a release, plus SHA256SUMS, into dist/.
# The PowerShell module's ModuleVersion is set to <version>.
# Usage: bash scripts/package.sh 1.2.0

set -euo pipefail

version=${1:-}
version=${version#v}
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <version>   e.g. $0 1.2.0 (or v1.2.0)" >&2
  exit 1
fi

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dist=$root/dist
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

rm -rf "$dist"
mkdir -p "$dist"

# Each zip holds one folder, named so it can be dropped in place:
#   zsh:        sf-shortcuts/  (an Oh My Zsh custom plugin folder)
#   bash:       sf-shortcuts/
#   powershell: SfShortcuts/   (a folder on $env:PSModulePath)
pack() {
  local shell=$1 folder=$2
  shift 2
  mkdir -p "$work/$shell/$folder"
  cp "$@" "$root/README.md" "$root/LICENSE" "$work/$shell/$folder/"
}

pack zsh sf-shortcuts "$root/sf-shortcuts.plugin.zsh"
pack bash sf-shortcuts "$root/bash/sf-shortcuts.bash"
pack powershell SfShortcuts "$root/powershell/SfShortcuts.psd1" "$root/powershell/SfShortcuts.psm1"

psd1=$work/powershell/SfShortcuts/SfShortcuts.psd1
sed -i.bak -E "s/^( *ModuleVersion *= *)'[^']*'/\1'$version'/" "$psd1"
rm "$psd1.bak"
grep -q "ModuleVersion *= *'$version'" "$psd1" || { echo "Could not set ModuleVersion in $psd1" >&2; exit 1; }

for shell in zsh bash powershell; do
  (cd "$work/$shell" && zip -qr -X "$dist/sf-shortcuts-$shell.zip" .)
done

# Unzipped PowerShell module, for publishing to the PowerShell Gallery
cp -R "$work/powershell/SfShortcuts" "$dist/SfShortcuts"

cd "$dist"
if command -v sha256sum >/dev/null; then
  sha256sum *.zip > SHA256SUMS
else
  shasum -a 256 *.zip > SHA256SUMS
fi

ls -1 "$dist"
