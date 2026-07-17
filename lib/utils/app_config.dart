import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const double officeLat = 33.717810797788445;
  static const double officeLng = 73.07266545222373;
  static const String officeIP = '203.101.190.122';
  static const String allowedDomain = 'gmail.com';
  static String get googleServerClientId =>
      dotenv.env['GOOGLE_SERVER_CLIENT_ID'] ??
      '1011764140696-f11ro7v81riu3n56m1derfmiasf7c5up.apps.googleusercontent.com';

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

  // /// FCM Server Key (Legacy Key) from Firebase Console -> Project Settings -> Cloud Messaging.
  // /// Used for sending push notifications directly from the app on the free Spark plan.
  // static const String fcmServerKey = 'YOUR_FCM_SERVER_KEY';
}
