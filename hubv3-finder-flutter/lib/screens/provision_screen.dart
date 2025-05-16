import 'dart:convert';

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
  bool _dialogOpen = false;

  @override
  void dispose() {
    // Disconnect BLE when leaving the page
    BleService().disconnect();
    super.dispose();
  }

  void _showLoadingDialog(String title) {
    _dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16)), // Smaller font size
          content: Row(
            children: const [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Please wait...')),
            ],
          ),
        );
      },
    ).then((_) {
      _dialogOpen = false;
    });
  }

  void _closeDialogIfOpen() {
    if (_dialogOpen && mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
      _dialogOpen = false;
    }
  }

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showManualSsidInput = false;
  bool _obscurePassword = true;
  List<WiFiNetwork> _wifiNetworks = [];
  String? _selectedSSID;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLoadingDialog('Scanning WiFi list...');
      _startWiFiScan();
    });
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
        _wifiNetworks = accessPoints
            .where((ap) => ap.ssid.isNotEmpty)
            .map((ap) => WiFiNetwork(
              ssid: ap.ssid,
              signalStrength: ap.level,
              isSecured: ap.capabilities.contains('WPA') || ap.capabilities.contains('WEP'),
              bssid: ap.bssid,
            ))
            .toList();
        _wifiNetworks.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to scan for WiFi networks: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() { _isLoading = false; });
      _closeDialogIfOpen(); // Close the WiFi scan dialog
    }
  }

  Future<void> _provision() async {
    if (!_formKey.currentState!.validate()) return;
    _showLoadingDialog('Setting WiFi configuration...');
    setState(() {
      _isLoading = true;
    });
    
    int retryCount = 0;
    const maxRetries = 3;
    String? errorMessage;
    
    while (retryCount < maxRetries) {
      try {
        // Call BLE provisioning interface with restore=false
        final bleService = BleService();
        
        // If this is a retry attempt, update the dialog
        if (retryCount > 0) {
          _closeDialogIfOpen();
          _showLoadingDialog('Reconnecting to device (Attempt ${retryCount + 1}/${maxRetries})...');
          // Add a small delay before retry
          await Future.delayed(const Duration(milliseconds: 500));
        }
        
        final result = await bleService.configureWiFi(
          _selectedSSID ?? '',
          _passwordController.text,
          false
        );
        
        // Process the result - successful connection, exit retry loop
        final Map<String, dynamic> json = result is String ? Map<String, dynamic>.from(jsonDecode(result)) : {};
        if (json['connected'] == true && json['ip_address'] != null && json['ip_address'].toString().isNotEmpty) {
        // Provisioning successful, save information
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_device_ip', json['ip_address']);
        await prefs.setString('selected_device_id', widget.deviceId);
        
        // Save the selected SSID
        if (_selectedSSID != null && _selectedSSID!.isNotEmpty) {
          await prefs.setString('selected_ssid', _selectedSSID!);
        }
        
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
        
        // Call the success callback if provided
        if (widget.onProvisionSuccess != null) {
          widget.onProvisionSuccess!(json['ip_address']);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Provisioning successful, redirecting...'), 
            backgroundColor: Colors.green
          )
        );
        
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
        // Success! Break out of the retry loop
        break;
      } else {
        // WiFi configuration failed but not due to BLE connection issue
        errorMessage = 'Failed to configure WiFi. Please check the password and try again.';
        break; // Exit retry loop for non-BLE errors
      }
      } catch (e) {
        print('Error configuring WiFi networks: $e');
        errorMessage = 'Error: $e';
        
        // Check if this is a BLE connection error that we should retry
        if (e.toString().contains('FlutterBluePlusException') && 
            e.toString().contains('device is not connected')) {
          retryCount++;
          if (retryCount < maxRetries) {
            print('BLE connection lost. Retrying (${retryCount}/$maxRetries)...');
            continue; // Try again
          } else {
            errorMessage = 'Failed to connect to device after $maxRetries attempts. Please try again.';
          }
        } else {
          // Not a BLE connection error, don't retry
          break;
        }
      }
    }
    
    // After all retries, check if we had an error
    if (errorMessage != null) {
      _showErrorSnackBar(errorMessage);
    }
    
    setState(() {
      _isLoading = false;
    });
    _closeDialogIfOpen(); // Close the WiFi configuration dialog
  }
  
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  void _showBluetoothErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to previous screen
            },
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
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
                                    items: _wifiNetworks
                                        .map((network) => network.ssid)
                                        .toSet() // Ensure SSID uniqueness
                                        .map((ssid) {
                                      final network = _wifiNetworks.firstWhere((n) => n.ssid == ssid);
                                      return DropdownMenuItem<String>(
                                        value: ssid,
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
                                if (value == null || value.isEmpty) {
                                  return 'Please enter the SSID';
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
                              labelText: 'WiFi Password',
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
      appBar: AppBar(title: const Text('WiFi Configuration')),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: _buildWifiWidget(context),
      ),
    );
  }
}
