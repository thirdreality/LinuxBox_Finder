import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../models/wifi_network.dart';
import '../services/ble_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart'; // for firstWhereOrNull

class ProvisionScreen extends StatefulWidget {
  final String deviceId;
  final void Function(String ipAddr)? onProvisionSuccess;
  const ProvisionScreen({Key? key, required this.deviceId, this.onProvisionSuccess}) : super(key: key);

  @override
  _ProvisionScreenState createState() => _ProvisionScreenState();
}

class _ProvisionScreenState extends State<ProvisionScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showManualSsidInput = false;
  bool _obscurePassword = true;
  String? _errorMsg;
  List<WiFiNetwork> _wifiNetworks = [];
  String? _selectedSSID;

  @override
  void initState() {
    super.initState();
    _startWiFiScan();
  }

  Future<void> _startWiFiScan() async {
    setState(() {
      _isLoading = true;
      _wifiNetworks = [];
    });
    try {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        throw Exception('Location permission denied');
      }
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan != CanStartScan.yes) {
        throw Exception('Cannot start WiFi scan: $canScan');
      }
      final result = await WiFiScan.instance.startScan();
      if (result != true) {
        throw Exception('Failed to start WiFi scan: $result');
      }
      await Future.delayed(const Duration(seconds: 3));
      final accessPoints = await WiFiScan.instance.getScannedResults();
      setState(() {
        _wifiNetworks = accessPoints.map((ap) => WiFiNetwork(
          ssid: ap.ssid,
          signalStrength: ap.level,
          isSecured: ap.capabilities.contains('WPA') || ap.capabilities.contains('WEP'),
          bssid: ap.bssid,
        )).toList();
        _wifiNetworks.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to scan for WiFi networks: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _provision() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      // Call BLE provisioning interface with restore=false
      final bleService = BleService();
      final result = await bleService.configureWiFi(
        _selectedSSID ?? '',
        _passwordController.text,
        false
      );
      final Map<String, dynamic> json = result is String ? Map<String, dynamic>.from(jsonDecode(result)) : {};
      if (json['connected'] == true && json['ip_address'] != null && json['ip_address'].toString().isNotEmpty) {
        // Provisioning successful, save information
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_device_ip', json['ip_address']);
        await prefs.setString('selected_device_id', widget.deviceId);
        // Get current device name (optional, retrieve from BLEService or pass it)
        String? deviceName;
        try {
          // Use singleton instance to access discovered devices
          final devices = BleService().discoveredDevices;
          final match = devices.firstWhereOrNull((d) => d.id == widget.deviceId);
          if (match != null && match.name != null) {
            deviceName = match.name;
            await prefs.setString('selected_device_name', deviceName!);
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配网成功，正在跳转...'), backgroundColor: Colors.green));
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      } else {
        setState(() {
          _errorMsg = '配网失败，请重试';
        });
      }
    } catch (e) {
      print('Error Config Wifi networks: $e');
      setState(() {
        _errorMsg = '配网异常: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  Widget _buildWifiWidget(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Available WiFi Networks',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: _startWiFiScan,
                              tooltip: 'Scan for WiFi networks',
                            ),
                          ],
                        ),
                        const Divider(),
                        _wifiNetworks.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: Text('No WiFi networks found. Tap the refresh button to scan again.'),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Select a network:'),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _selectedSSID,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'WiFi SSID'),
                                    items: _wifiNetworks.map((network) {
                                      return DropdownMenuItem<String>(
                                        value: network.ssid,
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.wifi,
                                              color: network.signalStrength > -60 ? Colors.green : (network.signalStrength > -80 ? Colors.orange : Colors.red),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(child: Text(network.ssid, overflow: TextOverflow.ellipsis)),
                                            const SizedBox(width: 8),
                                            Text('${network.signalStrength} dBm', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                            const SizedBox(width: 8),
                                            Icon(
                                              network.isSecured ? Icons.lock : Icons.lock_open,
                                              size: 16,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedSSID = value;
                                      });
                                    },
                                    validator: (v) => v == null || v.isEmpty ? 'Please select a WiFi network' : null,
                                  ),
                                ],
                              ),
                        TextButton.icon(
                          icon: Icon(_showManualSsidInput ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                          label: Text(_showManualSsidInput ? 'Hide manual input' : 'Enter SSID manually'),
                          onPressed: () {
                            setState(() {
                              _showManualSsidInput = !_showManualSsidInput;
                            });
                          },
                        ),
                        if (_showManualSsidInput)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: TextFormField(
                              decoration: const InputDecoration(
                                labelText: 'SSID',
                                prefixIcon: Icon(Icons.wifi),
                              ),
                              onChanged: (v) {
                                setState(() {
                                  _selectedSSID = v;
                                });
                              },
                              validator: (value) {
                                if (_showManualSsidInput && (value == null || value.isEmpty)) {
                                  return 'Please enter an SSID';
                                }
                                return null;
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WiFi Configuration',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Divider(),
                          const Text('Input the correct password:'),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscurePassword,
                            validator: (v) => v == null || v.isEmpty ? 'Please enter password' : null,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _provision,
                                icon: const Icon(Icons.wifi),
                                label: const Text('Connect'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (_errorMsg != null) ...[
                            const SizedBox(height: 16),
                            Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi 配网'), backgroundColor: Theme.of(context).colorScheme.primary),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: _buildWifiWidget(context)
      ),
    );
  }

}

