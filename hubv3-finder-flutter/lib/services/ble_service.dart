import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../models/ble_device.dart';
import '../models/wifi_network.dart';

class BleService {
  // Singleton instance
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // BLE instance - updated for new API
  // No need for .instance anymore, directly use the class methods

  // Service and characteristic UUIDs
  // Use standard UUIDs for GATT attributes
  static const String CCCD_DESCRIPTOR_UUID = "00002902-0000-1000-8000-00805f9b34fb"; // 标准CCCD描述符UUID
  static const String SERVICE_UUID = "6e400000-0000-4e98-8024-bc5b71e0893e";
  static const String HUBV3_WIFI_STATUS_CHAR_UUID = "6e400001-0000-4e98-8024-bc5b71e0893e";
  static const String HUBV3_WIFI_CONFIG_CHAR_UUID = "6e400002-0000-4e98-8024-bc5b71e0893e";
  static const String HUBV3_SYSINFO_CHAR_UUID = "6e400003-0000-4e98-8024-bc5b71e0893e";
  static const String HUBV3_CUSTOM_COMMAND_CHAR_UUID = "6e400004-0000-4e98-8024-bc5b71e0893e";

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
          // Only add devices with our service UUID or with ArmBianWiFi in the name
          String deviceName = result.device.platformName;

          if (deviceName.isEmpty) {
            continue;
          }

