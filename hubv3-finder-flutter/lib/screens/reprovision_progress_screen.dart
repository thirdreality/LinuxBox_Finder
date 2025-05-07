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
    '1. 检查设备是否在线',
    '2. WIFI设置的准备工作',
    '3. 扫描附近BLE设备',
    '4. 连接当前选中的BLE设备',
    '5. 跳转配网页面',
  ];

  @override
  void initState() {
    super.initState();
    _startReprovision();
  }

  Future<void> _startReprovision() async {
    setState(() { _step = 0; _errorMsg = null; });
    // 1. 检查设备是否在线
    bool isOnline = false;
    try {
      final httpService = HttpService();
      httpService.configure(widget.deviceIp);
      isOnline = await httpService.checkConnectivity();
      setState(() { _step = 1; });
    } catch (e) {
      setState(() { _errorMsg = '检查设备在线状态失败: $e'; });
      return;
    }
    // 2. WIFI设置的准备工作
    if (isOnline) {
      try {
        setState(() { _step = 2; });
        final resp = await HttpService().sendCommand('prepare_wifi_provision');
        final json = resp.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(resp)) : {};
        if (json['success'] == true) {
          _restoreResult = json['restore']?.toString();
        } else {
          setState(() { _errorMsg = '设备未响应或失败'; });
          return;
        }
      } catch (e) {
        setState(() { _errorMsg = 'WIFI设置准备失败: $e'; });
        return;
      }
    }
    // 3. 扫描附近BLE设备
    try {
      setState(() { _step = 3; });
      await BleService().startScan();
    } catch (e) {
      setState(() { _errorMsg = 'BLE扫描失败: $e'; });
      return;
    }
    // 4. 连接BLE设备
    try {
      setState(() { _step = 4; });
      await BleService().connectToDevice(widget.deviceId, enableHttp: false);
      _bleConnected = true;
    } catch (e) {
      setState(() { _errorMsg = 'BLE连接失败: $e'; });
      return;
    }
    // 5. 跳转配网页面
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
      appBar: AppBar(title: const Text('重新设置WIFI')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
              ),
            ...List.generate(_steps.length, (i) => _buildStepTile(i, _steps[i])),
            if (_step < 5 && _errorMsg == null)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
