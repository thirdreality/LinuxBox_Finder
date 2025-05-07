import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/ble_device.dart';
import './http_service.dart';
import '../models/WiFiConnectionStatus.dart';

class BleService {


  // Public getter for discovered devices
  List<BleDevice> get discoveredDevices => _discoveredDevices;
  /// Get WiFi status, automatically switch HTTP/BLE mode, return WiFiConnectionStatus
  Future<WiFiConnectionStatus> getWiFiStatus() async {
    try {
      String statusJson;
      if (_useHttpMode) {
        // HTTP mode, get via REST API first
        statusJson = await _httpService.getWifiStatus();
      } else {
        // BLE mode, get via BLE characteristic
        statusJson = await configureWiFi('', '', false); // Read-only status
      }
      return WiFiConnectionStatus.fromJson(statusJson);
    } catch (e) {
      return WiFiConnectionStatus.error('Failed to get WiFi status: $e');
    }
  }
  // Singleton instance
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // HTTP Service instance
  final HttpService _httpService = HttpService();

  // Communication mode flags
  bool _useHttpMode = false;

  // BLE instance - updated for new API
  // No need for .instance anymore, directly use the class methods

  // Service and characteristic UUIDs
  // Use standard UUIDs for GATT attributes
  static const String CCCD_DESCRIPTOR_UUID = "00002902-0000-1000-8000-00805f9b34fb"; // 标准CCCD描述符UUID
  static const String SERVICE_UUID = "6e400000-0000-4e98-8024-bc5b71e0893e";
  static const String HUBV3_WIFI_CONFIG_CHAR_UUID = "6e400001-0000-4e98-8024-bc5b71e0893e";

  // Stream controllers
  final StreamController<List<BleDevice>> _deviceStreamController = StreamController<List<BleDevice>>.broadcast();
  Stream<List<BleDevice>> get deviceStream => _deviceStreamController.stream;

  BluetoothDevice? _connectedDevice;
  final List<BleDevice> _discoveredDevices = [];

  // Initialize BLE
  Future<bool> initialize() async {
    try {
      // Request permissions
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      // Check if Bluetooth is available and turned on
      if (!(await FlutterBluePlus.isAvailable)) {
        return false;
      }

      if (!(await FlutterBluePlus.isOn)) {
        return false;
      }

      return true;
    } catch (e) {
      print('Error initializing BLE: $e');
      return false;
    }
  }

