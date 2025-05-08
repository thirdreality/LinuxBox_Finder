import 'package:flutter/material.dart';
import '../services/http_service.dart';
import 'dart:convert';

class SoftwareManagerScreen extends StatefulWidget {
  final String deviceIp;

  const SoftwareManagerScreen({Key? key, required this.deviceIp}) : super(key: key);

  @override
  State<SoftwareManagerScreen> createState() => _SoftwareManagerScreenState();
}

class _SoftwareManagerScreenState extends State<SoftwareManagerScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _softwarePackages;
  String? _errorMessage;
  bool _isResetting = false;
  
  // Map to track which packages have their services expanded
  final Map<String, bool> _showServices = {};
  
  // Map to store service information for each package
  final Map<String, Map<String, dynamic>?> _serviceInfo = {};

  @override
  void initState() {
    super.initState();
    _loadSoftwarePackages();
  }

  Future<void> _loadSoftwarePackages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await HttpService().getSoftwareInfo();
      
      setState(() {
        _softwarePackages = response;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load software packages: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateSoftwarePackage(String packageId, String action) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('${action.substring(0, 1).toUpperCase() + action.substring(1)}ing $packageId...'),
          ],
        ),
      ),
    );

    try {
      await HttpService().updateSoftwarePackage(packageId, action);
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      // Refresh software packages
      await _loadSoftwarePackages();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$packageId $action operation initiated')),
      );
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to $action $packageId: $e')),
      );
    }
  }

  Future<void> _enablePackage(String packageId) async {
    // First disable any currently enabled package
    if (_softwarePackages != null) {
      for (final entry in _softwarePackages!.entries) {
        if (entry.key != packageId && entry.value['enabled'] == true) {
          await _updateSoftwarePackage(entry.key, 'disable');
          break;
        }
      }
    }
    
    // Then enable the selected package
    await _updateSoftwarePackage(packageId, 'enable');
  }

  Future<void> _resetToDefault() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Default'),
        content: const Text(
            'Are you sure you want to reset all software packages to their default configuration?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isResetting = true;
    });

    try {
      await HttpService().resetSoftwareToDefaultLegacy();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Software reset to default configuration')),
      );
      
      await _loadSoftwarePackages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reset software: $e')),
      );
    } finally {
      setState(() {
        _isResetting = false;
      });
    }
  }

  Future<void> _loadServiceInfo(String packageId) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading service information...'),
          ],
        ),
      ),
    );

    try {
      final response = await HttpService().getSingleServiceInfo(packageId);
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      setState(() {
        _serviceInfo[packageId] = response;
      });
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load service information: $e')),
      );
    }
  }
  
  void _toggleShowServices(String packageId) {
    setState(() {
      // Initialize if not exists
      _showServices[packageId] = !(_showServices[packageId] ?? false);
    });
    
    // Load service info if showing and not already loaded
    if (_showServices[packageId]! && (_serviceInfo[packageId] == null)) {
      _loadServiceInfo(packageId);
    }
  }
  
  Future<void> _updateServiceStatus(String packageId, String serviceName, String action) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await HttpService().updateServiceStatus(packageId, serviceName, action);
      // Refresh service info after update
      await _loadServiceInfo(packageId);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update service: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildServiceItem(String serviceId, Map<String, dynamic> serviceData, String packageId) {
    final bool isEnabled = serviceData['enabled'] as bool;
    final bool isRunning = serviceData['running'] as bool;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceId,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Enabled status
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isEnabled ? Colors.blue[50] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isEnabled ? 'Enabled' : 'Disabled',
                        style: TextStyle(
                          fontSize: 11,
                          color: isEnabled ? Colors.blue[800] : Colors.grey[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // Running status
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isRunning ? Colors.green[100] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isRunning ? 'Running' : 'Stopped',
                        style: TextStyle(
                          fontSize: 11,
                          color: isRunning ? Colors.green[800] : Colors.grey[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Menu button
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.more_vert, size: 20),
            itemBuilder: (context) => [
              if (isEnabled)
                PopupMenuItem(
                  value: 'disable',
                  child: const Text('Disable'),
                )
              else
                PopupMenuItem(
                  value: 'enable',
                  child: const Text('Enable'),
                ),
              if (isRunning)
                PopupMenuItem(
                  value: 'stop',
                  child: const Text('Stop'),
                )
              else
                PopupMenuItem(
                  value: 'start',
                  child: const Text('Start'),
                ),
            ],
            onSelected: (action) => _updateServiceStatus(packageId, serviceId, action),
          ),
        ],
      ),
    );
  }

  Widget _buildSoftwarePackage(String packageId, Map<String, dynamic> packageData) {
    final String packageName = packageData['name'] as String;
    final bool isInstalled = packageData['installed'] as bool;
    final bool isEnabled = packageData['enabled'] as bool;
    final List<dynamic> softwareList = packageData['software'] as List<dynamic>;
    
    // Initialize show services state if not already set
    if (!_showServices.containsKey(packageId)) {
      _showServices[packageId] = false;
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        packageName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isInstalled ? Colors.green[100] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isInstalled ? 'Installed' : 'Not Installed',
                        style: TextStyle(
                          color: isInstalled ? Colors.green[800] : Colors.grey[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isInstalled) ...[  
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isEnabled ? Colors.blue[100] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isEnabled ? 'Enabled' : 'Disabled',
                          style: TextStyle(
                            color: isEnabled ? Colors.blue[800] : Colors.grey[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (softwareList.isNotEmpty) ...[  
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Components:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              ...softwareList.map((sw) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sw['name'] as String,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (sw['version'] != null && sw['version'].toString().isNotEmpty) ...[  
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          sw['version'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              )),
            ],
            
            // Only show Services section for enabled software
            if (isEnabled) ...[  
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Services:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  TextButton.icon(
                    icon: Icon(
                      _showServices[packageId]! ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                    ),
                    label: Text(
                      _showServices[packageId]! ? 'Hide' : 'Show',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                      minimumSize: const Size(60, 24),
                    ),
                    onPressed: () => _toggleShowServices(packageId),
                  ),
                ],
              ),
              if (_showServices[packageId]!) ...[  
                if (_serviceInfo[packageId] == null) ...[  
                  const SizedBox(height: 8),
                  const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ] else ...[  
                  const SizedBox(height: 4),
                  if (_serviceInfo[packageId]!.containsKey(packageId) && 
                      _serviceInfo[packageId]![packageId]['service'] != null) ...[  
                    ...(_serviceInfo[packageId]![packageId]['service'] as List<dynamic>)
                      .map((service) => _buildServiceItem(
                        service['name'] as String,
                        service,
                        packageId,
                      )),
                  ] else ...[  
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('No services found', style: TextStyle(fontStyle: FontStyle.italic)),
                    ),
                  ],
                ],
              ],
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: isInstalled
                ? [
                  OutlinedButton(
                    child: const Text(
                      'Enable',
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(60, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      side: const BorderSide(
                        color: Colors.grey,
                      ),
                    ),
                    // Disable the button if the software is already enabled
                    onPressed: isEnabled ? null : () => _updateSoftwarePackage(packageId, 'enable'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.system_update,
                      size: 16,
                      color: Colors.green,
                    ),
                    label: const Text(
                      'Upgrade',
                      style: TextStyle(
                        color: Colors.green,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(60, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      side: const BorderSide(
                        color: Colors.green,
                      ),
                    ),
                    onPressed: () => _updateSoftwarePackage(packageId, 'upgrade'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Colors.red,
                    ),
                    label: const Text(
                      'Uninstall',
                      style: TextStyle(
                        color: Colors.red,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(60, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      side: const BorderSide(
                        color: Colors.red,
                      ),
                    ),
                    onPressed: () => _updateSoftwarePackage(packageId, 'uninstall'),
                  ),
                ]
                : [
                    // Install button
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Install'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(60, 32),
                      ),
                      onPressed: () => _updateSoftwarePackage(packageId, 'install'),
                    ),
                  ],
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
        title: const Text('Software Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadSoftwarePackages,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _softwarePackages == null
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
                        onPressed: _loadSoftwarePackages,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSoftwarePackages,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 8),
                            if (_softwarePackages != null)
                              ..._softwarePackages!.entries
                                  .map((entry) => _buildSoftwarePackage(entry.key, entry.value))
                                  .toList(),
                            const SizedBox(height: 80), // Space for the bottom button
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, -2),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isResetting ? null : _resetToDefault,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: _isResetting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Text('Reset to Default'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
