import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'main_navigation.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Wellness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A237E),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          if (!snapshot.data!.emailVerified && snapshot.data!.providerData.every((p) => p.providerId == 'password')) {
            // User is logged in via email/password but not verified
            return const LoginScreen(requireVerification: true);
          }
          return const _PermissionCheck();
        }
        return const LoginScreen();
      },
    );
  }
}

// Checks if onboarding is done; if yes, skip to main navigation
class _PermissionCheck extends StatefulWidget {
  const _PermissionCheck();

  @override
  State<_PermissionCheck> createState() => _PermissionCheckState();
}

class _PermissionCheckState extends State<_PermissionCheck> {
  bool _checking = true;
  bool _onboardingDone = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool('onboarding_done') ?? false;
    setState(() {
      _onboardingDone = done;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_onboardingDone) {
      return const MainNavigationScreen();
    }
    return OnboardingScreen(
      onComplete: () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_done', true);
        setState(() => _onboardingDone = true);
      },
    );
  }
}
