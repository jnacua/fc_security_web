import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'security_sidebar.dart';
import 'api_service.dart';

class SecurityLogs extends StatefulWidget {
  const SecurityLogs({super.key});

  @override
  State<SecurityLogs> createState() => _SecurityLogsState();
}

class _SecurityLogsState extends State<SecurityLogs> {
  late Future<List<dynamic>> _logsFuture;
  String _searchQuery = '';
  String _filterType = 'ALL';
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _refreshLogs();
  }

  void _refreshLogs() {
    setState(() {
      _logsFuture = ApiService.getAllSecurityLogs();
    });
  }

  // ✅ Generate a unique ID for each log based on plate + timestamp (rounded to minute) + type
  String _getUniqueLogId(dynamic log) {
    final plate =
        log['plateNumber'] ??
        log['visitorName'] ??
        log['residentName'] ??
        'unknown';

    String timeKey = '';
    final timestamp =
        log['scanTimestamp'] ??
        log['entryTime'] ??
        log['timestamp'] ??
        log['createdAt'];

    if (timestamp != null) {
      try {
        final date = DateTime.parse(timestamp.toString());
        timeKey =
            '${date.year}${date.month}${date.day}${date.hour}${date.minute}';
      } catch (e) {
        timeKey = timestamp.toString();
      }
    }

    final type = log['type'] ?? 'unknown';
    return '$plate|$timeKey|$type';
  }

  // ✅ Remove duplicate logs from the list
  List<dynamic> _removeDuplicates(List<dynamic> logs) {
    final seen = <String, dynamic>{};
    final result = <dynamic>[];

    for (var log in logs) {
      final id = _getUniqueLogId(log);
      if (!seen.containsKey(id)) {
        seen[id] = log;
        result.add(log);
      }
    }

    print("📊 Removed duplicates: ${logs.length} -> ${result.length}");
    return result;
  }

  // ✅ Helper function to extract formatted time from any log type
  String _getFormattedTime(dynamic log) {
    if (log['formattedTime'] != null &&
        log['formattedTime'].toString().contains(' - ')) {
      return log['formattedTime'].toString();
    }

    if (log['localSaveTime'] != null) {
      return _formatPhilippineTime(log['localSaveTime']);
    }

    final timestamp =
        log['scanTimestamp'] ??
        log['entryTime'] ??
        log['timestamp'] ??
        log['createdAt'];

    if (timestamp != null) {
      return _formatPhilippineTime(timestamp);
    }

    return '--:-- --';
  }

  // ✅ Format UTC time to Philippine Time (UTC+8)
  String _formatPhilippineTime(dynamic timestamp) {
    if (timestamp == null) return '--:-- --';
    try {
      DateTime time;
      if (timestamp is String) {
        time = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        time = timestamp;
      } else {
        return '--:-- --';
      }

      final philippineTime = time.add(const Duration(hours: 8));

      return '${_getMonthAbbr(philippineTime.month)} ${philippineTime.day}, ${philippineTime.year} - ${_formatTime(philippineTime)}';
    } catch (e) {
      return '--:-- --';
    }
  }

  // ✅ Helper function to extract timestamp for sorting
  dynamic _extractTimestamp(dynamic log) {
    if (log['scanTimestamp'] != null) return log['scanTimestamp'];
    if (log['entryTime'] != null) return log['entryTime'];
    if (log['timestamp'] != null) return log['timestamp'];
    if (log['createdAt'] != null) return log['createdAt'];
    if (log['localSaveTime'] != null) return log['localSaveTime'];
    return null;
  }

  // ✅ Filter logs based on search query and type filter
  List<dynamic> _filterLogs(List<dynamic> logs) {
    return logs.where((log) {
      if (_filterType != 'ALL') {
        final logType = log['type']?.toString().toUpperCase() ?? 'VEHICLE_SCAN';
        if (logType != _filterType &&
            !(_filterType == 'VEHICLE_SCAN' && logType == 'VEHICLE')) {
          return false;
        }
      }

      if (_searchQuery.isNotEmpty) {
        final searchLower = _searchQuery.toLowerCase();
        final name =
            (log['name'] ??
                    log['ownerName'] ??
                    log['visitorName'] ??
                    log['residentName'] ??
                    '')
                .toString()
                .toLowerCase();
        final plateNumber = (log['plateNumber'] ?? '').toString().toLowerCase();
        final details = (log['details'] ?? '').toString().toLowerCase();
        final purpose = (log['purpose'] ?? '').toString().toLowerCase();

        if (!name.contains(searchLower) &&
            !plateNumber.contains(searchLower) &&
            !details.contains(searchLower) &&
            !purpose.contains(searchLower)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // ✅ Generate PDF Report
  Future<void> _generatePDFReport(List<dynamic> logs, String reportType) async {
    setState(() {
      _isPrinting = true;
    });

    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Center(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 200),
                  pw.Text(
                    'FIESTA CASITAS SECURITY',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'SECURITY LOGS REPORT',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    reportType,
                    style: pw.TextStyle(fontSize: 16, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 40),
                  pw.Text(
                    'Generated on: ${DateTime.now().toString().substring(0, 19)}',
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Total Records: ${logs.length}',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          orientation: pw.PageOrientation.landscape,
          build: (context) => [
            pw.Header(
              level: 0,
              child: pw.Text(
                'SECURITY LOGS DETAILS',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table.fromTextArray(
              headers: ['Date & Time', 'Type', 'Details', 'Status'],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 12,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(5),
              data: logs.map((log) {
                final timestamp = _getFormattedTime(log);
                final type = _getLogTypeDisplay(
                  log['type']?.toString() ?? 'VEHICLE_SCAN',
                );
                final details = _getLogDetails(log);
                final status = log['status'] ?? 'COMPLETED';
                return [timestamp, type, details, status];
              }).toList(),
            ),
            pw.SizedBox(height: 30),
            pw.Text(
              'End of Report',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Security_Logs_Report_${DateTime.now().toIso8601String()}.pdf',
      );
    } catch (e) {
      print("❌ Error generating PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error generating report: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isPrinting = false;
      });
    }
  }

  // ✅ Show report options dialog
  void _showReportOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Generate Report"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions_car, color: Colors.green),
              title: const Text("Vehicle Scan Logs"),
              subtitle: const Text("Export all vehicle scan records"),
              onTap: () async {
                Navigator.pop(context);
                final logs = await _logsFuture;
                final vehicleLogs = logs
                    .where(
                      (log) =>
                          log['type'] == 'VEHICLE_SCAN' ||
                          log['type'] == 'VEHICLE' ||
                          (log['plateNumber'] != null &&
                              log['ownerName'] != null),
                    )
                    .toList();
                await _generatePDFReport(
                  vehicleLogs,
                  "VEHICLE SCAN LOGS REPORT",
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning, color: Colors.orange),
              title: const Text("Panic Alert Logs"),
              subtitle: const Text("Export all panic alert records"),
              onTap: () async {
                Navigator.pop(context);
                final logs = await _logsFuture;
                final panicLogs = logs
                    .where(
                      (log) =>
                          log['type'] == 'PANIC' ||
                          log['emergencyType'] != null,
                    )
                    .toList();
                await _generatePDFReport(panicLogs, "PANIC ALERT LOGS REPORT");
              },
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Colors.blue),
              title: const Text("Visitor Logs"),
              subtitle: const Text("Export all visitor records"),
              onTap: () async {
                Navigator.pop(context);
                final logs = await _logsFuture;
                final visitorLogs = logs
                    .where(
                      (log) =>
                          log['type'] == 'VISITOR' ||
                          log['visitorName'] != null,
                    )
                    .toList();
                await _generatePDFReport(visitorLogs, "VISITOR LOGS REPORT");
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.green),
              title: const Text("Complete Report"),
              subtitle: const Text("Export all security logs"),
              onTap: () async {
                Navigator.pop(context);
                final logs = await _logsFuture;
                await _generatePDFReport(logs, "COMPLETE SECURITY LOGS REPORT");
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
        ],
      ),
    );
  }

  // ✅ Get formatted log type display
  String _getLogTypeDisplay(String type) {
    switch (type.toUpperCase()) {
      case 'VEHICLE_SCAN':
      case 'VEHICLE':
        return 'VEHICLE';
      case 'PANIC':
        return 'PANIC';
      case 'VISITOR':
        return 'VISITOR';
      default:
        return 'VEHICLE';
    }
  }

  // ✅ Get log type color
  Color _getLogTypeColor(String type) {
    switch (type.toUpperCase()) {
      case 'VEHICLE_SCAN':
      case 'VEHICLE':
        return Colors.green;
      case 'PANIC':
        return Colors.red;
      case 'VISITOR':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  // ✅ FIXED: Get log details text with better location extraction for panic reports
  String _getLogDetails(Map<String, dynamic> log) {
    final type = log['type']?.toString().toUpperCase() ?? 'VEHICLE_SCAN';

    switch (type) {
      case 'VEHICLE_SCAN':
      case 'VEHICLE':
        final plateNumber = log['plateNumber'] ?? 'N/A';
        final ownerName = log['ownerName'] ?? '';
        final vehicleType = log['vehicleType'] ?? '';
        String details = plateNumber;
        if (ownerName.isNotEmpty) details += ' - $ownerName';
        if (vehicleType.isNotEmpty) details += ' ($vehicleType)';
        return details;

      case 'PANIC':
        final residentName =
            log['residentName'] ?? log['name'] ?? 'Unknown Resident';

        // Try multiple possible location fields
        String location =
            log['blockLot'] ??
            log['houseNo'] ??
            log['address'] ??
            log['location']?.toString() ??
            'Unknown Location';

        // If location is still N/A or empty, try to get from user data if available
        if (location == 'N/A' ||
            location == 'Unknown Location' ||
            location.isEmpty) {
          location =
              log['userBlockLot'] ??
              log['userId_blockLot'] ??
              'Address not available';
        }

        // Add emergency type if available
        final emergencyType = log['emergencyType'];
        String details = '$residentName - Location: $location';
        if (emergencyType != null &&
            emergencyType != 'Emergency Alert' &&
            emergencyType != 'N/A') {
          details += ' [$emergencyType]';
        }
        return details;

      case 'VISITOR':
        final visitorName =
            log['visitorName'] ?? log['name'] ?? 'Unknown Visitor';
        final purpose = log['purpose'] ?? 'Visit';
        final plateNumber = log['plateNumber'];
        String details = '$visitorName - $purpose';
        if (log['residentToVisit'] != null &&
            log['residentToVisit'] != 'Unknown') {
          details += ' (Visiting: ${log['residentToVisit']})';
        }
        if (plateNumber != null && plateNumber != 'N/A') {
          details += ' [Vehicle: $plateNumber]';
        }
        return details;

      default:
        final plateNumber = log['plateNumber'] ?? 'N/A';
        final ownerName = log['ownerName'] ?? '';
        return '$plateNumber - $ownerName';
    }
  }

  // ✅ Get status color
  Color _getStatusColor(String status) {
    final statusUpper = status.toUpperCase();
    if (statusUpper == 'APPROVED' ||
        statusUpper == 'AUTHORIZED' ||
        statusUpper == 'RESOLVED' ||
        statusUpper == 'COMPLETED') {
      return Colors.green;
    } else if (statusUpper == 'PENDING' || statusUpper == 'ACTIVE') {
      return Colors.orange;
    } else if (statusUpper == 'REJECTED') {
      return Colors.red;
    }
    return Colors.green;
  }

  String _getMonthAbbr(int month) {
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
    return months[month - 1];
  }

  String _formatTime(DateTime time) {
    int hour = time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0E0E0),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SecuritySideNav(activeRoute: '/security_logs'),
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
                      ),
                      child: Column(
                        children: [
                          _buildSearchAndFilter(),
                          _buildTableHeader(),
                          Expanded(
                            child: FutureBuilder<List<dynamic>>(
                              future: _logsFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }

                                if (snapshot.hasError) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.error_outline,
                                          size: 50,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          "Error loading logs: ${snapshot.error}",
                                        ),
                                        const SizedBox(height: 10),
                                        ElevatedButton(
                                          onPressed: _refreshLogs,
                                          child: const Text("RETRY"),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                if (!snapshot.hasData ||
                                    snapshot.data!.isEmpty) {
                                  return const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.history,
                                          size: 50,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 10),
                                        Text("No logs found."),
                                        SizedBox(height: 5),
                                        Text(
                                          "Scan a vehicle QR code to see logs here",
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final uniqueLogs = _removeDuplicates(
                                  snapshot.data!,
                                );
                                final filteredLogs = _filterLogs(uniqueLogs);

                                if (filteredLogs.isEmpty) {
                                  return const Center(
                                    child: Text(
                                      "No logs match your search criteria.",
                                    ),
                                  );
                                }

                                return RefreshIndicator(
                                  onRefresh: () async {
                                    _refreshLogs();
                                    return Future.value();
                                  },
                                  child: ListView.separated(
                                    itemCount: filteredLogs.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final log = filteredLogs[index];
                                      final logType = _getLogTypeDisplay(
                                        log['type']?.toString() ??
                                            'VEHICLE_SCAN',
                                      );
                                      final logDetails = _getLogDetails(log);
                                      final status =
                                          log['status'] ?? 'APPROVED';
                                      final time = _getFormattedTime(log);

                                      return _buildLogRow(
                                        logType,
                                        logDetails,
                                        status,
                                        time,
                                        _getLogTypeColor(
                                          log['type']?.toString() ??
                                              'VEHICLE_SCAN',
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
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

  Widget _buildLogRow(
    String type,
    String details,
    String status,
    String time,
    Color typeColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                type,
                style: TextStyle(fontWeight: FontWeight.bold, color: typeColor),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              details,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              status,
              style: TextStyle(
                color: _getStatusColor(status),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              time,
              style: const TextStyle(color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() => Container(
    color: Colors.grey[100],
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    child: Row(
      children: const [
        Expanded(
          flex: 2,
          child: Text(
            "LOG TYPE",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text("DETAILS", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          flex: 2,
          child: Text("STATUS", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          flex: 3,
          child: Text(
            "TIME OCCURRED",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  Widget _buildSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: const InputDecoration(
                hintText: "SEARCH BY NAME, PLATE, OR BLOCK...",
                prefixIcon: Icon(Icons.search),
                filled: true,
                fillColor: Color(0xFFF5F5F5),
                border: OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _filterType,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('ALL LOGS')),
                DropdownMenuItem(
                  value: 'VEHICLE_SCAN',
                  child: Text('VEHICLE SCANS'),
                ),
                DropdownMenuItem(value: 'PANIC', child: Text('PANIC ALERTS')),
                DropdownMenuItem(value: 'VISITOR', child: Text('VISITOR LOGS')),
              ],
              onChanged: (value) =>
                  setState(() => _filterType = value ?? 'ALL'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _showReportOptions,
            tooltip: 'Print Report',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _isPrinting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isPrinting ? null : _refreshLogs,
            tooltip: 'Refresh Logs',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() => Container(
    color: Colors.white,
    padding: const EdgeInsets.all(16),
    child: Row(
      children: const [
        Icon(Icons.history, size: 30, color: Color(0xFF176F63)),
        SizedBox(width: 10),
        Text(
          "SECURITY HISTORY LOGS",
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}
