import 'package:flutter/material.dart';
import '../services/http_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/WiFiConnectionStatus.dart';
import 'device_scan_screen.dart';
import 'device_detail_screen.dart';
import 'software_manager_screen.dart';
import 'firmware_manager_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedDeviceId;
  String? _selectedDeviceIp;
  String? _selectedDeviceName;
  WiFiConnectionStatus? _wifiStatus;
  bool _loadingDevice = false;
  String? _restoreResult;

  @override
  void initState() {
    super.initState();
    _loadSelectedDevice();
  }

  Future<void> _loadSelectedDevice() async {
    setState(() {
      _loadingDevice = true;
    });
    final prefs = await SharedPreferences.getInstance();
    _selectedDeviceId = prefs.getString('selected_device_id');
    _selectedDeviceIp = prefs.getString('selected_device_ip');
    _selectedDeviceName = prefs.getString('selected_device_name');
    if (_selectedDeviceIp != null) {
      HttpService().configure(_selectedDeviceIp!);
      try {
        final wifiStatusJson = await HttpService().getWifiStatus(ltime: 3);
        _wifiStatus = WiFiConnectionStatus.fromJson(wifiStatusJson);
      } catch (e) {
        _wifiStatus = WiFiConnectionStatus.error('Failed to get WiFi status');
      }
    } else {
      _wifiStatus = null;
    }
    setState(() {
      _loadingDevice = false;
    });
  }

  Future<void> _saveSelectedDevice(
      {required String id,
      required String ip,
      String? deviceName,
      String? wifiMac}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_device_id', id);
    await prefs.setString('selected_device_ip', ip);
    if (deviceName != null)
      await prefs.setString('selected_device_name', deviceName);
    if (wifiMac != null) await prefs.setString('selected_wifi_mac', wifiMac);
    setState(() {
      _selectedDeviceId = id;
      _selectedDeviceIp = ip;
      _selectedDeviceName = deviceName;
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add_circle_outline, color: Colors.blue, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'Add Device',
                    style: TextStyle(fontSize: 20, color: Colors.blue),
                  ),
                ],
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
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_selectedDeviceIp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('IP: $_selectedDeviceIp',
                          style: const TextStyle(fontSize: 14)),
                    ),
                  if (_wifiStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Device Status: ',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                _wifiStatus!.isConnected
                                    ? 'Online'
                                    : 'Offline/Unavailable',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _wifiStatus!.isConnected
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          // Show network reminder message when device is offline
                          if (!_wifiStatus!.isConnected)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Please ensure App and device are on the same network.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.red[700],
                                  fontStyle: FontStyle.italic,
                                ),
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
              tooltip: 'Device Details',
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

  Future<void> _handle_command(String command) async {
    try {
      switch (command) {
        case 'reboot':
          // 设备重启 - Show confirmation dialog first
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Reboot Device'),
              content: const Text('Are you sure you want to reboot the device?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Reboot'),
                ),
              ],
            ),
          );
          
          if (confirmed == true) {
            await HttpService().sendCommand('reboot');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Reboot command sent.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
          break;
        case 'software_manager':
          // 跳转到软件管理页面
          if (_selectedDeviceIp != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SoftwareManagerScreen(
                  deviceIp: _selectedDeviceIp!,
                ),
              ),
            );
          }
          break;
        case 'firmware_manager':
          // 跳转到固件管理页面
          if (_selectedDeviceIp != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FirmwareManagerScreen(
                  deviceIp: _selectedDeviceIp!,
                ),
              ),
            );
          }
          break;
        case 'factory_reset':
          // 恢复出厂设置
          // 添加确认对话框
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Factory Reset'),
              content: const Text(
                  'Are you sure you want to reset this device to factory settings? This will erase all data and settings.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await HttpService().sendCommand('factory_reset');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Factory Reset command sent.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: const Text('Reset', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          break;
        default:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unknown command: $command')),
          );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Command failed: $e')),
      );
    }
  }

  Widget _buildCommandList() {
    final commands = [
      {
        'label': 'Software Manager',
        'command': 'software_manager',
        'icon': Icons.apps
      },
      // {
      //   'label': 'Service Manager',
      //   'command': 'service_manager',
      //   'icon': Icons.miscellaneous_services
      // },           
      {
        'label': 'Firmware Manager',
        'command': 'firmware_manager',
        'icon': Icons.system_update
      },
      {
        'label': 'Factory Reset',
        'command': 'factory_reset',
        'icon': Icons.settings_backup_restore
      }, 
      {
        'label': 'Reboot device',
        'command': 'reboot',
        'icon': Icons.restart_alt
      },      
    ];
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('Functions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Divider(),
          ...commands.map((cmd) => ListTile(
                leading: Icon(cmd['icon'] as IconData),
                title: Text(cmd['label'] as String),
                // Add trailing arrow icon for manager screens
                trailing: (cmd['command'] == 'software_manager' || 
                       cmd['command'] == 'service_manager' || 
                       cmd['command'] == 'firmware_manager') 
                  ? const Icon(Icons.arrow_forward_ios, size: 16) 
                  : null,
                onTap: () async {
                  if (_wifiStatus == null) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Device Unavailable'),
                        content: const Text(
                            'The device is offline or unavailable. Please connect to a device first.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  try {
                    _handle_command(cmd['command'] as String);
                  } catch (e) {
                    return;
                  } 

                  // // For demonstration, actually should call BleService/HttpService to send the command
                  // ScaffoldMessenger.of(context).showSnackBar(
                  //   SnackBar(content: Text('Command sent: ${cmd['label']}')),
                  // );
                },
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ThirdReality Hub Finder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Device',
            onPressed: _loadSelectedDevice,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSelectedDevice,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildDeviceCard(),
            _buildCommandList(),
          ],
        ),
      ),
    );
  }
}
