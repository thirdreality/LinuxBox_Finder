import 'package:flutter/material.dart';
import '../models/ble_device.dart';
import '../services/ble_service.dart';
import 'provision_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({Key? key}) : super(key: key);

  @override
  _DeviceScanScreenState createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final BleService _bleService = BleService();
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

  void _onConnectToDevice(BleDevice device) async {
    // Check if there is an IP address and it is not 0
    final hasIp = device.ipAddress != null && device.ipAddress!.isNotEmpty && device.ipAddress != '0.0.0.0';
    if (hasIp) {
      // HTTP mode, directly configure HTTP Service and navigate to control page
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
              Text('Connecting via HTTP...'),
            ],
          ),
        ),
      );
      try {
        await _bleService.connectToDevice(device.id);
        // Save device information to SharedPreferences
        print('device.id = $device.id');
        print('device.ipAddress = $device.ipAddress');
        print('device.name = $device.name');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_device_id', device.id);
        if (device.ipAddress != null) {
          await prefs.setString('selected_device_ip', device.ipAddress!);
        }
        if (device.name != null) {
          await prefs.setString('selected_device_name', device.name!);
        }
        // WiFi MAC is not available for now, can be extended
        // Return to home page and refresh
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        _showConnectionErrorDialog(e.toString(), device);
      }
    } else {
      // Connect BLE first, ensure BLE is connected before entering provisioning page
      try {
        await _bleService.connectToDevice(device.id);
        // After successful connection, navigate to ProvisionScreen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProvisionScreen(deviceId: device.id),
          ),
        );
        // Provisioning success, saving info and navigation logic handled in provision_screen, no need to navigate here
      } catch (e) {
        _showConnectionErrorDialog(e.toString(), device);
      }
    }
  }

  void _showConnectionErrorDialog(String errorMessage, BleDevice device) {
    String errorTitle = 'Connection Failed';
    String errorDetails = errorMessage;
    String errorGuide = '请尝试以下操作：\n- 确保设备已开机并在附近\n- 关闭并重新打开手机蓝牙\n- 重启应用程序';
    
    // 检查是否为 Android 错误码 133
    if (errorMessage.contains('android-code: 133')) {
      errorTitle = '蓝牙连接错误 (错误码: 133)';
      errorDetails = '无法连接到设备，可能原因：\n1. 设备已被其他应用程序连接\n2. 设备不在范围内或已关闭\n3. 手机蓝牙存在问题';
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
            child: const Text('关闭'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _onConnectToDevice(device);
            },
            child: const Text('重试连接'),
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
