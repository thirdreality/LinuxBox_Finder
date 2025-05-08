import 'package:flutter/material.dart';
import '../services/http_service.dart';
import 'dart:convert';

class ServiceManagerScreen extends StatefulWidget {
  final String deviceIp;

  const ServiceManagerScreen({Key? key, required this.deviceIp}) : super(key: key);

  @override
  State<ServiceManagerScreen> createState() => _ServiceManagerScreenState();
}

class _ServiceManagerScreenState extends State<ServiceManagerScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _serviceStatus;
  String? _errorMessage;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _loadServiceStatus();
  }

  Future<void> _loadServiceStatus() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await HttpService().getServiceInfo();
      
      setState(() {
        _serviceStatus = response;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load service status: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateServiceStatus(String serviceId, String action) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Updating service status...'),
          ],
        ),
      ),
    );

    try {
      await HttpService().updateServiceStatus(serviceId, action);
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      // Refresh service status
      await _loadServiceStatus();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Service $serviceId $action completed')),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update service: $e')),
      );
    }
  }

  // Reset to Default functionality removed as requested

  Widget _buildServiceGroup(String groupId, Map<String, dynamic> groupData) {
    final String groupName = groupData['name'] as String;
    final List<dynamic> services = groupData['service'] as List<dynamic>;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              groupName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(height: 1),
          ...services.map((service) => _buildServiceItem(groupId, service)),
        ],
      ),
    );
  }

  Widget _buildServiceItem(String groupId, Map<String, dynamic> serviceData) {
    final String serviceName = serviceData['name'] as String;
    final bool isEnabled = serviceData['enabled'] as bool;
    final bool isRunning = serviceData['running'] as bool;

    // Extract service ID from the service name
    final String serviceId = serviceName;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  serviceName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isRunning ? Colors.green[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isRunning ? 'Running' : 'Stopped',
                  style: TextStyle(
                    color: isRunning ? Colors.green[800] : Colors.grey[800],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Enable/Disable button
              OutlinedButton(
                onPressed: () => _updateServiceStatus(
                  serviceId,
                  isEnabled ? 'disable' : 'enable',
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: isEnabled ? Colors.red : Colors.blue,
                  ),
                ),
                child: Text(
                  isEnabled ? 'Disable' : 'Enable',
                  style: TextStyle(
                    color: isEnabled ? Colors.red : Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Start/Stop button
              ElevatedButton(
                onPressed: isEnabled
                    ? () => _updateServiceStatus(
                          serviceId,
                          isRunning ? 'stop' : 'start',
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning ? Colors.red[400] : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(isRunning ? 'Stop' : 'Start'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadServiceStatus,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _serviceStatus == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadServiceStatus,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadServiceStatus,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 8),
                      if (_serviceStatus != null)
                        ..._serviceStatus!.entries
                            .map((entry) => _buildServiceGroup(entry.key, entry.value))
                            .toList(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
    );
  }
}
