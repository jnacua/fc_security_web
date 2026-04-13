import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ UNCOMMENTED
import 'security_sidebar.dart';

class PanicReportScreen extends StatefulWidget {
  const PanicReportScreen({super.key});

  @override
  State<PanicReportScreen> createState() => _PanicReportScreenState();
}

class _PanicReportScreenState extends State<PanicReportScreen> {
  final String apiUrl = "https://fcapp-backend.onrender.com/api/panic";

  // ✅ FIXED: Corrected token retrieval
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<List<dynamic>> fetchPanicReports() async {
    try {
      String? token = await _getToken();

      final response = await http.get(
        Uri.parse('$apiUrl/my-alerts'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load reports: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  Future<void> resolveReport(String id) async {
    try {
      String? token = await _getToken();

      final response = await http.patch(
        Uri.parse('$apiUrl/resolve/$id'),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: json.encode({"status": "Resolved"}),
      );

      if (response.statusCode == 200) {
        setState(() {}); // Refresh the list to show it as Resolved
      }
    } catch (e) {
      debugPrint("Error resolving: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SecuritySideNav(activeRoute: '/panic_report'),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10),
                        ],
                      ),
                      child: FutureBuilder<List<dynamic>>(
                        future: fetchPanicReports(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          } else if (snapshot.hasError) {
                            return Center(
                              child: Text("Error: ${snapshot.error}"),
                            );
                          } else if (!snapshot.hasData ||
                              snapshot.data!.isEmpty) {
                            return const Center(
                              child: Text("No panic records found."),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: snapshot.data!.length,
                            itemBuilder: (context, index) {
                              final report = snapshot.data![index];
                              // ✅ Accepts 'Pending' or 'Active' as the active state
                              bool isActive =
                                  report['status'].toString().toLowerCase() !=
                                  'resolved';

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: _buildAlertCard(
                                  report['_id'],
                                  "PANIC ALERT",
                                  report['residentName'] ?? "Unknown Resident",
                                  report['houseNo'] ?? "No House No",
                                  isActive,
                                  report['createdAt'] ?? "",
                                ),
                              );
                            },
                          );
                        },
                      ),
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

  Widget _buildAlertCard(
    String id,
    String type,
    String name,
    String loc,
    bool isActive,
    String time,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFEBEE) : Colors.white,
        border: Border.all(color: isActive ? Colors.red : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            isActive ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: isActive ? Colors.red : Colors.green,
            size: 45,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.toUpperCase(),
                  style: TextStyle(
                    color: isActive ? Colors.red : Colors.black87,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Resident: $name",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  "House No: $loc",
                  style: const TextStyle(color: Colors.black54),
                ),
                if (time.isNotEmpty)
                  Text(
                    "Date: ${time.substring(0, 10)} | Time: ${time.substring(11, 16)}",
                    style: const TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          if (isActive)
            ElevatedButton(
              onPressed: () => resolveReport(id),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text("MARK RESOLVED"),
            )
          else
            const Chip(
              label: Text(
                "RESOLVED",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Color(0xFFE8F5E9),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          const Icon(Icons.security, size: 30, color: Color(0xFF176F63)),
          const SizedBox(width: 15),
          const Text(
            "PANIC REPORT HISTORY",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
