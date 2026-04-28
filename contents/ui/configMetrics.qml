import QtQuick 2.0
import QtQuick.Controls 2.0
import QtQuick.Layouts 1.0
import org.kde.kirigami 2.5 as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support

KCM.SimpleKCM {
    id: metricsPage

    property bool cfg_showCpu
    property bool cfg_showRam
    property bool cfg_showTemp
    property bool cfg_showGpu
    property bool cfg_showBattery
    property bool cfg_showPower
    property bool cfg_showNetwork
    property bool cfg_showUptime
    property string cfg_networkInterface: "auto"
    property string cfg_batteryDevice: "auto"
    property string cfg_metricOrder: "cpu,ram,temp,gpu,bat,pwr,net,uptime"

    property var ifaceList: ["auto"]

    readonly property var allKeys: ["cpu", "ram", "temp", "gpu", "bat", "pwr", "net", "uptime"]

    readonly property var metricLabels: ({
        "cpu":  i18n("CPU Usage"),
        "ram":  i18n("RAM Usage"),
        "temp": i18n("CPU Temperature"),
        "gpu":  i18n("GPU Metrics"),
        "bat":  i18n("Battery Status"),
        "pwr":  i18n("Power Consumption"),
        "net":  i18n("Network Speed"),
        "uptime": i18n("Uptime")
    })

    property var currentOrder: {
        var keys = cfg_metricOrder.split(",").map(function(k) { return k.trim(); }).filter(function(k) { return k.length > 0 && metricLabels[k] !== undefined; });
        // Add any missing keys at the end
        for (var j = 0; j < allKeys.length; j++) {
            if (keys.indexOf(allKeys[j]) < 0) {
                keys.push(allKeys[j]);
            }
        }
        return keys;
    }

    function isChecked(key) {
        switch (key) {
            case "cpu":  return cfg_showCpu;
            case "ram":  return cfg_showRam;
            case "temp": return cfg_showTemp;
            case "gpu":  return cfg_showGpu;
            case "bat":  return cfg_showBattery;
            case "pwr":  return cfg_showPower;
            case "net":  return cfg_showNetwork;
            case "uptime": return cfg_showUptime;
        }
        return false;
    }

    function setChecked(key, val) {
        switch (key) {
            case "cpu":  cfg_showCpu     = val; break;
            case "ram":  cfg_showRam     = val; break;
            case "temp": cfg_showTemp    = val; break;
            case "gpu":  cfg_showGpu     = val; break;
            case "bat":  cfg_showBattery = val; break;
            case "pwr":  cfg_showPower   = val; break;
            case "net":  cfg_showNetwork = val; break;
            case "uptime": cfg_showUptime = val; break;
        }
    }

    function moveMetric(fromIndex, toIndex) {
        var keys = currentOrder.slice();
        var item = keys.splice(fromIndex, 1)[0];
        keys.splice(toIndex, 0, item);
        cfg_metricOrder = keys.join(",");
    }

    function trimmed(text) {
        return (text || "").toString().trim();
    }

    function syncBatteryInput() {
        if (!batteryInput)
            return;
        var desired = cfg_batteryDevice === "auto" ? "" : cfg_batteryDevice;
        if (batteryInput.text !== desired)
            batteryInput.text = desired;
    }

    onCfg_batteryDeviceChanged: syncBatteryInput()
    Component.onCompleted: syncBatteryInput()

    Plasma5Support.DataSource {
        id: ifaceSource
        engine: "executable"
        connectedSources: ["ls /sys/class/net/"]

        onNewData: function(source, data) {
            if (data["exit code"] !== 0) return;
            var raw = data["stdout"].trim();
            if (raw.length === 0) return;
            var ifaces = raw.split("\n").filter(function(name) {
                return name !== "lo" && name.length > 0;
            });
            ifaces.unshift("auto");
            metricsPage.ifaceList = ifaces;
        }
    }

    Kirigami.FormLayout {

        Label {
            Kirigami.FormData.label: i18n("Metric order:")
            text: i18n("Use ↑ ↓ to reorder metrics in the panel.")
            opacity: 0.7
            font.italic: true
        }

        ColumnLayout {
            spacing: 2

            Repeater {
                model: metricsPage.currentOrder

                delegate: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    Layout.fillWidth: true

                    CheckBox {
                        checked: metricsPage.isChecked(modelData)
                        onToggled: metricsPage.setChecked(modelData, checked)
                    }

                    Label {
                        text: metricsPage.metricLabels[modelData] || modelData
                        Layout.fillWidth: true
                    }

                    Button {
                        icon.name: "arrow-up"
                        enabled: index > 0
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: metricsPage.moveMetric(index, index - 1)
                    }

                    Button {
                        icon.name: "arrow-down"
                        enabled: index < metricsPage.currentOrder.length - 1
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        onClicked: metricsPage.moveMetric(index, index + 1)
                    }
                }
            }
        }

        ComboBox {
            id: ifaceCombo
            Kirigami.FormData.label: i18n("Network interface:")
            model: metricsPage.ifaceList
            enabled: cfg_showNetwork
            currentIndex: {
                var idx = metricsPage.ifaceList.indexOf(cfg_networkInterface);
                return idx >= 0 ? idx : 0;
            }
            onActivated: {
                cfg_networkInterface = metricsPage.ifaceList[currentIndex];
            }
        }

        TextField {
            id: batteryInput
            Kirigami.FormData.label: i18n("Battery device:")
            enabled: cfg_showBattery
            placeholderText: i18n("Leave empty for auto (e.g. battery_BAT0)")
            onTextEdited: {
                var value = metricsPage.trimmed(text);
                cfg_batteryDevice = value.length > 0 ? value : "auto";
            }
        }

        Label {
            text: i18n("Empty value uses automatic detection.")
            opacity: 0.7
            visible: cfg_showBattery
        }
    }
}
