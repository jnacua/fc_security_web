import 'package:flutter/material.dart';
import 'security_sidebar.dart';
import 'api_service.dart';

class SecurityDashboard extends StatefulWidget {
  const SecurityDashboard({super.key});

  @override
  State<SecurityDashboard> createState() => _SecurityDashboardState();
}

class _SecurityDashboardState extends State<SecurityDashboard> {
  late Future<Map<String, dynamic>> _statsFuture;
  late Future<List<dynamic>> _recentLogsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ✅ Loads both the card statistics and the activity feed
  void _loadData() {
    setState(() {
      _statsFuture = ApiService.getSecurityDashboardStats();
      _recentLogsFuture = ApiService.getAllSecurityLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. SIDEBAR
          const SecuritySideNav(activeRoute: '/security_dashboard'),

          // 2. MAIN CONTENT AREA
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

                        // ✅ STATS ROW: Specifically for Visitors and Panics
                        FutureBuilder<Map<String, dynamic>>(
                          future: _statsFuture,
                          builder: (context, snapshot) {
                            final data = snapshot.data ?? {};
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
                                  "PANIC REPORTS",
                                  data['panics']?.toString() ?? "0",
                                  Icons.warning_amber_rounded,
                                  Colors.red,
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 30),

                        // ✅ RECENT ACTIVITY HEADER
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
                            TextButton.icon(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text("REFRESH FEED"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),

                        // ✅ ACTIVITY TABLE/LIST
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
          color: Colors.white, // ✅ Correctly placed inside BoxDecoration
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
        color: Colors.white, // ✅ Correctly placed inside BoxDecoration
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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(50),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final logs = snapshot.data?.take(10).toList() ?? [];

          return Column(
            children: [
              if (logs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text("No recent activity detected."),
                )
              else
                ...logs.map((log) => _buildLogItem(log)).toList(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLogItem(dynamic log) {
    final bool isPanic = log['type'] == "PANIC";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Icon(
            isPanic ? Icons.error_outline : Icons.person_outline,
            color: isPanic ? Colors.red : Colors.blue,
            size: 22,
          ),
          const SizedBox(width: 15),
          Expanded(
            flex: 2,
            child: Text(
              log['type'] ?? "",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isPanic ? Colors.red : Colors.blue,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              log['name'] ?? "Unknown",
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isPanic ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              log['status'] ?? "",
              style: TextStyle(
                color: isPanic ? Colors.red : Colors.green,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      // ✅ decoration handles the background color now
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
