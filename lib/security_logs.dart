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
  List<dynamic> _localLogs = [];
  bool _isLoadingLocal = true;

  @override
  void initState() {
    super.initState();
    _loadLocalLogs();
    _refreshLogs();
  }

  // ✅ Load local logs from SharedPreferences
  Future<void> _loadLocalLogs() async {
    setState(() {
      _isLoadingLocal = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final localLogsJson = prefs.getStringList('vehicle_scan_logs') ?? [];

      List<dynamic> localLogs = [];
      for (var logJson in localLogsJson) {
        try {
          final log = jsonDecode(logJson);
          localLogs.add(log);
        } catch (e) {
          print("Error parsing log: $e");
        }
      }

      setState(() {
        _localLogs = localLogs;
        _isLoadingLocal = false;
      });

      print("✅ Loaded ${_localLogs.length} local logs");
    } catch (e) {
      print("❌ Error loading local logs: $e");
      setState(() {
        _isLoadingLocal = false;
      });
    }
  }

  void _refreshLogs() {
    setState(() {
      _logsFuture = ApiService.getAllSecurityLogs();
    });
    _loadLocalLogs();
  }

  // ✅ Combine local and backend logs
  Future<List<dynamic>> _getCombinedLogs() async {
    final backendLogs = await _logsFuture;
    List<dynamic> combinedLogs = [..._localLogs];

    if (backendLogs != null) {
      combinedLogs.addAll(backendLogs);
    }

    // Remove duplicates based on plateNumber and timestamp
    final uniqueLogs = <String, dynamic>{};
    for (var log in combinedLogs) {
      final key =
          '${log['plateNumber']}_${log['scanTimestamp'] ?? log['localSaveTime'] ?? log['createdAt']}';
      if (!uniqueLogs.containsKey(key)) {
        uniqueLogs[key] = log;
      }
    }

    // Sort by timestamp (newest first)
    final sortedLogs = uniqueLogs.values.toList();
    sortedLogs.sort((a, b) {
      final timeA =
          a['scanTimestamp'] ?? a['localSaveTime'] ?? a['createdAt'] ?? '';
      final timeB =
          b['scanTimestamp'] ?? b['localSaveTime'] ?? b['createdAt'] ?? '';
      return timeB.compareTo(timeA);
    });

    return sortedLogs;
  }

  // ✅ Filter logs based on search query and type filter
  List<dynamic> _filterLogs(List<dynamic> logs) {
    return logs.where((log) {
      // Filter by type
      if (_filterType != 'ALL') {
        final logType = log['type'] ?? 'VEHICLE_SCAN';
        if (logType != _filterType) {
          return false;
        }
      }

      // Filter by search query (name, plate number, or block)
      if (_searchQuery.isNotEmpty) {
        final searchLower = _searchQuery.toLowerCase();
        final name = (log['name'] ?? log['ownerName'] ?? '').toLowerCase();
        final plateNumber = (log['plateNumber'] ?? '').toLowerCase();
        final block = (log['blockLot'] ?? log['ownerAddress'] ?? '')
            .toLowerCase();

        if (!name.contains(searchLower) &&
            !plateNumber.contains(searchLower) &&
            !block.contains(searchLower)) {
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

      // Add cover page
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

      // Add logs data page
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
                final timestamp = _formatTimestampForPDF(
                  log['scanTimestamp'] ??
                      log['localSaveTime'] ??
                      log['createdAt'],
                );
                final type = _getLogTypeDisplay(log['type'] ?? 'VEHICLE_SCAN');
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

      // Print the PDF
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

  // ✅ Format timestamp for PDF
  String _formatTimestampForPDF(dynamic timestamp) {
    if (timestamp == null) return '--:-- --';

    try {
      DateTime time;
      if (timestamp is String) {
        time = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        time = timestamp;
      } else {
        return timestamp.toString();
      }

      return '${time.month}/${time.day}/${time.year} ${_formatTime(time)}';
    } catch (e) {
      return timestamp.toString();
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
                final combinedLogs = await _getCombinedLogs();
                final vehicleLogs = combinedLogs
                    .where(
                      (log) =>
                          log['type'] == 'VEHICLE_SCAN' ||
                          log['plateNumber'] != null,
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
                if (logs != null) {
                  final panicLogs = logs
                      .where((log) => log['type'] == 'PANIC')
                      .toList();
                  await _generatePDFReport(
                    panicLogs,
                    "PANIC ALERT LOGS REPORT",
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.people, color: Colors.blue),
              title: const Text("Visitor Logs"),
              subtitle: const Text("Export all visitor records"),
              onTap: () async {
                Navigator.pop(context);
                final logs = await _logsFuture;
                if (logs != null) {
                  final visitorLogs = logs
                      .where((log) => log['type'] == 'VISITOR')
                      .toList();
                  await _generatePDFReport(visitorLogs, "VISITOR LOGS REPORT");
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.green),
              title: const Text("Complete Report"),
              subtitle: const Text("Export all security logs"),
              onTap: () async {
                Navigator.pop(context);
                final combinedLogs = await _getCombinedLogs();
                await _generatePDFReport(
                  combinedLogs,
                  "COMPLETE SECURITY LOGS REPORT",
                );
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
        return Colors.green;
      case 'PANIC':
        return Colors.red;
      case 'VISITOR':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  // ✅ Get log details text
  String _getLogDetails(Map<String, dynamic> log) {
    final type = log['type']?.toUpperCase() ?? 'VEHICLE_SCAN';

    switch (type) {
      case 'VEHICLE_SCAN':
        final plateNumber = log['plateNumber'] ?? 'N/A';
        final ownerName = log['ownerName'] ?? '';
        final vehicleType = log['vehicleType'] ?? '';
        String details = plateNumber;
        if (ownerName.isNotEmpty) details += ' - $ownerName';
        if (vehicleType.isNotEmpty) details += ' ($vehicleType)';
        return details;
      case 'PANIC':
        final blockLot = log['blockLot'] ?? log['ownerAddress'] ?? 'N/A';
        final residentName = log['name'] ?? 'Unknown Resident';
        return '$residentName - Location: $blockLot';
      case 'VISITOR':
        return log['purpose'] ??
            log['details'] ??
            log['name'] ??
            'Visitor Entry';
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
        statusUpper == 'RESOLVED') {
      return Colors.green;
    } else if (statusUpper == 'PENDING') {
      return Colors.orange;
    } else if (statusUpper == 'REJECTED') {
      return Colors.red;
    }
    return Colors.green;
  }

  // ✅ Get formatted timestamp
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '--:-- --';

    try {
      DateTime time;
      if (timestamp is String) {
        time = DateTime.parse(timestamp);
      } else if (timestamp is DateTime) {
        time = timestamp;
      } else {
        return timestamp.toString();
      }

      final formatted =
          '${_getMonthAbbr(time.month)} ${time.day}, ${time.year} - ${_formatTime(time)}';
      return formatted;
    } catch (e) {
      return timestamp.toString();
    }
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
                              future: _getCombinedLogs(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                        ConnectionState.waiting ||
                                    _isLoadingLocal) {
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
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final allLogs = snapshot.data!;
                                final filteredLogs = _filterLogs(allLogs);

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
                                        log['type'] ?? 'VEHICLE_SCAN',
                                      );
                                      final logDetails = _getLogDetails(log);
                                      final status =
                                          log['status'] ?? 'APPROVED';
                                      final timestamp = _formatTimestamp(
                                        log['scanTimestamp'] ??
                                            log['localSaveTime'] ??
                                            log['createdAt'],
                                      );

                                      return _buildLogRow(
                                        logType,
                                        logDetails,
                                        status,
                                        timestamp,
                                        _getLogTypeColor(
                                          log['type'] ?? 'VEHICLE_SCAN',
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
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
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
              onChanged: (value) {
                setState(() {
                  _filterType = value ?? 'ALL';
                });
              },
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
