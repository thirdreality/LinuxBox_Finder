import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/http_service.dart';
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
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _deviceInfoFuture = _fetchDeviceInfo();
  }
  
  // Method to refresh device information
  void _refreshDeviceInfo() {
    setState(() {
      _isRefreshing = true;
      _deviceInfoFuture = _fetchDeviceInfo().then((value) {
        setState(() {
          _isRefreshing = false;
        });
        return value;
      });
    });
  }

  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    try {
      HttpService().configure(widget.deviceIp);
      final resp = await HttpService().getSystemInfo();
      final Map<String, dynamic> data = resp.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(resp)) : {};
      return {
        ...data,
      };
    } catch (e) {
      return {
        'Device Name': widget.deviceName ?? 'Unknown',
        'Device ID': widget.deviceId,
        'Device IP': widget.deviceIp,
        'Error': 'Failed to fetch device info: $e',
      };
    }
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
      appBar: AppBar(
        title: const Text('Device information'),
        actions: [
          IconButton(
            icon: _isRefreshing 
              ? const SizedBox(
                  width: 20, 
                  height: 20, 
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.refresh),
            tooltip: 'Refresh device information',
            onPressed: _isRefreshing ? null : _refreshDeviceInfo,
          ),
        ],
      ),
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
                return ListView.separated(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: info.entries.length,
                  separatorBuilder: (context, index) => const Divider(height: 24),
                  itemBuilder: (context, index) {
                    final entry = info.entries.elementAt(index);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: Text(
                            entry.value.toString(),
                            style: const TextStyle(
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
