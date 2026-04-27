import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';

class ApiService {
  static const String baseUrl = "https://fcapp-backend.onrender.com/api";
  static String? _token;
  static IO.Socket? _socket;
  static Timer? _heartbeatTimer;
  static Timer? _pollingTimer;
  static int _reconnectAttempts = 0;
  static final int maxReconnectAttempts = 20;
  static bool _isSocketInitialized = false;

  // Track processed alerts to prevent duplicates/spamming
  static final Set<String> _processedAlertIds = {};
  static String? _currentActiveAlertId;
  static bool _isDialogShowing = false;
  static Timer? _cleanupTimer;

  // ================= GLOBAL SOCKET & PANIC ALERTS =================

  static void initSocketAndListen() {
    if (_isSocketInitialized) return;
    _isSocketInitialized = true;

    initSocket();
    _startEmergencyPolling();
    _startCleanupTimer();
  }

  static void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_processedAlertIds.length > 50) {
        final idsToRemove = _processedAlertIds.take(20).toList();
        for (var id in idsToRemove) {
          _processedAlertIds.remove(id);
        }
      }
      debugPrint(
        "🧹 Cleaned up processed alerts cache. Size: ${_processedAlertIds.length}",
      );
    });
  }

  static IO.Socket initSocket() {
    if (_socket != null && _socket!.connected) {
      debugPrint('✅ Socket already connected');
      return _socket!;
    }

    if (_socket != null) {
      _socket!.disconnect();
      _socket!.clearListeners();
    }

    debugPrint('🔌 Initializing socket connection...');

    _socket = IO.io(
      'https://fcapp-backend.onrender.com',
      IO.OptionBuilder()
          .setTransports(['polling', 'websocket'])
          .setPath('/socket.io')
          .enableAutoConnect()
          .setReconnectionAttempts(maxReconnectAttempts)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(15000)
          .setTimeout(40000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('✅ Security Socket Connected! ID: ${_socket!.id}');
      _reconnectAttempts = 0;
      _startHeartbeat();
    });

    _socket!.onConnectError((err) {
      debugPrint('❌ Socket Connect Error: $err');
      _reconnectAttempts++;
    });

    _socket!.onError((err) {
      debugPrint('⚠️ Socket Error: $err');
    });

    _socket!.onDisconnect((_) {
      debugPrint('❌ Security Socket Disconnected');
      _stopHeartbeat();
    });

    _socket!.on('emergency-alert', (data) {
      debugPrint("🚨 EMERGENCY EVENT RECEIVED!");
      debugPrint("📦 Data: $data");
      _handleEmergencyAlert(data);
    });

    _socket!.on('panic-resolved', (data) {
      debugPrint("✅ Panic resolved: $data");
      final resolvedId = data['id'] ?? data['_id'];
      if (resolvedId != null && _currentActiveAlertId == resolvedId) {
        _currentActiveAlertId = null;
        _isDialogShowing = false;
      }
    });

    _socket!.on('pong', (_) {
      debugPrint('💓 Heartbeat received');
    });

    _socket!.connect();
    debugPrint('🔌 Socket connect() called');

    return _socket!;
  }

  static void _handleEmergencyAlert(dynamic data) {
    final alertId =
        data['id'] ??
        data['_id'] ??
        '${data['name']}_${data['blockLot']}_${DateTime.now().millisecondsSinceEpoch}';

    if (_processedAlertIds.contains(alertId)) {
      debugPrint("⚠️ Duplicate alert prevented: $alertId");
      return;
    }

    if (_currentActiveAlertId == alertId && _isDialogShowing) {
      debugPrint("⚠️ Alert already showing, skipping duplicate");
      return;
    }

    _processedAlertIds.add(alertId);
    _currentActiveAlertId = alertId;
    _showGlobalPanicDialog(data);
  }

  static void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('ping');
        debugPrint('💓 Heartbeat sent');
      }
    });
  }

  static void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  static void _startEmergencyPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final token = await _getToken();
        if (token == null) return;

        final response = await http
            .get(
              Uri.parse('$baseUrl/panic/active'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
            )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final List<dynamic> activePanics = jsonDecode(response.body);
          debugPrint("📊 Polling: Found ${activePanics.length} active panics");

          if (activePanics.isEmpty) {
            if (_currentActiveAlertId != null) {
              debugPrint("✅ No active panics, resetting alert state");
              _currentActiveAlertId = null;
              _isDialogShowing = false;
            }
            return;
          }

          final latestPanic = activePanics.first;
          final alertId = latestPanic['_id'] ?? latestPanic['id'];

          if (_processedAlertIds.contains(alertId)) {
            return;
          }

          if (_currentActiveAlertId == alertId && _isDialogShowing) {
            return;
          }

          _processedAlertIds.add(alertId);
          _currentActiveAlertId = alertId;

          _showGlobalPanicDialog({
            'id': alertId,
            'name': latestPanic['residentName'] ?? latestPanic['name'],
            'blockLot': latestPanic['blockLot'] ?? latestPanic['houseNo'],
            'latitude': latestPanic['location']?['latitude'],
            'longitude': latestPanic['location']?['longitude'],
            'emergencyType': latestPanic['emergencyType'],
            'status': 'ACTIVE',
          });
        }
      } catch (e) {
        // Silent fail
      }
    });
  }

  static void _stopEmergencyPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  static void disconnectSocket() {
    _stopHeartbeat();
    _stopEmergencyPolling();
    _cleanupTimer?.cancel();
    _socket?.disconnect();
    _socket?.clearListeners();
    _socket = null;
    _isSocketInitialized = false;
    _reconnectAttempts = 0;
    _processedAlertIds.clear();
    _currentActiveAlertId = null;
    _isDialogShowing = false;
    debugPrint('🔌 Socket manually disconnected');
  }

  static Future<void> _launchMap(double lat, double lng) async {
    final String googleMapsUrl =
        "https://www.google.com/maps/search/?api=1&query=$lat,$lng";
    final Uri url = Uri.parse(googleMapsUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      debugPrint("Could not launch $googleMapsUrl");
    }
  }

  // ✅ Helper function to get emergency type color
  static Color _getEmergencyColor(String type) {
    final lowerType = type.toLowerCase();
    if (lowerType.contains('medical') ||
        lowerType.contains('heart') ||
        lowerType.contains('stroke') ||
        lowerType.contains('bleeding') ||
        lowerType.contains('unconscious') ||
        lowerType.contains('seizure') ||
        lowerType.contains('difficulty breathing')) {
      return Colors.red;
    } else if (lowerType.contains('fire')) {
      return Colors.orange;
    } else if (lowerType.contains('security') ||
        lowerType.contains('theft') ||
        lowerType.contains('robbery') ||
        lowerType.contains('shooter') ||
        lowerType.contains('assault')) {
      return Colors.purple;
    } else if (lowerType.contains('accident') || lowerType.contains('car')) {
      return Colors.orange;
    } else if (lowerType.contains('natural') ||
        lowerType.contains('flood') ||
        lowerType.contains('earthquake') ||
        lowerType.contains('typhoon') ||
        lowerType.contains('storm')) {
      return Colors.blue;
    }
    return Colors.red;
  }

  // ✅ Helper function to get emergency type icon
  static IconData _getEmergencyIcon(String type) {
    final lowerType = type.toLowerCase();
    if (lowerType.contains('medical') ||
        lowerType.contains('heart') ||
        lowerType.contains('stroke')) {
      return Icons.local_hospital;
    } else if (lowerType.contains('fire')) {
      return Icons.fire_extinguisher;
    } else if (lowerType.contains('security') ||
        lowerType.contains('theft') ||
        lowerType.contains('shooter')) {
      return Icons.security;
    } else if (lowerType.contains('accident') || lowerType.contains('car')) {
      return Icons.car_crash;
    } else if (lowerType.contains('natural') || lowerType.contains('flood')) {
      return Icons.water_damage;
    } else if (lowerType.contains('earthquake')) {
      return Icons.terrain;
    } else if (lowerType.contains('typhoon')) {
      return Icons.cloud;
    } else if (lowerType.contains('child') ||
        lowerType.contains('elderly') ||
        lowerType.contains('missing')) {
      return Icons.person_search;
    }
    return Icons.warning_amber_rounded;
  }

  // ✅ UPDATED: Show global panic dialog with emergency type
  static void _showGlobalPanicDialog(dynamic data) {
    final context = globalNavigatorKey.currentContext;
    if (context == null) return;

    if (_isDialogShowing) {
      debugPrint("⚠️ Dialog already showing, skipping");
      return;
    }

    _isDialogShowing = true;

    final double lat =
        double.tryParse(data['latitude']?.toString() ?? '14.5995') ?? 14.5995;
    final double lng =
        double.tryParse(data['longitude']?.toString() ?? '120.9842') ??
        120.9842;

    // Get emergency type
    final String emergencyType = data['emergencyType'] ?? 'Emergency Alert';
    final Color emergencyColor = _getEmergencyColor(emergencyType);
    final IconData emergencyIcon = _getEmergencyIcon(emergencyType);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 550,
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
                const Icon(Icons.report_problem, color: Colors.red, size: 80),
                const SizedBox(height: 20),
                const Text(
                  "DISTRESS SIGNAL",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: Colors.red,
                  ),
                ),
                const Divider(height: 30, thickness: 2),

                // ✅ Emergency Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: emergencyColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: emergencyColor, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(emergencyIcon, color: emergencyColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        emergencyType.toUpperCase(),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: emergencyColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  "RESIDENT: ${data['name'] ?? data['residentName'] ?? 'UNKNOWN'}"
                      .toUpperCase(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  "LOCATION: ${data['blockLot'] ?? data['houseNo'] ?? 'UNKNOWN'}",
                  style: const TextStyle(fontSize: 18, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // ✅ Emergency Type Details Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: emergencyColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: emergencyColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(emergencyIcon, color: emergencyColor, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "EMERGENCY TYPE",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              emergencyType,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: emergencyColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                ElevatedButton.icon(
                  onPressed: () => _launchMap(lat, lng),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text("VIEW LOCATION ON FULL MAP"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade900,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _isDialogShowing = false;
                  },
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
    ).then((_) {
      _isDialogShowing = false;
    });
  }

  // ================= RESOLVE PANIC =================
  static Future<bool> resolvePanic(String panicId) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/panic/resolve/$panicId'),
        headers: await _getHeaders(),
      );
      debugPrint("📡 Resolve Panic Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        _processedAlertIds.remove(panicId);
        if (_currentActiveAlertId == panicId) {
          _currentActiveAlertId = null;
          _isDialogShowing = false;
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Resolve Panic Error: $e");
      return false;
    }
  }

  // ================= VEHICLE SCANNING METHODS =================

  static Future<Map<String, dynamic>?> verifyVehicleQR(String qrData) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/vehicles/scan/${Uri.encodeComponent(qrData)}'),
        headers: await _getHeaders(),
      );
      debugPrint("📡 Vehicle Scan Response Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        return responseData;
      } else if (response.statusCode == 403) {
        final Map<String, dynamic> errorData = jsonDecode(response.body);
        return {
          'success': false,
          'message': errorData['message'],
          'status': errorData['status'],
        };
      } else if (response.statusCode == 404) {
        return {'success': false, 'message': 'Vehicle not found in the system'};
      } else {
        return {'success': false, 'message': 'Failed to verify vehicle'};
      }
    } catch (e) {
      debugPrint("❌ Vehicle Scan Error: $e");
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

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

  static Future<List<dynamic>> getAllSecurityLogs() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/logs/all'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("📊 Fetched ${data is List ? data.length : 0} logs");
        return data;
      }
      debugPrint("❌ Failed to fetch logs: ${response.statusCode}");
      return [];
    } catch (e) {
      debugPrint("❌ Log Fetch Error: $e");
      return [];
    }
  }

  static Future<Map<String, dynamic>> getSecurityDashboardStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/logs/security-stats'),
        headers: await _getHeaders(),
      );

      debugPrint("📊 Dashboard Stats Response Status: ${response.statusCode}");
      debugPrint("📊 Dashboard Stats Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint("📊 Dashboard Stats Data: $data");

        return {
          'visitors': data['visitors'] ?? data['totalVisitors'] ?? 0,
          'visitorsToday': data['visitorsToday'] ?? 0,
          'panics': data['panics'] ?? data['activePanics'] ?? 0,
          'totalPanics': data['totalPanics'] ?? 0,
          'vehicleScans': data['vehicleScans'] ?? 0,
          'incoming': data['incoming'] ?? 0,
          'outgoing': data['outgoing'] ?? 0,
        };
      }

      debugPrint(
        "❌ Dashboard Stats failed with status: ${response.statusCode}",
      );
      return {
        'visitors': 0,
        'visitorsToday': 0,
        'panics': 0,
        'totalPanics': 0,
        'vehicleScans': 0,
        'incoming': 0,
        'outgoing': 0,
      };
    } catch (e) {
      debugPrint("❌ Dashboard Stats Error: $e");
      return {
        'visitors': 0,
        'visitorsToday': 0,
        'panics': 0,
        'totalPanics': 0,
        'vehicleScans': 0,
        'incoming': 0,
        'outgoing': 0,
      };
    }
  }

  static Future<List<dynamic>> getActivePanics() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/logs/panic/active'),
        headers: await _getHeaders(),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      debugPrint("❌ Get active panics error: $e");
      return [];
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

        _processedAlertIds.clear();
        _currentActiveAlertId = null;
        _isDialogShowing = false;
        initSocketAndListen();

        return data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
