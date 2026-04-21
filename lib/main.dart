import 'package:flutter/material.dart';
import 'api_service.dart'; // Adjust path as needed

// SCREEN IMPORTS
import 'security_login_screen.dart';
import 'security_dashboard.dart';
import 'visitor_scanning.dart';
import 'panic_report.dart';
import 'security_logs.dart';
import 'vehicle_scanning_page.dart';

// ✅ GlobalKey for ApiService to use for the Panic Pop-up
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize socket connection on app start
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ApiService.initSocketAndListen();
  });

  runApp(const SecurityApp());
}

class SecurityApp extends StatelessWidget {
  const SecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fiesta Casitas Security',

      // ✅ Attach the master key to your MaterialApp
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
          case '/login':
            page = const SecurityLoginScreen();
            break;
          case '/security_dashboard':
            page = const SecurityDashboard();
            break;
          case '/visitor_scanning':
            page = const VisitorScanningScreen();
            break;
          case '/vehicle_scanning':
            page = const VehicleScanningPage();
            break;
          case '/panic_report':
            page = const PanicReportScreen();
            break;
          case '/security_logs':
            page = const SecurityLogs();
            break;
          default:
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
