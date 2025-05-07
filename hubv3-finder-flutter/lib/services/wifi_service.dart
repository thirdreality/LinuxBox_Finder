import 'dart:async';

import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../models/wifi_network.dart';

class WiFiService {
  // Singleton instance
  static final WiFiService _instance = WiFiService._internal();
  factory WiFiService() => _instance;
  WiFiService._internal();

  final StreamController<List<WiFiNetwork>> _wifiNetworksController = StreamController<List<WiFiNetwork>>.broadcast();
  Stream<List<WiFiNetwork>> get wifiNetworksStream => _wifiNetworksController.stream;

  List<WiFiNetwork> _wifiNetworks = [];
  bool _isScanning = false;
  Timer? _scanTimer;

  // Initialize WiFi service
  Future<bool> initialize() async {
    // Request location permission (required for WiFi scanning)
    final status = await Permission.location.request();
    if (!status.isGranted) {
      return false;
    }

    // Check if WiFi scanning is available
    final canScan = await WiFiScan.instance.canStartScan();
    if (canScan != CanStartScan.yes) {
      return false;
    }

    return true;
  }

  // Start periodic WiFi scanning
  Future<bool> startWiFiScan() async {
    if (_isScanning) return true;

    final canStartScan = await WiFiScan.instance.canStartScan();
    if (canStartScan != CanStartScan.yes) {
      return false;
    }

    _isScanning = true;

    // Start periodic scanning
    _scanTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _scanOnce();
    });

    // Immediately perform the first scan
    await _scanOnce();
    return true;
  }

  // Perform a single WiFi scan
  Future<void> _scanOnce() async {
    try {
      // Start a WiFi scan
      final result = await WiFiScan.instance.startScan();
      if (result != true) {
        print('Failed to start WiFi scan: $result');
        return;
      }

      // Wait for scan results
      await Future.delayed(const Duration(seconds: 2));

      // Get scan results
      final results = await WiFiScan.instance.getScannedResults();

      // Convert to our model
      _wifiNetworks = results.map((accessPoint) {
        return WiFiNetwork(
          ssid: accessPoint.ssid,
          signalStrength: accessPoint.level,
          isSecured: accessPoint.capabilities.contains('WPA') || 
                    accessPoint.capabilities.contains('WEP'),
          bssid: accessPoint.bssid,
        );
      }).toList();

      // Sort by signal strength
      _wifiNetworks.sort((a, b) => b.signalStrength.compareTo(a.signalStrength));

      // Notify listeners
      _wifiNetworksController.add(_wifiNetworks);
    } catch (e) {
      print('Error scanning WiFi networks: $e');
    }
  }

  // Stop WiFi scanning
  void stopWiFiScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isScanning = false;
  }

  // Get the current list of WiFi networks
  List<WiFiNetwork> getNetworks() {
    return _wifiNetworks;
  }

  // Dispose resources
  void dispose() {
    stopWiFiScan();
    _wifiNetworksController.close();
  }
}
