import 'dart:async';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'security_sidebar.dart';
import 'api_service.dart';

class VisitorScanningScreen extends StatefulWidget {
  const VisitorScanningScreen({super.key});

  @override
  State<VisitorScanningScreen> createState() => _VisitorScanningScreenState();
}

class _VisitorScanningScreenState extends State<VisitorScanningScreen> {
  // Controllers for manual input
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();

  Map<String, dynamic>? visitorData;
  Map<String, dynamic>? activePanicAlert;
  late IO.Socket socket;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  void _connectSocket() {
    socket = ApiService.initSocket();
    socket.on('emergency-alert', (data) {
      if (mounted) setState(() => activePanicAlert = data);
    });
    socket.on('panic-resolved', (_) {
      if (mounted) setState(() => activePanicAlert = null);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _purposeController.dispose();
    _hostController.dispose();
    socket.off('emergency-alert');
    socket.off('panic-resolved');
    super.dispose();
  }

  // ✅ Previews the data on the right-side panel before saving
  void _previewVisitorData() {
    if (_nameController.text.trim().isEmpty ||
        _hostController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in Name and Resident details to preview."),
        ),
      );
      return;
    }
    setState(() {
      visitorData = {
        'name': _nameController.text.trim(),
        'purpose': _purposeController.text.trim(),
        'hostName': _hostController.text.trim(),
      };
    });
  }

  Future<void> _handleVisitorLog() async {
    if (visitorData == null) return;

    setState(() => _isSaving = true);

    Map<String, String> visitorInfo = {
      'name': visitorData!['name'],
      'purpose': visitorData!['purpose'],
      'hostName': visitorData!['hostName'],
    };

    // ✅ Logs the entry to your backend
    bool success = await ApiService.logVisitorEntry(visitorInfo);

    if (success) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Visitor Logged Successfully"),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        visitorData = null;
        _nameController.clear();
        _purposeController.clear();
        _hostController.clear();
      });
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to log visitor"),
          backgroundColor: Colors.red,
        ),
      );
    }
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F9),
      body: Stack(
        children: [
          Row(
            children: [
              const SecuritySideNav(activeRoute: '/visitor_scanning'),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 4, child: _buildInputPanel()),
                            const SizedBox(width: 24),
                            Expanded(flex: 5, child: _buildResultPanel()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (activePanicAlert != null) _buildPanicOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.edit_note_rounded,
            color: Color(0xFF176F63),
            size: 32,
          ),
          const SizedBox(width: 12),
          const Text(
            "VISITOR REGISTRATION",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "STATUS: GATE OPEN",
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputPanel() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "LOG NEW ENTRY",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 24),
            _buildTextField("Visitor Full Name", _nameController, Icons.person),
            const SizedBox(height: 16),
            _buildTextField(
              "Purpose of Visit",
              _purposeController,
              Icons.work_outline,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              "Resident Name / House No.",
              _hostController,
              Icons.home_work,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _previewVisitorData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade800,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                "PREVIEW LOG",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  visitorData = null;
                  _nameController.clear();
                  _purposeController.clear();
                  _hostController.clear();
                });
              },
              child: const Center(
                child: Text(
                  "Clear Fields",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Colors.blueGrey,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF176F63)),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            hintText: "Enter $label",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20),
        ],
      ),
      child: visitorData == null
          ? _buildEmptyState()
          : _buildVerificationCard(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.note_add_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            "Waiting for input verification...",
            style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              "PREVIEWING ENTRY",
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 40),
          const CircleAvatar(
            radius: 50,
            backgroundColor: Color(0xFFF0F2F5),
            child: Icon(Icons.person, size: 50, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Text(
            visitorData!['name'].toString().toUpperCase(),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          Text(
            "Visiting: ${visitorData!['hostName']}",
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const Divider(height: 60),
          _buildInfoRow(Icons.info_outline, "Purpose", visitorData!['purpose']),
          const Spacer(),
          const Text(
            "Verify that all credentials above are correct before saving to the logbook.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 65,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _handleVisitorLog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF176F63),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "SAVE TO DIGITAL LOGBOOK",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 20),
        const SizedBox(width: 12),
        Text(
          "$label: ",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ),
        Text(
          value.isEmpty ? "N/A" : value,
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildPanicOverlay() {
    return Container(
      color: Colors.red.withOpacity(0.9),
      child: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.report_problem, color: Colors.red, size: 80),
              const SizedBox(height: 20),
              const Text(
                "EMERGENCY SIGNAL",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const Divider(height: 40),
              Text(
                "RESIDENT: ${activePanicAlert!['name']}",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "LOCATION: ${activePanicAlert!['blockLot']}",
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => setState(() => activePanicAlert = null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                ),
                child: const Text("ACKNOWLEDGE"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
