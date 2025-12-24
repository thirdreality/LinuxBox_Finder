import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/ble_service.dart';
import 'provision_screen.dart';
import 'post_config_screen.dart';

class ConfigPrepareScreen extends StatefulWidget {
  final String deviceId;
  
  const ConfigPrepareScreen({Key? key, required this.deviceId}) : super(key: key);

  @override
  State<ConfigPrepareScreen> createState() => _ConfigPrepareScreenState();
}

class _ConfigPrepareScreenState extends State<ConfigPrepareScreen> {
  final BleService _bleService = BleService();
  bool _isProcessing = false;
  String _statusMessage = 'Initializing...';
  double? _progress;
  
  // Default host URL
  static const String _defaultHostUrl = 'https://hm.3reality.co/api/hub/v1';
  
  @override
  void initState() {
    super.initState();
    _startConfigProcess();
  }

  Future<void> _startConfigProcess() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Connecting to device...';
      _progress = 0.1;
    });

    try {
      // Step 1: Connect to device
      print('[ConfigPrepare] Connecting to device: ${widget.deviceId}');
      await _bleService.connectToDevice(widget.deviceId);
      print('[ConfigPrepare] Connected successfully');
      
      setState(() {
        _statusMessage = 'Querying system information...';
        _progress = 0.3;
      });

      // Step 2: Query system info
      print('[ConfigPrepare] Querying system info');
      final systemInfoResult = await _bleService.querySystemInfo('services');
      print('[ConfigPrepare] System info result: $systemInfoResult');
      
      // Parse the result
      Map<String, dynamic> systemInfo;
      try {
        systemInfo = jsonDecode(systemInfoResult);
      } catch (e) {
        throw Exception('Failed to parse system information: $e');
      }

      // Step 3: Check Version
      if (!systemInfo.containsKey('Version')) {
        throw Exception('Version field not found in system information');
      }

      String version = systemInfo['Version'];
      print('[ConfigPrepare] Device version: $version');

      // Compare version (expecting format: 1.14.01.16 or similar)
      if (!_isVersionValid(version)) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Version check failed';
        });
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Version Not Supported'),
            content: Text(
              'The device version ($version) is not supported.\n\n'
              'Minimum required version: 1.14.01.16\n\n'
              'Please update your device firmware first.'
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to previous screen
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      print('[ConfigPrepare] Version check passed');
      
      setState(() {
        _statusMessage = 'Version check passed. Configuring bridge...';
        _progress = 0.5;
      });

      // Automatically configure bridge with default host URL
      await _configureBridge();

    } catch (e) {
      print('[ConfigPrepare] Error: $e');
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: $e';
      });
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Configuration Error'),
          content: Text('Failed to initialize configuration:\n\n$e'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Go back to previous screen
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  bool _isVersionValid(String version) {
    // Parse version string (format: v1.14.01.20 or 1.14.01.16)
    try {
      // Remove 'v' prefix if present
      String cleanVersion = version.toLowerCase().startsWith('v') 
        ? version.substring(1) 
        : version;
      
      List<String> parts = cleanVersion.split('.');
      if (parts.length < 3) {
        print('[ConfigPrepare] Invalid version format: $version');
        return false;
      }

      int major = int.parse(parts[0]);
      int minor = int.parse(parts[1]);
      int patch = int.parse(parts[2]);
      
      // Compare with minimum version 1.14.01
      if (major > 1) return true;
      if (major < 1) return false;
      
      if (minor > 14) return true;
      if (minor < 14) return false;
      
      if (patch >= 1) return true;
      
      return false;
    } catch (e) {
      print('[ConfigPrepare] Error parsing version: $e');
      return false;
    }
  }

  Future<void> _configureBridge() async {
    setState(() {
      _statusMessage = 'Configuring bridge with default URL...';
      _progress = 0.7;
    });

    try {
      print('[ConfigPrepare] Configuring bridge with URL: $_defaultHostUrl');
      final result = await _bleService.configureBridge(
        hostUrl: _defaultHostUrl,
      );
      print('[ConfigPrepare] Bridge config result: $result');

      // Parse result
      Map<String, dynamic> configResult;
      try {
        configResult = jsonDecode(result);
      } catch (e) {
        throw Exception('Failed to parse bridge configuration result: $e');
      }

      // Check if configuration was successful
      if (configResult.containsKey('status') && configResult['status'] == 'error') {
        throw Exception(configResult['message'] ?? 'Unknown error');
      }

      print('[ConfigPrepare] Bridge configured successfully');
      
      setState(() {
        _statusMessage = 'Bridge configured successfully. Proceeding to WiFi setup...';
        _progress = 0.9;
      });

      // Wait a moment before navigating
      await Future.delayed(const Duration(seconds: 1));

      // Navigate to WiFi provision screen (complex flow)
      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProvisionScreen(
              deviceId: widget.deviceId,
              isComplexFlow: true, // 标记为复杂流程，WiFi配置后不断开BLE连接
            ),
          ),
        );
        
        // Check if WiFi configuration was successful
        if (mounted && result != null && result['success'] == true) {
          print('[ConfigPrepare] WiFi configuration successful, navigating to post config screen');
          // Navigate to post config screen
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PostConfigScreen(deviceId: widget.deviceId),
            ),
          );
        } else {
          // WiFi configuration failed, go back to home
          print('[ConfigPrepare] WiFi configuration failed, returning to home');
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          }
        }
      }

    } catch (e) {
      print('[ConfigPrepare] Bridge configuration error: $e');
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Bridge configuration failed';
      });
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Configuration Error'),
          content: Text('Failed to configure bridge:\n\n$e'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prepare Device Configuration'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_progress != null)
              Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 16),
                ],
              ),
            Card(
              elevation: 4.0,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(
                      _isProcessing 
                        ? Icons.settings 
                        : (_progress != null && _progress! >= 0.5)
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 48,
                      color: _isProcessing 
                        ? Colors.blue 
                        : (_progress != null && _progress! >= 0.5)
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isProcessing)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

