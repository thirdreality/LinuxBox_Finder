import 'package:flutter/material.dart';
import 'screens/device_scan_screen.dart';
import 'screens/device_control_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThirdReality Hub Finder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routes: {
        '/': (context) => const DeviceScanScreen(),
        '/device_control': (context) => const DeviceControlScreen(),
      },
      initialRoute: '/',
    );
  }
}
