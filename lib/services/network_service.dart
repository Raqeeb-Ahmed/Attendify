import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_config.dart';

class NetworkService {
  final NetworkInfo _networkInfo = NetworkInfo();

  Future<String?> getPublicIP() async {
    try {
      final response = await http.get(Uri.parse('https://api.ipify.org?format=json'));
      if (response.statusCode == 200) {
        return json.decode(response.body)['ip'];
      }
    } catch (e) {
      debugPrint("Error getting public IP: $e");
    }
    return null;
  }

  Future<Map<String, String?>> getWifiInfo() async {
    if (kIsWeb) return {'name': null, 'bssid': null};
    try {
      final name = await _networkInfo.getWifiName();
      final bssid = await _networkInfo.getWifiBSSID();
      return {'name': name, 'bssid': bssid};
    } catch (e) {
      debugPrint("Error getting wifi info: $e");
      return {'name': null, 'bssid': null};
    }
  }

  bool isOfficeIP(String? currentIP) {
    return currentIP == AppConfig.officeIP;
  }
}
