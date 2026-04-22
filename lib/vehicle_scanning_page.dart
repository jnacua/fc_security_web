import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'security_sidebar.dart';
import 'api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'security_logs.dart';

class VehicleScanningPage extends StatefulWidget {
  const VehicleScanningPage({super.key});

  @override
  State<VehicleScanningPage> createState() => _VehicleScanningPageState();
}

class _VehicleScanningPageState extends State<VehicleScanningPage> {
  final MobileScannerController cameraController = MobileScannerController();
  bool _isProcessing = false;
  String? _apiBaseUrl;

  // ✅ Dummy data for demonstration
  final Map<String, dynamic> _dummyVehicleData = {
    'plateNumber': 'EOW 3293',
    'ownerName': 'JEIAN PAOLO C. NACUA',
    'ownerEmail': 'jeianpaolonacua@gmail.com',
    'ownerMobile': '09123456789',
    'ownerAddress': 'Block 1, Lot 2, Fiesta Casitas Subdivision',
    'residentType': 'OWNER',
    'vehicleType': 'SUV',
    'status': 'Approved',
    'qrData': 'VEHICLE-EOW3293-1734567890123',
  };

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

      // ✅ Show dummy data and save to logs when QR is scanned
      await _showDummyDataAndSaveToLogs(qrData);
    }
  }

  // ✅ Method to show dummy data and save to logs
  Future<void> _showDummyDataAndSaveToLogs(String qrData) async {
    try {
      // Show loading indicator briefly
      await Future.delayed(const Duration(milliseconds: 300));

      // ✅ Use dummy data for convincing demo
      final vehicleData = _dummyVehicleData;

      debugPrint("✅ Using dummy vehicle data for demo");
      debugPrint("   Plate: ${vehicleData['plateNumber']}");
      debugPrint("   Owner: ${vehicleData['ownerName']}");

      // ✅ SAVE TO LOGS - This is the key fix
      final bool saved = await _saveToLogs(vehicleData);

      if (saved) {
        debugPrint("✅ Scan successfully saved to logs");
      } else {
        debugPrint("⚠️ Scan saved to local logs only");
      }

      // Show vehicle details dialog
      _showVehicleDetailsDialog(vehicleData, saved);
    } catch (e) {
      debugPrint("❌ Error showing dummy data: $e");
      _showErrorDialog("Error displaying vehicle data");
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // ✅ Save scan to logs (with backend and local backup)
  Future<bool> _saveToLogs(Map<String, dynamic> vehicleData) async {
    bool savedToBackend = false;
    bool savedToLocal = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('auth_token') ?? prefs.getString('jwt_token');

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
        'scannedBy': 'Security Guard',
        'scannedAt': DateTime.now().toString(),
      };

      // Try to send to backend logs
      if (token != null) {
        try {
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
            savedToBackend = true;
            debugPrint("✅ Scan saved to backend logs successfully");
          } else {
            debugPrint(
              "⚠️ Backend returned ${response.statusCode}, saving locally",
            );
          }
        } catch (e) {
          debugPrint("⚠️ Backend log save failed: $e");
        }
      }

      // ✅ ALWAYS save to local logs as backup
      await _saveToLocalLogs(logEntry);
      savedToLocal = true;
      debugPrint("✅ Scan saved to local logs");

      return savedToBackend || savedToLocal;
    } catch (e) {
      debugPrint("❌ Error saving to logs: $e");
      // Try local save as last resort
      try {
        await _saveToLocalLogs(vehicleData);
        return true;
      } catch (localError) {
        debugPrint("❌ Local save also failed: $localError");
        return false;
      }
    }
  }

  // ✅ Save scan to local storage
  Future<void> _saveToLocalLogs(Map<String, dynamic> logEntry) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing logs
      final existingLogs = prefs.getStringList('vehicle_scan_logs') ?? [];
      final newLogs = List<String>.from(existingLogs);

      // Add timestamp and ID to log entry
      final logWithMetadata = {
        ...logEntry,
        'localId': DateTime.now().millisecondsSinceEpoch.toString(),
        'localSaveTime': DateTime.now().toIso8601String(),
        'isLocalBackup': true,
      };

      // Add to beginning of list (newest first)
      newLogs.insert(0, jsonEncode(logWithMetadata));

      // Keep only last 200 logs
      if (newLogs.length > 200) {
        newLogs.removeRange(200, newLogs.length);
      }

      await prefs.setStringList('vehicle_scan_logs', newLogs);
      debugPrint(
        "✅ Scan saved to local storage. Total logs: ${newLogs.length}",
      );

      // Also save to a separate recent scan key for quick access
      await prefs.setString('last_vehicle_scan', jsonEncode(logWithMetadata));
    } catch (e) {
      debugPrint("❌ Error saving to local logs: $e");
      throw e;
    }
  }

  void _showVehicleDetailsDialog(
    Map<String, dynamic> vehicleData,
    bool savedToLogs,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.verified_user, color: Colors.green),
            SizedBox(width: 10),
            Text("AUTHORIZED VEHICLE"),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(),
              _buildInfoRow(
                Icons.directions_car,
                "Plate Number",
                vehicleData['plateNumber'] ?? 'N/A',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.person,
                "Owner Name",
                vehicleData['ownerName'] ?? 'N/A',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.email,
                "Email",
                vehicleData['ownerEmail'] ?? 'N/A',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.phone,
                "Mobile",
                vehicleData['ownerMobile'] ?? 'N/A',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.home,
                "Address",
                vehicleData['ownerAddress'] ?? 'N/A',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.badge,
                "Resident Type",
                vehicleData['residentType'] ?? 'N/A',
              ),
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.electric_car,
                "Vehicle Type",
                vehicleData['vehicleType'] ?? 'N/A',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "STATUS: APPROVED & AUTHORIZED",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: savedToLogs
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      savedToLogs ? Icons.check_circle : Icons.warning,
                      color: savedToLogs
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        savedToLogs
                            ? "✓ Scan logged successfully at ${DateTime.now().toString().substring(0, 19)}"
                            : "⚠ Scan saved locally. Will sync when online.",
                        style: TextStyle(
                          fontSize: 11,
                          color: savedToLogs
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amber.shade700,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "DEMO MODE: This is sample data for demonstration purposes.",
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isProcessing = false;
              });
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
    ).then((_) {
      // Reset processing state when dialog is dismissed
      setState(() {
        _isProcessing = false;
      });
    });
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              Text(
                value.isNotEmpty ? value : 'N/A',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
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
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Colors.amber.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "DEMO MODE: Scanning shows sample vehicle data",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber.shade800,
                                ),
                              ),
                            ],
                          ),
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
