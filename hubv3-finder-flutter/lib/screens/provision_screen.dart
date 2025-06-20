import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../models/wifi_network.dart';
import '../services/ble_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProvisionScreen extends StatefulWidget {
  final String deviceId;
  final void Function(String ipAddr)? onProvisionSuccess;
  const ProvisionScreen({Key? key, required this.deviceId, this.onProvisionSuccess}) : super(key: key);

  @override
  _ProvisionScreenState createState() => _ProvisionScreenState();
}

class _ProvisionScreenState extends State<ProvisionScreen> {
  bool _dialogOpen = false;
  bool _suppressConnectionLostMessages = false; // Flag to suppress connection lost messages during provision
  String _deviceName = '';

  @override
  void dispose() {
    print('[Provision] ProvisionScreen being disposed - navigation may have occurred');
    //print('[Provision] Stack trace for dispose:');
    //print(StackTrace.current);
    // Disconnect BLE when leaving the page
    BleService().disconnect();
    super.dispose();
  }

  void _showLoadingDialog(String title) {
    print('[Dialog] Showing loading dialog: $title');
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
      if (mounted) {
        print('[Dialog] Dialog closed via .then() callback');
        _dialogOpen = false;
      }
    });
  }

  void _closeDialogIfOpen() {
    print('[Dialog] Attempting to close dialog. _dialogOpen: $_dialogOpen, mounted: $mounted');
    if (_dialogOpen && mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
        print('[Dialog] Dialog closed successfully');
      } catch (e) {
        print('[Dialog] Error closing dialog: $e');
      }
      _dialogOpen = false;
    } else {
      print('[Dialog] Dialog not open or widget not mounted. _dialogOpen: $_dialogOpen, mounted: $mounted');
    }
  }

  void _forceCloseDialog() {
    print('[Dialog] Force closing dialog - _dialogOpen: $_dialogOpen, mounted: $mounted');
    if (mounted) {
      try {
        // Always try to pop dialog regardless of _dialogOpen state
        // This handles cases where dialog state tracking might be out of sync
        Navigator.of(context, rootNavigator: true).pop();
        print('[Dialog] Dialog force closed successfully');
      } catch (e) {
        print('[Dialog] Error force closing dialog (this is normal if no dialog is open): $e');
      }
    }
    _dialogOpen = false;
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
    
    // Load device name from SharedPreferences
    _loadDeviceInfo();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLoadingDialog('Scanning WiFi list...');
      _scanForWiFiNetworks();
    });
  }

  Future<void> _loadDeviceInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceName = prefs.getString('provision_device_name') ?? 'Unknown Device';
    });
  }

  Future<bool> _requestWiFiScanPermissions() async {
    try {
      final status = await Permission.location.request();
      if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        throw Exception('Location permission permanently denied. Please enable it in App Settings.');
      } else {
        throw Exception('Location permission required for WiFi scanning');
      }
    } catch (e) {
      print('WiFi permission error: $e');
      rethrow;
    }
  }

  Future<void> _scanForWiFiNetworks() async {
    setState(() {
      _isLoading = true;
      _wifiNetworks = [];
    });
    try {
      // Request WiFi scanning permissions with detailed feedback
      bool permissionGranted = await _requestWiFiScanPermissions();
      if (!permissionGranted) {
        throw Exception('Failed to obtain WiFi scanning permissions');
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
        print('WiFi scan error: $e');
        
        // Show user-friendly error message with action button
        if (e.toString().contains('permanently denied') || e.toString().contains('enable it in App Settings')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('WiFi scanning permission required'),
              backgroundColor: Colors.orange,
              action: SnackBarAction(
                label: 'Open Settings',
                textColor: Colors.white,
                onPressed: () async {
                  await openAppSettings();
                },
              ),
              duration: Duration(seconds: 10),
            ),
          );
        } else if (e.toString().contains('Location services must be enabled')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please enable Location services in device Settings'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 8),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to scan WiFi: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
      setState(() { _isLoading = false; });
      _closeDialogIfOpen(); // Close the WiFi scan dialog
    }
  }

  Future<void> _provision() async {
    print('[Provision] Starting provision process');
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _suppressConnectionLostMessages = true; // Suppress connection messages during provision
    });
    print('[Provision] _isLoading set to true, back button should be disabled');

    const maxRetries = 3;
    int connectionRetryCount = 0;
    String? errorMessage;

    while (connectionRetryCount < maxRetries) {
      try {
        _showLoadingDialog('Connecting to device (Attempt ${connectionRetryCount + 1}/$maxRetries)...');

        // Step 1: Connect to BLE device
        final bleService = BleService();
        try {
          print('[Provision] Attempting BLE connection to device: ${widget.deviceId}');
          await bleService.connectToDevice(widget.deviceId);
          print('[Provision] BLE connection successful');
        } catch (bleError) {
          print('[Provision] BLE connection failed: $bleError');
          
          // Check if this is android-code: 133 (don't count towards retry limit)
          if (bleError.toString().contains('android-code: 133')) {
            print('[Provision] Android error code 133 detected, retrying connection...');
            _forceCloseDialog();
            _showLoadingDialog('Bluetooth error 133 detected. Retrying connection...');
            await Future.delayed(const Duration(seconds: 2));
            continue; // Don't increment connectionRetryCount
          }

          connectionRetryCount++;
          if (connectionRetryCount >= maxRetries) {
            errorMessage = 'Failed to connect to device after $maxRetries attempts: $bleError';
            break;
          }

          _forceCloseDialog();
          _showLoadingDialog('Connection failed. Retrying (${connectionRetryCount + 1}/$maxRetries)...');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        // Step 2: Configure WiFi (no retry for configuration errors)
        try {
          _forceCloseDialog();
          _showLoadingDialog('Configuring WiFi...');

          final result = await bleService.configureWiFi(
            _selectedSSID ?? '',
            _passwordController.text,
            false,
          );

          print('[Provision] WiFi configuration result: $result');

          final Map<String, dynamic> json = result is String ? Map<String, dynamic>.from(jsonDecode(result)) : {};

          // Handle error response
          if (json.containsKey('error')) {
            errorMessage = json['error'];
            print('[Provision] Configuration returned error: $errorMessage');
            // Only disconnect if BLE is actually connected
            if (bleService.isConnected) {
              bleService.disconnect();
            }
            break; // Exit retry loop for configuration errors
          }

          // Handle success/failure response
          if (json.containsKey('connected')) {
            if (json['connected'] == true && json['ip_address'] != null && json['ip_address'].toString().isNotEmpty) {
              // Success case
              print('[Provision] WiFi configuration successful');
              await bleService.disconnect();
              
              // Save device information
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('selected_device_ip', json['ip_address']);
              await prefs.setString('selected_device_id', widget.deviceId);
              if (_selectedSSID != null && _selectedSSID!.isNotEmpty) {
                await prefs.setString('selected_ssid', _selectedSSID!);
              }
              if (_deviceName.isNotEmpty) {
                await prefs.setString('selected_device_name', _deviceName);
              }
              
              // Call success callback
              if (widget.onProvisionSuccess != null) {
                widget.onProvisionSuccess!(json['ip_address']);
              }
              
              _forceCloseDialog();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('WiFi configuration successful! Returning to home page.'),
                  backgroundColor: Colors.green,
                ),
              );
              
              // Clean up state before navigation to prevent any delayed callbacks
              setState(() {
                _isLoading = false;
                _suppressConnectionLostMessages = false;
              });
              
              // Navigate immediately without delay to prevent issues with disposed widget
              if (mounted) {
                print('[Provision] Navigating to home page after successful configuration');
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
              return;
            } else {
              // Failure case - connected: false
              print('[Provision] Configuration failed - connected: false, staying on current page');
              // Only disconnect if BLE is actually connected
              if (bleService.isConnected) {
                bleService.disconnect();
              }
              errorMessage = 'WiFi configuration failed, please check your password and try again.';
              break; // Exit retry loop for configuration failures
            }
          }

          // Invalid response format
          // Only disconnect if BLE is actually connected
          if (bleService.isConnected) {
            bleService.disconnect();
          }
          errorMessage = 'Invalid response from device';
          break;

        } catch (configError) {
          print('[Provision] WiFi configuration error: $configError');
          // Only disconnect if BLE is actually connected
          if (bleService.isConnected) {
            bleService.disconnect();
          }
          
          // Check if this is a connection-related error that should trigger retry
          if (configError.toString().contains('connection') || 
              configError.toString().contains('disconnect') ||
              configError.toString().contains('timeout')) {
            connectionRetryCount++;
            if (connectionRetryCount >= maxRetries) {
              errorMessage = 'WiFi configuration failed after $maxRetries attempts: $configError';
              break;
            } else {
              _forceCloseDialog();
              _showLoadingDialog('Configuration error. Reconnecting for retry (${connectionRetryCount + 1}/$maxRetries)...');
              await Future.delayed(const Duration(seconds: 1));
            }
            continue; // Retry connection
          } else {
            // Non-connection error, don't retry
            errorMessage = 'WiFi configuration error: $configError';
            break;
          }
        }

      } catch (e) {
        print('[Provision] General error: $e');
        connectionRetryCount++;
        if (connectionRetryCount >= maxRetries) {
          errorMessage = 'Provision failed after $maxRetries attempts: $e';
        } else {
          _forceCloseDialog();
          _showLoadingDialog('Error occurred. Retrying (${connectionRetryCount + 1}/$maxRetries)...');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }

    // Show error if we failed after all retries
    if (errorMessage != null) {
      print('[Provision] Showing error message and staying on current page: $errorMessage');
      _forceCloseDialog();
      _showErrorSnackBar(errorMessage);
    }

    setState(() {
      _isLoading = false;
      _suppressConnectionLostMessages = false; // Re-enable connection messages after provision
    });
    print('[Provision] _isLoading set to false, back button should be re-enabled');
    print('[Provision] Provision process completed, staying on current page');
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

  Widget _buildWifiWidget(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Device information card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selected Device',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Divider(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _deviceName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                              onPressed: _scanForWiFiNetworks,
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
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                              ),
                              children: [
                                const TextSpan(text: 'Input the '),
                                                                  const TextSpan(
                                    text: 'correct password',
                                    style: TextStyle(
                                      color: Colors.blue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                          ),
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
                                onPressed: _isLoading ? null : _provision,
                                icon: Icon(_isLoading ? Icons.hourglass_empty : Icons.wifi),
                                label: Text(_isLoading ? 'Connecting...' : 'Connect'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isLoading ? Colors.grey : Colors.blue,
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
      appBar: AppBar(
        title: const Text('WiFi Configuration'),
        automaticallyImplyLeading: !_isLoading, // Disable back button during loading
        leading: _isLoading ? null : null, // Explicitly set leading to null during loading
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: _buildWifiWidget(context),
      ),
    );
  }
}
