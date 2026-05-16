class AppConfig {
  static const double officeLat = 33.717810797788445;
  static const double officeLng = 73.07266545222373;
  static const String officeIP = '203.101.190.122';
  static const String allowedDomain = 'gmail.com';
  static const String googleServerClientId =
      '477847847076-02hr552ar5snhost8f3fslv0bp23q13a.apps.googleusercontent.com';

  /// Office WiFi SSID names for auto check-in detection
  /// Add your office WiFi network names here (case insensitive)
  /// Example: ['Office-WiFi', 'Company-Network', 'Corp-5G']
  static const List<String> officeWifiNames = [
    // Your office WiFi SSIDs
    'HUAWEI 73Np-5P',
    'StormFiber-ACF0-5G',
  ];
}
