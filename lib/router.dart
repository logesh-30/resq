import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/role_selection_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/user/user_setup_screen.dart';
import 'screens/user/dashboard_screen.dart';
import 'screens/user/tracking_screen.dart';
import 'screens/user/history_screen.dart';
import 'screens/driver/driver_setup_screen.dart';
import 'screens/driver/driver_dashboard_screen.dart';
import 'screens/driver/navigation_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final loggingIn = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/';
      if (user == null && !loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (c, s) => const RoleSelectionScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/user-setup', builder: (c, s) => const UserSetupScreen()),
      GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
      GoRoute(path: '/history', builder: (c, s) => const HistoryScreen()),
      GoRoute(
        path: '/tracking/:emergencyId',
        builder: (c, s) => TrackingScreen(
          emergencyId: s.pathParameters['emergencyId']!,
        ),
      ),
      GoRoute(
          path: '/driver-setup', builder: (c, s) => const DriverSetupScreen()),
      GoRoute(
          path: '/driver-dashboard',
          builder: (c, s) => const DriverDashboardScreen()),
      GoRoute(
        path: '/driver-navigation/:emergencyId',
        builder: (c, s) => DriverNavigationScreen(
          emergencyId: s.pathParameters['emergencyId']!,
        ),
      ),
    ],
  );
});
