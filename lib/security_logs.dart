import 'package:flutter/material.dart';
import 'security_sidebar.dart';
import 'api_service.dart'; // ✅ Ensure this is imported

class SecurityLogsScreen extends StatefulWidget {
  const SecurityLogsScreen({super.key});

  @override
  State<SecurityLogsScreen> createState() => _SecurityLogsScreenState();
}

class _SecurityLogsScreenState extends State<SecurityLogsScreen> {
  late Future<List<dynamic>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = ApiService.getAllSecurityLogs();
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
                                if (!snapshot.hasData ||
                                    snapshot.data!.isEmpty) {
                                  return const Center(
                                    child: Text("No logs found."),
                                  );
                                }

                                final logs = snapshot.data!;
                                return RefreshIndicator(
                                  onRefresh: () async {
                                    setState(() {
                                      _logsFuture =
                                          ApiService.getAllSecurityLogs();
                                    });
                                  },
                                  child: ListView.separated(
                                    itemCount: logs.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final log = logs[index];
                                      return _buildLogRow(
                                        log['type'] ?? 'VISITOR',
                                        log['name'] ?? 'N/A',
                                        log['status'] ?? 'COMPLETED',
                                        log['timestamp'] ?? '--:--',
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

  Widget _buildLogRow(String type, String name, String status, String time) {
    // ✅ Dynamic styling based on log type
    Color typeColor = type == "PANIC" ? Colors.red : Colors.blue;

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
              name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              status,
              style: TextStyle(
                color: status == "IN" || status == "RESOLVED"
                    ? Colors.green
                    : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(time, style: const TextStyle(color: Colors.grey)),
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
          child: Text(
            "DETAILS / NAME",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
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

  Widget _buildSearchAndFilter() => const Padding(
    padding: EdgeInsets.all(16.0),
    child: TextField(
      decoration: InputDecoration(
        hintText: "SEARCH BY NAME OR BLOCK...",
        prefixIcon: Icon(Icons.search),
        filled: true,
        fillColor: Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderSide: BorderSide.none),
      ),
    ),
  );

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