          if (deviceName.contains('3RHUB-') ||
              result.advertisementData.serviceUuids.contains(SERVICE_UUID)) {

            print('find deviceName $deviceName');
            print('find deviceName: ${result.device.remoteId.str}');

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
              );
            } else {
              // Add new device
              _discoveredDevices.add(BleDevice(
                id: result.device.remoteId.str,
                name: deviceName.isNotEmpty ? deviceName : 'Unknown Device',
                rssi: result.rssi,
                device: result.device,
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
  Future<BluetoothDevice?> connectToDevice(String deviceId) async {
    try {
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
        // 设备未连接，继续尝试连接
        print('设备未连接，准备进行连接: $e');
      }

      // 检查扫描结果中是否有设备
      BleDevice? targetDevice;
      try {
        targetDevice = _discoveredDevices.firstWhere(
              (d) => d.id == deviceId,
        );
      } catch (e) {
        targetDevice = null;
      }

      // 如果在扫描结果中找不到设备，尝试重新扫描
      if (targetDevice == null) {
        print('在缓存的扫描结果中找不到设备，尝试重新扫描');
        await startScan();

        // 再次检查扫描结果
        try {
          targetDevice = _discoveredDevices.firstWhere(
                (d) => d.id == deviceId,
          );
        } catch (e) {
          targetDevice = null;
        }

        if (targetDevice == null) {
          print('在重新扫描后仍找不到设备，尝试使用系统缓存的设备ID直接连接');

          // 创建一个新的BluetoothDevice实例，使用系统缓存而不是扫描结果
          try {
            // 创建设备ID
            DeviceIdentifier deviceIdentifier = DeviceIdentifier(deviceId);
            device = BluetoothDevice(remoteId: deviceIdentifier);
            print('已创建系统设备实例，尝试连接');
          } catch (e) {
            print('创建设备实例失败: $e');
            throw Exception('无法创建设备实例: $e');
          }
        } else {
          device = targetDevice.device;
          print('在重新扫描后找到设备');
        }
      } else {
        device = targetDevice.device;
        print('在现有扫描结果中找到设备');
      }

      // 确保我们有一个设备实例来连接
      if (device == null) {
        throw Exception('无法获取设备实例');
      }

      print('开始连接设备: ${device.remoteId.str}');

      // 尝试连接，带有重试
      int maxRetries = 3;
      int retryCount = 0;
      bool connected = false;

      while (!connected && retryCount < maxRetries) {
        try {
          // 在连接前确保任何之前的连接已断开
          try {
            await device.disconnect();
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            // 如果设备未连接，断开连接会抛出异常，可以忽略
            print('断开可能的旧连接: $e');
          }

          // 连接到设备
          await device.connect(
            timeout: const Duration(seconds: 15),
            autoConnect: false, // 尝试直接连接而非自动连接
          );

          // 连接成功
          connected = true;
          print('成功连接到设备！');
        } catch (e) {
          retryCount++;
          print('连接尝试 $retryCount 失败: $e');

          if (retryCount >= maxRetries) {
            throw Exception('连接失败，已达最大尝试次数: $e');
          }

          // 等待一段时间再重试
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      // 如果成功连接，更新连接的设备
      _connectedDevice = device;
      return device;
    } catch (e) {
      print('连接设备时出错: $e');

      // 确保任何失败的连接尝试都会断开连接
      if (_connectedDevice != null) {
        try {
          await _connectedDevice!.disconnect();
        } catch (e) {
          print('断开连接失败: $e');
        }
        _connectedDevice = null;
      }

      throw Exception('连接设备失败: $e');
    }
  }

  // Get WiFi Status
  Future<String> getWifiStatus() async {
    // 默认返回未连接状态的JSON字符串
    String defaultResult = '{"connected":false,"ssid":"","ip_address":"","mac_address":""}';

    try {
      if (_connectedDevice == null) {
        throw Exception('Not connected to any device');
      }

      // 尝试设置MTU
      try {
        await _connectedDevice!.requestMtu(512);
        print('MTU请求为512');
      } catch (e) {
        print('MTU请求失败: $e');
      }

      // Discover services
      print('正在发现服务...');
      List<BluetoothService> services = await _connectedDevice!.discoverServices();
      print('发现服务数量: ${services.length}');

      // Find our service
      BluetoothService? service;
      try {
        service = services.firstWhere(
              (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
        );
        print('找到目标服务: ${service.uuid.toString()}');
      } catch (e) {
        print('未找到服务UUID: $SERVICE_UUID');
        print('可用服务: ${services.map((s) => s.uuid.toString()).join(", ")}');
        throw Exception('未找到服务');
      }

      // 查找WiFi状态特征值
      BluetoothCharacteristic? wifiStatusChar;
      try {
        wifiStatusChar = service.characteristics.firstWhere(
              (c) => c.uuid.toString().toLowerCase() == HUBV3_WIFI_STATUS_CHAR_UUID.toLowerCase(),
        );
        print('找到WiFi状态特征值: ${wifiStatusChar.uuid.toString()}, 属性: [读:${wifiStatusChar.properties.read}, 写:${wifiStatusChar.properties.write}, 通知:${wifiStatusChar.properties.notify}, 指示:${wifiStatusChar.properties.indicate}]');
      } catch (e) {
        print('未找到WiFi状态特征值: $HUBV3_WIFI_STATUS_CHAR_UUID');
        throw Exception('未找到WiFi状态特征值');
      }

      // 创建一个Completer来等待响应
      Completer<String> completer = Completer<String>();
      StreamSubscription<List<int>>? subscription;

      // 设置超时
      Timer timer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete(defaultResult);
          print('获取WiFi状态超时，返回默认状态');
        }
      });

      // 监听indicate通知
      subscription = wifiStatusChar.onValueReceived.listen((value) {
        print('收到WiFi状态通知: ${value.length} 字节');

        // 解码并清理字符串
        String rawString = utf8.decode(value);
        print('原始WiFi状态字符串: $rawString');

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
        print('WiFi状态通知错误: $error');
        if (!completer.isCompleted) {
          completer.complete(defaultResult);
        }
        subscription?.cancel();
        timer.cancel();
      });

      // 开启indicate
      try {
        await wifiStatusChar.setNotifyValue(true);
        print('已开启WiFi状态通知');

        // 可能需要主动请求一次状态
        if (wifiStatusChar.properties.write) {
          try {
            await wifiStatusChar.write(utf8.encode('GET_STATUS'));
            print('已发送状态请求');
          } catch (e) {
            print('发送状态请求失败: $e');
          }
        }

        // 等待通知结果或超时
        final result = await completer.future;

        // 完成后关闭通知
        try {
          await wifiStatusChar.setNotifyValue(false);
          print('已关闭WiFi状态通知');
        } catch (e) {
          print('关闭通知失败: $e');
        }

        return result;
      } catch (e) {
        subscription?.cancel();
        timer.cancel();
        print('WiFi状态通知设置失败: $e');
        return defaultResult;
      }
    } catch (e) {
      print('获取WiFi状态错误: $e');
      return defaultResult;
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
  Future<String> configureWiFi(String ssid, String password) async {
    try {
      if (_connectedDevice == null) {
        throw Exception('Not connected to any device');
      }

      // Discover services
      List<BluetoothService> services = await _connectedDevice!.discoverServices();
      print('发现服务数量: ${services.length}');

      // Find our service
      BluetoothService service = services.firstWhere(
            (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
        orElse: () => throw Exception('Service not found'),
      );

      // 查找WiFi配置特征值
      BluetoothCharacteristic? wifiConfigChar;
      try {
        wifiConfigChar = service.characteristics.firstWhere(
              (c) => c.uuid.toString().toLowerCase() == HUBV3_WIFI_CONFIG_CHAR_UUID.toLowerCase(),
        );
        print('找到WiFi配置特征值: ${wifiConfigChar.uuid.toString()}, 属性: [读:${wifiConfigChar.properties.read}, 写:${wifiConfigChar.properties.write}, 写无响应:${wifiConfigChar.properties.writeWithoutResponse}, 通知:${wifiConfigChar.properties.notify}, 指示:${wifiConfigChar.properties.indicate}]');
      } catch (e) {
        print('未找到WiFi配置特征值: $HUBV3_WIFI_CONFIG_CHAR_UUID');
        throw Exception('未找到WiFi配置特征值');
      }

      // 创建一个Completer来等待响应
      Completer<String> completer = Completer<String>();
      StreamSubscription<List<int>>? subscription;

      // 设置超时 (30秒，因为WiFi连接可能需要更长时间)
      Timer timer = Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete('Error: WiFi configuration timeout after 30 seconds');
          print('WiFi配置超时');
        }
      });

      // 监听indicate通知
      subscription = wifiConfigChar.onValueReceived.listen((value) {
        print('收到WiFi配置响应: ${value.length} 字节');

        // 解码响应
        String response = utf8.decode(value);
        print('WiFi配置响应内容: $response');

        // 取消订阅和定时器
        subscription?.cancel();
        timer.cancel();

        // 完成Completer - 在这里立即返回结果，不等待写入操作完成
        if (!completer.isCompleted) {
          completer.complete(response);
        }
      }, onError: (error) {
        print('WiFi配置响应错误: $error');
        if (!completer.isCompleted) {
          completer.complete('Error: $error');
        }
        subscription?.cancel();
        timer.cancel();
      });

      // 开启indicate
      try {
        await wifiConfigChar.setNotifyValue(true);
        print('已开启WiFi配置特征值指示');

        // 准备WiFi配置数据
        Map<String, String> config = {
          'action': 'connect',
          'ssid': ssid,
          'password': password,
        };

        // 转换为JSON并发送
        String jsonConfig = jsonEncode(config);
        print('发送WiFi配置: $jsonConfig');

        // 可能需要主动请求一次状态
        if (wifiConfigChar.properties.write) {
          try {
            await wifiConfigChar.write(utf8.encode(jsonConfig), withoutResponse: false, timeout:30);
            print('成功写入命令（标准方式）');
          } catch (e) {
            print('标准写入失败: $e');
          }
        }

        // 等待响应或超时
        print('等待WiFi配置结果...');
        final result = await completer.future;

        // 完成后关闭indicate（不管关闭是否成功）
        try {
          await wifiConfigChar.setNotifyValue(false);
          print('已关闭WiFi配置特征值指示');
        } catch (e) {
          print('关闭指示失败（可忽略）: $e');
        }

        return result;
      } catch (e) {
        subscription?.cancel();
        timer.cancel();
        print('WiFi配置失败: $e');
        return 'Error: $e';
      }
    } catch (e) {
      print('Error configuring WiFi: $e');
      return 'Error: $e';
    }
  }

  // Delete WiFi networks
  Future<String> deleteWiFiNetworks() async {
    try {
      if (_connectedDevice == null) {
        throw Exception('Not connected to any device');
      }

      // Discover services
      List<BluetoothService> services = await _connectedDevice!.discoverServices();
      print('发现服务数量: ${services.length}');

      // Find our service
      BluetoothService service = services.firstWhere(
            (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
        orElse: () => throw Exception('Service not found'),
      );

      // 查找WiFi配置特征值
      BluetoothCharacteristic? wifiConfigChar;
      try {
        wifiConfigChar = service.characteristics.firstWhere(
              (c) => c.uuid.toString().toLowerCase() == HUBV3_WIFI_CONFIG_CHAR_UUID.toLowerCase(),
        );
        print('找到WiFi配置特征值: ${wifiConfigChar.uuid.toString()}, 属性: [读:${wifiConfigChar.properties.read}, 写:${wifiConfigChar.properties.write}, 写无响应:${wifiConfigChar.properties.writeWithoutResponse}, 通知:${wifiConfigChar.properties.notify}, 指示:${wifiConfigChar.properties.indicate}]');
      } catch (e) {
        print('未找到WiFi配置特征值: $HUBV3_WIFI_CONFIG_CHAR_UUID');
        throw Exception('未找到WiFi配置特征值');
      }

      // 创建一个Completer来等待响应
      Completer<String> completer = Completer<String>();
      StreamSubscription<List<int>>? subscription;

      // 设置超时
      Timer timer = Timer(const Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete('Error: WiFi delete operation timeout after 10 seconds');
          print('删除WiFi网络超时');
        }
      });

      // 监听indicate通知
      subscription = wifiConfigChar.onValueReceived.listen((value) {
        print('收到删除WiFi网络响应: ${value.length} 字节');

        // 解码响应
        String response = utf8.decode(value);
        print('删除WiFi网络响应内容: $response');

        // 取消订阅和定时器
        subscription?.cancel();
        timer.cancel();

        // 完成Completer - 在这里立即返回结果，不等待写入操作完成
        if (!completer.isCompleted) {
          completer.complete(response);
        }
      }, onError: (error) {
        print('删除WiFi网络响应错误: $error');
        if (!completer.isCompleted) {
          completer.complete('Error: $error');
        }
        subscription?.cancel();
        timer.cancel();
      });

      // 开启indicate
      try {
        await wifiConfigChar.setNotifyValue(true);
        print('已开启WiFi配置特征值指示');

        // 准备删除配置数据
        Map<String, String> config = {
          'action': 'delete_connects'
        };

        // 转换为JSON并发送
        String jsonConfig = jsonEncode(config);
        print('发送删除WiFi网络命令: $jsonConfig');

        // 强制写入方法1：使用原始写入方法
        try {
          await wifiConfigChar.write(utf8.encode(jsonConfig), withoutResponse: false, timeout:30);
          print('成功写入命令（标准方式）');
        } catch (e) {
          print('标准写入失败: $e');
        }

        // 等待响应或超时
        print('等待删除WiFi网络结果...');
        final result = await completer.future;

        // 完成后关闭indicate（不管关闭是否成功）
        try {
          await wifiConfigChar.setNotifyValue(false);
          print('已关闭WiFi配置特征值指示');
        } catch (e) {
          print('关闭指示失败（可忽略）: $e');
        }

        return result;
      } catch (e) {
        subscription?.cancel();
        timer.cancel();
        print('删除WiFi网络失败: $e');
        return 'Error: $e';
      }
    } catch (e) {
      print('Error deleting WiFi networks: $e');
      return 'Error: $e';
    }
  }

  // Send command
  Future<String> sendCommand(String command) async {
    try {
      if (_connectedDevice == null) {
        throw Exception('Not connected to any device');
      }

      // Discover services
      List<BluetoothService> services = await _connectedDevice!.discoverServices();
      print('发现服务数量: ${services.length}');

      // Find our service
      BluetoothService service = services.firstWhere(
            (s) => s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase(),
        orElse: () => throw Exception('Service not found'),
      );

      // 打印所有特征值以便调试
      print('服务特征值:');
      for (var char in service.characteristics) {
        print('  UUID: ${char.uuid.toString()}, 属性: [读:${char.properties.read}, 写:${char.properties.write}, 写无响应:${char.properties.writeWithoutResponse}, 通知:${char.properties.notify}, 指示:${char.properties.indicate}]');
        // 打印描述符
        if (char.descriptors.isNotEmpty) {
          print('    描述符:');
          for (var desc in char.descriptors) {
            print('      UUID: ${desc.uuid.toString()}');
          }
        }
      }

      // 获取命令特征值 (用于写入命令和接收响应)
      BluetoothCharacteristic? commandChar;
      try {
        commandChar = service.characteristics.firstWhere(
              (c) => c.uuid.toString().toLowerCase() == HUBV3_CUSTOM_COMMAND_CHAR_UUID.toLowerCase(),
        );
        print('找到命令特征值: ${commandChar.uuid.toString()}, 属性: [读:${commandChar.properties.read}, 写:${commandChar.properties.write}, 写无响应:${commandChar.properties.writeWithoutResponse}, 通知:${commandChar.properties.notify}, 指示:${commandChar.properties.indicate}]');
      } catch (e) {
        print('未找到命令特征值: $HUBV3_CUSTOM_COMMAND_CHAR_UUID');
        throw Exception('未找到命令特征值');
      }

      // 创建一个Completer来等待响应
      Completer<String> completer = Completer<String>();
      StreamSubscription<List<int>>? subscription;

      // 设置超时
      Timer timer = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete('Error: Command timeout after 10 seconds');
          print('命令执行超时');
        }
      });

      // 监听indicate通知
      subscription = commandChar.onValueReceived.listen((value) {
        print('收到命令响应: ${value.length} 字节');

        // 解码响应
        String response = utf8.decode(value);
        print('命令响应内容: $response');

        // 取消订阅和定时器
        subscription?.cancel();
        timer.cancel();

        // 完成Completer
        if (!completer.isCompleted) {
          completer.complete(response);
        }
      }, onError: (error) {
        print('命令响应错误: $error');
        if (!completer.isCompleted) {
          completer.complete('Error: $error');
        }
        subscription?.cancel();
        timer.cancel();
      });

      // 开启indicate
      try {
        await commandChar.setNotifyValue(true);
        print('已开启命令特征值指示');

        // 尝试强制写入命令特征值，即使报告没有写入权限
        try {
          // 使用私有API或反射来绕过权限检查（不推荐，但在这种特殊情况下可以尝试）
          print('尝试写入命令: $command');

          // 强制写入方法1：使用原始写入方法
          try {
            await commandChar.write(utf8.encode(command), withoutResponse: false);
            print('成功写入命令（标准方式）');
          } catch (e) {
            print('标准写入失败: $e，尝试无响应写入');

            // 强制写入方法2：尝试使用无响应写入
            try {
              await commandChar.write(utf8.encode(command), withoutResponse: true);
              print('成功写入命令（无响应方式）');
            } catch (e) {
              print('无响应写入也失败: $e，尝试使用下一种方法');

              // 强制写入方法3：使用原始平台通道（只是打印错误，不阻止继续尝试）
              try {
                final methodChannel = MethodChannel('flutter_blue_plus/methods');
                await methodChannel.invokeMethod('writeCharacteristic', {
                  'deviceId': _connectedDevice!.remoteId.str,
                  'serviceUuid': SERVICE_UUID,
                  'characteristicUuid': HUBV3_CUSTOM_COMMAND_CHAR_UUID,
                  'value': utf8.encode(command),
                  'writeType': 2,  // WRITE_TYPE_DEFAULT
                });
                print('成功使用平台通道写入命令');
              } catch (e) {
                print('平台通道写入失败: $e');
              }
            }
          }
        } catch (e) {
          print('所有写入方法都失败: $e');
          // 继续执行，看看是否会收到响应
        }

        // 等待响应或超时
        print('等待设备响应...');
        final result = await completer.future;

        // 完成后关闭indicate
        try {
          await commandChar.setNotifyValue(false);
          print('已关闭命令特征值指示');
        } catch (e) {
          print('关闭指示失败: $e');
        }

        return result;
      } catch (e) {
        subscription?.cancel();
        timer.cancel();
        print('命令执行失败: $e');
        return 'Error: $e';
      }
    } catch (e) {
      print('Error sending command: $e');
      return 'Error: $e';
    }
  }

  // Disconnect
  Future<void> disconnect() async {
    try {
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
        _connectedDevice = null;
      }
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  // Dispose
  void dispose() {
    _deviceStreamController.close();
    disconnect();
  }
}

