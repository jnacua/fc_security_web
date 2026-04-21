import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart'; // ✅ Required for opening the new tab
import '../main.dart';

class ApiService {
  static const String baseUrl = "https://fcapp-backend.onrender.com/api";
  static String? _token;
  static IO.Socket? _socket;

  // ================= GLOBAL SOCKET & PANIC ALERTS =================

  static IO.Socket initSocket() {
    if (_socket != null) return _socket!;

    _socket = IO.io(
      'https://fcapp-backend.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) => debugPrint('✅ Security Socket Connected'));
    _socket!.onConnectError(
      (err) => debugPrint('❌ Socket Connect Error: $err'),
    );
    _socket!.onDisconnect((_) => debugPrint('❌ Security Socket Disconnected'));

    _socket!.on('emergency-alert', (data) {
      debugPrint("🚨 EMERGENCY EVENT RECEIVED: $data");
      _showGlobalPanicDialog(data);
    });

    return _socket!;
  }

  // ✅ THIS FUNCTION OPENS THE NEW TAB
  static Future<void> _launchMap(double lat, double lng) async {
    // Correct Google Maps URL format for coordinates
    final String googleMapsUrl =
        "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    final Uri url = Uri.parse(googleMapsUrl);

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint("Could not launch $googleMapsUrl");
    }
  }

  static void _showGlobalPanicDialog(dynamic data) {
    final context = globalNavigatorKey.currentContext;
    if (context == null) return;

    final double lat =
        double.tryParse(data['latitude']?.toString() ?? '14.5995') ?? 14.5995;
    final double lng =
        double.tryParse(data['longitude']?.toString() ?? '120.9842') ??
        120.9842;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.red, width: 8),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 20),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.report_problem, color: Colors.red, size: 100),
                const SizedBox(height: 20),
                const Text(
                  "DISTRESS SIGNAL",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.red,
                  ),
                ),
                const Divider(height: 40, thickness: 2),
                Text(
                  "RESIDENT: ${data['name'] ?? 'UNKNOWN'}".toUpperCase(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "LOCATION: ${data['blockLot'] ?? 'UNKNOWN'}",
                  style: const TextStyle(fontSize: 20, color: Colors.black87),
                ),
                const SizedBox(height: 40),

                // ✅ BUTTON TO GO TO THE MAP
                ElevatedButton.icon(
                  onPressed: () => _launchMap(lat, lng),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text("VIEW LOCATION ON FULL MAP"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade900,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text(
                    "CLOSE ALERT",
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================= VEHICLE SCANNING METHODS =================

  // ✅ NEW: Verify Resident Vehicle QR (UPDATED to match backend endpoint)
  static Future<Map<String, dynamic>?> verifyVehicleQR(String qrData) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/vehicles/scan/${Uri.encodeComponent(qrData)}'),
        headers: await _getHeaders(),
      );

      debugPrint("📡 Vehicle Scan Response Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        debugPrint("✅ Vehicle verified successfully: ${responseData['data']}");
        return responseData;
      } else if (response.statusCode == 403) {
        final Map<String, dynamic> errorData = jsonDecode(response.body);
        debugPrint("❌ Vehicle not approved: ${errorData['message']}");
        return {
          'success': false,
          'message': errorData['message'],
          'status': errorData['status'],
        };
      } else if (response.statusCode == 404) {
        debugPrint("❌ Vehicle not found");
        return {'success': false, 'message': 'Vehicle not found in the system'};
      } else {
        debugPrint("❌ Vehicle verification failed: ${response.statusCode}");
        return {'success': false, 'message': 'Failed to verify vehicle'};
      }
    } catch (e) {
      debugPrint("❌ Vehicle Scan Error: $e");
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  // ✅ NEW: Search vehicle by plate number (manual entry)
  static Future<Map<String, dynamic>?> searchVehicleByPlate(
    String licenseNumber,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/vehicles/search/${Uri.encodeComponent(licenseNumber)}',
        ),
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint("❌ Vehicle Search Error: $e");
      return null;
    }
  }

  // ================= LOG FETCHING METHODS =================

  // ✅ NEW: Fetch all consolidated security logs (Visitors + Panics)
  static Future<List<dynamic>> getAllSecurityLogs() async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/logs/all',
        ), // This endpoint should combine your visitor and panic data
        headers: await _getHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint("❌ Failed to fetch logs: ${response.statusCode}");
      return [];
    } catch (e) {
      debugPrint("❌ Log Fetch Error: $e");
      return [];
    }
  }

  // ✅ NEW: Fetch Real-time Dashboard Statistics
  static Future<Map<String, dynamic>> getSecurityDashboardStats() async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/logs/security-stats',
        ), // Endpoint for the 4 stat cards
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {"incoming": 0, "outgoing": 0, "visitors": 0, "panics": 0};
    } catch (e) {
      debugPrint("❌ Dashboard Stats Error: $e");
      return {"incoming": 0, "outgoing": 0, "visitors": 0, "panics": 0};
    }
  }

  // ================= STANDARD HTTP METHODS =================

  static Future<String?> _getToken() async {
    if (_token != null) return _token;
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('jwt_token') ?? prefs.getString('auth_token');
    return _token;
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<bool> logVisitorEntry(Map<String, String> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/visitor/log-entry'),
        headers: await _getHeaders(),
        body: jsonEncode(data),
      );
      return response.statusCode == 201;
    } catch (e) {
      debugPrint("❌ Visitor Log Exception: $e");
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getLatestSecurityScan() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/security/latest-scan'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<void> clearScanSession() async {
    try {
      await http.post(
        Uri.parse('$baseUrl/security/clear-scan'),
        headers: await _getHeaders(),
      );
    } catch (e) {
      debugPrint("Clear Error: $e");
    }
  }

  static Future<Map<String, dynamic>?> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', data['token']);
        await prefs.setString('auth_token', data['token']);
        _token = data['token'];
        return data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
