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
                // 判断是否有IP地址且不为0
                final hasIp = device.ipAddress != null && device.ipAddress!.isNotEmpty && device.ipAddress != '0.0.0.0';
                if (hasIp) {
                  // HTTP模式，直接配置HTTP Service并跳转控制页
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
                    // 保存设备信息到SharedPreferences
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
                    // 这里假设WiFi MAC暂不可得，可扩展
                    // 返回首页并刷新
                    if (mounted) {
                      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                    }
                  } catch (e) {
                    if (mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to connect: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  // 先连接蓝牙，确保进入配网页面时BLE已连接
                  try {
                    await _bleService.connectToDevice(device.id);
                    // 连接成功后跳转到ProvisionScreen
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProvisionScreen(deviceId: device.id),
                      ),
                    );
                    // 配网成功，保存信息和跳转逻辑已在provision_screen处理，这里无需跳转
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('蓝牙连接失败: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
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
