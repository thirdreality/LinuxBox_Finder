import 'dart:convert';
import 'package:http/http.dart' as http;

class HttpService {
  // Singleton instance
  static final HttpService _instance = HttpService._internal();
  factory HttpService() => _instance;
  HttpService._internal();

  // The base URL for API calls
  String? _baseUrl;
  
  // Check if service is configured with a valid URL
  bool get isConfigured => _baseUrl != null;

  // Set the base URL with the device's IP address
  void configure(String ipAddress) {
    _baseUrl = 'http://$ipAddress:8086';
    print('HTTP Service configured with base URL: $_baseUrl');
  }

  // Clear configuration
  void clear() {
    _baseUrl = null;
  }

  // Get WiFi Status
  Future<String> getWifiStatus({int ltime = 10}) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/wifi/status'),
      ).timeout(Duration(seconds: ltime));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to get WiFi status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting WiFi status: $e');
      throw Exception('Error getting WiFi status: $e');
    }
  }

  // 为配网做一点准备工作，例如关闭home-assistant.service
  Future<String> prepareWifiProvision(String ssid, String password) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/system/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'command': 'prepare_wifi_provision',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to delete WiFi connections: ${response.statusCode}');
      }
    } catch (e) {
      print('Error deleting WiFi networks: $e');
      throw Exception('Error deleting WiFi networks: $e');
    }
  }

  // Delete WiFi Networks
  Future<String> deleteWiFiNetworks() async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/system/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'command': 'delete_networks',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to delete WiFi connections: ${response.statusCode}');
      }
    } catch (e) {
      print('Error deleting WiFi networks: $e');
      throw Exception('Error deleting WiFi networks: $e');
    }
  }

  // Send System Command
  Future<String> sendCommand(String command) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/system/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'command': command,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to send command: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending command: $e');
      throw Exception('Error sending command: $e');
    }
  }

  // Get System Info
  Future<String> getSystemInfo() async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/system/info'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to get system info: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting system info: $e');
      throw Exception('Error getting system info: $e');
    }
  }

  // Check HTTP connectivity to the device
  Future<bool> checkConnectivity() async {
    if (_baseUrl == null) {
      return false;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/wifi/status'),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      print('HTTP connectivity check failed: $e');
      return false;
    }
  }
}
