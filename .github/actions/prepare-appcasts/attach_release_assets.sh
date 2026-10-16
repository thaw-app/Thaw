#!/usr/bin/env bash
# Usage: attach_release_assets.sh <owner/repo> <tag> <file>...
#
# Uploads each file the release is missing. A published asset is never
# replaced: one that already matches is kept, and one that differs fails the
# run, since someone may already have downloaded it.
set -euo pipefail

repo="$1" tag="$2"
shift 2

existing="$(gh release view "$tag" --repo "$repo" --json assets \
  --jq '.assets[] | "\(.name)\t\(.digest // "")"')"

for file in "$@"; do
  name="$(basename "$file")"
  digest="sha256:$(shasum -a 256 "$file" | cut -d' ' -f1)"
  # "present:<digest>" when the release has an asset with exactly this name.
  match="$(awk -F'\t' -v name="$name" '$1 == name { print "present:" $2; exit }' <<< "$existing")"
  published="${match#present:}"
  if [[ -z "$match" ]]; then
    gh release upload "$tag" "$file" --repo "$repo"
    echo "uploaded ${name}"
  elif [[ "$published" == "$digest" ]]; then
    echo "kept ${name}: already published with the same digest"
  else
    echo "::error::${repo}@${tag} already has a different ${name} (${published:-no digest}, expected ${digest})"
    exit 1
  fi
done
