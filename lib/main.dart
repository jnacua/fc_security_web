import 'package:flutter/material.dart';

// SCREEN IMPORTS
import 'security_login_screen.dart'; // ✅ Added Login Screen Import
import 'security_dashboard.dart';
import 'visitor_scanning.dart';
import 'panic_report.dart';
import 'security_logs.dart';
// ✅ ADD THIS IMPORT for your new Resident Vehicle QR Scanner pagefl
import 'vehicle_scanning_page.dart';

// ✅ 1. Add this GlobalKey globally so ApiService can use it for the Panic Pop-up
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

void main() {
  runApp(const SecurityApp());
}

class SecurityApp extends StatelessWidget {
  const SecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fiesta Casitas Security',

      // ✅ 2. Attach the master key to your MaterialApp
      navigatorKey: globalNavigatorKey,

      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176F63)),
        useMaterial3: true,
      ),

      // ✅ Changed initialRoute to Login instead of Dashboard
      initialRoute: '/login',

      // Route Generator (Standard Admin Pattern)
      onGenerateRoute: (settings) {
        Widget page;

        switch (settings.name) {
          case '/login': // ✅ Added Login Case
            page = const SecurityLoginScreen();
            break;
          case '/security_dashboard':
            page = const SecurityDashboard();
            break;
          case '/visitor_scanning':
            // This is your existing page for manual visitor entry
            page = const VisitorScanningScreen();
            break;
          // ✅ ADDED THIS CASE so clicking the sidebar doesn't go to login
          case '/vehicle_scanning':
            page = const VehicleScanningPage();
            break;
          case '/panic_report':
            page = const PanicReportScreen();
            break;
          case '/security_logs':
            page = const SecurityLogsScreen();
            break;

          default:
            // If route not found, go back to login
            page = const SecurityLoginScreen();
        }

        // Zero-duration transition makes it feel instant like a web tab
        return PageRouteBuilder(
          settings: settings,
          pageBuilder: (_, __, ___) => page,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
      },
    );
  }
}
