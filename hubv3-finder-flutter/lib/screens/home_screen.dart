import 'package:flutter/material.dart';
import '../services/http_service.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/WiFiConnectionStatus.dart';
import 'device_scan_screen.dart';
import 'device_detail_screen.dart';
import 'software_manager_screen.dart';
import 'firmware_manager_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/browser_url.dart';
import 'provision_prepare_screen.dart';

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

  List<BrowserUrl> _browserUrls = [];
  bool _loadingBrowserUrls = false;
  String? _browserUrlsError;

  @override
  void initState() {
    super.initState();
    _loadSelectedDevice();
  }

  Future<void> _loadSelectedDevice() async {
    if (mounted) {
      setState(() {
        _loadingDevice = true;
        _wifiStatus = null; // Reset wifi status
        _browserUrls = []; // Reset browser URLs
        _loadingBrowserUrls = false;
        _browserUrlsError = null;
      });
    }
    final prefs = await SharedPreferences.getInstance();
    _selectedDeviceId = prefs.getString('selected_device_id');
    _selectedDeviceIp = prefs.getString('selected_device_ip');
    _selectedDeviceName = prefs.getString('selected_device_name');
    if (_selectedDeviceIp != null) {
      HttpService().configure(_selectedDeviceIp!);
      try {
        final wifiStatusJson = await HttpService().getWifiStatus(ltime: 3);
        _wifiStatus = WiFiConnectionStatus.fromJson(wifiStatusJson);
        if (_wifiStatus != null && _wifiStatus!.isConnected) {
          try {
            await _fetchBrowserUrls();
          } catch (e) {
            // Initial fetch failed, start background retries
            _retryFetchBrowserUrls();
          }
        } else {
          if (mounted) {
            setState(() {
              _browserUrls = []; // Clear if not connected
            });
          }
        }
      } catch (e) {
        _wifiStatus = WiFiConnectionStatus.error('Offline');
      }
    } else {
      _wifiStatus = null;
      if (mounted) {
        setState(() {
          _browserUrls = []; // Clear if no IP
        });
      }
    }
    if (mounted) {
      setState(() {
        _loadingDevice = false;
      });
    }
  }

  Future<void> _fetchBrowserUrls() async {
    if (!mounted) return;
    setState(() {
      _loadingBrowserUrls = true;
      _browserUrlsError = null;
    });

    try {
      final urls = await HttpService().getBrowserInfo();
      if (!mounted) return;
      setState(() {
        _browserUrls = urls;
        _loadingBrowserUrls = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBrowserUrls = false;
      });
      throw e; // Re-throw to be caught by the caller
    }
  }

  void _retryFetchBrowserUrls() async {
    for (int i = 0; i < 3; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      try {
        final urls = await HttpService().getBrowserInfo();
        if (!mounted) return;
        setState(() {
          _browserUrls = urls;
          _loadingBrowserUrls = false;
          _browserUrlsError = null; // Clear error on success
        });
        return; // Success, exit retry loop
      } catch (e) {
        // Log retry error, continue to next attempt
        if (i == 2) {
          // Last retry failed
          if (!mounted) return;
          setState(() {
            _browserUrlsError = 'Failed to load browser URLs after retries.';
            _loadingBrowserUrls = false;
          });
        }
      }
    }
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

  void _goToProvisionPrepare() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProvisionPrepareScreen()),
    );
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
        onTap: _goToProvisionPrepare,
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
                              _wifiStatus!.isConnected
                                  ? const Icon(Icons.check_circle,
                                      color: Colors.green, size: 16)
                                  : const Icon(Icons.error,
                                      color: Colors.red, size: 16),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _wifiStatus!.isConnected
                                      ? 'Available'
                                      : 'Unavailable',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _wifiStatus!.isConnected
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (_wifiStatus!.ssid != null &&
                              _wifiStatus!.ssid!.isNotEmpty)
                            Text('SSID: ${_wifiStatus!.ssid!}',
                                style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onPressed: _goToDetail,
            ),
          ],
        ),
      ),
    );
  }

  void _goToDetail() {
    if (_selectedDeviceId != null && _selectedDeviceIp != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DeviceDetailScreen(
            deviceId: _selectedDeviceId!,
            deviceIp: _selectedDeviceIp!,
          ),
        ),
      );
    }
  }

  Future<void> _handle_command(String command) async {
    try {
      switch (command) {
        case 'software_manager':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SoftwareManagerScreen(
                deviceIp: _selectedDeviceIp!,
              ),
            ),
          );
          break;
        // case 'firmware_manager':
        //   Navigator.push(
        //     context,
        //     MaterialPageRoute(
        //       builder: (context) => FirmwareManagerScreen(
        //         deviceIp: _selectedDeviceIp!,
        //       ),
        //     ),
        //   );
        //   break;
        case 'reboot':
          await HttpService().rebootDevice();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reboot command sent')),
          );
          break;
        case 'factory_reset':
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confirm Factory Reset'),
              content: const Text(
                  'Are you sure you want to perform a factory reset? This action cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop(); // Close the dialog
                    try {
                      await HttpService().factoryReset();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Factory reset command sent')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to send command: $e')),
                      );
                    }
                  },
                  child:
                      const Text('Reset', style: TextStyle(color: Colors.red)),
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
      // {
      //   'label': 'Firmware Manager',
      //   'command': 'firmware_manager',
      //   'icon': Icons.system_update
      // },
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

  Widget _buildBrowserUrlCards() {
    if (_loadingBrowserUrls) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_browserUrlsError != null) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
            'The server might not be ready yet, please click the refresh button.',
            style: const TextStyle(color: Colors.red)),
      );
    }

    if (_browserUrls.isEmpty) {
      return const SizedBox.shrink(); // No URLs to show, or not applicable
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Device Web Interfaces:',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _browserUrls.length,
          itemBuilder: (context, index) {
            final browserUrl = _browserUrls[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading:
                    const Icon(Icons.travel_explore, color: Colors.blueAccent),
                title: Text(browserUrl.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(browserUrl.url,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600])),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () async {
                  final uri = Uri.parse(browserUrl.url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('Could not launch ${browserUrl.url}')),
                      );
                    }
                  }
                },
              ),
            );
          },
        ),
      ],
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
            if (_wifiStatus != null && _wifiStatus!.isConnected)
              _buildBrowserUrlCards(),
            _buildCommandList(),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 32, // 明确指定高度
          alignment: Alignment.center,
          child: Text(
            'version 1.1.2+1',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
