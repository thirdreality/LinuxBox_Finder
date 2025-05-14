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
  static const String CCCD_DESCRIPTOR_UUID = "00002902-0000-1000-8000-00805f9b34fb"; // Standard CCCD descriptor UUID
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
            
            // Check manufacturer data, try to extract IP address
            String? ipAddress;
            if (result.advertisementData.manufacturerData.isNotEmpty) {
              // Manufacturer ID 0x0133 data contains IP address
              final data = result.advertisementData.manufacturerData[0x0133];
              if (data != null && data.length >= 4) {
                // Extract IP address, format is 4 bytes [192, 168, 1, 100]
                ipAddress = '${data[0]}.${data[1]}.${data[2]}.${data[3]}';
                print('Extracted device IP address: $ipAddress');
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

            print('find All deviceName: ${_deviceStreamController}'); // Debug: print all found device names
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
      // Print _discoveredDevices for debugging
      print('_discoveredDevices dump:');
      for (var device in _discoveredDevices) {
        print('  ${device.toString()}');
      }
      // Find the selected device
      BleDevice? selectedDevice;
      for (var device in _discoveredDevices) {
        if (device.id == deviceId) {
          selectedDevice = device;
          break;
        }
      }
      
      // Check if device has IP address
      if (selectedDevice != null && selectedDevice.ipAddress != null && enableHttp) {
        final ip = selectedDevice.ipAddress!;
        if (ip == '0.0.0.0' || ip.isEmpty) {
          print('Device IP address is 0.0.0.0 or empty, skip HTTP connection and use BLE mode directly');
          _useHttpMode = false;
        } else {
          print('Device has IP address: $ip, trying HTTP connection...');
          // Configure HTTP service
          _httpService.configure(ip);
          // Check HTTP connection
          bool httpConnected = await _httpService.checkConnectivity();
          if (httpConnected) {
            print('HTTP connection successful, will use HTTP mode');
            _useHttpMode = true;
            // In HTTP mode, we still store the original BLE device reference, but mainly use HTTP service
            _connectedDevice = selectedDevice.device;
            return selectedDevice.device;
          } else {
            print('HTTP connection failed, will use BLE mode');
            _useHttpMode = false;
            _httpService.clear();
          }
        }
      } else {
        print('Device has no IP address, will use BLE mode');
        _useHttpMode = false;
      }
      
      // If HTTP connection fails or device has no IP address, use BLE connection
      BluetoothDevice? device;

      // First check if already connected
      print('Check if device is already connected: $deviceId');
      try {
        List<BluetoothDevice> connectedDevices = await FlutterBluePlus.connectedDevices;
        device = connectedDevices.firstWhere(
              (d) => d.remoteId.str == deviceId,
        );
        // If reached here, device is connected
        print('Device connected: $deviceId');
        _connectedDevice = device;
        return device;
      } catch (e) {
        // Device not connected, need to connect
        print('Device not connected, trying to connect: $deviceId');
      }

      // Find the device to connect
      device = null;
      for (BleDevice bleDevice in _discoveredDevices) {
        if (bleDevice.id == deviceId && bleDevice.device != null) {
          device = bleDevice.device;
          break;
        }
      }

      if (device == null) {
        print('Device not found: $deviceId');
        throw Exception('Device not found');
      }

      // Disconnect previous connection
      if (_connectedDevice != null) {
        await disconnect();
      }

      // Connect to device with retry logic
      print('Connecting to device: ${device.platformName}');
      int retryCount = 0;
      const maxRetries = 3;
      
      while (retryCount < maxRetries) {
        try {
          // Before attempting to connect, ensure any previous connections are properly closed
          try {
            // Try to disconnect first to clear any stale connections
            await device.disconnect();
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            // Ignore errors during disconnect as the device might not be connected
            print('Disconnect before connect attempt: $e');
          }
          
          // Now try to connect
          await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);
          print('BlueTooth connected successfully');
          _connectedDevice = device;
          return device;
        } catch (e) {
          retryCount++;
          print('Connection attempt $retryCount failed: $e');
          
          // Check if this is the Android error code 133
          if (e.toString().contains('android-code: 133')) {
            print('Android error code 133 detected, waiting before retry...');
            // Wait longer between retries for this specific error
            await Future.delayed(const Duration(seconds: 2));
            
            // If this is the last retry, try toggling Bluetooth
            if (retryCount == maxRetries - 1) {
              print('Last retry attempt, suggesting Bluetooth reset');
              // We can't toggle Bluetooth programmatically, so we'll just inform the user
            }
          } else {
            // For other errors, wait a shorter time
            await Future.delayed(const Duration(milliseconds: 500));
          }
          
          // If we've reached max retries, rethrow the error
          if (retryCount >= maxRetries) {
            throw Exception('Failed to connect after $maxRetries attempts: $e');
          }
        }
      }
      
      // This should not be reached due to the exception in the loop, but just in case
      throw Exception('Failed to connect to device after multiple attempts');
    } catch (e) {
      print('Error connecting to device: $e');
      throw Exception('Failed to connect to device: $e');
    }
  }

  // Clean up JSON string, remove invalid characters
  String _cleanJsonString(String input) {
    // Find the first '{' and the last '}', extract the content in between
    int startIndex = input.indexOf('{');
    int endIndex = input.lastIndexOf('}');

    if (startIndex >= 0 && endIndex > startIndex) {
      return input.substring(startIndex, endIndex + 1);
    }

    // If a complete JSON structure is not found, return the original string
    return input;
  }

  // Configure WiFi
  Future<String> configureWiFi(String ssid, String password, bool restore) async {
    String defaultResult = '{"connected":false, "ip_address":""}';
    try {
      // Check if HTTP mode is used
      if (_useHttpMode) {
        return defaultResult;
      }
      
      print('Configuring WiFi using BLE mode');
      
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
      print('Sending WiFi config: $jsonPayload');

      // Create a Completer to wait for response
      Completer<String> completer = Completer<String>();
      StreamSubscription<List<int>>? subscription;
 
      // Set timeout
      Timer timer = Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          subscription?.cancel();
          completer.complete(defaultResult);
          print('Timeout getting WiFi config result, returning default state');
        }
      });

      // Listen to indicate notification
      subscription = wifiConfigChar.onValueReceived.listen((value) {
        print('Received WiFi config result notification: ${value.length} bytes');

        // Decode and clean up string
        String rawString = utf8.decode(value);
        print('Raw WiFi config result string: $rawString');

        // Clean up string, keep only JSON part
        String resultString = _cleanJsonString(rawString);
        print('Cleaned WiFi status string: $resultString');

        // Validate JSON
        try {
          jsonDecode(resultString);
          print('WiFi status JSON valid');
        } catch (e) {
          print('WiFi status JSON invalid: $e');
          resultString = defaultResult;
        }

        // Cancel subscription and timer
        subscription?.cancel();
        timer.cancel();

        // Complete Completer
        if (!completer.isCompleted) {
          completer.complete(resultString);
        }
      }, onError: (error) {
        print('WiFi config notification error: $error');
        if (!completer.isCompleted) {
          completer.complete(defaultResult);
        }
        subscription?.cancel();
        timer.cancel();
      });

      // Enable indicate
      try {
        await wifiConfigChar.setNotifyValue(true);
        print('WiFi config notification enabled');

        // May need to actively request status once
        if (wifiConfigChar.properties.write) {
          try {
            await wifiConfigChar.write(utf8.encode(jsonPayload));
            print('WiFi config request sent');
          } catch (e) {
            print('Failed to send WiFi config request: $e');
          }
        }

        // Wait for notification result or timeout
        final result = await completer.future;

        // Close notification after completion
        try {
          await wifiConfigChar.setNotifyValue(false);
          print('WiFi config result notification closed');
        } catch (e) {
          print('Failed to close notification: $e');
        }

        return result;
      } catch (e) {
        subscription?.cancel();
        timer.cancel();
        print('Failed to set WiFi config result notification: $e');
        return defaultResult;
      }

    } catch (e) {
      print('Failed to configure WiFi: $e');
      return defaultResult;
    }
  }


  // Send command
  Future<String> sendCommand(String command) async {
    try {
      // Check if HTTP mode is used
      if (_useHttpMode) {
        print('Send command using HTTP mode');
        return await _httpService.sendCommand(command);
      }

      throw Exception('Not connected to any device');
    } catch (e) {
      print('Failed to send command: $e');
      return 'Error: $e';
    }
  }

  // Disconnect from device
  Future<void> disconnect() async {
    // Clear HTTP mode
    _useHttpMode = false;
    _httpService.clear();
    
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        print('BlueTooth Disconnected');
      } catch (e) {
        print('Error when disconnecting: $e');
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
