import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/http_service.dart';
import 'provision_screen.dart';

class ReprovisionProgressScreen extends StatefulWidget {
  final String deviceId;
  final String deviceIp;
  final String? deviceName;
  const ReprovisionProgressScreen({Key? key, required this.deviceId, required this.deviceIp, this.deviceName}) : super(key: key);

  @override
  State<ReprovisionProgressScreen> createState() => _ReprovisionProgressScreenState();
}

class _ReprovisionProgressScreenState extends State<ReprovisionProgressScreen> {
  int _step = 0;
  String? _errorMsg;
  String? _restoreResult;
  bool _bleConnected = false;

  final List<String> _steps = [
    '1. Check if device is online',
    '2. Prepare WiFi settings',
    '3. Scan for nearby devices',
    '4. Connect to selected device',
    '5. Navigate to provisioning page',
  ];

  @override
  void initState() {
    super.initState();
    _startReprovision();
  }

  Future<void> _startReprovision() async {
    setState(() { _step = 0; _errorMsg = null; });
    // 1. Check if device is online
    bool isOnline = false;
    try {
      final httpService = HttpService();
      httpService.configure(widget.deviceIp);
      isOnline = await httpService.checkConnectivity();
      setState(() { _step = 1; });
    } catch (e) {
      setState(() { _errorMsg = 'Failed to check device online status: $e'; });
      return;
    }
    // 2. Prepare WiFi settings
    if (isOnline) {
      try {
        setState(() { _step = 2; });
        final resp = await HttpService().sendCommand('prepare_wifi_provision');
        final json = resp.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(resp)) : {};
        if (json['success'] == true) {
          _restoreResult = json['restore']?.toString();
        } else {
          setState(() { _errorMsg = 'Device did not respond or failed'; });
          return;
        }
      } catch (e) {
        setState(() { _errorMsg = 'WiFi preparation failed: $e'; });
        return;
      }
    }
    // 3. Scan for nearby BLE devices
    try {
      setState(() { _step = 3; });
      await BleService().startScan();
    } catch (e) {
      setState(() { _errorMsg = 'BLE scan failed: $e'; });
      return;
    }
    // 4. Connect to BLE device
    try {
      setState(() { _step = 4; });
      await BleService().connectToDevice(widget.deviceId, enableHttp: false);
      _bleConnected = true;
    } catch (e) {
      // 提供更详细的错误信息
      String errorMessage = 'BLE connection failed: $e';
      
      // 针对 Android 错误码 133 提供更具体的错误信息
      if (e.toString().contains('android-code: 133')) {
        errorMessage = '蓝牙连接错误 (错误码: 133)：可能原因包括设备已被其他应用连接、设备不在范围内或已关闭、手机蓝牙存在问题。请尝试关闭并重新打开手机蓝牙，确保设备已开机并在附近，或重启应用程序。';
      }
      
      setState(() { _errorMsg = errorMessage; });
      return;
    }
    // 5. Navigate to provisioning page
    setState(() { _step = 5; });
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ProvisionScreen(
          deviceId: widget.deviceId,
          onProvisionSuccess: (ipAddr) async {
            Navigator.of(context).pop();
          },
        ),
        settings: RouteSettings(arguments: {
          'restore': _restoreResult,
        }),
      ),
    );
  }

  Widget _buildStepTile(int idx, String text) {
    Icon icon;
    if (_step > idx) {
      icon = const Icon(Icons.check_circle, color: Colors.green);
    } else if (_step == idx) {
      icon = const Icon(Icons.autorenew, color: Colors.blue);
    } else {
      icon = const Icon(Icons.radio_button_unchecked, color: Colors.grey);
    }
    return ListTile(
      leading: icon,
      title: Text(text, style: const TextStyle(fontSize: 16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reprovision WiFi')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...List.generate(_steps.length, (i) => _buildStepTile(i, _steps[i])),
            if (_step < 5 && _errorMsg == null)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            const Spacer(),
            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _errorMsg!,
                  style: const TextStyle(color: Colors.red, fontSize: 15),
                  textAlign: TextAlign.left,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _errorMsg != null
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _startReprovision,
                ),
              ),
            )
          : null,
    );
  }
}
