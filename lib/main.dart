import 'package:flutter/material.dart';
// Import SystemMouseCursors
import 'package:responsive_framework/responsive_framework.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:route_force/widgets/auth_gate.dart'; // Import the new AuthGate widget

Future<void> main() async {
  // Make main async
  // Initialize Google Maps before running the app
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      //brightness: Brightness.light, // Default for ThemeData
    );

    final ThemeData darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      //brightness: Brightness.dark,
    );

    return MaterialApp(
      builder:
          (context, child) => ResponsiveBreakpoints.builder(
            child: child!,
            breakpoints: [
              const Breakpoint(start: 0, end: 450, name: MOBILE),
              const Breakpoint(start: 451, end: 800, name: TABLET),
              const Breakpoint(start: 801, end: double.infinity, name: DESKTOP),
            ],
          ),
      title: 'Trip Planner',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system, // This tells Flutter to use the system theme
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
    );
  }
}
