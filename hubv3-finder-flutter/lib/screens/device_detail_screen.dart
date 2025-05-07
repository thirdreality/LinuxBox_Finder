import 'package:flutter/material.dart';
import 'package:hubfinder/screens/reprovision_progress_screen.dart';
import '../services/ble_service.dart';
import '../services/http_service.dart';
import 'provision_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;
  final String deviceIp;
  final String? deviceName;
  const DeviceDetailScreen({Key? key, required this.deviceId, required this.deviceIp, this.deviceName}) : super(key: key);

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Future<Map<String, dynamic>> _deviceInfoFuture;

  @override
  void initState() {
    super.initState();
    _deviceInfoFuture = _fetchDeviceInfo();
  }

  Future<Map<String, dynamic>> _fetchDeviceInfo() async {
    // TODO: 替换为真实的HTTP接口调用，返回设备信息Map
    await Future.delayed(const Duration(seconds: 1));
    return {
      '设备名称': widget.deviceName ?? '未知',
      '设备ID': widget.deviceId,
      '设备IP': widget.deviceIp,
      // 其他信息...
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device information')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _deviceInfoFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('加载失败: \\${snapshot.error}'));
                }
                final info = snapshot.data ?? {};
                return ListView(
                  children: info.entries.map((e) => ListTile(
                    title: Text(e.key),
                    subtitle: Text(e.value.toString()),
                  )).toList(),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(32),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () async {
                      // print("1. 检查设备是否在线");
                      // // 1. 检查设备是否在线（假设有widget.deviceIp）
                      // bool isOnline = false;
                      // try {
                      //   final httpService = HttpService();
                      //   httpService.configure(widget.deviceIp);
                      //   isOnline = await httpService.checkConnectivity();
                      // } catch (_) {}

                      // String? restoreResult;
                      // if (isOnline) {
                      //   print("1. 2. 在线：展示loading，发送prepare_wifi_provision");
                      //   // 2. 在线：展示loading，发送prepare_wifi_provision
                      //   showDialog(
                      //     context: context,
                      //     barrierDismissible: false,
                      //     builder: (context) => const AlertDialog(
                      //       title: Text('正在准备重新设置wifi', style: TextStyle(fontSize: 16)),
                      //       content: Row(
                      //         children: [
                      //           CircularProgressIndicator(),
                      //           SizedBox(width: 16),
                      //           Expanded(child: Text('请稍候...')),
                      //         ],
                      //       ),
                      //     ),
                      //   );
                      //   try {
                      //     final resp = await HttpService().sendCommand('prepare_wifi_provision');
                      //     final json = resp.isNotEmpty ? Map<String, dynamic>.from(jsonDecode(resp)) : {};
                      //     if (json['success'] == true) {
                      //       restoreResult = json['restore']?.toString();
                      //     } else {
                      //       throw Exception('设备未响应或失败');
                      //     }
                      //   } catch (e) {
                      //     Navigator.of(context, rootNavigator: true).maybePop();
                      //     ScaffoldMessenger.of(context).showSnackBar(
                      //       SnackBar(content: Text('设备响应失败: $e'), backgroundColor: Colors.red),
                      //     );
                      //     return;
                      //   }
                      //   Navigator.of(context, rootNavigator: true).maybePop();
                      // }

                      // print("3. BLE 连接流程");
                      // // 3. BLE 连接流程
                      // int retry = 0;
                      // bool bleConnected = false;
                      // BleService bleService = BleService();
                      // // 若BLE设备缓存为空，先扫描
                      // if (bleService.discoveredDevices.isEmpty) {
                      //   await bleService.startScan();
                      // }
                      // while (retry < 3 && !bleConnected) {
                      //   showDialog(
                      //     context: context,
                      //     barrierDismissible: false,
                      //     builder: (context) => const AlertDialog(
                      //       title: Text('正在连接设备', style: TextStyle(fontSize: 16)),
                      //       content: Row(
                      //         children: [
                      //           CircularProgressIndicator(),
                      //           SizedBox(width: 16),
                      //           Expanded(child: Text('请稍候...')),
                      //         ],
                      //       ),
                      //     ),
                      //   );
                      //   try {
                      //     await bleService.connectToDevice(widget.deviceId, enableHttp: false);
                      //     bleConnected = true;
                      //   } catch (e) {
                      //     retry++;
                      //     Navigator.of(context, rootNavigator: true).maybePop();
                      //     if (retry >= 3) {
                      //       ScaffoldMessenger.of(context).showSnackBar(
                      //         SnackBar(content: Text('蓝牙连接失败: $e'), backgroundColor: Colors.red),
                      //       );
                      //       return;
                      //     }
                      //     await Future.delayed(const Duration(milliseconds: 300));
                      //   }
                      //   Navigator.of(context, rootNavigator: true).maybePop();
                      // }
                      // if (!bleConnected) return;
                      // 4. 跳转到配网页面
                      print("4. 跳转到配网页面");
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ReprovisionProgressScreen(
                          deviceId: widget.deviceId,
                          deviceIp: widget.deviceIp,
                          deviceName: widget.deviceName,
                        ),
                      ));
                    },
                    child: const Text('重新连接', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(16),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () async {
                      // 1. 删除设备相关SharePreference
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove('selected_device_id');
                      await prefs.remove('selected_device_ip');
                      await prefs.remove('selected_device_name');
                      await prefs.remove('selected_wifi_mac');
                      // 2. 返回首页
                      if (!mounted) return;
                      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                    },
                    child: const Text('解除绑定', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
