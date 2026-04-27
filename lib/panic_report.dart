import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'security_sidebar.dart';

class PanicReportScreen extends StatefulWidget {
  const PanicReportScreen({super.key});

  @override
  State<PanicReportScreen> createState() => _PanicReportScreenState();
}

class _PanicReportScreenState extends State<PanicReportScreen> {
  final String apiUrl = "https://fcapp-backend.onrender.com/api/panic";

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  // ✅ Format UTC time to Philippine Time (UTC+8)
  String _formatPhilippineTime(String utcTime) {
    if (utcTime.isEmpty) return '--:-- --';
    try {
      // Parse UTC time
      DateTime utcDateTime = DateTime.parse(utcTime);
      // Add 8 hours for Philippine Time
      DateTime philippineTime = utcDateTime.add(const Duration(hours: 8));

      // Format as "Apr 27, 2026 - 2:37 PM"
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      String month = months[philippineTime.month - 1];
      int day = philippineTime.day;
      int year = philippineTime.year;
      int hour = philippineTime.hour;
      String minute = philippineTime.minute.toString().padLeft(2, '0');
      String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;

      return '$month $day, $year - $hour:$minute $period';
    } catch (e) {
      return utcTime;
    }
  }

  // ✅ Format only the date part
  String _formatDateOnly(String utcTime) {
    if (utcTime.isEmpty) return '--/--/----';
    try {
      DateTime utcDateTime = DateTime.parse(utcTime);
      DateTime philippineTime = utcDateTime.add(const Duration(hours: 8));
      return '${philippineTime.year}-${philippineTime.month.toString().padLeft(2, '0')}-${philippineTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return utcTime.substring(0, 10);
    }
  }

  // ✅ Format only the time part
  String _formatTimeOnly(String utcTime) {
    if (utcTime.isEmpty) return '--:-- --';
    try {
      DateTime utcDateTime = DateTime.parse(utcTime);
      DateTime philippineTime = utcDateTime.add(const Duration(hours: 8));
      int hour = philippineTime.hour;
      String minute = philippineTime.minute.toString().padLeft(2, '0');
      String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $period';
    } catch (e) {
      return utcTime.substring(11, 16);
    }
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
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Panic report resolved successfully"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error resolving: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error resolving report: $e"),
          backgroundColor: Colors.red,
        ),
      );
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
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    size: 50,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(height: 10),
                                  Text("Error: ${snapshot.error}"),
                                  const SizedBox(height: 10),
                                  ElevatedButton(
                                    onPressed: () => setState(() {}),
                                    child: const Text("RETRY"),
                                  ),
                                ],
                              ),
                            );
                          } else if (!snapshot.hasData ||
                              snapshot.data!.isEmpty) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 10),
                                  Text("No panic records found."),
                                  SizedBox(height: 5),
                                  Text(
                                    "All panic alerts will appear here once sent.",
                                  ),
                                ],
                              ),
                            );
                          }

                          return ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: snapshot.data!.length,
                            itemBuilder: (context, index) {
                              final report = snapshot.data![index];
                              bool isActive =
                                  report['status'].toString().toLowerCase() !=
                                  'resolved';

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: _buildAlertCard(
                                  report['_id'],
                                  "PANIC ALERT",
                                  report['residentName'] ?? "Unknown Resident",
                                  report['houseNo'] ??
                                      report['blockLot'] ??
                                      "No Address",
                                  isActive,
                                  report['createdAt'] ?? "",
                                  report['emergencyType'] ?? "Emergency Alert",
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
    String emergencyType,
  ) {
    // Format the time to Philippine Time
    final formattedDateTime = _formatPhilippineTime(time);
    final formattedDate = _formatDateOnly(time);
    final formattedTimeOnly = _formatTimeOnly(time);

    // Determine emergency type color
    Color emergencyColor = Colors.orange;
    if (emergencyType.contains('Medical') ||
        emergencyType.contains('Heart') ||
        emergencyType.contains('Stroke')) {
      emergencyColor = Colors.red;
    } else if (emergencyType.contains('Fire')) {
      emergencyColor = Colors.orange;
    } else if (emergencyType.contains('Security') ||
        emergencyType.contains('Theft')) {
      emergencyColor = Colors.purple;
    }

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
                Row(
                  children: [
                    Text(
                      type.toUpperCase(),
                      style: TextStyle(
                        color: isActive ? Colors.red : Colors.black87,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: emergencyColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: emergencyColor.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        emergencyType,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: emergencyColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Resident: $name",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  "Location: $loc",
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 12,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.access_time,
                      size: 12,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      formattedTimeOnly,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
          const Icon(
            Icons.warning_amber_rounded,
            size: 30,
            color: Color(0xFF176F63),
          ),
          const SizedBox(width: 15),
          const Text(
            "PANIC REPORT HISTORY",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "ACTIVE ALERTS",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }
}
