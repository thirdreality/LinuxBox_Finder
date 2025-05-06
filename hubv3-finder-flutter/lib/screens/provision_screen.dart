import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/material.dart';

import '../services/ble_service.dart';

class ProvisionScreen extends StatefulWidget {
  final String deviceId;
  final void Function(String ipAddr)? onProvisionSuccess;
  const ProvisionScreen({Key? key, required this.deviceId, this.onProvisionSuccess}) : super(key: key);

  @override
  _ProvisionScreenState createState() => _ProvisionScreenState();
}

class _ProvisionScreenState extends State<ProvisionScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _pskController = TextEditingController();
  bool _isLoading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _ssidController.dispose();
    _pskController.dispose();
    super.dispose();
  }

  Future<void> _provision() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      // 这里只调用 BLE 配网接口，参数包含 restore=false
      // 需按你项目的 BLE service 实现调用
      final bleService = BleService();
      final result = await bleService.configureWiFi(
        _ssidController.text,
        _pskController.text,
        false as Bool,
      );
      final Map<String, dynamic> json = result is String ? Map<String, dynamic>.from(jsonDecode(result)) : {};
      if (json['connect'] == true && json['ip_addr'] != null && json['ip_addr'].toString().isNotEmpty) {
        // 配网成功
        if (widget.onProvisionSuccess != null) {
          widget.onProvisionSuccess!(json['ip_addr']);
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('配网成功，正在跳转...'), backgroundColor: Colors.green));
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.of(context).pop(json['ip_addr']);
      } else {
        setState(() {
          _errorMsg = '配网失败，请重试';
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg = '配网异常: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi 配网'), backgroundColor: Theme.of(context).colorScheme.primary),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _ssidController,
                decoration: const InputDecoration(labelText: 'WiFi SSID'),
                validator: (v) => v == null || v.isEmpty ? '请输入SSID' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pskController,
                decoration: const InputDecoration(labelText: 'WiFi 密码'),
                obscureText: true,
                validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
              ),
              const SizedBox(height: 32),
              if (_isLoading) const CircularProgressIndicator(),
              if (_errorMsg != null) ...[
                Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _provision,
                  child: const Text('连接'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
