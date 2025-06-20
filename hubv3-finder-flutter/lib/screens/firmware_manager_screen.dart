import 'package:flutter/material.dart';
import '../services/http_service.dart';
import 'dart:convert';

class FirmwareManagerScreen extends StatefulWidget {
  final String deviceIp;

  const FirmwareManagerScreen({Key? key, required this.deviceIp}) : super(key: key);

  @override
  State<FirmwareManagerScreen> createState() => _FirmwareManagerScreenState();
}

class _FirmwareManagerScreenState extends State<FirmwareManagerScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _firmwareInfo;
  String? _errorMessage;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    // 确保在加载固件信息之前配置 HTTP 服务的 IP 地址
    HttpService().configure(widget.deviceIp);
    _loadFirmwareInfo();
  }

  Future<void> _loadFirmwareInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 假设有一个API来获取固件信息
      final response = await HttpService().getFirmwareInfo();
      
      setState(() {
        _firmwareInfo = Map<String, dynamic>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load firmware information: $e';
        _isLoading = false;
        // 如果API不存在，使用模拟数据进行演示
        _firmwareInfo = {
          'current_version': 'v1.2.3',
          'latest_version': 'v1.3.0',
          'update_available': true,
          'release_date': '2025-04-15',
          'release_notes': 'Bug fixes and performance improvements:\n- Fixed WiFi connection stability issues\n- Improved BLE scanning performance\n- Added support for new device types',
          'device_model': 'LinuxBox Dev Edition',
          'build_number': '20250415-1234'
        };
      });
    }
  }

  Future<void> _updateFirmware() async {
    try {
      setState(() {
        _isUpdating = true;
      });
      
      await HttpService().sendCommand('update_firmware');
      
      // 模拟更新过程
      await Future.delayed(const Duration(seconds: 3));
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Firmware update started. The device will reboot when complete.')),
      );
      
      setState(() {
        _isUpdating = false;
        // 更新本地数据以反映更新
        if (_firmwareInfo != null) {
          _firmwareInfo!['current_version'] = _firmwareInfo!['latest_version'];
          _firmwareInfo!['update_available'] = false;
        }
      });
    } catch (e) {
      setState(() {
        _isUpdating = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update firmware: $e')),
      );
    }
  }

  Widget _buildFirmwareInfoCard() {
    if (_firmwareInfo == null) {
      return const SizedBox.shrink();
    }

    final bool updateAvailable = _firmwareInfo!['update_available'] ?? false;
    
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _firmwareInfo!['device_model'] ?? 'Unknown Device',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Current Version', _firmwareInfo!['current_version'] ?? 'Unknown'),
            _buildInfoRow('Build Number', _firmwareInfo!['build_number'] ?? 'Unknown'),
            if (updateAvailable) ...[
              const Divider(height: 32),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.system_update, color: Colors.blue[700]),
                        const SizedBox(width: 8),
                        Text(
                          'Update Available',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('Latest Version', _firmwareInfo!['latest_version'] ?? 'Unknown'),
                    _buildInfoRow('Release Date', _firmwareInfo!['release_date'] ?? 'Unknown'),
                    const SizedBox(height: 8),
                    const Text(
                      'Release Notes:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_firmwareInfo!['release_notes'] ?? 'No release notes available'),
                    const SizedBox(height: 16),
                    Center(
                      child: _isUpdating
                          ? const CircularProgressIndicator()
                          : ElevatedButton.icon(
                              icon: const Icon(Icons.system_update_alt),
                              label: const Text('Update Firmware'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              ),
                              onPressed: _updateFirmware,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
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
        title: const Text('Firmware Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFirmwareInfo,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null && _firmwareInfo == null
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
                        onPressed: _loadFirmwareInfo,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFirmwareInfo,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildFirmwareInfoCard(),
                      const SizedBox(height: 16),
                      Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Firmware Update Instructions',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '1. Make sure the device is connected to a stable power source.\n'
                                '2. Ensure the device has a stable internet connection.\n'
                                '3. Do not disconnect the device during the update process.\n'
                                '4. The device will automatically reboot after the update is complete.',
                                style: TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
