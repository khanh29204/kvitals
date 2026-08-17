#!/bin/bash
# kvitals-disk-usage.sh - Reports free space for / and /home for the KVitals
# Plasma widget, excluding space pinned by btrfs snapshots (snapper backups).
#
# Must run as root (reads exclusive qgroup usage + /.snapshots).
# See setup-disk-helper.sh for installation and the sudoers rule.
#
# Output format (one line per mount, only when the mount exists):
#   root <total> <avail> <snapshot_reserved>
#   home <total> <avail> <snapshot_reserved>
# All values are in bytes.
#
# With --debug: prints per-filesystem snapshot/qgroup details and exits
# (never writes the cache).
set -u

CACHE="/run/kvitals-disk-usage.cache"
CACHE_TTL=30

# statvfs of a mount point: <used> <total> <avail>, all in bytes
mount_stats() {
    local path="$1" line
    line=$(df -B1 --output=used,size,avail "$path" 2>/dev/null | tail -n 1)
    [ -n "$line" ] || return 1
    # shellcheck disable=SC2086
    set -- $line
    [ "$#" -eq 3 ] || return 1
    echo "$1 $2 $3"
}

# Exclusive (unshared) bytes held by every snapshot subvolume of the
# filesystem mounted at $1. Deleting those snapshots would free this amount.
# Requires btrfs quota to be enabled: btrfs quota enable <mount>
# Only readable as root. Falls back to the apparent size of the snapper
# data directory (<mount>/.snapshots) when quota is not enabled.
snapshot_reserved_bytes() {
    local mount="$1" qgroups id excl sum=0
    if [ "$(df -T "$mount" 2>/dev/null | tail -n 1 | awk '{print $2}')" != "btrfs" ]; then
        echo 0
        return
    fi

    # btrfs qgroup show --raw columns: qgroupid  rfer  excl  (values in bytes)
    qgroups=$(btrfs qgroup show --raw "$mount" 2>/dev/null)
    if [ -n "$qgroups" ]; then
        # btrfs subvolume list -s columns: ID <id> gen ... path <path>
        for id in $(btrfs subvolume list -s "$mount" 2>/dev/null | awk '{print $2}'); do
            excl=$(printf '%s\n' "$qgroups" | awk -v id="0/$id" '$1 == id {print $3}')
            case "$excl" in ''|*[!0-9]*) continue ;; esac
            sum=$((sum + excl))
        done
        echo "$sum"
        return
    fi

    if [ -d "$mount/.snapshots" ]; then
        sum=$(du -sb "$mount/.snapshots" 2>/dev/null | awk '{print $1}')
        case "$sum" in ''|*[!0-9]*) sum=0 ;; esac
    fi
    echo "$sum"
}

# --- Debug mode: verify snapshot exclusion ---
if [ "${1:-}" = "--debug" ]; then
    for mount in / /home; do
        fstype=$(df -T "$mount" 2>/dev/null | tail -n 1 | awk '{print $2}')
        echo "=== $mount ($fstype) ==="
        if [ "$fstype" != "btrfs" ]; then
            echo "not btrfs: snapshot_reserved=0"
            continue
        fi
        echo "-- snapshot subvolumes (btrfs subvolume list -s):"
        btrfs subvolume list -s "$mount" || echo "   (failed)"
        echo "-- qgroups (btrfs qgroup show --raw, first 20):"
        btrfs qgroup show --raw "$mount" 2>&1 | head -20 || echo "   (failed)"
        echo "-- total snapshot exclusive: $(snapshot_reserved_bytes "$mount") bytes"
    done
    exit 0
fi

# --- Cache: reuse a recent result so multiple widget instances (or a fast
# --- update interval) don't each trigger a root process.
now=$(date +%s)
if [ -s "$CACHE" ]; then
    mtime=$(stat -c %Y "$CACHE" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -lt "$CACHE_TTL" ]; then
        cat "$CACHE"
        exit 0
    fi
fi

out=""

# --- / (btrfs snapshots, e.g. snapper, are on the same filesystem) ---
stats=$(mount_stats /) || stats=""
if [ -n "$stats" ]; then
    read -r _used total avail <<< "$stats"
    reserved=$(snapshot_reserved_bytes /)
    out="root $total $avail $reserved"
fi

# --- /home (separate partition; snapshots there live in <mount>/.snapshots) ---
stats=$(mount_stats /home) || stats=""
if [ -n "$stats" ]; then
    read -r _used total avail <<< "$stats"
    reserved=$(snapshot_reserved_bytes /home)
    out="$out
home $total $avail $reserved"
fi

if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
    echo "ERROR: no readable mounts" >&2
    exit 1
fi
printf '%s\n' "$out" 2>/dev/null > "$CACHE" || true
printf '%s\n' "$out"
