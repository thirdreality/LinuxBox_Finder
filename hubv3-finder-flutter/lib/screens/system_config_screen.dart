import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class SystemConfigScreen extends StatefulWidget {
  final String deviceId;
  
  const SystemConfigScreen({Key? key, required this.deviceId}) : super(key: key);

  @override
  State<SystemConfigScreen> createState() => _SystemConfigScreenState();
}

class _SystemConfigScreenState extends State<SystemConfigScreen> {
  final BleService _bleService = BleService();
  bool _isConnecting = false;
  bool _isLoading = false;
  bool _isConfiguring = false;
  Map<String, dynamic>? _servicesInfo;
  String? _errorMessage;
  
  // Form controllers with default test values
  final _baseTopicController = TextEditingController(text: 'demo2mqtt');
  final _serverController = TextEditingController(text: 'mqtt://demo_host:1883');
  final _userController = TextEditingController(text: 'demo_user');
  final _passController = TextEditingController(text: 'demo_pass');
  final _clientIdController = TextEditingController(text: 'demo_id');

  @override
  void initState() {
    super.initState();
    _connectAndQueryServices();
  }

  @override
  void dispose() {
    _baseTopicController.dispose();
    _serverController.dispose();
    _userController.dispose();
    _passController.dispose();
    _clientIdController.dispose();
    super.dispose();
  }

  Future<void> _connectAndQueryServices() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });

    try {
      // Connect to device
      await _bleService.connectToDevice(widget.deviceId);
      
      setState(() {
        _isConnecting = false;
        _isLoading = true;
      });

      // Query services
      final result = await _bleService.querySystemInfo('services');
      final data = jsonDecode(result);
      
      setState(() {
        _servicesInfo = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to connect or query services: $e';
        _isConnecting = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _configureServer() async {
    if (_serverController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server is required')),
      );
      return;
    }

    setState(() {
      _isConfiguring = true;
    });

    try {
      // Only include clientId if it's not empty
      String? clientId = _clientIdController.text.trim().isEmpty 
          ? null 
          : _clientIdController.text.trim();
      
      final result = await _bleService.configureServer(
        action: 'set',
        baseTopic: _baseTopicController.text.isNotEmpty ? _baseTopicController.text : null,
        server: _serverController.text,
        user: _userController.text.isNotEmpty ? _userController.text : null,
        password: _passController.text.isNotEmpty ? _passController.text : null,
        clientId: clientId,
      );
      
      final data = jsonDecode(result);
      
      // Show toast with response
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['message'] ?? 'Configuration completed'),
          backgroundColor: data['status'] == 'success' ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Configuration failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isConfiguring = false;
      });
    }
  }

  void _goBack() async {
    // Disconnect BLE and return to home
    await _bleService.disconnect();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  Widget _buildServicesInfo() {
    if (_servicesInfo == null) {
      return const SizedBox.shrink();
    }

    // Parse services string (format: "z2m,otbr")
    final servicesString = _servicesInfo!['Services'] as String? ?? '';
    final servicesList = servicesString.split(',').where((s) => s.isNotEmpty).toList();
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Model ID', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(_servicesInfo!['ModelID'] ?? 'Unknown'),
            ),
            ListTile(
              title: const Text('Version', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(_servicesInfo!['Version'] ?? 'Unknown'),
            ),
            ListTile(
              title: const Text('Mac Address', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(_servicesInfo!['MacAddress'] ?? 'Unknown'),
            ),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Services',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...servicesList.map((service) => ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(service.trim()),
              dense: true,
            )).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigForm() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MQTT Configuration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _baseTopicController,
              decoration: const InputDecoration(
                labelText: 'Base Topic',
                hintText: 'demo2mqtt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _serverController,
              decoration: const InputDecoration(
                labelText: 'Server',
                hintText: 'mqtt://demo_host:1883',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(
                labelText: 'User',
                hintText: 'demo_user',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passController,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'demo_pass',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _clientIdController,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                hintText: 'demo_id',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isConfiguring ? null : _configureServer,
                child: _isConfiguring 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Config'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Config'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Error',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _connectAndQueryServices,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _isConnecting || _isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Connecting to device and querying services...'),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildServicesInfo(),
                      _buildConfigForm(),
                    ],
                  ),
                ),
    );
  }
}
