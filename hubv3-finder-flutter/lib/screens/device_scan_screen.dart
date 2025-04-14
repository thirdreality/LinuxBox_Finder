import 'package:flutter/material.dart';
import '../models/ble_device.dart';
import '../services/ble_service.dart';

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({Key? key}) : super(key: key);

  @override
  _DeviceScanScreenState createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final BleService _bleService = BleService();
  List<BleDevice> _devices = [];
  bool _isScanning = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeBle();
  }

  Future<void> _initializeBle() async {
    final initialized = await _bleService.initialize();
    setState(() {
      _isInitialized = initialized;
    });

    if (_isInitialized) {
      _startScan();
      _bleService.deviceStream.listen((devices) {
        setState(() {
          _devices = devices;
        });
      });
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
    });
    
    await _bleService.startScan();
    
    setState(() {
      _isScanning = false;
    });
  }

  @override
  void dispose() {
    // No need to call stopScan explicitly as it's handled internally
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ThirdReality Hub Finder'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: !_isInitialized
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.bluetooth_disabled, size: 48, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    'Bluetooth not available or permissions not granted',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _startScan,
              child: _buildDeviceList(),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isScanning ? null : _startScan,
        child: _isScanning
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.refresh),
        tooltip: 'Scan for devices',
      ),
    );
  }

  Widget _buildDeviceList() {
    if (_devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isScanning
                ? const CircularProgressIndicator()
                : const Icon(Icons.bluetooth_searching, size: 48),
            const SizedBox(height: 16),
            Text(
              _isScanning
                  ? 'Scanning for devices...'
                  : 'No devices found. Pull to refresh or tap the button to scan again.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: Icon(
              Icons.bluetooth,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(device.name.isEmpty ? 'Unknown Device' : device.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ID: ${device.id}'),
                // MAC address is no longer in the device model
                Text('Signal: ${device.rssi} dBm'),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () async {
                // Show connecting dialog
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const AlertDialog(
                    title: Text('Connecting'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Connecting to device...'),
                      ],
                    ),
                  ),
                );

                // Attempt to connect
                try {
                  await _bleService.connectToDevice(device.id);
                  
                  // Dismiss the dialog
                  Navigator.pop(context);
                  
                  // If we get here, connection was successful
                  // Navigate to the device control screen
                  Navigator.pushNamed(context, '/device_control');
                } catch (e) {
                  // Dismiss the dialog
                  Navigator.pop(context);
                  
                  // Show error message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to connect: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Connect'),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}
