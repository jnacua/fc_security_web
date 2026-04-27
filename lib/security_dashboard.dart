import 'package:flutter/material.dart';
import 'security_sidebar.dart';
import 'api_service.dart';
import 'dart:async';

class SecurityDashboard extends StatefulWidget {
  const SecurityDashboard({super.key});

  @override
  State<SecurityDashboard> createState() => _SecurityDashboardState();
}

class _SecurityDashboardState extends State<SecurityDashboard> {
  late Future<Map<String, dynamic>> _statsFuture;
  late Future<List<dynamic>> _recentLogsFuture;
  String _selectedDateFilter = 'TODAY';
  List<dynamic> _allLogs = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  // Date filter options
  final List<String> _dateFilters = [
    'TODAY',
    'YESTERDAY',
    'THIS WEEK',
    'LAST 7 DAYS',
    'ALL TIME',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _loadData() {
    setState(() {
      _statsFuture = ApiService.getSecurityDashboardStats();
      _recentLogsFuture = ApiService.getAllSecurityLogs().then((logs) {
        _allLogs = logs;
        _isLoading = false;
        return logs;
      });
    });
  }

  List<dynamic> _filterLogsByDate(List<dynamic> logs) {
    if (_selectedDateFilter == 'ALL TIME') return logs;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return logs.where((log) {
      DateTime logDate;
      try {
        final timestamp =
            log['timestamp'] ??
            log['scanTimestamp'] ??
            log['entryTime'] ??
            log['createdAt'];
        if (timestamp == null) return false;
        logDate = DateTime.parse(timestamp.toString());
      } catch (e) {
        return false;
      }

      switch (_selectedDateFilter) {
        case 'TODAY':
          return logDate.year == today.year &&
              logDate.month == today.month &&
              logDate.day == today.day;
        case 'YESTERDAY':
          final yesterday = today.subtract(const Duration(days: 1));
          return logDate.year == yesterday.year &&
              logDate.month == yesterday.month &&
              logDate.day == yesterday.day;
        case 'THIS WEEK':
          final weekStart = today.subtract(Duration(days: today.weekday - 1));
          return logDate.isAfter(weekStart.subtract(const Duration(days: 1)));
        case 'LAST 7 DAYS':
          final sevenDaysAgo = today.subtract(const Duration(days: 7));
          return logDate.isAfter(sevenDaysAgo);
        default:
          return true;
      }
    }).toList();
  }

  int _countVehicleScansToday(List<dynamic> logs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return logs.where((log) {
      final isVehicle =
          (log['type'] == 'VEHICLE' || log['type'] == 'VEHICLE_SCAN') &&
          log['visitorName'] == null;
      if (!isVehicle) return false;

      try {
        final timestamp =
            log['timestamp'] ?? log['scanTimestamp'] ?? log['createdAt'];
        if (timestamp == null) return false;
        final logDate = DateTime.parse(timestamp.toString());
        return logDate.year == today.year &&
            logDate.month == today.month &&
            logDate.day == today.day;
      } catch (e) {
        return false;
      }
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SecuritySideNav(activeRoute: '/security_dashboard'),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(25.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "SECURITY OVERVIEW",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 15),

                        FutureBuilder<Map<String, dynamic>>(
                          future: _statsFuture,
                          builder: (context, snapshot) {
                            final data = snapshot.data ?? {};
                            final vehicleScansToday = _isLoading
                                ? 0
                                : _countVehicleScansToday(_allLogs);
                            final totalPanics = _isLoading
                                ? 0
                                : _allLogs
                                      .where((log) => log['type'] == "PANIC")
                                      .length;

                            return Row(
                              children: [
                                _buildStatCard(
                                  "TOTAL VISITORS",
                                  data['visitors']?.toString() ?? "0",
                                  Icons.people_alt,
                                  Colors.blue,
                                ),
                                const SizedBox(width: 20),
                                _buildStatCard(
                                  "VEHICLE SCANS",
                                  vehicleScansToday.toString(),
                                  Icons.directions_car,
                                  Colors.green,
                                ),
                                const SizedBox(width: 20),
                                _buildStatCard(
                                  "PANIC REPORTS",
                                  totalPanics.toString(),
                                  Icons.warning_amber_rounded,
                                  Colors.red,
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 30),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "LIVE ACTIVITY FEED",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: DropdownButton<String>(
                                    value: _selectedDateFilter,
                                    underline: const SizedBox(),
                                    items: _dateFilters.map((filter) {
                                      return DropdownMenuItem(
                                        value: filter,
                                        child: Text(filter),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedDateFilter = value ?? 'TODAY';
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                TextButton.icon(
                                  onPressed: _loadData,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text("REFRESH FEED"),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),

                        _buildActivityTable(),
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

  Widget _buildStatCard(
    String title,
    String count,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 25),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 25),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FutureBuilder<List<dynamic>>(
        future: _recentLogsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting ||
              _isLoading) {
            return const Padding(
              padding: EdgeInsets.all(50),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(50),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 50,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 10),
                    Text("Error loading logs: ${snapshot.error}"),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _loadData,
                      child: const Text("RETRY"),
                    ),
                  ],
                ),
              ),
            );
          }

          final allLogs = snapshot.data ?? [];
          final filteredLogs = _filterLogsByDate(allLogs);
          final filterSummary = _getFilterSummary();

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      filterSummary,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      "Total: ${filteredLogs.length} entries",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        "TYPE",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        "NAME / DETAILS",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        "STATUS",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        "DATE & TIME",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (filteredLogs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(Icons.history, size: 50, color: Colors.grey),
                      SizedBox(height: 10),
                      Text("No activity found for selected date range."),
                    ],
                  ),
                )
              else
                // ✅ FIXED: Show ALL filtered logs instead of only 20
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredLogs.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final log = filteredLogs[index];
                    return _buildLogItem(log);
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  String _getFilterSummary() {
    switch (_selectedDateFilter) {
      case 'TODAY':
        return '📅 Showing logs for TODAY (${_getTodayDate()})';
      case 'YESTERDAY':
        return '📅 Showing logs for YESTERDAY (${_getYesterdayDate()})';
      case 'THIS WEEK':
        return '📅 Showing logs for THIS WEEK (${_getWeekRange()})';
      case 'LAST 7 DAYS':
        return '📅 Showing logs for LAST 7 DAYS';
      case 'ALL TIME':
        return '📅 Showing ALL TIME logs';
      default:
        return '📅 Showing logs';
    }
  }

  String _getTodayDate() {
    final now = DateTime.now();
    return '${now.month}/${now.day}/${now.year}';
  }

  String _getYesterdayDate() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return '${yesterday.month}/${yesterday.day}/${yesterday.year}';
  }

  String _getWeekRange() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';
  }

  // ✅ IMPROVED: Better log type detection for visitor entries
  Widget _buildLogItem(dynamic log) {
    // Determine log type with priority checks
    final bool hasVisitorName = log['visitorName'] != null;
    final bool hasResidentName = log['residentName'] != null;
    final bool hasPlateNumber =
        log['plateNumber'] != null && log['plateNumber'] != 'N/A';
    final bool hasOwnerName = log['ownerName'] != null;

    // Priority 1: Check if it's a PANIC (has residentName or type PANIC)
    final bool isPanic = log['type'] == "PANIC" || hasResidentName;

    // Priority 2: Check if it's a VISITOR (has visitorName or type VISITOR)
    final bool isVisitor = log['type'] == "VISITOR" || hasVisitorName;

    // Priority 3: Check if it's a VEHICLE (has plateNumber and ownerName, and not visitor)
    final bool isVehicle =
        (log['type'] == "VEHICLE" ||
            log['type'] == "VEHICLE_SCAN" ||
            (hasPlateNumber && hasOwnerName)) &&
        !isVisitor;

    IconData icon;
    Color iconColor;
    String displayType;
    String details;

    if (isPanic) {
      icon = Icons.warning_amber_rounded;
      iconColor = Colors.red;
      displayType = "PANIC";
      details = log['residentName'] ?? log['name'] ?? 'Unknown Resident';
      if (log['blockLot'] != null && log['blockLot'] != 'N/A') {
        details += " - ${log['blockLot']}";
      }
    } else if (isVisitor) {
      icon = Icons.person_outline;
      iconColor = Colors.blue;
      displayType = "VISITOR";
      details = log['visitorName'] ?? log['name'] ?? 'Unknown Visitor';
      if (log['purpose'] != null && log['purpose'] != 'Visit') {
        details += " - ${log['purpose']}";
      }
      if (log['residentToVisit'] != null &&
          log['residentToVisit'] != 'Unknown') {
        details += " (Visiting: ${log['residentToVisit']})";
      }
      if (hasPlateNumber && log['plateNumber'] != 'N/A') {
        details += " [Vehicle: ${log['plateNumber']}]";
      }
    } else if (isVehicle) {
      icon = Icons.directions_car;
      iconColor = Colors.green;
      displayType = "VEHICLE";
      String plate = log['plateNumber'] ?? 'N/A';
      String owner = log['ownerName'] ?? log['name'] ?? 'Unknown';
      details = "$plate - $owner";
      if (log['vehicleType'] != null && log['vehicleType'] != 'N/A') {
        details += " (${log['vehicleType']})";
      }
    } else {
      icon = Icons.info_outline;
      iconColor = Colors.grey;
      displayType = "OTHER";
      details = log['name'] ?? log['details'] ?? 'Unknown';
    }

    String status = log['status'] ?? "COMPLETED";
    Color statusColor = isPanic
        ? Colors.red
        : (isVehicle ? Colors.green : Colors.blue);

    String dateTime = '--:-- --';
    if (log['formattedTime'] != null) {
      dateTime = log['formattedTime'].toString();
    } else {
      dateTime = _fallbackFormatDateTime(log);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Text(
                  displayType,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: iconColor,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              details,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              dateTime,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _fallbackFormatDateTime(dynamic log) {
    try {
      final timestamp =
          log['timestamp'] ??
          log['scanTimestamp'] ??
          log['entryTime'] ??
          log['createdAt'];

      if (timestamp == null) return '--:-- --';

      DateTime time;
      if (timestamp is DateTime) {
        time = timestamp;
      } else if (timestamp is String) {
        time = DateTime.parse(timestamp);
      } else {
        return '--:-- --';
      }

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
      int hour = time.hour;
      final minute = time.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;

      return '${months[time.month - 1]} ${time.day}, ${time.year} - $hour:$minute $period';
    } catch (e) {
      return '--:-- --';
    }
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "SECURITY PORTAL",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A332F),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.notifications_none, color: Colors.grey),
              const SizedBox(width: 20),
              Container(
                height: 40,
                width: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFF176F63),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
