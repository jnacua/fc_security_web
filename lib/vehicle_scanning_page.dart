import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'security_sidebar.dart'; // ✅ Matches your filename
import 'api_service.dart';

class VehicleScanningPage extends StatefulWidget {
  const VehicleScanningPage({super.key});

  @override
  State<VehicleScanningPage> createState() => _VehicleScanningPageState();
}

class _VehicleScanningPageState extends State<VehicleScanningPage> {
  final MobileScannerController cameraController = MobileScannerController();
  bool _isProcessing = false;

  void _handleCapture(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String code = barcodes.first.rawValue ?? "";

      setState(() {
        _isProcessing = true;
      });

      _showResultDialog(code);
    }
  }

  void _showResultDialog(String data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Vehicle Scanned"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 60),
            const SizedBox(height: 16),
            Text(
              "Plate/ID: $data",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text("Status: AUTHORIZED RESIDENT"),
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
            child: const Text("OK"),
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
                            // TORCH BUTTON
                            IconButton(
                              color: const Color(0xFF176F63),
                              icon: ValueListenableBuilder<MobileScannerState>(
                                valueListenable: cameraController,
                                builder: (context, state, child) {
                                  switch (state.torchState) {
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
                            // CAMERA SWITCH BUTTON
                            IconButton(
                              color: const Color(0xFF176F63),
                              icon: ValueListenableBuilder<MobileScannerState>(
                                valueListenable: cameraController,
                                builder: (context, state, child) {
                                  // ✅ Corrected property name and exhaustive cases
                                  switch (state.cameraFacing) {
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
