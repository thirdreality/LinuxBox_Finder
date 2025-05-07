import 'package:flutter/material.dart';
import 'reprovision_progress_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;
  final String deviceIp;
  final String? deviceName;

  const DeviceDetailScreen(
      {Key? key,
      required this.deviceId,
      required this.deviceIp,
      this.deviceName})
      : super(key: key);

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Future<Map<String, dynamic>> _deviceInfoFuture;

  @override
  void initState() {
    super.initState();
    _deviceInfoFuture = _fetchDeviceInfo();
  }

  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    // TODO: Replace with real HTTP API call to return device info map
    await Future.delayed(const Duration(seconds: 1));
    return {
      'Device Name': widget.deviceName ?? 'Unknown',
      'Device ID': widget.deviceId,
      'Device IP': widget.deviceIp,
      // Other info...
    };
  }

  void _onChangeWifi(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReprovisionProgressScreen(
        deviceId: widget.deviceId,
        deviceIp: widget.deviceIp,
        deviceName: widget.deviceName,
      ),
    ));
  }

  void _onClearCurrentHub(BuildContext context) async {
    // 1. Remove device-related SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_device_id');
    await prefs.remove('selected_device_ip');
    await prefs.remove('selected_device_name');
    await prefs.remove('selected_wifi_mac');
    // 2. Navigate to home screen
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device information')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _deviceInfoFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Failed to load: \\${snapshot.error}'));
                }
                final info = snapshot.data ?? {};
                return ListView(
                  children: info.entries
                      .map((e) => ListTile(
                            title: Text(e.key),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(left: 16.0),
                              child: Text(e.value.toString()),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(32),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () async {
                      _onChangeWifi(context);
                    },
                    child: const Text('Change Wifi Connection',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(16),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () async {
                      _onClearCurrentHub(context);
                    },
                    child: const Text('Unbind Device',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
