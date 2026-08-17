#!/usr/bin/env bash
# setup-disk-helper.sh - Installs the KVitals disk-usage helper:
#   1. Copies kvitals-disk-usage.sh to /usr/local/bin (owned by root, 0755)
#   2. Adds a sudoers rule so the calling user can run it WITHOUT a password
#   3. Enables btrfs quota on / so snapper snapshot sizes can be measured,
#      and starts the (one-time) qgroup rescan in the background
#
# Run once with:  sudo bash setup-disk-helper.sh
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_SRC="$SRC_DIR/kvitals-disk-usage.sh"
HELPER_DST="/usr/local/bin/kvitals-disk-usage.sh"
SUDOERS_FILE="/etc/sudoers.d/kvitals-disk-usage"

# The user who will get the NOPASSWD rule (the caller of sudo, not root)
TARGET_USER="${SUDO_USER:-$USER}"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: run with sudo:  sudo bash setup-disk-helper.sh" >&2
    exit 1
fi

if [[ -z "${TARGET_USER:-}" || "$TARGET_USER" == "root" ]]; then
    echo "ERROR: could not determine the target user; run via sudo from your normal account" >&2
    exit 1
fi

if [[ ! -f "$HELPER_SRC" ]]; then
    echo "ERROR: helper script not found at $HELPER_SRC" >&2
    exit 1
fi

echo "==> Installing helper script to $HELPER_DST"
install -m 0755 -o root -g root "$HELPER_SRC" "$HELPER_DST"

echo "==> Adding sudoers rule for user '$TARGET_USER'"
cat > "$SUDOERS_FILE" <<EOF
# KVitals: allow $TARGET_USER to run the disk usage helper without a password
$TARGET_USER ALL=(root) NOPASSWD: $HELPER_DST
EOF
chmod 0440 "$SUDOERS_FILE"
if ! visudo -c -q -f "$SUDOERS_FILE"; then
    rm -f "$SUDOERS_FILE"
    echo "ERROR: generated sudoers file failed validation; removed it" >&2
    exit 1
fi
echo "    OK: $SUDOERS_FILE"

# Enable btrfs quota so the exclusive size of snapshots can be read.
# This is required for excluding snapper backups from the free-space figure.
if [[ "$(df -T / 2>/dev/null | tail -n 1 | awk '{print $2}')" == "btrfs" ]]; then
    fsuuid=$(findmnt -no UUID / 2>/dev/null || true)
    if [[ -n "$fsuuid" && -d "/sys/fs/btrfs/$fsuuid/qgroups" ]]; then
        echo "==> btrfs quota already enabled on /"
    else
        echo "==> Enabling btrfs quota on /"
        if btrfs quota enable /; then
            echo "    Quota enabled. Starting qgroup rescan (runs in the background;"
            echo "    snapshot sizes appear once it finishes. Check: btrfs qgroup rescan-status /)"
            btrfs qgroup rescan / >/dev/null 2>&1 || true
        else
            echo "    WARNING: could not enable quota; the helper will fall back to"
            echo "    measuring /.snapshots with du instead of exact qgroup numbers."
        fi
    fi
else
    echo "==> / is not btrfs; skipping quota setup"
fi

echo ""
echo "✅ Setup complete. Test it with:"
echo "    sudo $HELPER_DST"
echo "    sudo $HELPER_DST --debug   # per-snapshot breakdown"
echo ""
echo "Then (re)install the plasmoid with ./install.sh and restart the panel:"
echo "    plasmashell --replace &"
