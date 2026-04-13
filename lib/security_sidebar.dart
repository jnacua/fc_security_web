import 'package:flutter/material.dart';
import 'api_service.dart'; // ✅ Import your ApiService

class SecuritySideNav extends StatefulWidget {
  final String activeRoute; // Matches the Admin logic

  const SecuritySideNav({super.key, required this.activeRoute});

  @override
  State<SecuritySideNav> createState() => _SecuritySideNavState();
}

class _SecuritySideNavState extends State<SecuritySideNav> {
  @override
  void initState() {
    super.initState();
    // ✅ Initialize the global socket listener as soon as the sidebar loads
    ApiService.initSocket();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      color: const Color(0xFF176F63),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LOGO (Replaced Image with a clean Icon & Text)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(12.0),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.shield, size: 28, color: Color(0xFF176F63)),
                SizedBox(width: 8),
                Text(
                  "FC SECURITY",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF176F63),
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(flex: 1),

          // NAV BUTTONS (Using Routes)
          // Note: We use widget.activeRoute because it's now a StatefulWidget
          _NavButton(
            "DASHBOARD",
            '/security_dashboard',
            widget.activeRoute,
            context,
          ),
          _NavButton(
            "VISITOR SCANNING",
            '/visitor_scanning',
            widget.activeRoute,
            context,
          ),
          _NavButton(
            "PANIC REPORT",
            '/panic_report',
            widget.activeRoute,
            context,
          ),
          _NavButton("LOGS", '/security_logs', widget.activeRoute, context),

          const Spacer(flex: 2),

          // LOGOUT
          _NavButton(
            "LOG OUT",
            '/login',
            widget.activeRoute,
            context,
            isLogout: true,
          ),
        ],
      ),
    );
  }

  Widget _NavButton(
    String label,
    String route,
    String activeRoute,
    BuildContext context, {
    bool isLogout = false,
  }) {
    bool isActive = activeRoute == route;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 40,
        child: ElevatedButton(
          onPressed: () {
            if (isLogout) {
              // Handle Logout logic here
              Navigator.pushReplacementNamed(context, '/login');
            } else if (!isActive) {
              // Navigate only if different page
              Navigator.pushReplacementNamed(context, route);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? Colors.white : const Color(0xFF176F63),
            foregroundColor: isActive ? const Color(0xFF176F63) : Colors.white,
            elevation: isActive ? 2 : 0,
            side: const BorderSide(color: Colors.white, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
