import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/ble_device.dart';
import '../services/ble_service.dart';
import '../services/http_service.dart';
import 'provision_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({Key? key}) : super(key: key);

  @override
  _DeviceScanScreenState createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final BleService _bleService = BleService();
  final HttpService _httpService = HttpService();
  List<BleDevice> _devices = [];
  bool _isScanning = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeBle();
  }

  Future<void> _initializeBle() async {
    final initialized = await _bleService.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = initialized;
      });
    }

    if (_isInitialized) {
      _startScan();
      _bleService.deviceStream.listen((devices) {
        if (mounted) {
          setState(() {
            _devices = devices;
          });
        }
      });
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    
    if (mounted) {
      setState(() {
        _isScanning = true;
      });
    }
    
    await _bleService.startScan();
    
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  @override
  void dispose() {
    // No need to call stopScan explicitly as it's handled internally
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hub Scan List')
      ),
      body: !_isInitialized
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.bluetooth_disabled, size: 48, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Bluetooth not available or permissions not granted',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _startScan,
              child: _buildDeviceList(),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? null : _startScan,
        child: _isScanning
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.refresh),
        tooltip: 'Scan for devices',
      ),
    );
  }

  void _onConnectToDevice(BleDevice device, {bool enableHttp = true, bool showPrompt = true}) async {
    // Check if there is an IP address and it is not 0
    final hasIp = device.ipAddress != null && device.ipAddress!.isNotEmpty && device.ipAddress != '0.0.0.0';
    if (hasIp && enableHttp) {
      // HTTP mode, configure HTTP Service and check connectivity
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('Connecting'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to device by ip address ...'),
            ],
          ),
        ),
      );
      try {
        // Configure HTTP service with device IP
        _httpService.configure(device.ipAddress!);
        
        // Get WiFi status instead of just checking connectivity
        final wifiStatusResponse = await _httpService.getWifiStatus();
        final wifiStatus = jsonDecode(wifiStatusResponse);
        
        // Close the loading dialog
        if (mounted) {
          Navigator.of(context).pop();
        }
        
        if (wifiStatus['connected'] == true) {
          // HTTP connection successful, save device information
          print('HTTP connection successful');
          print('device.id = ${device.id}');
          print('device.ipAddress = ${device.ipAddress}');
          print('device.name = ${device.name}');
          print('WiFi SSID = ${wifiStatus['ssid']}');
          
          // Save the SSID to SharedPreferences
          if (wifiStatus['ssid'] != null && wifiStatus['ssid'].toString().isNotEmpty) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('selected_ssid', wifiStatus['ssid']);
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('selected_device_id', device.id);
          if (device.ipAddress != null) {
            await prefs.setString('selected_device_ip', device.ipAddress!);
          }
          if (device.name != null) {
            await prefs.setString('selected_device_name', device.name!);
          }
          // Return to home page and refresh
          if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      } else {
          // HTTP connection failed, show network configuration dialog
          _showNetworkConfigDialog(device);
        }
      } catch (e) {
        // Close the loading dialog if still open
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showNetworkConfigDialog(device);
      }
    } else {

      if(showPrompt) {
        // Show prompt dialog for WiFi setup
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('WiFi provision'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(TextSpan(
                  children: [
                    TextSpan(text: '1. Press and hold the button on the device for 7-8 seconds until the LED changes from GREEN to '),
                    TextSpan(text: 'YELLOW', style: TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: ', then release the button'),
                  ],
                )),
                SizedBox(height: 16),
                Text('2. Click Next to continue'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Back'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _onConnectToDevice(device, enableHttp: false, showPrompt: false);
                },
                child: const Text('Next'),
              ),
            ],
          ),
        );
        return;
      }

      // Connect BLE first, ensure BLE is connected before entering provisioning page
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('Connecting'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Connecting to device ...'),
            ],
          ),
        ),
      );
      
      try {
        await _bleService.connectToDevice(device.id, enableHttp: false);
        
        // Close the loading dialog
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        
        // After successful connection, navigate to ProvisionScreen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProvisionScreen(deviceId: device.id),
          ),
        );
        // Provisioning success, saving info and navigation logic handled in provision_screen, no need to navigate here
      } catch (e) {
        // Close the loading dialog if still open
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        _showConnectionErrorDialog(e.toString(), device);
      }
    }
  }

  // Show network configuration dialog when HTTP connection fails
  void _showNetworkConfigDialog(BleDevice device) async {
    // Get the saved SSID from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedSsid = prefs.getString('selected_ssid') ?? 'Unknown';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('WiFi provision'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(TextSpan(
              children: [
                TextSpan(text: 'If you want to connect to an existing device, please confirm that the App and device are connected to the same wireless network: '),
                TextSpan(text: savedSsid, style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            )),
            SizedBox(height: 12),
            Text('If you want to connect this device to a new wireless network, please follow these steps:'),
            SizedBox(height: 8),
            Text.rich(TextSpan(
              children: [
                TextSpan(text: '1. Press and hold the button on the device for 7-8 seconds until the LED changes from GREEN to '),
                TextSpan(text: 'YELLOW', style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: ', then release the button'),
              ],
            )),
            SizedBox(height: 8),
            Text.rich(TextSpan(
              children: [
                TextSpan(text: '2. Click '),
                TextSpan(text: 'Next', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              _onConnectToDevice(device, enableHttp: false, showPrompt: false);
              //await _bleService.connectToDevice(device.id, enableHttp: false);
            },
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  void _showConnectionErrorDialog(String errorMessage, BleDevice device) {
    String errorTitle = 'Connection Failed';
    String errorDetails = errorMessage;
    String errorGuide = 'Please try the following:\n- Ensure the device is powered on and nearby\n- Turn off and on your phone\'s Bluetooth\n- Restart the application';
    
    // Check if it's Android error code 133
    if (errorMessage.contains('android-code: 133')) {
      errorTitle = 'Bluetooth Connection Error (Code: 133)';
      errorDetails = 'Unable to connect to the device. Possible reasons:\n1. Device is connected to another application\n2. Device is out of range or powered off\n3. Phone Bluetooth has issues';
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(errorTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errorDetails),
            const SizedBox(height: 16),
            Text(errorGuide),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _onConnectToDevice(device, enableHttp: false, showPrompt: false);
            },
            child: const Text('Retry Connection'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isScanning
                ? const CircularProgressIndicator()
                : const Icon(Icons.bluetooth_searching, size: 48),
            const SizedBox(height: 16),
            Text(
              _isScanning
                  ? 'Scanning for devices...'
                  : 'No devices found. Pull to refresh or tap the button to scan again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: Icon(
              Icons.bluetooth,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(device.name.isEmpty ? 'Unknown Device' : device.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${device.id}'),
                if (device.ipAddress != null && device.ipAddress!.isNotEmpty && device.ipAddress != '0.0.0.0')
                  Text('IP: ${device.ipAddress}', style: const TextStyle(color: Colors.green)),
                Text('Signal: ${device.rssi} dBm'),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () async {
                _onConnectToDevice(device);
              },
              child: const Text('Connect'),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
