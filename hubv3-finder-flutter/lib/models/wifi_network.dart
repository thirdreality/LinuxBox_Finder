class WiFiNetwork {
  final String ssid;
  final int signalStrength;
  final bool isSecured;
  final String? bssid;

  WiFiNetwork({
    required this.ssid,
    required this.signalStrength,
    required this.isSecured,
    this.bssid,
  });

  @override
  String toString() {
    return 'WiFiNetwork{ssid: $ssid, signalStrength: $signalStrength, isSecured: $isSecured, bssid: $bssid}';
  }
}