  // Start scanning for devices
  Future<void> startScan() async {
    try {
      _discoveredDevices.clear();

      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          // Only add devices with our service UUID or with 3RHUB- in the name
          String deviceName = result.device.platformName;

          if (deviceName.isEmpty) {
            continue;
          }

          if (deviceName.contains('3RHUB-') ||
              result.advertisementData.serviceUuids.contains(SERVICE_UUID)) {

            print('find deviceName $deviceName');
            print('find deviceName: ${result.device.remoteId.str}');
            
            // 检查制造商数据，尝试提取IP地址
            String? ipAddress;
            if (result.advertisementData.manufacturerData.isNotEmpty) {
              // 制造商ID为0x0133的数据包含IP地址
              final data = result.advertisementData.manufacturerData[0x0133];
              if (data != null && data.length >= 4) {
                // 提取IP地址，格式为4个字节 [192, 168, 1, 100]
                ipAddress = '${data[0]}.${data[1]}.${data[2]}.${data[3]}';
                print('提取到设备IP地址: $ipAddress');
              }
            }

            // Check if device is already in our list
            final existingDeviceIndex = _discoveredDevices.indexWhere(
                  (device) => device.id == result.device.remoteId.str,
            );

            if (existingDeviceIndex >= 0) {
              // Update existing device
              _discoveredDevices[existingDeviceIndex] = BleDevice(
                id: result.device.remoteId.str,
                name: deviceName.isNotEmpty ? deviceName : 'Unknown Device',
                rssi: result.rssi,
                device: result.device,
                ipAddress: ipAddress,
              );
            } else {
              // Add new device
              _discoveredDevices.add(BleDevice(
                id: result.device.remoteId.str,
                name: deviceName.isNotEmpty ? deviceName : 'Unknown Device',
                rssi: result.rssi,
                device: result.device,
                ipAddress: ipAddress,
              ));
            }

            // Emit updated list
            _deviceStreamController.add(_discoveredDevices);

            print('find All deviceName: ${_deviceStreamController}');
          }
        }
      });

      // Start the scan
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidScanMode: AndroidScanMode.lowLatency,
      );

      // Stop scan after timeout (handled automatically, but we'll also stop it manually)
      await Future.delayed(const Duration(seconds: 10));
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (e) {
      print('Error scanning for devices: $e');
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    }
  }

  // Connect to device
  Future<BluetoothDevice?> connectToDevice(String deviceId, {bool enableHttp = true}) async {
    try {
      // 打印_discoveredDevices内容，便于调试
      print('_discoveredDevices dump:');
      for (var device in _discoveredDevices) {
        print('  ${device.toString()}');
      }
      // 查找选定的设备
      BleDevice? selectedDevice;
      for (var device in _discoveredDevices) {
        if (device.id == deviceId) {
          selectedDevice = device;
          break;
        }
      }

      
      // 检查设备是否有IP地址
      if (selectedDevice != null && selectedDevice.ipAddress != null && enableHttp) {
        final ip = selectedDevice.ipAddress!;
        if (ip == '0.0.0.0' || ip.isEmpty) {
          print('设备IP地址为0.0.0.0或空，跳过HTTP连接，直接使用蓝牙模式');
          _useHttpMode = false;
        } else {
          print('设备有IP地址: $ip，尝试HTTP连接...');
          // 配置HTTP服务
          _httpService.configure(ip);
          // 检查HTTP连接
          bool httpConnected = await _httpService.checkConnectivity();
          if (httpConnected) {
            print('HTTP连接成功，将使用HTTP模式');
            _useHttpMode = true;
            // 在HTTP模式下，我们仍然存储原始蓝牙设备引用，但主要使用HTTP服务
            _connectedDevice = selectedDevice.device;
            return selectedDevice.device;
          } else {
            print('HTTP连接失败，将使用蓝牙模式');
            _useHttpMode = false;
            _httpService.clear();
          }
        }
      } else {
        print('设备没有IP地址，将使用蓝牙模式');
        _useHttpMode = false;
      }
      
      // 如果HTTP连接失败或设备没有IP地址，则使用蓝牙连接
      BluetoothDevice? device;

      // 首先检查是否已连接
      print('检查设备是否已连接: $deviceId');
      try {
        List<BluetoothDevice> connectedDevices = await FlutterBluePlus.connectedDevices;
        device = connectedDevices.firstWhere(
              (d) => d.remoteId.str == deviceId,
        );
        // 如果到达这里，设备已连接
        print('设备已连接: $deviceId');
        _connectedDevice = device;
        return device;
      } catch (e) {
        // 设备未连接，需要连接
        print('设备未连接，尝试连接: $deviceId');
      }

      // 查找要连接的设备
      device = null;
      for (BleDevice bleDevice in _discoveredDevices) {
        if (bleDevice.id == deviceId && bleDevice.device != null) {
          device = bleDevice.device;
          break;
        }
      }

      if (device == null) {
        print('找不到设备: $deviceId');
        throw Exception('找不到设备');
      }

      // 断开之前的连接
      if (_connectedDevice != null) {
        await disconnect();
      }

      // 连接到设备
      print('连接到设备: ${device.platformName}');
      await device.connect(timeout: Duration(seconds: 15), autoConnect: false);
      
      print('设备已连接');
      _connectedDevice = device;
      return device;
    } catch (e) {
      print('连接设备时出错: $e');
      throw Exception('连接设备失败: $e');
    }
  }

  // 清理JSON字符串，移除非法字符
  String _cleanJsonString(String input) {
    // 寻找第一个{和最后一个}，提取中间内容
    int startIndex = input.indexOf('{');
    int endIndex = input.lastIndexOf('}');

    if (startIndex >= 0 && endIndex > startIndex) {
      return input.substring(startIndex, endIndex + 1);
    }

    // 如果没有找到完整的JSON结构，返回原字符串
    return input;
  }

  // Configure WiFi
  Future<String> configureWiFi(String ssid, String password, bool restore) async {
    String defaultResult = '{"connected":false, "ip_address":""}';
    try {
      // 检查是否使用HTTP模式
      if (_useHttpMode) {
        return defaultResult;
      }
      
      print('使用蓝牙模式配置WiFi');
      
      if (_connectedDevice == null) {
        throw Exception('Not connected to any device');
      }

      // Discover services
      List<BluetoothService> services = await _connectedDevice!.discoverServices();

      // Find our service
      BluetoothService service = services.firstWhere(
            (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
      );

      // Find WiFi Config characteristic
      BluetoothCharacteristic wifiConfigChar = service.characteristics.firstWhere(
            (c) => c.uuid.toString().toLowerCase() == HUBV3_WIFI_CONFIG_CHAR_UUID.toLowerCase(),
      );

      // Prepare the JSON payload
      Map<String, dynamic> payload = {
        'ssid': ssid,
        'password': password,
        'restore': restore,
      };

      String jsonPayload = jsonEncode(payload);
      print('发送WiFi配置: $jsonPayload');

      // 创建一个Completer来等待响应
      Completer<String> completer = Completer<String>();
      StreamSubscription<List<int>>? subscription;

      // 设置超时
      Timer timer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete(defaultResult);
          print('获取WiFi设置结果超时，返回默认状态');
        }
      });

      // 监听indicate通知
      subscription = wifiConfigChar.onValueReceived.listen((value) {
        print('收到WiFi设置结果通知: ${value.length} 字节');

        // 解码并清理字符串
        String rawString = utf8.decode(value);
        print('原始WiFi设置结果字符串: $rawString');

        // 清理字符串，只保留JSON部分
        String resultString = _cleanJsonString(rawString);
        print('清理后的WiFi状态字符串: $resultString');

        // 验证JSON有效性
        try {
          jsonDecode(resultString);
          print('WiFi状态JSON有效');
        } catch (e) {
          print('WiFi状态JSON无效: $e');
          resultString = defaultResult;
        }

        // 取消订阅和定时器
        subscription?.cancel();
        timer.cancel();

        // 完成Completer
        if (!completer.isCompleted) {
          completer.complete(resultString);
        }
      }, onError: (error) {
        print('WiFi设置通知错误: $error');
        if (!completer.isCompleted) {
          completer.complete(defaultResult);
        }
        subscription?.cancel();
        timer.cancel();
      });

      // 开启indicate
      try {
        await wifiConfigChar.setNotifyValue(true);
        print('已开启WiFi设置通知');

        // 可能需要主动请求一次状态
        if (wifiConfigChar.properties.write) {
          try {
            await wifiConfigChar.write(utf8.encode(jsonPayload));
            print('已发送WiFi设置请求');
          } catch (e) {
            print('发送WiFi设置请求失败: $e');
          }
        }

        // 等待通知结果或超时
        final result = await completer.future;

        // 完成后关闭通知
        try {
          await wifiConfigChar.setNotifyValue(false);
          print('已关闭WiFi设置结果通知');
        } catch (e) {
          print('关闭通知失败: $e');
        }

        return result;
      } catch (e) {
        subscription?.cancel();
        timer.cancel();
        print('WiFi设置结果通知设置失败: $e');
        return defaultResult;
      }

    } catch (e) {
      print('配置WiFi失败: $e');
      return defaultResult;
    }
  }

  // Delete WiFi networks
  Future<String> deleteWiFiNetworks() async {
    try {
      // 检查是否使用HTTP模式
      if (_useHttpMode) {
        print('使用HTTP模式删除WiFi网络');
        await _httpService.deleteWiFiNetworks();
      }

      throw Exception('Not connected to any device');
    } catch (e) {
      print('删除WiFi网络失败: $e');
      return 'Error: $e';
    }
  }

  // Send command
  Future<String> sendCommand(String command) async {
    try {
      // 检查是否使用HTTP模式
      if (_useHttpMode) {
        print('使用HTTP模式发送命令');
        return await _httpService.sendCommand(command);
      }

      throw Exception('Not connected to any device');
    } catch (e) {
      print('发送命令失败: $e');
      return 'Error: $e';
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    // 清除HTTP模式
    _useHttpMode = false;
    _httpService.clear();
    
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        print('已断开连接');
      } catch (e) {
        print('断开连接时出错: $e');
      }
      _connectedDevice = null;
    }
  }

  // Dispose
  void dispose() {
    _deviceStreamController.close();
    BleService().disconnect();
  }
}
