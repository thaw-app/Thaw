#!/usr/bin/env bash
#
# thaw-reset.sh — Reset Thaw's macOS state for a clean dev test run.
#
# Default: quit Thaw, reset its TCC permissions (Accessibility, Screen
# Recording, …) and delete its UserDefaults. Pass --hard to ALSO remove logs,
# Application Support, and saved window state.
#
# Usage:
#   Scripts/thaw-reset.sh           # permissions + defaults
#   Scripts/thaw-reset.sh --hard    # the above + logs / app-support / saved-state
#
# After running, Thaw starts from scratch and will re-prompt for permissions on
# next launch.
#
set -uo pipefail

HARD=0
case "${1:-}" in
    --hard) HARD=1 ;;
    "")     ;;
    *)      echo "Unknown option: $1 (use --hard or no args)"; exit 2 ;;
esac

# Real targets (release + debug) + the virtual MenuBarHost owner name.
BUNDLES=(
    "com.stonerl.Thaw"
    "com.stonerl.Thaw.debug"
    "com.stonerl.Thaw.MenuBarItemService"
    "com.stonerl.Thaw.MenuBarHost"
)

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
skip() { printf '    \033[2m·\033[0m %s\n' "$*"; }

say "Quitting Thaw…"
osascript -e 'tell application id "com.stonerl.Thaw" to quit' >/dev/null 2>&1 || true
sleep 0.5
if pkill -9 -x Thaw >/dev/null 2>&1; then ok "killed Thaw"; else skip "Thaw not running"; fi
if pkill -9 -f MenuBarItemService >/dev/null 2>&1; then ok "killed MenuBarItemService"; else skip "service not running"; fi
sleep 1

say "Resetting TCC permissions (Accessibility, Screen Recording, …)…"
for b in "${BUNDLES[@]}"; do
    if tccutil reset All "$b" >/dev/null 2>&1; then ok "reset All   $b"; else skip "no TCC entries   $b"; fi
done

say "Deleting UserDefaults…"
for b in "${BUNDLES[@]}"; do
    if defaults delete "$b" >/dev/null 2>&1; then ok "deleted   $b"; else skip "no defaults   $b"; fi
    rm -f "$HOME/Library/Preferences/$b.plist" 2>/dev/null || true
done

say "Flushing preference cache…"
if killall -u "$USER" cfprefsd >/dev/null 2>&1; then ok "cfprefsd restarted"; else skip "cfprefsd not running"; fi

if [[ $HARD -eq 1 ]]; then
    say "Hard clean: logs, Application Support, saved state…"
    for d in \
        "$HOME/Library/Logs/Thaw" \
        "$HOME/Library/Application Support/Thaw" \
        "$HOME/Library/Saved Application State/com.stonerl.Thaw.savedState"
    do
        if [[ -e "$d" ]]; then
            rm -rf "$d" && ok "removed   ${d/#$HOME/~}"
        else
            skip "absent   ${d/#$HOME/~}"
        fi
    done
fi

say "Done — Thaw state is clean. You'll be re-prompted for permissions next launch."
