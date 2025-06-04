import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/http_service.dart';

class PackageManagerScreen extends StatefulWidget {
  final String packageId;
  final String deviceIp;

  const PackageManagerScreen({Key? key, required this.packageId, required this.deviceIp}) : super(key: key);

  @override
  _PackageManagerScreenState createState() => _PackageManagerScreenState();
}

class _PackageManagerScreenState extends State<PackageManagerScreen> {
  String? zigbeeMode;

  @override
  void initState() {
    super.initState();
    _fetchZigbeeInfo();
  }

  Future<void> _fetchZigbeeInfo() async {
    try {
      final mode = await HttpService().fetchZigbeeInfo();
      setState(() {
        zigbeeMode = mode;
      });
    } catch (e) {
      setState(() {
        zigbeeMode = null;
      });
    }
  }

  Future<void> _sendZigbeeCommand(String action) async {
    try {
      await HttpService().sendZigbeeCommand(action);
    } catch (e) {
      // Handle error if necessary
    }
  }

  Widget _buildPackageCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('HomeAssistant',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.swap_horiz, color: zigbeeMode == 'z2m' || zigbeeMode == null ? Colors.blue : Colors.grey),
            title: Text('Switch ZHA Mode',
                style: TextStyle(color: zigbeeMode == 'z2m' || zigbeeMode == null ? Colors.blue : Colors.grey)),
            trailing: zigbeeMode == 'zha'
                ? null
                : IconButton(
                    icon: Icon(Icons.arrow_forward_ios, color: Colors.blue),
                    onPressed: () => _sendZigbeeCommand('zha'),
                  ),
          ),
          ListTile(
            leading: Icon(Icons.swap_horiz, color: zigbeeMode == 'zha' || zigbeeMode == null ? Colors.blue : Colors.grey),
            title: Text('Switch Z2M Mode',
                style: TextStyle(color: zigbeeMode == 'zha' || zigbeeMode == null ? Colors.blue : Colors.grey)),
            trailing: zigbeeMode == 'z2m'
                ? null
                : IconButton(
                    icon: Icon(Icons.arrow_forward_ios, color: Colors.blue),
                    onPressed: () => _sendZigbeeCommand('z2m'),
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
        title: const Text('Package Manager'),
      ),
      body: Column(
        children: [
          _buildPackageCard(),
        ],
      ),
    );
  }
}
