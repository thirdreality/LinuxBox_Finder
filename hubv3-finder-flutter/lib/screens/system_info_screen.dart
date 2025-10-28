import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/ble_service.dart';

class SystemInfoScreen extends StatefulWidget {
  const SystemInfoScreen({Key? key}) : super(key: key);

  @override
  State<SystemInfoScreen> createState() => _SystemInfoScreenState();
}

class _SystemInfoScreenState extends State<SystemInfoScreen> {
  bool _isLoadingServices = false;
  bool _isLoadingSystem = false;
  bool _isLoadingServerConfig = false;
  bool _isSettingServerConfig = false;
  
  Map<String, dynamic>? _servicesInfo;
  Map<String, dynamic>? _systemInfo;
  Map<String, dynamic>? _serverConfig;
  
  String? _errorMessage;
  
  // Server configuration form fields
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadServerConfig();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadServerConfig() async {
    setState(() {
      _isLoadingServerConfig = true;
      _errorMessage = null;
    });

    try {
      final result = await BleService().configureServer(action: 'get');
      final data = jsonDecode(result);
      
      setState(() {
        _serverConfig = data;
        _isLoadingServerConfig = false;
        
        // Populate form fields if config exists
        if (data['server'] != null) {
          _serverUrlController.text = data['server'];
        }
        if (data['user'] != null) {
          _usernameController.text = data['user'];
        }
        if (data['password'] != null) {
          _passwordController.text = data['password'];
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load server config: $e';
        _isLoadingServerConfig = false;
      });
    }
  }

  Future<void> _queryServices() async {
    setState(() {
      _isLoadingServices = true;
      _errorMessage = null;
    });

    try {
      final result = await BleService().querySystemInfo('services');
      final data = jsonDecode(result);
      
      setState(() {
        _servicesInfo = data;
        _isLoadingServices = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to query services: $e';
        _isLoadingServices = false;
      });
    }
  }

  Future<void> _querySystemInfo() async {
    setState(() {
      _isLoadingSystem = true;
      _errorMessage = null;
    });

    try {
      final result = await BleService().querySystemInfo('system');
      final data = jsonDecode(result);
      
      setState(() {
        _systemInfo = data;
        _isLoadingSystem = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to query system info: $e';
        _isLoadingSystem = false;
      });
    }
  }

  Future<void> _setServerConfig() async {
    if (_serverUrlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server URL is required')),
      );
      return;
    }

    setState(() {
      _isSettingServerConfig = true;
      _errorMessage = null;
    });

    try {
      final result = await BleService().configureServer(
        action: 'set',
        server: _serverUrlController.text,
        user: _usernameController.text.isNotEmpty ? _usernameController.text : null,
        password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
      );
      
      final data = jsonDecode(result);
      
      if (data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server configuration saved successfully')),
        );
        _loadServerConfig(); // Reload config
      } else {
        setState(() {
          _errorMessage = data['message'] ?? 'Failed to save server configuration';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to set server config: $e';
      });
    } finally {
      setState(() {
        _isSettingServerConfig = false;
      });
    }
  }

  Future<void> _testServerConnection() async {
    setState(() {
      _isSettingServerConfig = true;
      _errorMessage = null;
    });

    try {
      final result = await BleService().configureServer(action: 'test');
      final data = jsonDecode(result);
      
      if (data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Connection test successful')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Connection test failed')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection test failed: $e')),
      );
    } finally {
      setState(() {
        _isSettingServerConfig = false;
      });
    }
  }

  Widget _buildInfoCard(String title, Widget content) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildServicesInfo() {
    if (_isLoadingServices) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_servicesInfo == null) {
      return Column(
        children: [
          const Text('No services information available'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _queryServices,
            child: const Text('Query Services'),
          ),
        ],
      );
    }

    final services = _servicesInfo!['services'] as List<dynamic>? ?? [];
    
    return Column(
      children: [
        ElevatedButton(
          onPressed: _queryServices,
          child: const Text('Refresh Services'),
        ),
        const SizedBox(height: 16),
        ...services.map((service) => ListTile(
          title: Text(service['name'] ?? 'Unknown'),
          trailing: Chip(
            label: Text(service['status'] ?? 'Unknown'),
            backgroundColor: service['status'] == 'active' 
                ? Colors.green.shade100 
                : Colors.red.shade100,
          ),
        )).toList(),
      ],
    );
  }

  Widget _buildSystemInfo() {
    if (_isLoadingSystem) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_systemInfo == null) {
      return Column(
        children: [
          const Text('No system information available'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _querySystemInfo,
            child: const Text('Query System Info'),
          ),
        ],
      );
    }

    return Column(
      children: [
        ElevatedButton(
          onPressed: _querySystemInfo,
          child: const Text('Refresh System Info'),
        ),
        const SizedBox(height: 16),
        ..._systemInfo!.entries.map((entry) => ListTile(
          title: Text(entry.key),
          subtitle: Text(entry.value.toString()),
        )).toList(),
      ],
    );
  }

  Widget _buildServerConfigForm() {
    return Column(
      children: [
        TextField(
          controller: _serverUrlController,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://api.example.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username (Optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Password (Optional)',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isSettingServerConfig ? null : _setServerConfig,
                child: _isSettingServerConfig 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Config'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _isSettingServerConfig ? null : _testServerConnection,
                child: _isSettingServerConfig 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Test Connection'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoadingServerConfig ? null : _loadServerConfig,
          child: _isLoadingServerConfig 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Load Current Config'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Information'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
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
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildInfoCard('Services Status', _buildServicesInfo()),
                  _buildInfoCard('System Information', _buildSystemInfo()),
                  _buildInfoCard('Server Configuration', _buildServerConfigForm()),
                ],
              ),
            ),
    );
  }
}
