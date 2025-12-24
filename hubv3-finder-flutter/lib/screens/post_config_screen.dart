import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/ble_service.dart';

class PostConfigScreen extends StatefulWidget {
  final String deviceId;
  
  const PostConfigScreen({Key? key, required this.deviceId}) : super(key: key);

  @override
  State<PostConfigScreen> createState() => _PostConfigScreenState();
}

class _PostConfigScreenState extends State<PostConfigScreen> {
  final BleService _bleService = BleService();
  bool _isProcessing = false;
  String _statusMessage = 'Ready to start bridge initialization';
  bool _isCompleted = false;
  String? _resultMessage;

  @override
  void dispose() {
    // 退出时断开BLE连接
    print('[PostConfig] PostConfigScreen being disposed - disconnecting BLE');
    _bleService.disconnect();
    super.dispose();
  }

  Future<void> _startBridgeInit() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Initializing bridge service...';
      _isCompleted = false;
      _resultMessage = null;
    });

    try {
      print('[PostConfig] Starting bridge initialization with name: bridge');
      final result = await _bleService.initBridge(name: 'bridge');
      print('[PostConfig] Bridge init result: $result');

      // Parse result
      Map<String, dynamic> initResult;
      try {
        initResult = jsonDecode(result);
      } catch (e) {
        throw Exception('Failed to parse bridge initialization result: $e');
      }

      // Check if initialization was successful
      if (initResult.containsKey('status') && initResult['status'] == 'error') {
        throw Exception(initResult['message'] ?? 'Unknown error');
      }

      print('[PostConfig] Bridge initialized successfully');
      
      setState(() {
        _isProcessing = false;
        _isCompleted = true;
        _statusMessage = 'Bridge initialization completed';
        _resultMessage = 'Bridge service has been initialized successfully!';
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bridge initialization successful!'),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print('[PostConfig] Bridge initialization error: $e');
      setState(() {
        _isProcessing = false;
        _isCompleted = true;
        _statusMessage = 'Bridge initialization failed';
        _resultMessage = 'Error: $e';
      });

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bridge initialization failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Configuration'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4.0,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Icon(
                      _isCompleted
                          ? (_resultMessage?.contains('Error') ?? false
                              ? Icons.error_outline
                              : Icons.check_circle_outline)
                          : Icons.settings,
                      size: 64,
                      color: _isCompleted
                          ? (_resultMessage?.contains('Error') ?? false
                              ? Colors.red
                              : Colors.green)
                          : Colors.blue,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    if (_resultMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _resultMessage!,
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (_isProcessing) ...[
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startBridgeInit,
              icon: Icon(_isProcessing ? Icons.hourglass_empty : Icons.play_arrow),
              label: Text(_isProcessing ? 'Processing...' : 'Start'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: _isProcessing ? Colors.grey : Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (_isCompleted)
              OutlinedButton.icon(
                onPressed: () {
                  // 返回Home页面
                  Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                },
                icon: const Icon(Icons.home),
                label: const Text('Return to Home'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

