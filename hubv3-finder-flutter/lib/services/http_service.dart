import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import '../models/browser_url.dart';
import '../models/task_info.dart';

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

  // Send System Command
  Future<String> sendCommand(String command, {String param = "", int timeout = 10}) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      // 1. 构造参数map
      Map<String, String> paramMap = {};
      paramMap['command'] = command;
      if (param.isNotEmpty) {
        final paramBase64 = base64Encode(utf8.encode(param));
        paramMap['param'] = paramBase64;
      }
      int tvalue = DateTime.now().millisecondsSinceEpoch;
      paramMap['_ct'] = tvalue.toString();

      // 2. 按key排序，拼接签名用字符串
      var sortedKeys = paramMap.keys.toList()..sort();
      var signParts = <String>[];
      for (var k in sortedKeys) {
        signParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
      }
      String signStr = signParts.join('&');
      String md5Input = '$signStr&ThirdReality';
      print('Signature: $md5Input');
      String sig = md5.convert(utf8.encode(md5Input)).toString();

      // 3. 添加_sig字段
      paramMap['_sig'] = sig;

      // 4. 按添加顺序拼接body字符串
      List<String> orderedKeys = ['command', 'param', '_ct', '_sig'];
      var bodyParts = <String>[];
      for (var k in orderedKeys) {
        if (paramMap.containsKey(k)) {
          bodyParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
        }
      }
      String bodyStr = bodyParts.join('&');

      print('sending command: $bodyStr');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/system/command'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: bodyStr,
      ).timeout(Duration(seconds: timeout));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to send command: \\${response.statusCode}');
      }
    } catch (e) {
      print('Error sending command: $e');
      throw Exception('Error sending command: $e');
    }
  }



  // Reboot device
  Future<void> rebootDevice() async {
    await sendCommand('reboot');
  }

  // Factory reset
  Future<void> factoryReset() async {
    await sendCommand('factory_reset');
  }

  // Get Task Info
  Future<TaskInfo> getTaskInfo(String task, {int timeout = 10}) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/task/info?task=$task'),
      ).timeout(Duration(seconds: timeout));

      if (response.statusCode == 200) {
        return TaskInfo.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to get task info: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting task info: $e');
      throw Exception('Error getting task info: $e');
    }
  }

  // Get System Info
  Future<String> getSystemInfo({int timeout = 30}) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/system/info'),
      ).timeout(Duration(seconds: timeout));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to get system info: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting system info: $e');
      if (e is TimeoutException) {
        throw Exception('Device response timed out. Please ensure the device is powered on and connected to the network.');
      } else {
        throw Exception('Error getting system info: $e');
      }
    }
  }

  // Get Browser Info
  Future<List<BrowserUrl>> getBrowserInfo({int timeout = 10}) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/browser/info'),
      ).timeout(Duration(seconds: timeout));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data.containsKey('browser_url') && data['browser_url'] is List) {
          final List<dynamic> browserUrlList = data['browser_url'];
          return browserUrlList
              .map((item) => BrowserUrl.fromJson(item as Map<String, dynamic>))
              .toList();
        } else {
          // If browser_url is not present or not a list, return an empty list or handle as an error
          return []; // Or throw Exception('Invalid format for browser_url');
        }
      } else {
        throw Exception('Failed to get browser info: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting browser info: $e');
      if (e is TimeoutException) {
        throw Exception('Device response timed out while fetching browser info.');
      } else {
        throw Exception('Error getting browser info: $e');
      }
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

  Future<Map<String, dynamic>> getSoftwareInfo() async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/software/info'),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to get software info: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting software info: $e');
      // 如果API不存在，返回模拟数据
      return {
        "homeassistant_core": {
          "name": "Home Assistant",
          "installed": false,
          "enabled": false,
          "software": [
          ]
        },
        "openhab": {
          "name": "OpneHab",
          "installed": false,
          "enabled": false,
          "software": [
          ]
        }
      };
    }
  }

  // Get Firmware Info
  Future<Map<String, dynamic>> getFirmwareInfo() async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/firmware/info'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to get firmware info: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting firmware info: $e');
      // 如果API不存在，返回模拟数据
      return {
        'current_version': 'v1.2.3',
        'latest_version': 'v1.3.0',
        'update_available': true,
        'release_date': '2025-04-15',
        'release_notes': 'Bug fixes and performance improvements:\n- Fixed WiFi connection stability issues\n- Improved BLE scanning performance\n- Added support for new device types',
        'device_model': 'LinuxBox Hub v3',
        'build_number': '20250415-1234'
      };
    }
  }

  // Get Service Status
  Future<Map<String, dynamic>> getServiceInfo() async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/service/info'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to get service status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting service status: $e');
      // 如果API不存在，返回模拟数据
      return {
        "homeassistant_core": {
          "name": "Home Assistant",
          "service": [
          ]
        },
        "openhab": {
          "name": "OpenHab",
          "service": [
          ]
        }
      };
    }
  }
  
  // Get Single Service Status
  Future<Map<String, dynamic>> getSingleServiceInfo(String service) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }
    
    // Validate service parameter
    if (!['homeassistant_core', 'openhab'].contains(service)) {
      throw Exception('Invalid service parameter. Must be one of: homeassistant_core, openhab');
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/service/info/$service'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to get service status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting single service status: $e');
      // 如果API不存在，返回模拟数据
      final mockData = {
        "homeassistant_core": {
          "name": "Home Assistant",
          "service": [
          ]
        },
        "openhab": {
          "name": "OpenHab",
          "service": [
          ]
        }
      };
      
      // Return only the requested service
      if (mockData.containsKey(service)) {
        return {service: mockData[service]!};
      } else {
        return {};
      }
    }
  }
  
  // Update Service Status for a specific service in a package
  Future<void> updateServiceStatus(String packageId, String serviceName, String action) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }
    
    // Validate action parameter
    if (!['enable', 'disable', 'start', 'stop'].contains(action)) {
      throw Exception('Invalid action parameter. Must be one of: enable, disable, start, stop');
    }
    
    try {
      // 1. 构造参数map
      Map<String, String> paramMap = {};
      paramMap['action'] = action;
      
      // Create param JSON string and encode it
      final paramJson = jsonEncode({
        'package': packageId,
        'service': serviceName
      });

      print('sending Service param: $paramJson');
      final paramBase64 = base64Encode(utf8.encode(paramJson));
      paramMap['param'] = paramBase64;
      
      // Add timestamp
      int tvalue = DateTime.now().millisecondsSinceEpoch;
      paramMap['_ct'] = tvalue.toString();

      // 2. 按key排序，拼接签名用字符串
      var sortedKeys = paramMap.keys.toList()..sort();
      var signParts = <String>[];
      for (var k in sortedKeys) {
        signParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
      }
      String signStr = signParts.join('&');
      String md5Input = '$signStr&ThirdReality';
      String sig = md5.convert(utf8.encode(md5Input)).toString();

      // 3. 添加_sig字段
      paramMap['_sig'] = sig;

      // 4. 按添加顺序拼接body字符串
      List<String> orderedKeys = ['action', 'param', '_ct', '_sig'];
      var bodyParts = <String>[];
      for (var k in orderedKeys) {
        if (paramMap.containsKey(k)) {
          bodyParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
        }
      }
      String bodyStr = bodyParts.join('&');
      print('sending Service update command: $bodyStr');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/service/control'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: bodyStr,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Failed to update service status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating service status: $e');
      throw Exception('Failed to update service: $e');
    }
  }
  
  // Update Software Package
  Future<void> updateSoftwarePackage(String packageId, String action) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }
    
    // Validate action parameter
    if (!['install', 'uninstall', 'enable', 'disable', 'upgrade'].contains(action)) {
      throw Exception('Invalid action parameter. Must be one of: install, uninstall, enable, disable, upgrade');
    }
    
    try {
      // 1. 构造参数map
      Map<String, String> paramMap = {};
      paramMap['action'] = action;
      
      // Create param JSON string and encode it
      final paramJson = jsonEncode({
        'package': packageId
      });

      print('sending Software param: $paramJson');
      final paramBase64 = base64Encode(utf8.encode(paramJson));
      paramMap['param'] = paramBase64;
      
      // Add timestamp
      int tvalue = DateTime.now().millisecondsSinceEpoch;
      paramMap['_ct'] = tvalue.toString();

      // 2. 按key排序，拼接签名用字符串
      var sortedKeys = paramMap.keys.toList()..sort();
      var signParts = <String>[];
      for (var k in sortedKeys) {
        signParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
      }
      String signStr = signParts.join('&');
      String md5Input = '$signStr&ThirdReality';
      String sig = md5.convert(utf8.encode(md5Input)).toString();

      // 3. 添加_sig字段
      paramMap['_sig'] = sig;

      // 4. 按添加顺序拼接body字符串
      List<String> orderedKeys = ['action', 'param', '_ct', '_sig'];
      var bodyParts = <String>[];
      for (var k in orderedKeys) {
        if (paramMap.containsKey(k)) {
          bodyParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
        }
      }
      String bodyStr = bodyParts.join('&');
      print('sending Software update command: $bodyStr');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/software/command'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: bodyStr,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Failed to update software package: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating software package: $e');
      throw Exception('Failed to update software package: $e');
    }
  }


  // Fetch Zigbee Info
  Future<String?> fetchZigbeeInfo() async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }
    final response = await http.get(Uri.parse('$_baseUrl/api/zigbee/info'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['zigbee'];
    } else {
      return null;
    }
  }

  // Send Zigbee Command
  Future<void> sendZigbeeCommand(String action) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      // Construct parameter map
      Map<String, String> paramMap = {};

      paramMap['command'] = 'zigbee';

      paramMap['action'] = action;

      // Add timestamp
      int tvalue = DateTime.now().millisecondsSinceEpoch;
      paramMap['_ct'] = tvalue.toString();

      // Sort keys and create signature
      var sortedKeys = paramMap.keys.toList()..sort();
      var signParts = <String>[];
      for (var k in sortedKeys) {
        signParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
      }
      String signStr = signParts.join('&');
      String md5Input = '$signStr&ThirdReality';
      String sig = md5.convert(utf8.encode(md5Input)).toString();

      // Add signature to parameters
      paramMap['_sig'] = sig;

      // Construct body string
      List<String> orderedKeys = ['command', 'action', '_ct', '_sig'];
      var bodyParts = <String>[];
      for (var k in orderedKeys) {
        if (paramMap.containsKey(k)) {
          bodyParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
        }
      }
      String bodyStr = bodyParts.join('&');
      print('sending Zigbee command: $bodyStr');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/system/command'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: bodyStr,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Failed to send Zigbee command: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending Zigbee command: $e');
      throw Exception('Failed to send Zigbee command: $e');
    }
  }


  // Send Setting Command
  Future<String> sendSettingCommand(String command, {String action = ""}) async {
    if (_baseUrl == null) {
      throw Exception('HTTP Service not configured with a device IP');
    }

    try {
      // 1. Construct parameter map
      Map<String, String> paramMap = {};
      paramMap['command'] = command;
      if (action.isNotEmpty) {
        paramMap['action'] = action;
      }
      int tvalue = DateTime.now().millisecondsSinceEpoch;
      paramMap['_ct'] = tvalue.toString();

      // 2. Sort keys and build signature string
      var sortedKeys = paramMap.keys.toList()..sort();
      var signParts = <String>[];
      for (var k in sortedKeys) {
        signParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
      }
      String signStr = signParts.join('&');
      String md5Input = '$signStr&ThirdReality';
      String sig = md5.convert(utf8.encode(md5Input)).toString();

      // 3. Add signature to parameters
      paramMap['_sig'] = sig;

      // 4. Build body string in specific order
      List<String> orderedKeys = ['command', 'action', '_ct', '_sig'];
      var bodyParts = <String>[];
      for (var k in orderedKeys) {
        if (paramMap.containsKey(k)) {
          bodyParts.add('${Uri.encodeComponent(k)}=${Uri.encodeComponent(paramMap[k]!)}');
        }
      }
      String bodyStr = bodyParts.join('&');
      print('sending setting command: $bodyStr');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/system/command'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: bodyStr,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed to send setting command: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending setting command: $e');
      throw Exception('Error sending setting command: $e');
    }
  }
}
