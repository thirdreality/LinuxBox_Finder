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
  bool _isLoading = true;
  String? _errorMessage;
  
  // Initial device information
  late Map<String, dynamic> _initialInfo;

  @override
  void initState() {
    super.initState();
    // Set up initial information immediately
    _initialInfo = {
      'Device Name': widget.deviceName ?? 'Unknown',
      'Device ID': widget.deviceId,
      'Device IP': widget.deviceIp,
    };
    
    // Get SSID from SharedPreferences
    _loadSavedSsid();
    
    // Start fetching additional information
    _deviceInfoFuture = _fetchDeviceInfo();
  }
  
  Future<void> _loadSavedSsid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ssid = prefs.getString('selected_ssid');
      if (ssid != null && ssid.isNotEmpty) {
        setState(() {
          _initialInfo['WiFi SSID'] = ssid;
        });
      }
    } catch (e) {
      // Ignore errors when loading SSID
    }
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      HttpService().configure(widget.deviceIp);
      final resp = await HttpService().getSystemInfo(timeout: 10);
      final Map<String, dynamic> data = resp.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(resp)) : {};
      
      setState(() {
        _isLoading = false;
      });
      
      return {
        ...data,
      };
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to fetch device info: $e';
      });
      
      return {
        ..._initialInfo,
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
                // Show loading state with initial information
                if (_isLoading) {
                  return ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      // Display initial information
                      ..._initialInfo.entries.map((entry) => Column(
                        children: [
                          Row(
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
                          ),
                          const Divider(height: 24),
                        ],
                      )).toList(),
                      
                      // Loading indicator
                      const Center(
                        child: Column(
                          children: [
                            SizedBox(height: 16),
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Loading additional information...'),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                
                // Show error message with initial information
                if (_errorMessage != null) {
                  return ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      // Display initial information
                      ..._initialInfo.entries.map((entry) => Column(
                        children: [
                          Row(
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
                          ),
                          const Divider(height: 24),
                        ],
                      )).toList(),
                      
                      // Error message
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(top: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Error',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(_errorMessage!),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                
                // Show successful network request data (no initial information)
                if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError) {
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
                }
                
                // Show a loading indicator if we're still waiting for data
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,  // Changed to red
                      side: const BorderSide(color: Colors.red),  // Red border
                      minimumSize: const Size.fromHeight(16),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () async {
                      _onClearCurrentHub(context);
                    },
                    child: const Text('Unbind Device',
                        style: TextStyle(fontSize: 16, color: Colors.red)),  // Red text
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
