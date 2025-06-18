import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
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
  StreamSubscription<bool>? _connectionSubscription;
  bool _isConnected = false; // Initially not connected
  String _deviceName = '';

  @override
  void dispose() {
    // Cancel connection subscription
    _connectionSubscription?.cancel();
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
    
    // Load device name from SharedPreferences
    _loadDeviceInfo();
    
    // Listen to global connection state changes
    _connectionSubscription = BleService.globalConnectionStateStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
      });
      
      if (!isConnected) {
        // Show connection lost message only if we were previously connected
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Device connection lost.')),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        // Show reconnection success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Device connected successfully'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLoadingDialog('Scanning WiFi list...');
      _startWiFiScan();
    });
  }

  Future<void> _loadDeviceInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _deviceName = prefs.getString('provision_device_name') ?? 'Unknown Device';
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
    
    setState(() {
      _isLoading = true;
    });
    
    const maxRetries = 3;
    int bleConnectionRetryCount = 0;
    int configRetryCount = 0;
    int android133Count = 0; // Track android-code: 133 errors separately
    String? errorMessage;
    
    while (bleConnectionRetryCount < maxRetries) {
      try {
        _showLoadingDialog('Connecting to device (Attempt ${bleConnectionRetryCount + 1}/$maxRetries)...');
        
        // Step 1: Connect to BLE device
        final bleService = BleService();
        
        try {
          print('[Provision] Attempting BLE connection to device: ${widget.deviceId}');
          await bleService.connectToDevice(widget.deviceId, enableHttp: false);
          print('[Provision] BLE connection successful');
        } catch (bleError) {
          print('[Provision] BLE connection failed: $bleError');
          
          // Check if this is android-code: 133 (don't count towards retry limit)
          if (bleError.toString().contains('android-code: 133')) {
            android133Count++;
            print('[Provision] Android error code 133 detected (count: $android133Count)');
            _closeDialogIfOpen();
            _showLoadingDialog('Bluetooth error 133 detected. Retrying connection...');
            await Future.delayed(const Duration(seconds: 2));
            continue; // Don't increment bleConnectionRetryCount
          }
          
          bleConnectionRetryCount++;
          if (bleConnectionRetryCount >= maxRetries) {
            errorMessage = 'Failed to connect to device after $maxRetries attempts: $bleError';
            break;
          }
          
          _closeDialogIfOpen();
          _showLoadingDialog('Connection failed. Retrying (${bleConnectionRetryCount + 1}/$maxRetries)...');
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }
        
        // Step 2: Configure WiFi with retry for password errors
        configRetryCount = 0;
        while (configRetryCount < maxRetries) {
          try {
            _closeDialogIfOpen();
            _showLoadingDialog('Configuring WiFi (Attempt ${configRetryCount + 1}/$maxRetries)...');
            
            final result = await bleService.configureWiFi(
          _selectedSSID ?? '',
          _passwordController.text,
          false
        );
        
            print('[Provision] WiFi configuration result: $result');
            
            // Process the result
        final Map<String, dynamic> json = result is String ? Map<String, dynamic>.from(jsonDecode(result)) : {};
        
            // Check for explicit errors first
        if (json.containsKey('error')) {
          errorMessage = json['error'];
              print('[Provision] Configuration returned error: $errorMessage');
              
              // Check if this might be a password error
              if (errorMessage!.toLowerCase().contains('password') || 
                  errorMessage!.toLowerCase().contains('auth') ||
                  errorMessage!.toLowerCase().contains('credential')) {
                print('[Provision] Possible password error detected');
                configRetryCount++;
                if (configRetryCount >= maxRetries) {
                  // Close BLE connection before showing error
                  await bleService.disconnect();
                  errorMessage = 'WiFi configuration failed after $maxRetries attempts. Please check your password and try again.';
                  break;
                }
                
                // Close BLE connection and reconnect for retry
                await bleService.disconnect();
                await Future.delayed(const Duration(seconds: 1));
                
                _closeDialogIfOpen();
                _showLoadingDialog('Password error. Reconnecting for retry (${configRetryCount + 1}/$maxRetries)...');
                
                // Reconnect BLE
                try {
                  await bleService.connectToDevice(widget.deviceId, enableHttp: false);
                  continue; // Retry WiFi configuration
                } catch (reconnectError) {
                  print('[Provision] Failed to reconnect after password error: $reconnectError');
                  errorMessage = 'Failed to reconnect to device after password error: $reconnectError';
                  break;
                }
              } else {
                // Other error, break out of config retry loop
                break;
              }
            } else if (json['connected'] == true && json['ip_address'] != null && json['ip_address'].toString().isNotEmpty) {
              // Success!
              print('[Provision] WiFi configuration successful');
              
              // Close BLE connection
              await bleService.disconnect();
              
              // Save device information
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_device_ip', json['ip_address']);
        await prefs.setString('selected_device_id', widget.deviceId);
        
        // Save the selected SSID
        if (_selectedSSID != null && _selectedSSID!.isNotEmpty) {
          await prefs.setString('selected_ssid', _selectedSSID!);
        }
        
              // Save device name
              if (_deviceName.isNotEmpty) {
                await prefs.setString('selected_device_name', _deviceName);
              }
        
        // Call the success callback if provided
        if (widget.onProvisionSuccess != null) {
          widget.onProvisionSuccess!(json['ip_address']);
        }
        
              _closeDialogIfOpen();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
                  content: Text('WiFi configuration successful! Returning to home page.'), 
            backgroundColor: Colors.green
          )
        );
        
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
              return; // Success, exit function
            } else {
              // WiFi configuration failed but not due to explicit error
              configRetryCount++;
              if (configRetryCount >= maxRetries) {
                await bleService.disconnect();
                errorMessage = 'WiFi configuration failed. Please check your network settings and try again.';
                break;
              }
              
              // Close BLE connection and reconnect for retry
              await bleService.disconnect();
              await Future.delayed(const Duration(seconds: 1));
              
              _closeDialogIfOpen();
              _showLoadingDialog('Configuration failed. Reconnecting for retry (${configRetryCount + 1}/$maxRetries)...');
              
              // Reconnect BLE
              try {
                await bleService.connectToDevice(widget.deviceId, enableHttp: false);
                continue; // Retry WiFi configuration
              } catch (reconnectError) {
                print('[Provision] Failed to reconnect for config retry: $reconnectError');
                errorMessage = 'Failed to reconnect to device for retry: $reconnectError';
                break;
              }
            }
          } catch (configError) {
            print('[Provision] WiFi configuration error: $configError');
            configRetryCount++;
            
            if (configRetryCount >= maxRetries) {
              await bleService.disconnect();
              errorMessage = 'WiFi configuration failed after $maxRetries attempts: $configError';
              break;
            }
            
            // Close BLE connection and reconnect for retry
            await bleService.disconnect();
            await Future.delayed(const Duration(seconds: 1));
            
            _closeDialogIfOpen();
            _showLoadingDialog('Configuration error. Reconnecting for retry (${configRetryCount + 1}/$maxRetries)...');
            
            // Reconnect BLE
            try {
              await bleService.connectToDevice(widget.deviceId, enableHttp: false);
              continue; // Retry WiFi configuration
            } catch (reconnectError) {
              print('[Provision] Failed to reconnect after config error: $reconnectError');
              errorMessage = 'Failed to reconnect to device after configuration error: $reconnectError';
              break;
            }
          }
        }
        
        // If we reach here, either success or config error
        break;
        
      } catch (e) {
        print('[Provision] General error: $e');
        bleConnectionRetryCount++;
        
        if (bleConnectionRetryCount >= maxRetries) {
          errorMessage = 'Provision failed after $maxRetries attempts: $e';
        } else {
          _closeDialogIfOpen();
          _showLoadingDialog('Error occurred. Retrying (${bleConnectionRetryCount + 1}/$maxRetries)...');
          await Future.delayed(const Duration(seconds: 1));
        }
      }
    }
    
    // Show error if we failed after all retries
    if (errorMessage != null) {
      _closeDialogIfOpen();
      _showErrorSnackBar(errorMessage);
    }
    
    setState(() {
      _isLoading = false;
    });
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
                            Icon(
                              Icons.bluetooth,
                              color: _isConnected ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _deviceName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                            ),
                            Text(
                              _isConnected ? 'Connected' : 'Not Connected',
                              style: TextStyle(
                                color: _isConnected ? Colors.green : Colors.grey,
                                fontSize: 12,
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
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        child: _buildWifiWidget(context),
      ),
    );
  }
}
