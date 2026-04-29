import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: root

    property int updateInterval: 2000
    
    property real cpuFanRaw: 0
    property real gpuFanRaw: 0
    readonly property real maxRpm: 6122
    
    readonly property string cpuFanValue: {
        if (cpuFanRaw <= 0) return "0%";
        let percentage = Math.min(Math.round((cpuFanRaw / maxRpm) * 100), 100);
        return percentage + "%";
    }
    
    readonly property string gpuFanValue: {
        if (gpuFanRaw <= 0) return "0%";
        let percentage = Math.min(Math.round((gpuFanRaw / maxRpm) * 100), 100);
        return percentage + "%";
    }

    Timer {
        id: updateTimer
        interval: root.updateInterval
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            fanDataSource.connectSource("sudo /usr/local/bin/get_fan_speed.sh");
        }
    }

    Plasma5Support.DataSource {
        id: fanDataSource
        engine: "executable"
        connectedSources: []
        
        onNewData: (sourceName, data) => {
            if (data["exit code"] === 0) {
                let stdout = data["stdout"].trim();
                if (stdout !== "") {
                    let output = stdout.split(/\s+/);
                    if (output.length >= 2) {
                        root.cpuFanRaw = parseFloat(output[0]);
                        root.gpuFanRaw = parseFloat(output[1]);
                    }
                }
            }
            disconnectSource(sourceName);
        }
    }
}