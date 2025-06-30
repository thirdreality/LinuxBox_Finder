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
  Map<String, dynamic>? channelInfo;
  bool loading = false;
  String? error;
  final ValueNotifier<int> _progressNotifier = ValueNotifier(0);
  final ValueNotifier<String> _messageNotifier = ValueNotifier("Starting...");

  @override
  void initState() {
    super.initState();
    _fetchChannelInfo();
  }

  @override
  void dispose() {
    _progressNotifier.dispose();
    _messageNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchChannelInfo() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final info = await HttpService().fetchChannelInfo();
      print('fetchChannelInfo result: ' + info.toString());
      if (mounted) {
        setState(() {
          channelInfo = info;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
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
            _fetchChannelInfo();
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

  Future<void> _sendSettingCommand(String action, {String file = ""}) async {
    try {
      await HttpService().sendSettingCommand('setting', action: action, file: file);
      _progressNotifier.value = 0;
      _messageNotifier.value = "Processing setting command...";
      _trackTaskProgress('setting');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send command: $e')),
      );
    }
  }

  Future<void> _handleRestore() async {
    try {
      final response = await HttpService().getSettingInfo();
      final data = jsonDecode(response);
      final List<dynamic> backups = data['backups'] ?? [];
      
      if (backups.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No backup files available')),
        );
        return;
      }
      
      if (backups.length == 1) {
        _sendSettingCommand('restore', file: backups[0].toString());
        return;
      }
      
      // Show backup selection dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text(
              'Select backups:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 16.0),
            contentPadding: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 0),
            content: SizedBox(
              width: double.maxFinite,
              height: (backups.length * 48.0 + (backups.length + 1) * 16.0).clamp(120.0, 400.0),
              child: Column(
                children: [
                  const Divider(),
                  Expanded(
                    child: ListView.separated(
                      itemCount: backups.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final backup = backups[index].toString();
                        return SizedBox(
                          height: 48.0,
                          child: ListTile(
                            leading: const Icon(Icons.backup, color: Colors.blue, size: 20),
                            title: Text(
                              backup,
                              style: const TextStyle(fontSize: 14),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                            dense: false,
                            onTap: () {
                              Navigator.of(context).pop();
                              _sendSettingCommand('restore', file: backup);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  foregroundColor: Colors.black87,
                ),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get backup info: $e')),
      );
    }
  }

  Future<void> _handleChannelSwitch(String type, int currentChannel) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: Text('Select $type channel'),
          children: [15, 20, 25].map((ch) => SimpleDialogOption(
            child: Row(
              children: [
                if (ch == currentChannel) Icon(Icons.check, color: Colors.blue),
                if (ch == currentChannel) SizedBox(width: 8),
                Text('Channel $ch', style: TextStyle(fontSize: 20)),
              ],
            ),
            onPressed: () => Navigator.pop(context, ch),
          )).toList(),
        );
      },
    );
    if (selected != null && selected != currentChannel) {
      try {
        // 显示loading对话框
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
        print('sendChannelCommand: type=$type, selected=$selected');
        final result = await HttpService().sendChannelCommand(type, selected);
        print('sendChannelCommand result: ' + result.toString());
        if (type == 'zigbee') {
          final mode = channelInfo?["zigbee_mode"] ?? "none";
          if (mode == 'z2m') {
            Navigator.of(context).pop(); // 关闭loading
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Notice'),
                content: const Text('Zigbee will reboot to switch channel. Please wait 2~3 minutes before refreshing.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else if (mode == 'zha') {
            Navigator.of(context).pop(); // 关闭loading
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Notice'),
                content: Text('Zigbee channel has been switched to $selected.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          } else {
            Navigator.of(context).pop(); // 关闭loading
          }
          await _fetchChannelInfo();
        } else if (type == 'thread') {
          Navigator.of(context).pop(); // 关闭loading
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Notice'),
              content: const Text('Thread device needs about 5 minutes to complete channel switching. Please refresh after 5 minutes.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          Navigator.of(context).pop(); // 关闭loading
        }
      } catch (e) {
        Navigator.of(context).pop(); // 关闭loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to switch $type channel: $e')),
        );
      }
    }
  }

  Widget _buildZigbeeCard() {
    final mode = channelInfo?["zigbee_mode"] ?? "none";
    final zigbeeChannel = channelInfo?["zigbee"] ?? 0;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.language),
                SizedBox(width: 8),
                Text('Zigbee', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Switch ZHA mode
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.swap_horiz, color: mode == 'zha' ? Colors.grey : Colors.blue),
            title: Text('Switch ZHA Mode', style: TextStyle(color: mode == 'zha' ? Colors.grey : Colors.blue)),
            trailing: mode == 'zha'
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.blue),
                    onPressed: () => _sendZigbeeCommand('zha'),
                  ),
          ),
          // Switch Z2M mode
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.swap_horiz, color: mode == 'z2m' ? Colors.grey : Colors.blue),
            title: Text('Switch Z2M Mode', style: TextStyle(color: mode == 'z2m' ? Colors.grey : Colors.blue)),
            trailing: mode == 'z2m'
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.blue),
                    onPressed: () => _sendZigbeeCommand('z2m'),
                  ),
          ),
          const Divider(),
          // Permit Join
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.search, color: Colors.blue),
            title: const Text('Permit Join'),
            trailing: IconButton(
              icon: const Icon(Icons.arrow_forward_ios, color: Colors.blue),
              onPressed: () {
                _sendZigbeeCommand('scan');
              },
            ),
          ),
          const Divider(),
          // Channel Switch
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.settings_input_antenna, color: Colors.orange),
            title: const Text('Channel switch'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$zigbeeChannel', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, color: Colors.blue),
                const SizedBox(width: 12),
              ],
            ),
            onTap: () => _handleChannelSwitch('zigbee', zigbeeChannel),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadCard() {
    final threadChannel = channelInfo?["thread"] ?? 0;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(Icons.device_hub, color: Colors.green),
                SizedBox(width: 8),
                Text('Thread', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.settings_input_antenna, color: Colors.orange),
            title: const Text('Channel switch'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$threadChannel', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, color: Colors.blue),
                const SizedBox(width: 12),
              ],
            ),
            onTap: () => _handleChannelSwitch('thread', threadChannel),
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
                Text('Setting', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.backup, color: Colors.blue),
            title: const Text('Backup'),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.blue),
            onTap: () {
              _sendSettingCommand('backup');
            },
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const Icon(Icons.restore, color: Colors.green),
            title: const Text('Restore'),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.blue),
            onTap: () {
              _handleRestore();
            },
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loading ? null : _fetchChannelInfo,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text('Error: ' + error!))
              : ListView(
                  children: [
                    if (channelInfo != null) ...[
                      _buildZigbeeCard(),
                      _buildThreadCard(),
                    ],
                    _buildSettingCard(),
                  ],
                ),
    );
  }
}

