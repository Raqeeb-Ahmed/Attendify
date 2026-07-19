import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const double officeLat = 33.717810797788445;
  static const double officeLng = 73.07266545222373;
  static const String officeIP = '203.101.190.122';
  static const String allowedDomain = 'gmail.com';
  static String get googleServerClientId =>
      dotenv.env['GOOGLE_SERVER_CLIENT_ID'] ??
      '1011764140696-948gaer6e9imdg4n0p12d22a3ctmnth9.apps.googleusercontent.com';

  /// Office WiFi SSID names for auto check-in detection
  /// Add your office WiFi network names here (case insensitive)
  /// Example: ['Office-WiFi', 'Company-Network', 'Corp-5G']
  static const List<String> officeWifiNames = [
    // Your office WiFi SSIDs
    'OS',
    'OS-5G',
    'Data X',
    'O.S TRAVEL 5G',
    'O.S TRAVEL',
  ];
}
