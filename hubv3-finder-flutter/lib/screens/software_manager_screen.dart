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
      await HttpService().resetSoftwareToDefault();
      
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

  Widget _buildSoftwarePackage(String packageId, Map<String, dynamic> packageData) {
    final String packageName = packageData['name'] as String;
    final bool isInstalled = packageData['installed'] as bool;
    final bool isEnabled = packageData['enabled'] as bool;
    final List<dynamic> softwareList = packageData['software'] as List<dynamic>;
    
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
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      '• ${sw['name']}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (sw['version'] != null && sw['version'].toString().isNotEmpty) ...[  
                      const SizedBox(width: 4),
                      Text(
                        '(${sw['version']})',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ],
                ),
              )),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: isInstalled
                ? [
                    // Enable/Disable button
                    OutlinedButton(
                      onPressed: isEnabled ? null : () => _enablePackage(packageId),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isEnabled ? Colors.grey : Colors.blue,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(60, 32),
                      ),
                      child: Text(
                        isEnabled ? 'Enabled' : 'Enable',
                        style: TextStyle(
                          color: isEnabled ? Colors.grey : Colors.blue,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Upgrade button
                    OutlinedButton.icon(
                      icon: const Icon(Icons.system_update, size: 16),
                      label: const Text('Upgrade'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(60, 32),
                      ),
                      onPressed: () => _updateSoftwarePackage(packageId, 'upgrade'),
                    ),
                    const SizedBox(width: 8),
                    // Uninstall button
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Uninstall'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[400],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        minimumSize: const Size(60, 32),
                      ),
                      onPressed: isEnabled ? null : () => _updateSoftwarePackage(packageId, 'uninstall'),
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
