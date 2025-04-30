import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleDevice {
  final String name;
  final String id;
  final int rssi;
  final BluetoothDevice? device; // Store reference to the actual BluetoothDevice
  final String? ipAddress; // IP address extracted from manufacturer data

  BleDevice({
    required this.name,
    required this.id,
    required this.rssi,
    this.device,
    this.ipAddress,
  });

  @override
  String toString() {
    return 'BleDevice{name: $name, id: $id, rssi: $rssi, ipAddress: $ipAddress}';
  }
}
