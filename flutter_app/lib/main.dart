import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/admin_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/queue_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  runApp(SmartQueueApp(api: api));
}

class SmartQueueApp extends StatelessWidget {
  const SmartQueueApp({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthProvider(api)),
        ChangeNotifierProvider(create: (_) => QueueProvider(api)),
        ChangeNotifierProvider(create: (_) => AdminProvider(api)),
      ],
      child: MaterialApp(
        title: 'Smart Queue',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xff145da0),
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xfff7f9fc),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
          ),
          cardTheme: const CardTheme(
            elevation: 0,
            margin: EdgeInsets.zero,
          ),
        ),
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isAuthenticated) return const HomeScreen();
        return const LoginScreen();
      },
    );
  }
}
