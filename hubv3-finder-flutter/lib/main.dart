import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/package_manager_screen.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3D6ADE)),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3D6ADE),
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      routes: {
        '/': (context) => const HomeScreen(),
        '/packageManager': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, String>;
          return PackageManagerScreen(
            packageId: args['packageId']!,
            deviceIp: args['deviceIp']!,
          );
        },
      },
      initialRoute: '/',
    );
  }
}
