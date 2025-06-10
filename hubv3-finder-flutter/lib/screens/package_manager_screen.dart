import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/task_info.dart';
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
  final ValueNotifier<int> _progressNotifier = ValueNotifier(0);
  final ValueNotifier<String> _messageNotifier = ValueNotifier("Starting...");

  @override
  void initState() {
    super.initState();
    _fetchZigbeeInfo();
  }

  @override
  void dispose() {
    _progressNotifier.dispose();
    _messageNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchZigbeeInfo() async {
    try {
      final mode = await HttpService().fetchZigbeeInfo();
      if (mounted) {
        setState(() {
          zigbeeMode = mode;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          zigbeeMode = null;
        });
      }
    }
  }

  Future<void> _trackTaskProgress(String taskName) async {
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Processing...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _progressNotifier,
                builder: (_, progress, __) {
                  return LinearProgressIndicator(value: progress / 100.0);
                },
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: _messageNotifier,
                builder: (_, message, __) {
                  return Text(message);
                },
              ),
            ],
          ),
        );
      },
    );

    timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final taskInfo = await HttpService().getTaskInfo(taskName);
        _progressNotifier.value = taskInfo.data.progress;
        _messageNotifier.value = taskInfo.data.message;

        if (taskInfo.data.progress >= 100 || taskInfo.data.status == 'success' || taskInfo.data.status == 'failed') {
          timer.cancel();
          Navigator.of(context).pop(); // Close dialog
          if (taskName == 'zigbee') {
            _fetchZigbeeInfo();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${taskInfo.data.subTask} ${taskInfo.data.status}!')),
          );
        }
      } catch (e) {
        timer.cancel();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $e')),
        );
      }
    });
  }

  Future<void> _sendZigbeeCommand(String action) async {
    try {
      await HttpService().sendZigbeeCommand(action);
      if (action == 'scan') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan command sent successfully!')),
        );
      } else {
        _progressNotifier.value = 0;
        _messageNotifier.value = "Switching Zigbee mode...";
        _trackTaskProgress('zigbee');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send command: $e')),
      );
    }
  }

  Future<void> _sendSettingCommand(String action) async {
    try {
      await HttpService().sendSettingCommand('setting', action: action);
      _progressNotifier.value = 0;
      _messageNotifier.value = "Processing setting command...";
      _trackTaskProgress('setting');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send command: $e')),
      );
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
            child: Row(
              children: [
                Icon(Icons.language), // Icon for Zigbee
                SizedBox(width: 8),
                Text('Zigbee',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.swap_horiz, color: zigbeeMode == 'z2m' || zigbeeMode == null ? Colors.blue : Colors.grey),
            title: Text('Switch ZHA Mode',
                style: TextStyle(color: zigbeeMode == 'z2m' || zigbeeMode == null ? Colors.blue : Colors.grey)),
            trailing: zigbeeMode == 'zha'
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.blue),
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
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.blue),
                    onPressed: () => _sendZigbeeCommand('z2m'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermitJoinCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.search, color: Colors.blue),
                SizedBox(width: 8),
                Text('Permit Join',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Scan'),
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward_ios, color: Colors.blue),
              onPressed: () {
                _sendZigbeeCommand('scan');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.settings), // Icon for Setting
                SizedBox(width: 8),
                Text('Setting',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Backup'),
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward_ios),
              onPressed: () {
                _sendSettingCommand('backup');
              },
            ),
          ),
          ListTile(
            title: const Text('Restore'),
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward_ios),
              onPressed: () {
                _sendSettingCommand('restore');
              },
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
        title: Text(widget.packageId),
      ),
      body: ListView(
        children: [
          _buildPackageCard(),
          _buildPermitJoinCard(),
          _buildSettingCard(),
        ],
      ),
    );
  }
}

