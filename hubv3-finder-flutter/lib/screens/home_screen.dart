import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/http_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/WiFiConnectionStatus.dart';
import 'device_scan_screen.dart';
import 'device_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedDeviceId;
  String? _selectedDeviceIp;
  String? _selectedDeviceName;
  String? _selectedWifiMac;
  WiFiConnectionStatus? _wifiStatus;
  bool _loadingDevice = false;

  @override
  void initState() {
    super.initState();
    _loadSelectedDevice();
  }

  Future<void> _loadSelectedDevice() async {
    setState(() { _loadingDevice = true; });
    final prefs = await SharedPreferences.getInstance();
    _selectedDeviceId = prefs.getString('selected_device_id');
    _selectedDeviceIp = prefs.getString('selected_device_ip');
    _selectedDeviceName = prefs.getString('selected_device_name');
    _selectedWifiMac = prefs.getString('selected_wifi_mac');
    if (_selectedDeviceIp != null) {
      HttpService().configure(_selectedDeviceIp!);
      try {
        final wifiStatusJson = await HttpService().getWifiStatus();
        _wifiStatus = WiFiConnectionStatus.fromJson(wifiStatusJson);
      } catch (e) {
        _wifiStatus = WiFiConnectionStatus.error('获取WiFi状态失败');
      }
    } else {
      _wifiStatus = null;
    }
    setState(() { _loadingDevice = false; });
  }

  Future<void> _saveSelectedDevice({required String id, required String ip, String? deviceName, String? wifiMac}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_device_id', id);
    await prefs.setString('selected_device_ip', ip);
    if (deviceName != null) await prefs.setString('selected_device_name', deviceName);
    if (wifiMac != null) await prefs.setString('selected_wifi_mac', wifiMac);
    setState(() {
      _selectedDeviceId = id;
      _selectedDeviceIp = ip;
      _selectedDeviceName = deviceName;
      _selectedWifiMac = wifiMac;
    });
  }

  void _goToScan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DeviceScanScreen()),
    );
    // Handle the returned device info from scan page and refresh
    if (result is Map && result['selected_device_id'] != null) {
      await _loadSelectedDevice();
    }
    // If result is not a valid selection, do not refresh device info
  }

  Widget _buildDeviceCard() {
    if (_loadingDevice) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: SizedBox(
          height: 120,
          child: Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 5),
            ),
          ),
        ),
      );
    }
    if (_selectedDeviceId == null || _selectedDeviceIp == null) {
      return GestureDetector(
        onTap: _goToScan,
        child: Card(
          color: Colors.grey[200],
          margin: const EdgeInsets.all(16),
          child: SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'Add Device',
                style: TextStyle(fontSize: 20, color: Colors.blue),
              ),
            ),
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.devices, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Device:',
                    style: TextStyle(fontSize: 15, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedDeviceName ?? _selectedDeviceId ?? '',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_selectedDeviceIp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('IP: $_selectedDeviceIp', style: const TextStyle(fontSize: 14)),
                    ),
                  if (_wifiStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Text(
                            'Device Status: ',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            _wifiStatus!.isConnected ? 'Online' : 'Offline/Unavailable',
                            style: TextStyle(
                              fontSize: 14,
                              color: _wifiStatus!.isConnected ? Colors.green : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),                    
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 22),
              onPressed: _goToDetail,
              tooltip: '设备详情',
            ),
          ],
        ),
      ),
    );
  }

  void _goToDetail() {
    if (_selectedDeviceId == null || _selectedDeviceIp == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceDetailScreen(
          deviceId: _selectedDeviceId!,
          deviceIp: _selectedDeviceIp!,
          deviceName: _selectedDeviceName,
        ),
      ),
    );
  }

  Widget _buildCommandList() {
    final commands = [
      {'label': 'Reboot device', 'command': 'reboot', 'icon': Icons.restart_alt},
      {'label': 'Install Software', 'command': 'install', 'icon': Icons.download},
      {'label': 'Uninstall Software', 'command': 'uninstall', 'icon': Icons.delete},
    ];
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Tools', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Divider(),
          ...commands.map((cmd) => ListTile(
            leading: Icon(cmd['icon'] as IconData),
            title: Text(cmd['label'] as String),
            onTap: () async {
              // 这里只做演示，实际应调用BleService/HttpService发送命令
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已发送指令: ${cmd['label']}')),
              );
            },
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ThirdReality Hub Finder')),
      body: Column(
        children: [
          _buildDeviceCard(),
          Expanded(child: _buildCommandList()),
        ],
      ),
    );
  }
}
