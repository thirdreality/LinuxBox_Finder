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
    
    try {
      await _bleService.startScan();
    } catch (e) {
      print('Error scanning for devices: $e');
      
      if (mounted) {
        // Show generic error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning for devices: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
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

  void _onSelectDevice(BleDevice device) async {
    // Stop scanning first
    if (_isScanning) {
      print('DeviceScanScreen: Stopping scan before selecting...');
      await _bleService.stopScan();
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
      print('DeviceScanScreen: Scan stopped.');
    }

    // Check if device has IP address and is already connected
    final hasIp = device.ipAddress != null && device.ipAddress!.isNotEmpty && device.ipAddress != '0.0.0.0';
    if (hasIp) {
      // Device has IP address, check if it's already connected
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('Checking Device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking device connection...'),
            ],
          ),
        ),
      );
      
      try {
        // Configure HTTP service with device IP
        _httpService.configure(device.ipAddress!);
        
        // Get WiFi status to check if device is already connected
        final wifiStatusResponse = await _httpService.getWifiStatus();
        final wifiStatus = jsonDecode(wifiStatusResponse);
        
        // Close the loading dialog
        if (mounted) {
          Navigator.of(context).pop();
        }
        
        if (wifiStatus['connected'] == true) {
          // Device is already connected to WiFi, save device information and return to home
          print('Device already connected to WiFi');
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
          
          // Show success message and return to home page
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device already connected. Returning to home page.'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Return to home page and refresh
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          }
          return;
        } else {
          // Device has IP but not connected to WiFi, proceed to provision
          _navigateToProvision(device);
        }
      } catch (e) {
        // Close the loading dialog if still open
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        // HTTP connection failed, proceed to provision
        _navigateToProvision(device);
      }
    } else {
      // Device has no IP address, proceed to provision
      _navigateToProvision(device);
    }
  }

  void _navigateToProvision(BleDevice device) async {
    // Save the selected device to SharedPreferences for the provision screen
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provision_device_id', device.id);
    await prefs.setString('provision_device_name', device.name);
    if (device.ipAddress != null) {
      await prefs.setString('provision_device_ip', device.ipAddress!);
    }
    
    // Navigate to ProvisionScreen without connecting BLE first
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProvisionScreen(deviceId: device.id),
      ),
    );
    
    // If provision was successful, result should contain device info
    if (result != null && result is Map<String, dynamic>) {
      print('[DeviceScan] Provision returned result, navigating to home page');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } else {
      print('[DeviceScan] Provision returned null or invalid result, staying on scan page');
    }
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
                _onSelectDevice(device);
              },
              child: const Text('Select'),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
