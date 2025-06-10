import 'dart:convert';

class WiFiConnectionStatus {
  final bool isConnected;
  final String? ssid;
  final String? ipAddress;
  final String? macAddress;
  final String? errorMessage;

  WiFiConnectionStatus({
    this.isConnected = false,
    this.ssid,
    this.ipAddress,
    this.macAddress,
    this.errorMessage,
  });



  String get statusMessage {
    if (isConnected) {
      return ssid ?? 'Connected';
    } else {
      return errorMessage ?? 'Offline/Unavailable';
    }
  }

  // Create from JSON string
  factory WiFiConnectionStatus.fromJson(String jsonString) {
    try {
      // 使用标准JSON解析
      Map<String, dynamic> data = jsonDecode(jsonString);

      return WiFiConnectionStatus(
        isConnected: data['connected'] ?? false,
        ssid: data['ssid'],
        ipAddress: data['ip_address'] ?? data['ip'],
        macAddress: data['mac_address'] ?? data['mac'],
      );
    } catch (e) {
      print('WiFiConnectionStatus解析错误: $e, JSON字符串: $jsonString');

      // 如果标准解析失败，尝试使用旧方法进行解析（向后兼容）
      try {
        Map<String, dynamic> data = {};

        // Basic parsing of key-value pairs from the string response
        final pairs = jsonString.split(',');
        for (var pair in pairs) {
          final keyValue = pair.split(':');
          if (keyValue.length == 2) {
            final key = keyValue[0].trim();
            final value = keyValue[1].trim();

            if (key == 'connected') {
              data[key] = value.toLowerCase() == 'true';
            } else {
              data[key] = value;
            }
          }
        }

        return WiFiConnectionStatus(
          isConnected: data['connected'] ?? false,
          ssid: data['ssid'],
          ipAddress: data['ip_address'] ?? data['ip'],
          macAddress: data['mac_address'] ?? data['mac'],
        );
      } catch (e2) {
        print('备用解析方法也失败: $e2');
        return WiFiConnectionStatus(
          isConnected: false,
          errorMessage: 'Error parsing status: $e -> $e2',
        );
      }
    }
  }

  // Factory constructor for error states
  factory WiFiConnectionStatus.error(String message) {
    return WiFiConnectionStatus(
      isConnected: false,
      errorMessage: message,
    );
  }

  @override
  String toString() {
    if (errorMessage != null) {
      return 'Error: $errorMessage';
    }
    return isConnected
        ? 'Connected to $ssid (IP: $ipAddress, MAC: $macAddress)'
        : 'Not connected';
  }
}
