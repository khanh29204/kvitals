import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: root

    property int updateInterval: 2000

    // Bytes per partition: total / free reported by df, plus the space
    // pinned by btrfs snapshots (snapper backups) which is excluded from
    // the used figure.
    property real rootTotal: NaN
    property real rootAvail: NaN
    property real rootReserved: 0

    property real homeTotal: NaN
    property real homeAvail: NaN
    property real homeReserved: 0

    // Effective free space = df free + snapshot-reserved space
    readonly property real rootEffAvail: isNaN(rootAvail) ? NaN : rootAvail + rootReserved
    readonly property real homeEffAvail: isNaN(homeAvail) ? NaN : homeAvail + homeReserved

    // Usage percentage (excluding snapshot space)
    readonly property real rootUsedPct: {
        if (isNaN(rootTotal) || isNaN(rootEffAvail) || rootTotal <= 0) return NaN;
        return Math.min(100, Math.max(0, (rootTotal - rootEffAvail) / rootTotal * 100));
    }
    readonly property real homeUsedPct: {
        if (isNaN(homeTotal) || isNaN(homeEffAvail) || homeTotal <= 0) return NaN;
        return Math.min(100, Math.max(0, (homeTotal - homeEffAvail) / homeTotal * 100));
    }

    readonly property bool rootReady: !isNaN(rootTotal) && !isNaN(rootEffAvail)
    readonly property bool homeReady: !isNaN(homeTotal) && !isNaN(homeEffAvail)

    // Show the metric once both partitions have reported, to avoid a
    // half-populated entry in the panel (same approach as BatterySensors).
    readonly property bool hasDiskData: rootReady && homeReady

    // --- Display values ---

    function fmtPct(pct) {
        return isNaN(pct) ? "?" : Math.round(pct) + "%";
    }

    readonly property string rootDisplay: rootReady
        ? Utils.formatFree(rootEffAvail) + "(" + fmtPct(rootUsedPct) + ")" : ""
    readonly property string homeDisplay: homeReady
        ? Utils.formatFree(homeEffAvail) + "(" + fmtPct(homeUsedPct) + ")" : ""

    // Panel value: free space + used % for both partitions, e.g. 1.4G(98%)•3.2G(99%)
    readonly property string displayValue: hasDiskData ? rootDisplay + "•" + homeDisplay : ""

    function fullValue(total, effAvail, usedPct, reserved) {
        if (isNaN(total) || isNaN(effAvail))
            return "";
        var text = Utils.formatFree(effAvail) + " free of " + Utils.formatFree(total) +
                   " (" + fmtPct(usedPct) + " used)";
        if (reserved > 1024 * 1024)
            text += " +" + Utils.formatFree(reserved) + " snap";
        return text;
    }

    readonly property string fullRootValue: fullValue(rootTotal, rootEffAvail, rootUsedPct, rootReserved)
    readonly property string fullHomeValue: fullValue(homeTotal, homeEffAvail, homeUsedPct, homeReserved)

    // --- Data sources ---

    // Preferred: sudo helper that can also read snapshot sizes
    readonly property string helperCmd: "sudo /usr/local/bin/kvitals-disk-usage.sh"
    // Fallback: plain df (no snapshot exclusion, no sudo needed)
    readonly property string fallbackCmd: "df -B1 --output=target,size,avail / /home"

    property bool helperAvailable: false
    property bool busy: false

    Timer {
        id: updateTimer
        interval: Math.max(root.updateInterval, 2000)
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.busy) return;
            root.busy = true;
            if (root.helperAvailable)
                dataSource.connectSource(root.helperCmd);
            else
                dataSource.connectSource(root.fallbackCmd);
        }
    }

    // Probe the helper every minute until it becomes available (e.g. right
    // after the user runs setup-disk-helper.sh), so snapshot exclusion
    // kicks in without restarting the panel. A failing "sudo -n" is cheap.
    Timer {
        interval: 60 * 1000
        repeat: true
        running: !root.helperAvailable
        onTriggered: {
            if (root.busy || root.helperAvailable) return;
            root.busy = true;
            dataSource.connectSource(root.helperCmd);
        }
    }

    Plasma5Support.DataSource {
        id: dataSource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            root.busy = false;
            var stdoutText = data["stdout"] ? data["stdout"].toString() : "";
            var isHelper = (sourceName === root.helperCmd);
            var helperOk = false;

            if (isHelper) {
                if (data["exit code"] === 0 && stdoutText.trim().length > 0) {
                    helperOk = true;
                    root.helperAvailable = true;
                    parseHelperOutput(stdoutText);
                } else {
                    root.helperAvailable = false;
                }
            } else if (data["exit code"] === 0) {
                parseDfOutput(stdoutText);
            }

            disconnectSource(sourceName);

            // Helper failed -> run the df fallback right away so we still
            // show free space (without snapshot exclusion)
            if (isHelper && !helperOk) {
                root.busy = true;
                connectSource(root.fallbackCmd);
            }
        }
    }

    // Helper output: "root <total> <avail> <reserved>" / "home <total> <avail> <reserved>"
    function parseHelperOutput(text) {
        var lines = text.trim().split("\n");
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].trim().split(/\s+/);
            if (parts.length < 3) continue;
            var total = parseFloat(parts[1]);
            var avail = parseFloat(parts[2]);
            var reserved = parts.length > 3 ? parseFloat(parts[3]) : 0;
            if (isNaN(total) || isNaN(avail)) continue;
            if (isNaN(reserved)) reserved = 0;

            if (parts[0] === "root") {
                rootTotal = total;
                rootAvail = avail;
                rootReserved = reserved;
            } else if (parts[0] === "home") {
                homeTotal = total;
                homeAvail = avail;
                homeReserved = reserved;
            }
        }
    }

    // df output lines: "<mountpoint> <size> <avail>"
    function parseDfOutput(text) {
        var lines = text.trim().split("\n");
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].trim().split(/\s+/);
            if (parts.length < 3) continue;
            var total = parseFloat(parts[1]);
            var avail = parseFloat(parts[2]);
            if (isNaN(total) || isNaN(avail)) continue;

            if (parts[0] === "/") {
                rootTotal = total;
                rootAvail = avail;
                rootReserved = 0;
            } else if (parts[0] === "/home") {
                homeTotal = total;
                homeAvail = avail;
                homeReserved = 0;
            }
        }
    }
}
