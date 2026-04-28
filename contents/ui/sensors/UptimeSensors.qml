import QtQuick
import org.kde.ksysguard.sensors as Sensors

Item {
    id: root
    property int updateInterval: 2000

    readonly property string uptimeValue: {
      // Kiểm tra trạng thái Sensor
      if (uptimeSensor.status !== Sensors.Sensor.Ready)
          return "...";
      
      let totalSeconds = parseFloat(uptimeSensor.value);
      if (isNaN(totalSeconds) || totalSeconds < 0) return "N/A";
  
      let days = Math.floor(totalSeconds / 86400);
      let hours = Math.floor((totalSeconds % 86400) / 3600);
      let minutes = Math.floor((totalSeconds % 3600) / 60);
  
      // Logic tự động chuyển đổi định dạng:
      if (days > 0) {
          // Nếu chạy trên 1 ngày: chỉ hiện Ngày và Giờ (Ví dụ: 2d 5h)
          return days + "d " + hours + "h";
      } 
      
      if (hours > 0) {
          // Nếu dưới 1 ngày nhưng trên 1 giờ: hiện Giờ và Phút (Ví dụ: 8h 12m)
          return hours + "h " + minutes + "m";
      } 
      
      // Nếu mới bật máy dưới 1 giờ: chỉ hiện số Phút (Ví dụ: 45m)
      return minutes + "m";
    }

    Sensors.Sensor {
        id: uptimeSensor
        // ĐỔI Ở ĐÂY: Plasma 6 dùng os/system/uptime
        sensorId: "os/system/uptime" 
        updateRateLimit: root.updateInterval
    }
}