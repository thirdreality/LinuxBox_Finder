import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';

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
        // BLE mode, get via BLE characteristic with reconnection
        statusJson = await configureWiFiWithReconnection('', '', false); // Read-only status
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
  static const String SERVICE_UUID = "6e400000-0000-4e98-8024-bc5b71e0893e";
  static const String HUBV3_WIFI_CONFIG_CHAR_UUID = "6e400001-0000-4e98-8024-bc5b71e0893e";

  // Stream controllers
  final StreamController<List<BleDevice>> _deviceStreamController = StreamController<List<BleDevice>>.broadcast();
  Stream<List<BleDevice>> get deviceStream => _deviceStreamController.stream;

  // Global connection state management
  static final StreamController<bool> _globalConnectionStateController = StreamController<bool>.broadcast();
  static final StreamController<String> _globalConnectionStatusController = StreamController<String>.broadcast();
  
  // Global static getters for connection state
  static Stream<bool> get globalConnectionStateStream => _globalConnectionStateController.stream;
  static Stream<String> get globalConnectionStatusStream => _globalConnectionStatusController.stream;
  static bool _globalIsConnected = false;
  static String _globalConnectionStatus = 'Disconnected';
  
  // Static getters for current state
  static bool get globalIsConnected => _globalIsConnected;
  static String get globalConnectionStatus => _globalConnectionStatus;
  
  // Update global connection state
  static void _updateGlobalConnectionState(bool isConnected, String status) {
    _globalIsConnected = isConnected;
    _globalConnectionStatus = status;
    _globalConnectionStateController.add(isConnected);
    _globalConnectionStatusController.add(status);
    print("[BLE-Global] State updated: $status (connected: $isConnected)");
  }

  BluetoothDevice? _connectedDevice;
  final List<BleDevice> _discoveredDevices = [];

  // Auto-reconnection management
  bool _isReconnecting = false;
  String? _lastDeviceId;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  Timer? _connectionCheckTimer;

  // MTU utility methods - Fixed MTU
  static const int BLE_MTU = 23; // Fixed MTU value
  
  int _currentMtu = BLE_MTU;
  int get currentMtu => _currentMtu;
  int get maxDataLength => _currentMtu - 3; // Subtract ATT header (3 bytes)

  // Huawei/HarmonyOS detection and handling
  bool _isHuaweiDevice = false;
  bool get isHuaweiDevice => _isHuaweiDevice;

  // Check if location services are enabled (required for Android 8.0+ BLE scanning)
  Future<void> _checkLocationServices() async {
    if (!Platform.isAndroid) return; // Only check on Android
    
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable location services in your device settings for Bluetooth scanning to work.');
    }
    
    print('Location services are enabled - BLE scanning allowed');
  }

  // Open location settings for user to enable location services
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      print('Error opening location settings: $e');
      return false;
    }
  }

  // Detect if running on Huawei/HarmonyOS device
  Future<bool> _detectHuaweiDevice() async {
    if (!Platform.isAndroid) return false;
    
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      
      String manufacturer = androidInfo.manufacturer.toLowerCase();
      String brand = androidInfo.brand.toLowerCase();
      String model = androidInfo.model.toLowerCase();
      
      _isHuaweiDevice = manufacturer.contains('huawei') || 
                       brand.contains('huawei') ||
                       brand.contains('honor') ||
                       manufacturer.contains('honor');
      
      print('Device Info: Manufacturer=$manufacturer, Brand=$brand, Model=$model');
      print('Is Huawei/HarmonyOS device: $_isHuaweiDevice');
      
      return _isHuaweiDevice;
    } catch (e) {
      print('Error detecting device type: $e');
      return false;
    }
  }

  // Special permission request for Huawei devices
  Future<bool> _requestHuaweiPermissions() async {
    print('Requesting permissions for Huawei/HarmonyOS device...');
    
    // For Huawei devices, request permissions one by one with delays
    List<Permission> permissions = [
      Permission.bluetooth,
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];
    
    for (Permission permission in permissions) {
      try {
        PermissionStatus status = await permission.request();
        print('Permission $permission status: $status');
        
        if (status.isPermanentlyDenied) {
          print('Permission $permission permanently denied - opening settings');
          await openAppSettings();
          return false;
        }
        
        // Small delay between permission requests for Huawei compatibility
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        print('Error requesting permission $permission: $e');
      }
    }
    
    return true;
  }

  // Initialize BLE
  Future<bool> initialize() async {
    try {
      // Detect device type first
      await _detectHuaweiDevice();
      
      // Use special permission handling for Huawei devices
      if (_isHuaweiDevice) {
        bool permissionsGranted = await _requestHuaweiPermissions();
        if (!permissionsGranted) {
          print('Failed to get required permissions on Huawei device');
          return false;
        }
      } else {
        // Standard permission request for other devices
        Map<Permission, PermissionStatus> permissions = await [
          Permission.bluetooth,          // Legacy Bluetooth permission
          Permission.bluetoothScan,     // Android 12+ BLE scan permission
          Permission.bluetoothConnect,  // Android 12+ BLE connect permission
          Permission.location,          // Location permission (required for BLE scanning)
          Permission.locationWhenInUse, // Alternative location permission
        ].request();

        // Check if any critical permissions were denied
        List<String> deniedPermissions = [];
        permissions.forEach((permission, status) {
          if (status.isDenied || status.isPermanentlyDenied) {
            deniedPermissions.add(permission.toString());
          }
        });

        if (deniedPermissions.isNotEmpty) {
          print('Some permissions were denied: $deniedPermissions');
          // Continue anyway as some permissions might not be required on all devices
        }
      }

      // Check if Bluetooth is available and turned on
      bool isAvailable;
      bool isOn;
      
      try {
        isAvailable = await FlutterBluePlus.isAvailable;
      } catch (e) {
        print('Error checking Bluetooth availability: $e');
        // On Huawei/HarmonyOS, this might fail due to permission issues
        if (e.toString().contains('BLUETOOTH')) {
          print('Bluetooth permission error detected - likely Huawei/HarmonyOS device');
          return false;
        }
        isAvailable = false;
      }

      if (!isAvailable) {
        print('Bluetooth is not available on this device');
        return false;
      }

      try {
        isOn = await FlutterBluePlus.isOn;
      } catch (e) {
        print('Error checking Bluetooth status: $e');
        if (e.toString().contains('BLUETOOTH')) {
          print('Bluetooth permission error - please enable Bluetooth permissions manually');
          return false;
        }
        isOn = false;
      }

      if (!isOn) {
        print('Bluetooth is not turned on');
        return false;
      }

      FlutterBluePlus.setLogLevel(LogLevel.verbose);

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

      // Check if location services are enabled (required for Android 8.0+)
      try {
        await _checkLocationServices();
      } catch (e) {
        print('Location services check failed: $e');
        throw Exception('Location services must be enabled for Bluetooth scanning. Please enable location services in your device settings and try again.');
      }

      // Listen to scan results
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          // Only add devices with our service UUID or with 3RHUB- in the name
          String deviceName = result.device.platformName;

          if (deviceName.isEmpty) {
            continue;
          }

          print('[1]find deviceName $deviceName');

          if (deviceName.contains('3RHUB-') ||
              result.advertisementData.serviceUuids.contains(SERVICE_UUID)) {

            print('[2]find deviceName $deviceName');
            print('[2]find deviceName: ${result.device.remoteId.str}');
            
            // Check manufacturer data, try to extract IP address
            String? ipAddress;
            if (result.advertisementData.manufacturerData.isNotEmpty) {
              // Manufacturer ID 0x0133 data contains encrypted IP address
              final data = result.advertisementData.manufacturerData[0x0133];
              if (data != null && data.length >= 5) { // Now 5 bytes (4 IP bytes + 1 checksum byte)
                // Decrypt the IP address
                ipAddress = _decryptIpAddress(data);
                print('Decrypted device IP address: $ipAddress');
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

  // Stop scanning for devices
  Future<void> stopScan() async {
    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
        print('BleService: Scan stopped by explicit call.');
      }
    } catch (e) {
      print('BleService: Error stopping scan: $e');
    }
  }

  // Connect to device with enhanced retry logic
  Future<BluetoothDevice?> connectToDevice(String deviceId, {bool enableHttp = true}) async {
    try {
      // Print _discoveredDevices for debugging
      print('_discoveredDevices dump:');
      for (var device in _discoveredDevices) {
        print('  ${device.toString()}');
      }
      
      // Stop any ongoing scan to free up resources
      if (FlutterBluePlus.isScanningNow) {
        print('Stopping scan before connection attempt...');
        await FlutterBluePlus.stopScan();
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Find the selected device
      BleDevice? selectedDevice;
      for (var device in _discoveredDevices) {
        if (device.id == deviceId) {
          selectedDevice = device;
          break;
        }
      }
      
      if (selectedDevice == null) {
        print('Device not found in discovered devices, attempting to find from system...');
        // Try to find device from system connected devices
        try {
          List<BluetoothDevice> systemDevices = FlutterBluePlus.connectedDevices;
          for (var sysDevice in systemDevices) {
            if (sysDevice.remoteId.str == deviceId) {
              print('Found device in system connected devices');
              _connectedDevice = sysDevice;
              _lastDeviceId = deviceId;
              _updateGlobalConnectionState(true, 'Connected');
              return sysDevice;
            }
          }
        } catch (e) {
          print('Error checking system connected devices: $e');
        }
        throw Exception('Device not found: $deviceId');
      }
      
      // Check if device has IP address
      if (selectedDevice.ipAddress != null && selectedDevice.ipAddress!.isNotEmpty && enableHttp) {
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
            _updateGlobalConnectionState(true, 'Connected via HTTP');
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
      BluetoothDevice? device = selectedDevice.device;

      if (device == null) {
        throw Exception('BLE device object is null');
      }

      // First check if already connected
      print('Check if device is already connected: $deviceId');
      try {
        List<BluetoothDevice> connectedDevices = FlutterBluePlus.connectedDevices;
        BluetoothDevice? connectedDevice = connectedDevices.where((d) => d.remoteId.str == deviceId).firstOrNull;
        if (connectedDevice != null && connectedDevice.isConnected) {
          // If reached here, device is connected
          print('Device already connected: $deviceId');
          _connectedDevice = connectedDevice;
          _lastDeviceId = deviceId; // Store device ID for auto-reconnection
          _updateGlobalConnectionState(true, 'Connected');
          return connectedDevice;
        }
      } catch (e) {
        // Device not connected, need to connect
        print('Device not connected, trying to connect: $deviceId');
      }

      // Disconnect previous connection if any
      if (_connectedDevice != null && _connectedDevice!.remoteId.str != deviceId) {
        print('Disconnect previous connection before new connection');
        await disconnect();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Enhanced connection with retry logic
      print('Connecting to device: ${device.platformName} (${device.remoteId})');
      const maxRetries = 3;
      int retryCount = 0;
      int android133Count = 0; // Track android-code: 133 errors separately

      // Set up connection state listener
      _connectionSubscription?.cancel(); // Cancel previous subscription
      _connectionSubscription = device.connectionState.listen((BluetoothConnectionState state) async {
        print("[BLE] Connection state changed: $state for device ${device.platformName}");
        
        if (state == BluetoothConnectionState.connected) {
          _updateGlobalConnectionState(true, 'Connected');
          _isReconnecting = false;
          print("[BLE] Device connected successfully");
        } else if (state == BluetoothConnectionState.disconnected) {
          _updateGlobalConnectionState(false, 'Disconnected - ${device.disconnectReason?.description ?? 'Unknown reason'}');
          print("[BLE] Device disconnected - Reason: ${device.disconnectReason?.code} ${device.disconnectReason?.description}");
          
          // If this was not an intentional disconnect and we have a device to reconnect to
          if (!_isReconnecting && _lastDeviceId != null) {
            print("[BLE] Starting auto-reconnection for device: $_lastDeviceId");
            _updateGlobalConnectionState(false, 'Reconnecting...');
            _startAutoReconnection();
          }
        }
      });

      // cleanup: cancel subscription when disconnected
      device.cancelWhenDisconnected(_connectionSubscription!);

      while (retryCount < maxRetries) {
        try {
          // Update status for current attempt
          _updateGlobalConnectionState(false, 'Connecting... (Attempt ${retryCount + 1}/$maxRetries)');
          
          // Before attempting to connect, ensure any previous connections are properly closed
          try {
            // Try to disconnect first to clear any stale connections
            await device.disconnect();
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            // Ignore errors during disconnect as the device might not be connected
            print('Disconnect before connect attempt: $e');
          }
          
          // Enhanced connection strategy with optimized parameters
          print('Attempting BLE connection with optimized parameters...');
          
          // Try with different connection strategies
          bool connectionSuccessful = false;
          Exception? lastConnectionError;
          
          // Strategy 1: Standard connection with shorter timeout
          try {
            await device.connect(
              timeout: const Duration(seconds: 5), // Reduced from 30s
              autoConnect: false,
              mtu: null
            );
            connectionSuccessful = true;
            print('Strategy 1 (standard) connection successful');
          } catch (e) {
            lastConnectionError = e as Exception;
            print('Strategy 1 failed: $e');
            
            // Strategy 2: Try with autoConnect enabled (for some problematic devices)
            try {
              await Future.delayed(const Duration(milliseconds: 1000));
              await device.connect(
                timeout: const Duration(seconds: 5),
                autoConnect: true,
                mtu: null
              );
              connectionSuccessful = true;
              print('Strategy 2 (autoConnect) connection successful');
            } catch (e2) {
              lastConnectionError = e2 as Exception;
              print('Strategy 2 failed: $e2');
              
              // Strategy 3: Force disconnect and retry
              try {
                await device.disconnect();
                await Future.delayed(const Duration(seconds: 2));
                await device.connect(
                  timeout: const Duration(seconds: 5),
                  autoConnect: false,
                  mtu: null
                );
                connectionSuccessful = true;
                print('Strategy 3 connection successful');
              } catch (e3) {
                lastConnectionError = e3 as Exception;
                print('Strategy 3 failed: $e3');
              }
            }
          }
          
          if (!connectionSuccessful) {
            throw lastConnectionError ?? Exception('All connection strategies failed');
          }
          
          print('Connected to ${device.platformName}');

          // Wait for connection to stabilize
          await Future.delayed(const Duration(milliseconds: 1500));

          // Verify the connection is still active
          if (!device.isConnected) {
            throw Exception('Connection lost immediately after connecting');
          }

          // Attempt to set connection priority for stability (optional)
          try {
            print('Requesting balanced connection priority...');
            await device.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.balanced);
            print('Connection priority set to balanced.');
          } catch (e) {
            print('BleService: Could not set connection priority: $e (continuing anyway)');
          }

          // Fixed MTU - no negotiation needed
          _currentMtu = BLE_MTU;
          print('Using fixed MTU: $BLE_MTU bytes');

          _connectedDevice = device;
          _lastDeviceId = deviceId; // Store device ID for auto-reconnection
          _updateGlobalConnectionState(true, 'Connected');
          return device;
          
        } catch (e) {
          print('Connection attempt ${retryCount + 1} failed: $e');
          
          // Check if this is the Android error code 133 (don't count towards retry limit)
          if (e.toString().contains('android-code: 133')) {
            android133Count++;
            print('Android error code 133 detected (count: $android133Count), waiting before retry...');
            // Wait longer between retries for this specific error
            await Future.delayed(const Duration(seconds: 3));
            
            // Special handling for android-code: 133
            if (android133Count >= 5) {
              // If we get too many 133 errors, suggest Bluetooth reset
              print('Too many android-code: 133 errors, suggesting Bluetooth reset');
              throw Exception('Connection failed with repeated Bluetooth errors. Please turn Bluetooth off and on, then try again.');
            }
            // Don't increment retryCount for android-code: 133
            continue;
          }
          
          retryCount++;
          
          // Check for other specific error types
          if (e.toString().contains('Connection timeout') || e.toString().contains('timeout') || e.toString().contains('Timed out')) {
            print('Connection timeout detected, retrying with shorter delay...');
            await Future.delayed(const Duration(milliseconds: 800));
          } else if (e.toString().contains('device is not available') || e.toString().contains('not found')) {
            print('Device not available error, waiting before retry...');
            await Future.delayed(const Duration(seconds: 2));
          } else if (e.toString().contains('already connected') || e.toString().contains('busy')) {
            print('Device busy/connected error, forcing disconnect and retry...');
            try {
              await device.disconnect();
              await Future.delayed(const Duration(seconds: 2));
            } catch (disconnectError) {
              print('Error during forced disconnect: $disconnectError');
            }
            await Future.delayed(const Duration(seconds: 1));
          } else {
            // For other errors, wait a standard amount
            await Future.delayed(const Duration(seconds: 1));
          }
          
          // If we've reached max retries, rethrow the error with more context
          if (retryCount >= maxRetries) {
            String enhancedError = 'Failed to connect after $maxRetries attempts: $e';
            if (android133Count > 0) {
              enhancedError += '\nAdditionally encountered ${android133Count} Android Bluetooth errors (code 133).';
            }
            enhancedError += '\n\nSuggestions:\n- Ensure the device is powered on and nearby\n- Move closer to the device\n- Turn Bluetooth off and on\n- Restart the app\n- Check if device is connected to another app';
            throw Exception(enhancedError);
          }
        }
      }
      
      // This should not be reached due to the exception in the loop, but just in case
      throw Exception('Failed to connect to device after multiple attempts');
    } catch (e) {
      print('Error connecting to device: $e');
      _updateGlobalConnectionState(false, 'Connection failed');
      throw Exception('Failed to connect to device: $e');
    }
  }

  // Clean up JSON string, remove invalid characters and extract valid JSON
  String _cleanJsonString(String input) {
    if (input.isEmpty) return input;
    
    print('Cleaning input string: "$input"');
    
    // First pass: find the first '{' and the last '}'
    int startIndex = input.indexOf('{');
    int endIndex = input.lastIndexOf('}');

    if (startIndex >= 0 && endIndex > startIndex) {
      String cleaned = input.substring(startIndex, endIndex + 1);
      print('Extracted JSON substring: "$cleaned"');
      
      // Second pass: remove any control characters or invalid UTF-8 sequences
      cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
      
      // Third pass: ensure proper JSON structure
      // Remove any trailing commas before closing braces/brackets
      cleaned = cleaned.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
      
      print('Final cleaned JSON: "$cleaned"');
      return cleaned;
    }

    print('No valid JSON structure found, returning original');
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
        'password': password
      };

      String jsonPayload = jsonEncode(payload);
      print('Sending WiFi config: $jsonPayload');

      // Create a Completer to wait for response
      Completer<String> completer = Completer<String>();
      StreamSubscription<List<int>>? subscription;

      // Buffer to collect fragmented data
      List<int> dataBuffer = [];
      int fragmentCount = 0;

      // Set timeout (will be reset when we start receiving data)
      Timer? timer;
      
      void startTimeout() {
        timer?.cancel();
        // Use different timeout based on whether we're receiving fragments
        Duration timeoutDuration = dataBuffer.isEmpty 
          ? const Duration(seconds: 60)  // Initial timeout
          : const Duration(seconds: 30); // Fragment timeout (shorter)
        
        timer = Timer(timeoutDuration, () {
          if (!completer.isCompleted) {
            subscription?.cancel();
            if (dataBuffer.isNotEmpty) {
              print('Timeout during fragment reception. Received $fragmentCount fragments, ${dataBuffer.length} bytes total');
              print('Partial data: "${String.fromCharCodes(dataBuffer)}"');
            } else {
              print('Timeout waiting for initial response');
            }
            completer.complete(defaultResult);
            print('Timeout getting WiFi config result, returning default state');
          }
        });
      }
      
      // Start initial timeout
      startTimeout();

      print('*** Setting up listener for characteristic: ${wifiConfigChar.uuid}');
      print('*** Characteristic properties: write=${wifiConfigChar.properties.write}, notify=${wifiConfigChar.properties.notify}, indicate=${wifiConfigChar.properties.indicate}');
      
      // Listen to indicate notification
      subscription = wifiConfigChar.onValueReceived.listen((value) {
        print('*** LISTENER TRIGGERED *** - Raw bytes received: ${value.length}');
        fragmentCount++;
        print('=== Fragment $fragmentCount received ===');
        print('Fragment size: ${value.length} bytes');
        
        // Convert bytes to string for debugging
        String currentFragment;
        try {
          currentFragment = utf8.decode(value);
          print('Fragment content: "$currentFragment"');
        } catch (e) {
          print('Fragment contains non-UTF8 data: ${value.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          currentFragment = '[Binary data]';
        }
        
        // Reset timeout when we receive data (extend time for fragmented messages)
        if (dataBuffer.isEmpty) {
          print('First fragment received, resetting timeout');
          startTimeout();
        }
        
        // Add received data to buffer
        dataBuffer.addAll(value);
        print('Total buffered data: ${dataBuffer.length} bytes');

        // Try to decode as string to check if we have a complete JSON
        String bufferedString;
        try {
          bufferedString = utf8.decode(dataBuffer);
        } catch (e) {
          print('UTF-8 decode error, waiting for more data: $e');
          return; // Wait for more data
        }
        
        print('Current buffered string: "$bufferedString"');

        // Check if we have a complete JSON by looking for matching braces
        int openBraces = 0;
        int closeBraces = 0;
        bool hasValidStart = false;
        bool hasValidEnd = false;
        
        for (int i = 0; i < bufferedString.length; i++) {
          if (bufferedString[i] == '{') {
            openBraces++;
            if (!hasValidStart) hasValidStart = true;
          }
          if (bufferedString[i] == '}') {
            closeBraces++;
            if (i == bufferedString.length - 1 || bufferedString.substring(i+1).trim().isEmpty) {
              hasValidEnd = true;
            }
          }
        }
        
        print('JSON completeness check - Open braces: $openBraces, Close braces: $closeBraces');
        print('Valid start: $hasValidStart, Valid end: $hasValidEnd');
        
        // Check for complete JSON: must have matching braces, valid start and end
        bool isCompleteJson = openBraces > 0 && openBraces == closeBraces && hasValidStart && hasValidEnd;
        
        if (isCompleteJson) {
          print('Complete JSON detected, processing...');
          // Clean up string, keep only JSON part
          String resultString = _cleanJsonString(bufferedString);
          print('Cleaned WiFi status string: "$resultString"');

          // Validate JSON
          try {
            final jsonData = jsonDecode(resultString);
            print('WiFi status JSON valid: $jsonData');
            print('Successfully reassembled $fragmentCount fragments into complete JSON');
            
            // Cancel subscription and timer
            subscription?.cancel();
            timer?.cancel();

            // Complete Completer
            if (!completer.isCompleted) {
              print('Completing with result: $resultString');
              completer.complete(resultString);
            }
          } catch (e) {
            print('WiFi status JSON invalid: $e');
            print('Invalid JSON content: "$resultString"');
            // If JSON is still invalid, wait for more data or timeout
            return;
          }
        } else {
          print('Incomplete JSON, waiting for more data. Braces: open=$openBraces, close=$closeBraces');
          print('Need more fragments to complete the message...');
        }
      }, onError: (error) {
        print('WiFi config notification error: $error');
        if (!completer.isCompleted) {
          completer.complete(defaultResult);
        }
        subscription?.cancel();
        timer?.cancel();
      });

      // Enable indicate
      try {
        print('*** Attempting to enable notifications for characteristic');
        print('*** Notify supported: ${wifiConfigChar.properties.notify}');
        print('*** Indicate supported: ${wifiConfigChar.properties.indicate}');
        
        await wifiConfigChar.setNotifyValue(true);
        print('WiFi config notification enabled');
        print('*** Listener should now be active and ready to receive data');

        // May need to actively request status once
        if (wifiConfigChar.properties.write) {
          try {
            List<int> data = utf8.encode(jsonPayload);
            print('WiFi config data length: ${data.length} bytes');
            
            // Use allowLongWrite to handle long data
            await wifiConfigChar.write(
              data,
              allowLongWrite: true,
              timeout: 5
            );
            print('WiFi config request sent successfully');
          } catch (e) {
            print('Failed to send WiFi config request with long write: $e');
            
            // Try alternative approach: smart chunking with fixed size
            try {
              await _writeDataWithSmartChunking(wifiConfigChar, utf8.encode(jsonPayload));
              print('WiFi config request sent successfully using smart chunking');
            } catch (smartChunkError) {
              print('Failed to send WiFi config request with smart chunking: $smartChunkError');
              
              // Final fallback: use traditional 20-byte chunks
              try {
                await _writeDataInChunks(wifiConfigChar, utf8.encode(jsonPayload));
                print('WiFi config request sent successfully using traditional chunking');
              } catch (chunkError) {
                print('Failed to send WiFi config request with all methods: $chunkError');
                print('WARNING: Send failed, but will continue listening for response (device might have received partial data)');
                // Don't cancel listener immediately - device might still respond
                // The timeout will handle completion if no response comes
              }
            }
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
        timer?.cancel();
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

  // Check if device is currently connected
  bool get isConnected {
    if (_useHttpMode) {
      return true; // In HTTP mode, assume connected if HTTP service is configured
    }
    // Check both internal state and actual device connection state
    return _connectedDevice != null && _connectedDevice!.isConnected;
  }

  // Auto-reconnection logic
  Future<void> _startAutoReconnection() async {
    if (_isReconnecting || _lastDeviceId == null) return;
    
    _isReconnecting = true;
    const maxReconnectAttempts = 5;
    const reconnectDelay = Duration(seconds: 2);
    
    for (int attempt = 1; attempt <= maxReconnectAttempts; attempt++) {
      try {
        print("[BLE] Auto-reconnection attempt $attempt/$maxReconnectAttempts");
        
        // Wait before attempting reconnection
        await Future.delayed(reconnectDelay);
        
        // Try to reconnect
        await connectToDevice(_lastDeviceId!, enableHttp: false);
        print("[BLE] Auto-reconnection successful on attempt $attempt");
        break;
        
      } catch (e) {
        print("[BLE] Auto-reconnection attempt $attempt failed: $e");
        
                 if (attempt == maxReconnectAttempts) {
           print("[BLE] Auto-reconnection failed after $maxReconnectAttempts attempts");
           _isReconnecting = false;
           _updateGlobalConnectionState(false, 'Connection failed');
         }
      }
    }
  }

  // Enhanced configureWiFi with auto-reconnection
  Future<String> configureWiFiWithReconnection(String ssid, String password, bool restore) async {
    const maxRetries = 3;
    int retryCount = 0;
    
    while (retryCount < maxRetries) {
      try {
        // Check if we're connected
        if (!isConnected) {
          print("[BLE] Not connected, attempting to reconnect...");
          if (_lastDeviceId != null) {
            try {
              await connectToDevice(_lastDeviceId!, enableHttp: false);
              print("[BLE] Reconnection successful");
            } catch (e) {
              print("[BLE] Reconnection failed: $e");
              if (retryCount == maxRetries - 1) {
                return '{"error": "Failed to reconnect to device after $maxRetries attempts: $e"}';
              }
              retryCount++;
              await Future.delayed(const Duration(seconds: 2));
              continue;
            }
          } else {
            return '{"error": "No device to reconnect to"}';
          }
        }
        
        // Now try to configure WiFi
        return await configureWiFi(ssid, password, restore);
        
      } catch (e) {
        print("[BLE] configureWiFi error: $e");
        
        // Check if this is a connection-related error
        if (e.toString().contains('device is not connected') || 
            e.toString().contains('FlutterBluePlusException')) {
          print("[BLE] Connection error detected, will retry...");
          retryCount++;
          
          if (retryCount < maxRetries) {
                         // Force reconnection on next attempt
             _connectedDevice = null;
             _updateGlobalConnectionState(false, 'Retrying connection...');
             await Future.delayed(const Duration(seconds: 1));
             continue;
          } else {
            return '{"error": "Failed to configure WiFi after $maxRetries attempts due to connection issues: $e"}';
          }
        } else {
          // Non-connection error, don't retry
          return '{"error": "WiFi configuration failed: $e"}';
        }
      }
    }
    
    return '{"error": "Failed to configure WiFi after $maxRetries attempts"}';
  }

  // Disconnect from device
  Future<void> disconnect() async {
    // Clear auto-reconnection
    _isReconnecting = false;
    _lastDeviceId = null;
    _connectionSubscription?.cancel();
    
    // Clear HTTP mode
    _useHttpMode = false;
    _httpService.clear();
    
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        print('Last BlueTooth device Disconnected');
      } catch (e) {
        print('Error when disconnecting: $e');
      }
      _connectedDevice = null;
    }
    
    _updateGlobalConnectionState(false, 'Disconnected');
  }

  // Helper method to write data in chunks
  Future<void> _writeDataInChunks(BluetoothCharacteristic characteristic, List<int> data) async {
    const int chunkSize = 20; // Safe chunk size for BLE
    int offset = 0;
    
    while (offset < data.length) {
      int end = (offset + chunkSize < data.length) ? offset + chunkSize : data.length;
      List<int> chunk = data.sublist(offset, end);
      
      print('Sending chunk ${offset ~/ chunkSize + 1}/${(data.length / chunkSize).ceil()}: ${chunk.length} bytes');
      
      // Use writeWithoutResponse for chunked data to avoid blocking
      await characteristic.write(
        chunk,
        withoutResponse: offset + chunkSize < data.length, // Use withoutResponse for all chunks except the last one
        timeout: 5
      );
      
      offset += chunkSize;
      
      // Small delay between chunks to avoid overwhelming the device
      if (offset < data.length) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  // Decrypt IP address from encrypted bytes
  String _decryptIpAddress(List<int> encryptedData) {
    try {
      // Check if we have at least 5 bytes (4 for IP + 1 for checksum)
      if (encryptedData.length < 5) {
        print('Invalid encrypted data length: ${encryptedData.length}');
        return '0.0.0.0';
      }
      
      // Extract encrypted bytes and checksum
      List<int> encryptedBytes = encryptedData.sublist(0, 4);
      int receivedChecksum = encryptedData[4];
      
      // Calculate checksum to verify integrity
      int calculatedChecksum = encryptedBytes.reduce((a, b) => a + b) & 0xFF;
      if (calculatedChecksum != receivedChecksum) {
        print('Checksum verification failed: calculated=$calculatedChecksum, received=$receivedChecksum');
        return '0.0.0.0';
      }
      
      // Use the same encryption key as the server
      final encryptionKey = utf8.encode('ThirdRealityKey');
      
      // Generate the XOR mask using MD5 hash
      final keyHash = md5.convert(encryptionKey).bytes.sublist(0, 4);
      
      // Decrypt the IP bytes using XOR with the key hash
      List<int> decryptedBytes = [];
      for (int i = 0; i < 4; i++) {
        decryptedBytes.add(encryptedBytes[i] ^ keyHash[i]);
      }
      
      // Format as IP address string
      return '${decryptedBytes[0]}.${decryptedBytes[1]}.${decryptedBytes[2]}.${decryptedBytes[3]}';
    } catch (e) {
      print('Error decrypting IP address: $e');
      return '0.0.0.0';
    }
  }

  // Smart chunking with fixed chunk size
  Future<void> _writeDataWithSmartChunking(BluetoothCharacteristic characteristic, List<int> data) async {
    final chunkSize = 20; // Fixed safe chunk size for BLE
    print('Using fixed chunking with size: $chunkSize bytes');
    
    int offset = 0;
    int chunkIndex = 0;
    
    while (offset < data.length) {
      int end = (offset + chunkSize < data.length) ? offset + chunkSize : data.length;
      List<int> chunk = data.sublist(offset, end);
      chunkIndex++;
      
      print('Sending smart chunk $chunkIndex/${(data.length / chunkSize).ceil()}: ${chunk.length} bytes');
      
      try {
        if (offset + chunkSize < data.length) {
          // Use writeWithoutResponse for intermediate chunks for better throughput
          await characteristic.write(
            chunk,
            withoutResponse: true,
            timeout: 5
          );
          // Shorter delay for writeWithoutResponse
          await Future.delayed(const Duration(milliseconds: 20));
        } else {
          // Use write with response for the last chunk to ensure delivery
          await characteristic.write(
            chunk,
            withoutResponse: false,
            timeout: 5
          );
        }
      } catch (e) {
        print('Smart chunk $chunkIndex failed: $e');
        // Fallback to smaller chunks if current chunk fails
        if (chunk.length > 20) {
          print('Falling back to safe 20-byte chunks');
          await _writeDataInChunks(characteristic, data.sublist(offset));
          return;
        }
        throw e;
      }
      
      offset += chunkSize;
    }
  }

  // Dispose
  void dispose() {
    _deviceStreamController.close();
    _globalConnectionStateController.close();
    _globalConnectionStatusController.close();
    _connectionSubscription?.cancel();
    BleService().disconnect();
  }
}
