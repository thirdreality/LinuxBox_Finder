# LinuxBox Finder

This project consists of two main components:

## 1. hubv3-finder-flutter

`hubv3-finder-flutter` is a mobile application designed to operate on both Android and iOS platforms. It leverages Bluetooth Low Energy (BLE) to interact with the `hubv3-gatt-server` running on HubV3. The app provides a user-friendly interface to send commands and manage the server's operations seamlessly.

### Features:
- Cross-platform compatibility (Android & iOS)
- Easy-to-use interface for interacting with the HubV3 server
- Secure BLE communication

## 2. hubv3-gatt-server

`hubv3-gatt-server` is a Bluetooth GATT server that runs on Linux, specifically on HubV3 devices. It is responsible for processing commands received from the `hubv3-finder-flutter` mobile app. The server facilitates several crucial operations such as:

- Configuring WiFi settings
- Monitoring WiFi status
- Restarting the device
- And more...

### Highlights:
- Efficient command handling
- Robust and scalable server design
- Seamless integration with the mobile app

---

Feel free to customize the sections further depending on additional details or specific project requirements you might have.




