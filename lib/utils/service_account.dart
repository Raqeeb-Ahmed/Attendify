import 'package:flutter_dotenv/flutter_dotenv.dart';

class ServiceAccountConfig {
  /// Load the Firebase Service Account credentials dynamically from the loaded .env file.
  static Map<String, dynamic> get jsonCredentials => {
        "type": dotenv.env['FCM_TYPE'] ?? 'service_account',
        "project_id": dotenv.env['FCM_PROJECT_ID'] ?? '',
        "private_key_id": dotenv.env['FCM_PRIVATE_KEY_ID'] ?? '',
        "private_key": (dotenv.env['FCM_PRIVATE_KEY'] ?? '').replaceAll(r'\n', '\n'),
        "client_email": dotenv.env['FCM_CLIENT_EMAIL'] ?? '',
        "client_id": dotenv.env['FCM_CLIENT_ID'] ?? '',
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url": dotenv.env['FCM_CLIENT_CERT_URL'] ?? '',
        "universe_domain": "googleapis.com",
      };
}
