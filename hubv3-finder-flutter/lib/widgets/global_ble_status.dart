import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import 'dart:async';

class GlobalBleStatus extends StatefulWidget {
  final bool showIcon;
  final bool showText;
  final double iconSize;
  final double fontSize;
  
  const GlobalBleStatus({
    Key? key,
    this.showIcon = true,
    this.showText = true,
    this.iconSize = 20,
    this.fontSize = 12,
  }) : super(key: key);

  @override
  State<GlobalBleStatus> createState() => _GlobalBleStatusState();
}

class _GlobalBleStatusState extends State<GlobalBleStatus> {
  late StreamSubscription<bool> _connectionSubscription;
  late StreamSubscription<String> _statusSubscription;
  bool _isConnected = false;
  String _status = 'Disconnected';

  @override
  void initState() {
    super.initState();
    
    // Initialize with current state
    _isConnected = BleService.globalIsConnected;
    _status = BleService.globalConnectionStatus;
    
    // Listen to connection state changes
    _connectionSubscription = BleService.globalConnectionStateStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isConnected = isConnected;
        });
      }
    });
    
    // Listen to status changes
    _statusSubscription = BleService.globalConnectionStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription.cancel();
    _statusSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showIcon) ...[
          Icon(
            _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: _isConnected ? Colors.green : Colors.red,
            size: widget.iconSize,
          ),
          if (widget.showText) const SizedBox(width: 4),
        ],
        if (widget.showText)
          Text(
            _status,
            style: TextStyle(
              color: _isConnected ? Colors.green : Colors.red,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

class GlobalBleStatusCard extends StatelessWidget {
  const GlobalBleStatusCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 8),
            const Text('BLE Status: ', style: TextStyle(fontSize: 14)),
            const GlobalBleStatus(showIcon: true, showText: true),
          ],
        ),
      ),
    );
  }
} 