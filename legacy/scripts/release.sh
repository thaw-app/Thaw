#!/usr/bin/env bash
# Dispatches .github/workflows/release.yml after picking a tag from a list.
#
# workflow_dispatch choice inputs are static YAML, so the tag has to stay a
# free-text field in the workflow. This script supplies the list the web UI
# cannot: it reads the tags that actually exist on the remote and dispatches
# the run with the one you pick, so a typo cannot reach the workflow.
set -euo pipefail

REPO="${REPO:-thaw-app/Thaw}"
WORKFLOW="release.yml"

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }

# Newest first. The workflow rejects anything that is not 1.2.3 or 1.2.3-rc.1,
# so filter to the same shape here rather than offering tags it will refuse.
# Read into an array without mapfile, which bash 3.2 (the macOS default) lacks.
tags=()
while IFS= read -r line; do
    tags+=("$line")
done < <(
    gh api --paginate "repos/$REPO/tags" --jq '.[].name' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9._]+)?$'
)
((${#tags[@]})) || { echo "no release-shaped tags on $REPO" >&2; exit 1; }

if command -v fzf >/dev/null; then
    tag="$(printf '%s\n' "${tags[@]}" | fzf --prompt='tag> ' --height=20)"
else
    PS3="tag> "
    select tag in "${tags[@]}"; do [[ -n "$tag" ]] && break; done
fi
[[ -n "${tag:-}" ]] || { echo "no tag selected" >&2; exit 1; }

ask() { # ask <prompt> <default-y|default-n>
    local reply suffix="[y/N]"
    [[ "$2" == y ]] && suffix="[Y/n]"
    read -r -p "$1 $suffix " reply
    reply="${reply:-$2}"
    [[ "$reply" =~ ^[Yy] ]]
}

dry_run=false; publish_release=false; publish_appcast=false
discussion_category=none

ask "Dry run (build and report, publish nothing)?" n && dry_run=true
if [[ "$dry_run" == false ]]; then
    ask "Publish the GitHub Release (otherwise it stays a draft)?" n && publish_release=true
    # The appcast and the discussion both require a published release: the
    # workflow gates them on publish_release, so asking otherwise collects an
    # answer it discards and prints it in the summary below.
    if [[ "$publish_release" == true ]]; then
        publish_appcast=true
        ask "Push the signed appcast to thaw-app/updates?" y || publish_appcast=false
        PS3="discussion category> "
        select discussion_category in none Announcements General Ideas; do
            [[ -n "$discussion_category" ]] && break
        done
    fi
fi

cat <<SUMMARY

  repo       $REPO
  tag        $tag
  channel    auto
  dry run    $dry_run
  publish    $publish_release
  appcast    $publish_appcast
  discussion $discussion_category

SUMMARY
ask "Dispatch?" n || { echo "aborted"; exit 1; }

gh workflow run "$WORKFLOW" --repo "$REPO" \
    -f tag="$tag" \
    -f channel=auto \
    -f dry_run="$dry_run" \
    -f publish_release="$publish_release" \
    -f publish_appcast="$publish_appcast" \
    -f discussion_category="$discussion_category"

echo "dispatched; watch with: gh run list --repo $REPO --workflow $WORKFLOW"
