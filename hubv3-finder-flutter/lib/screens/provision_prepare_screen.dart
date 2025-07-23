import 'package:flutter/material.dart';
import 'device_scan_screen.dart';

class ProvisionPrepareScreen extends StatelessWidget {
  const ProvisionPrepareScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prepare Wifi Provision'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Card(
              elevation: 4.0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
                child: const Text(
                  'Please double-click the button on the device to confirm the LED starts flashing yellow.',
                  style: TextStyle(fontSize: 16.0),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            FlashingLed(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const DeviceScanScreen()),
                      );
                    },
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FlashingLed extends StatefulWidget {
  const FlashingLed({Key? key}) : super(key: key);

  @override
  _FlashingLedState createState() => _FlashingLedState();
}

class _FlashingLedState extends State<FlashingLed> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 360,
      child: Stack(
        children: [
          Image.asset(
            'assets/images/linuxbox-config.png',
            width: 260,
            height: 360,
            fit: BoxFit.cover,
          ),
          Positioned(
            left: 80,
            top: 70,
            child: FadeTransition(
              opacity: _controller,
              child: Container(
                width: 32.0,
                height: 32.0,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.yellow,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
