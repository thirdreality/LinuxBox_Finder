import 'package:flutter/material.dart';
import '../models/WiFiConnectionStatus.dart';
import '../models/wifi_network.dart';
import '../services/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

class DeviceControlScreen extends StatefulWidget {
  const DeviceControlScreen({Key? key}) : super(key: key);

  @override
  _DeviceControlScreenState createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen> with SingleTickerProviderStateMixin {
  final BleService _bleService = BleService();
  WiFiConnectionStatus? _wifiStatus;
  bool _isLoading = true;
  late TabController _tabController;
  int _currentIndex = 0; // 当前选中的标签页索引

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // 监听标签页切换
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });

    _fetchWiFiStatus();
  }

  Future<void> _fetchWiFiStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get raw status string from the BLE service
      final statusString = await _bleService.getWifiStatus();

      print("getWifiStatus() statusString: ${statusString}");

      // Parse the status string into our WiFiConnectionStatus object
      final status = WiFiConnectionStatus.fromJson(statusString);

      print("Wifi status result: ${status}");

      setState(() {
        _wifiStatus = status;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _wifiStatus = WiFiConnectionStatus.error('Failed to fetch WiFi status: $e');
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Disconnect when navigating back
        await _bleService.disconnect();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Device Control'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchWiFiStatus,
              tooltip: 'Refresh Status',
            ),
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: () async {
                await _bleService.disconnect();
                if (mounted) {
                  Navigator.pop(context);
                }
              },
              tooltip: 'Disconnect',
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.yellow,
            labelColor: Colors.white, // 选中标签的文字颜色
            unselectedLabelColor: Colors.white70, // 未选中标签的文字颜色
            labelStyle: const TextStyle(fontWeight: FontWeight.bold), // 选中标签的文字样式
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal), // 未选中标签的文字样式
            indicatorWeight: 3.0, // 指示器厚度
            indicatorSize: TabBarIndicatorSize.tab, // 指示器大小与标签大小一致
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            tabs: const [
              Tab(text: 'Status', icon: Icon(Icons.info_outline)),
              Tab(text: 'WiFi Setup', icon: Icon(Icons.wifi)),
              Tab(text: 'Commands', icon: Icon(Icons.terminal)),
            ],
          ),
        ),
        // 使用IndexedStack替代TabBarView，保持所有页面的状态
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildStatusTab(),
            _buildWiFiSetupTab(),
            _buildCommandsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_wifiStatus == null) {
      return const Center(
        child: Text('No status information available'),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchWiFiStatus,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WiFi Connection Status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Divider(),
                _buildStatusRow(
                  'Status',
                  _wifiStatus!.isConnected ? 'Connected' : 'Disconnected',
                  _wifiStatus!.isConnected ? Icons.check_circle : Icons.cancel,
                  _wifiStatus!.isConnected ? Colors.green : Colors.red,
                ),
                if (_wifiStatus!.ssid != null)
                  _buildStatusRow('SSID', _wifiStatus!.ssid!, Icons.wifi, Colors.blue),
                if (_wifiStatus!.ipAddress != null)
                  _buildStatusRow('IP Address', _wifiStatus!.ipAddress!, Icons.language, Colors.purple),
                if (_wifiStatus!.macAddress != null)
                  _buildStatusRow('MAC Address', _wifiStatus!.macAddress!, Icons.developer_board, Colors.orange),
                if (_wifiStatus!.errorMessage != null)
                  _buildStatusRow('Error', _wifiStatus!.errorMessage!, Icons.error, Colors.red),

                // 添加Web界面访问按钮，仅当设备连接到WiFi且有IP地址时显示
                if (_wifiStatus!.isConnected && _wifiStatus!.ipAddress != null && _wifiStatus!.ipAddress!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Connect HomeAssistant:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () => _launchWebInterface(_wifiStatus!.ipAddress!),
                      icon: const Icon(Icons.open_in_browser),
                      label: Text('Connect to http://${_wifiStatus!.ipAddress}:8123'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 打开浏览器访问设备Web界面
  Future<void> _launchWebInterface(String ipAddress) async {
    final Uri url = Uri.parse('http://$ipAddress:8123');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not launch $url'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error launching browser: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatusRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWiFiSetupTab() {
    return WiFiSetupWidget(onConnectionStatusChanged: _fetchWiFiStatus);
  }

  Widget _buildCommandsTab() {
    return const CommandsWidget();
  }
}

class WiFiSetupWidget extends StatefulWidget {
  final VoidCallback? onConnectionStatusChanged;

  const WiFiSetupWidget({Key? key, this.onConnectionStatusChanged}) : super(key: key);

  @override
  _WiFiSetupWidgetState createState() => _WiFiSetupWidgetState();
}

class _WiFiSetupWidgetState extends State<WiFiSetupWidget> {
  final BleService _bleService = BleService();
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showManualSsidInput = false;
  List<WiFiNetwork> _wifiNetworks = [];
  String? _selectedSSID; // 添加跟踪当前选中网络的变量

  @override
  void initState() {
    super.initState();
    _startWiFiScan();
  }

  Future<void> _startWiFiScan() async {
    setState(() {
      _isLoading = true;
      _wifiNetworks = [];
    });

    try {
      // Request location permission (required for WiFi scanning)
      final status = await Permission.location.request();
      if (!status.isGranted) {
        throw Exception('Location permission denied');
      }

      // Check if WiFi scanning is available
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan != CanStartScan.yes) {
        throw Exception('Cannot start WiFi scan: $canScan');
      }

      // Start a WiFi scan
      final result = await WiFiScan.instance.startScan();
      if (result != true) {
        throw Exception('Failed to start WiFi scan: $result');
      }

      // Wait for the scan to complete (typically takes 2-4 seconds)
      await Future.delayed(const Duration(seconds: 3));

      // Get scan results
      final accessPoints = await WiFiScan.instance.getScannedResults();

      // Convert to our WiFiNetwork model
      setState(() {
        _wifiNetworks = accessPoints.map((ap) => WiFiNetwork(
          ssid: ap.ssid,
          signalStrength: ap.level,
          isSecured: ap.capabilities.contains('WPA') || ap.capabilities.contains('WEP'),
          bssid: ap.bssid,
        )).toList();

        // Sort by signal strength
        _wifiNetworks.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to scan for WiFi networks: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _connectToWiFi() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final ssid = _ssidController.text;
      final password = _passwordController.text;

      // configureWiFi现在返回字符串结果而非布尔值
      final result = await _bleService.configureWiFi(ssid, password);
      print("configureWiFi: $result");

      // 检查结果是否包含错误信息
      final bool isSuccess = result.toLowerCase().contains('"success":"true"');
      final String message = isSuccess ? 'Successfully connected to WiFi: $ssid' : 'Failed to connect to WiFi: $ssid';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isSuccess ? Colors.green : Colors.red,
        ),
      );

      // 如果成功，刷新状态
      if (isSuccess) {
        await Future.delayed(const Duration(seconds: 2));
        widget.onConnectionStatusChanged?.call();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteWiFiNetworks() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete WiFi Networks'),
        content: const Text('Are you sure you want to delete all saved WiFi networks?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() {
                _isLoading = true;
              });

              try {
                final result = await _bleService.deleteWiFiNetworks();
                // 检查结果是否包含错误信息
                final bool isSuccess = !result.toLowerCase().contains('error');
                final String message = isSuccess
                    ? 'Successfully deleted all WiFi networks'
                    : 'Failed to delete WiFi networks: ${result.replaceAll('Error:', '')}';

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    backgroundColor: isSuccess ? Colors.green : Colors.red,
                  ),
                );

                // 删除成功后刷新WiFi网络列表
                if (isSuccess) {
                  await Future.delayed(const Duration(seconds: 2));
                  // 调用刷新WiFi网络列表的方法
                  _startWiFiScan();
                  // 通知状态变化（如果有需要）
                  widget.onConnectionStatusChanged?.call();
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              } finally {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(
      child: CircularProgressIndicator(),
    )
        : SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  _buildWiFiNetworkList(),
                  TextButton.icon(
                    icon: Icon(_showManualSsidInput ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                    label: Text(_showManualSsidInput ? 'Hide manual input' : 'Enter SSID manually'),
                    onPressed: () {
                      setState(() {
                        _showManualSsidInput = !_showManualSsidInput;
                      });
                    },
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
                    if (_showManualSsidInput)
                      TextFormField(
                        controller: _ssidController,
                        decoration: const InputDecoration(
                          labelText: 'SSID',
                          prefixIcon: Icon(Icons.wifi),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter an SSID';
                          }
                          return null;
                        },
                      ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password',
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
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _connectToWiFi,
                          icon: const Icon(Icons.wifi),
                          label: const Text('Connect'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _deleteWiFiNetworks,
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text('Delete Networks', style: TextStyle(color: Colors.red)),
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

  Widget _buildWiFiNetworkList() {
    if (_wifiNetworks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('No WiFi networks found. Tap the refresh button to scan again.'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select a network:'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSSID,
                hint: const Text('Select WiFi network'),
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                borderRadius: BorderRadius.circular(8),
                icon: const Icon(Icons.arrow_drop_down),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedSSID = value;
                    _ssidController.text = value;
                    _showManualSsidInput = false;
                  });
                },
                items: _wifiNetworks.map((network) {
                  return DropdownMenuItem<String>(
                    value: network.ssid,
                    child: Row(
                      children: [
                        Icon(
                          Icons.wifi,
                          color: _getSignalColor(network.signalStrength),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            network.ssid,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${network.signalStrength} dBm',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getSignalColor(int signalStrength) {
    if (signalStrength > -60) {
      return Colors.green;
    } else if (signalStrength > -80) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }
}

class CommandsWidget extends StatefulWidget {
  const CommandsWidget({Key? key}) : super(key: key);

  @override
  _CommandsWidgetState createState() => _CommandsWidgetState();
}

class _CommandsWidgetState extends State<CommandsWidget> {
  final BleService _bleService = BleService();
  String _commandResponse = '';
  bool _isLoading = false;

  Future<void> _sendCommand(String command) async {
    setState(() {
      _isLoading = true;
      _commandResponse = '';
    });

    try {
      final response = await _bleService.sendCommand(command);
      setState(() {
        _commandResponse = response;
      });
    } catch (e) {
      setState(() {
        _commandResponse = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Commands',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  const Text(
                    'Send special commands to the device:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 使用Column替代Wrap，实现垂直排列
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch, // 让按钮填充整行宽度
                    children: [
                      _buildCommandButton(
                        'Restart Device',
                        Icons.restart_alt,
                        'restart_device',
                        Colors.orange,
                      ),
                      const SizedBox(height: 10), // 按钮之间的垂直间距
                      _buildCommandButton(
                        'Restart WiFi',
                        Icons.wifi_off,
                        'restart_wifi',
                        Colors.blue,
                      ),
                      const SizedBox(height: 10), // 按钮之间的垂直间距
                      _buildCommandButton(
                        'Factory Reset',
                        Icons.delete_forever,
                        'factory_reset',
                        Colors.red,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (_commandResponse.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Response',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Divider(),
                    Text(_commandResponse),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommandButton(String label, IconData icon, String command, Color color) {
    return ElevatedButton.icon(
      onPressed: () => _showCommandConfirmation(label, command),
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
    );
  }

  void _showCommandConfirmation(String label, String command) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm $label'),
        content: Text('Are you sure you want to $label?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _sendCommand(command);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}
