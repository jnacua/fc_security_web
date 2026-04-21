import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'security_sidebar.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'security_logs.dart'; // ✅ Corrected import (no underscore)

class VehicleScanningPage extends StatefulWidget {
  const VehicleScanningPage({super.key});

  @override
  State<VehicleScanningPage> createState() => _VehicleScanningPageState();
}

class _VehicleScanningPageState extends State<VehicleScanningPage> {
  final MobileScannerController cameraController = MobileScannerController();
  bool _isProcessing = false;
  String? _apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  void _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('api_base_url');
    setState(() {
      _apiBaseUrl = savedUrl ?? 'https://fcapp-backend.onrender.com/api';
    });
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  void _handleCapture(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String qrData = barcodes.first.rawValue ?? "";

      if (qrData.isEmpty) {
        _showErrorDialog("Invalid QR code detected");
        return;
      }

      setState(() {
        _isProcessing = true;
      });

      // Fetch vehicle details and save to logs
      await _fetchAndSaveVehicleDetails(qrData);
    }
  }

  Future<void> _fetchAndSaveVehicleDetails(String qrData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('auth_token') ?? prefs.getString('jwt_token');

      if (token == null) {
        _showErrorDialog("Authentication error. Please login again.");
        return;
      }

      // Call the backend to get vehicle details
      final response = await http
          .get(
            Uri.parse(
              '$_apiBaseUrl/vehicles/scan/${Uri.encodeComponent(qrData)}',
            ),
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final vehicleData = responseData['data'];

        // ✅ Save to logs after successful scan
        final bool saved = await _saveToLogs(vehicleData);

        if (saved) {
          // ✅ Show success and navigate to logs
          _showSuccessAndNavigateToLogs(vehicleData);
        } else {
          _showErrorDialog("Failed to save scan to logs");
        }
      } else if (response.statusCode == 403) {
        final errorData = jsonDecode(response.body);
        _showErrorDialog(errorData['message'] ?? "Vehicle not approved yet");
      } else if (response.statusCode == 404) {
        _showErrorDialog("Vehicle not found in the system");
      } else {
        _showErrorDialog("Failed to fetch vehicle details");
      }
    } catch (e) {
      print("❌ Error fetching vehicle details: $e");
      _showErrorDialog("Network error. Please try again.");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // ✅ Save scan to logs
  Future<bool> _saveToLogs(Map<String, dynamic> vehicleData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('auth_token') ?? prefs.getString('jwt_token');

      if (token == null) return false;

      final logEntry = {
        'type': 'vehicle_scan',
        'plateNumber': vehicleData['plateNumber'],
        'ownerName': vehicleData['ownerName'],
        'ownerEmail': vehicleData['ownerEmail'],
        'ownerMobile': vehicleData['ownerMobile'],
        'ownerAddress': vehicleData['ownerAddress'],
        'residentType': vehicleData['residentType'],
        'vehicleType': vehicleData['vehicleType'],
        'scanTimestamp': DateTime.now().toIso8601String(),
        'status': 'APPROVED & AUTHORIZED',
      };

      // Send to backend logs
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/logs/vehicle-scan'),
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
            },
            body: jsonEncode(logEntry),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        print("✅ Scan saved to logs successfully");
        return true;
      } else {
        print("⚠️ Failed to save scan to logs: ${response.statusCode}");
        // Also save locally as backup
        await _saveToLocalLogs(logEntry);
        return false;
      }
    } catch (e) {
      print("❌ Error saving to logs: $e");
      // Save locally as backup
      await _saveToLocalLogs(vehicleData);
      return false;
    }
  }

  // ✅ Save scan to local storage as backup
  Future<void> _saveToLocalLogs(Map<String, dynamic> logEntry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingLogs = prefs.getStringList('vehicle_scan_logs') ?? [];
      final newLogs = List<String>.from(existingLogs);
      newLogs.add(jsonEncode(logEntry));

      // Keep only last 100 logs
      if (newLogs.length > 100) {
        newLogs.removeAt(0);
      }

      await prefs.setStringList('vehicle_scan_logs', newLogs);
      print("✅ Scan saved to local logs");
    } catch (e) {
      print("❌ Error saving to local logs: $e");
    }
  }

  // ✅ Show success and navigate to logs
  void _showSuccessAndNavigateToLogs(Map<String, dynamic> vehicleData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 10),
            Text("SCAN SUCCESSFUL"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, color: Colors.green, size: 60),
            const SizedBox(height: 16),
            Text(
              "Vehicle: ${vehicleData['plateNumber']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              "Owner: ${vehicleData['ownerName']}",
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, color: Colors.blue.shade700, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Scan saved to logs at ${DateTime.now().toString().substring(0, 19)}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to logs page
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const SecurityLogs()),
              );
            },
            child: const Text("VIEW LOGS"),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 10),
            Text("SCAN FAILED"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, color: Colors.red, size: 50),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isProcessing = false;
              });
            },
            child: const Text("TRY AGAIN"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: Row(
        children: [
          const SecuritySideNav(activeRoute: '/vehicle_scanning'),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  color: Colors.white,
                  child: Row(
                    children: const [
                      Icon(Icons.qr_code_scanner, color: Color(0xFF176F63)),
                      SizedBox(width: 12),
                      Text(
                        "RESIDENT VEHICLE VERIFICATION",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF176F63),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Align Resident Vehicle QR Code within the frame",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 30),
                        Container(
                          width: 450,
                          height: 450,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF176F63),
                              width: 4,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: MobileScanner(
                              controller: cameraController,
                              onDetect: _handleCapture,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              color: const Color(0xFF176F63),
                              icon: ValueListenableBuilder<MobileScannerState>(
                                valueListenable: cameraController,
                                builder: (context, state, child) {
                                  final torchState = state.torchState;
                                  switch (torchState) {
                                    case TorchState.on:
                                      return const Icon(
                                        Icons.flash_on,
                                        color: Colors.orange,
                                      );
                                    case TorchState.off:
                                    default:
                                      return const Icon(
                                        Icons.flash_off,
                                        color: Colors.grey,
                                      );
                                  }
                                },
                              ),
                              iconSize: 32.0,
                              onPressed: () => cameraController.toggleTorch(),
                            ),
                            const SizedBox(width: 20),
                            IconButton(
                              color: const Color(0xFF176F63),
                              icon: ValueListenableBuilder<MobileScannerState>(
                                valueListenable: cameraController,
                                builder: (context, state, child) {
                                  final facing = state.cameraDirection;
                                  switch (facing) {
                                    case CameraFacing.front:
                                      return const Icon(Icons.camera_front);
                                    case CameraFacing.back:
                                    default:
                                      return const Icon(Icons.camera_rear);
                                  }
                                },
                              ),
                              iconSize: 32.0,
                              onPressed: () => cameraController.switchCamera(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
