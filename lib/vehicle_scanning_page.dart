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

  // Manual input fields
  final TextEditingController _manualPlateController = TextEditingController();
  bool _isManualMode = false;
  bool _isSearching = false;

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
    _manualPlateController.dispose();
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

      await _fetchAndSaveVehicleData(qrData);
    }
  }

  // ✅ Search by plate number manually
  Future<void> _searchByPlateNumber() async {
    final plateNumber = _manualPlateController.text.trim().toUpperCase();

    if (plateNumber.isEmpty) {
      _showErrorDialog("Please enter a plate number");
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('auth_token') ?? prefs.getString('jwt_token');

      if (token == null) {
        _showErrorDialog("Authentication error. Please login again.");
        setState(() {
          _isSearching = false;
        });
        return;
      }

      // Call the search endpoint
      final response = await http
          .get(
            Uri.parse(
              '$_apiBaseUrl/vehicles/search/${Uri.encodeComponent(plateNumber)}',
            ),
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final vehicleData = responseData['data'];

        if (vehicleData == null) {
          _showErrorDialog("No vehicle found with plate number: $plateNumber");
          setState(() {
            _isSearching = false;
          });
          return;
        }

        debugPrint("✅ Vehicle found via manual search");
        debugPrint("   Plate: ${vehicleData['plateNumber']}");
        debugPrint("   Owner: ${vehicleData['ownerName']}");

        // Save to logs
        final bool saved = await _saveToLogs(vehicleData);

        if (saved) {
          debugPrint("✅ Scan successfully saved to logs");
        } else {
          debugPrint("⚠️ Scan saved to local logs only");
        }

        // Show vehicle details dialog
        _showVehicleDetailsDialog(vehicleData, saved);
      } else if (response.statusCode == 404) {
        _showErrorDialog("No vehicle found with plate number: $plateNumber");
      } else {
        _showErrorDialog("Failed to fetch vehicle details. Please try again.");
      }
    } catch (e) {
      debugPrint("❌ Error searching vehicle: $e");
      _showErrorDialog("Network error. Please try again.");
    } finally {
      setState(() {
        _isSearching = false;
        _manualPlateController.clear();
      });
    }
  }

  Future<void> _fetchAndSaveVehicleData(String qrData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('auth_token') ?? prefs.getString('jwt_token');

      if (token == null) {
        _showErrorDialog("Authentication error. Please login again.");
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      _showLoadingDialog();

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
          .timeout(const Duration(seconds: 15));

      Navigator.of(context).pop();

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        final vehicleData = responseData['data'];

        debugPrint("✅ Vehicle data fetched successfully");
        debugPrint("   Plate: ${vehicleData['plateNumber']}");
        debugPrint("   Owner: ${vehicleData['ownerName']}");

        final bool saved = await _saveToLogs(vehicleData);

        _showVehicleDetailsDialog(vehicleData, saved);
      } else if (response.statusCode == 403) {
        final errorData = jsonDecode(response.body);
        _showErrorDialog(errorData['message'] ?? "Vehicle not approved yet");
        setState(() {
          _isProcessing = false;
        });
      } else if (response.statusCode == 404) {
        _showErrorDialog("Vehicle not found in the system");
        setState(() {
          _isProcessing = false;
        });
      } else {
        _showErrorDialog("Failed to fetch vehicle details");
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Error fetching vehicle data: $e");
      if (mounted) {
        Navigator.of(context).pop();
        _showErrorDialog("Network error. Please try again.");
      }
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }

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
        'scanMethod': _isManualMode ? 'Manual Entry' : 'QR Scan',
      };

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

      await _saveToLocalLogs(logEntry);
      savedToLocal = true;
      debugPrint("✅ Scan saved to local logs");

      return savedToBackend || savedToLocal;
    } catch (e) {
      debugPrint("❌ Error saving to logs: $e");
      try {
        await _saveToLocalLogs(vehicleData);
        return true;
      } catch (localError) {
        debugPrint("❌ Local save also failed: $localError");
        return false;
      }
    }
  }

  Future<void> _saveToLocalLogs(Map<String, dynamic> logEntry) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingLogs = prefs.getStringList('vehicle_scan_logs') ?? [];
      final newLogs = List<String>.from(existingLogs);

      final logWithMetadata = {
        ...logEntry,
        'localId': DateTime.now().millisecondsSinceEpoch.toString(),
        'localSaveTime': DateTime.now().toIso8601String(),
        'isLocalBackup': true,
      };

      newLogs.insert(0, jsonEncode(logWithMetadata));

      if (newLogs.length > 200) {
        newLogs.removeRange(200, newLogs.length);
      }

      await prefs.setStringList('vehicle_scan_logs', newLogs);
      debugPrint(
        "✅ Scan saved to local storage. Total logs: ${newLogs.length}",
      );
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
              if (_isManualMode)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.keyboard, color: Colors.blue, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "✓ Verified via Manual Plate Entry",
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isProcessing = false;
                _isManualMode = false;
              });
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
      setState(() {
        _isProcessing = false;
        _isManualMode = false;
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
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
                      // ✅ Toggle button for manual mode
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _isManualMode
                                      ? Icons.qr_code_scanner
                                      : Icons.keyboard,
                                  size: 16,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isManualMode ? "Scan Mode" : "Manual Mode",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                Switch(
                                  value: _isManualMode,
                                  onChanged: (value) {
                                    setState(() {
                                      _isManualMode = value;
                                      _manualPlateController.clear();
                                    });
                                  },
                                  activeColor: const Color(0xFF176F63),
                                  inactiveThumbColor: Colors.grey,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isManualMode
                      ? _buildManualInput()
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Align Resident Vehicle QR Code within the frame",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
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
                                    icon:
                                        ValueListenableBuilder<
                                          MobileScannerState
                                        >(
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
                                    onPressed: () =>
                                        cameraController.toggleTorch(),
                                  ),
                                  const SizedBox(width: 20),
                                  IconButton(
                                    color: const Color(0xFF176F63),
                                    icon:
                                        ValueListenableBuilder<
                                          MobileScannerState
                                        >(
                                          valueListenable: cameraController,
                                          builder: (context, state, child) {
                                            final facing =
                                                state.cameraDirection;
                                            switch (facing) {
                                              case CameraFacing.front:
                                                return const Icon(
                                                  Icons.camera_front,
                                                );
                                              case CameraFacing.back:
                                              default:
                                                return const Icon(
                                                  Icons.camera_rear,
                                                );
                                            }
                                          },
                                        ),
                                    iconSize: 32.0,
                                    onPressed: () =>
                                        cameraController.switchCamera(),
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
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  "TIP: Toggle to Manual Mode to enter plate number directly",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue,
                                  ),
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

  Widget _buildManualInput() {
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.keyboard, size: 60, color: Color(0xFF176F63)),
            const SizedBox(height: 16),
            const Text(
              "MANUAL PLATE ENTRY",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF176F63),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Enter the vehicle plate number to verify",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _manualPlateController,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: "Enter Plate Number (e.g., ABC-1234)",
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(
                  Icons.directions_car,
                  color: Color(0xFF176F63),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF176F63),
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _isManualMode = false;
                        _manualPlateController.clear();
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text("BACK TO SCAN"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSearching ? null : _searchByPlateNumber,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF176F63),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _isSearching
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "VERIFY PLATE",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "Manual entry is for backup when camera is not working. Please use QR scan when possible.",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
