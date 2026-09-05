import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/api.dart';
import 'core/shell.dart';
import 'core/theme.dart';
import 'features/auth.dart';
import 'features/dashboard.dart';
import 'features/catalog.dart';
import 'features/buyer.dart';
import 'features/operations.dart';
import 'features/transactions.dart';
import 'features/analytics.dart';
import 'features/settings.dart';

void main() => runApp(const ProviderScope(child: GatewayApp()));

class GatewayApp extends ConsumerStatefulWidget {
  const GatewayApp({super.key});
  @override
  ConsumerState<GatewayApp> createState() => _GatewayAppState();
}

class _GatewayAppState extends ConsumerState<GatewayApp> {
  late final GoRouter router = GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final signedIn = ref.read(sessionProvider) != null;
        if (!signedIn && state.uri.path != '/login') return '/login';
        if (signedIn && state.uri.path == '/login') return '/dashboard';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const AuthScreen()),
        ShellRoute(builder: (_, __, child) => AppShell(child: child), routes: [
          GoRoute(
              path: '/dashboard', builder: (_, __) => const DashboardScreen()),
          GoRoute(path: '/catalog', builder: (_, __) => const CatalogScreen()),
          GoRoute(
              path: '/readiness', builder: (_, __) => const ReadinessScreen()),
          GoRoute(path: '/buyer', builder: (_, __) => const BuyerScreen()),
          GoRoute(
              path: '/negotiations',
              builder: (_, __) => const NegotiationsScreen()),
          GoRoute(
              path: '/approvals', builder: (_, __) => const ApprovalsScreen()),
          GoRoute(
              path: '/policies', builder: (_, __) => const PoliciesScreen()),
          GoRoute(
              path: '/transactions',
              builder: (_, __) => const TransactionsScreen()),
          GoRoute(
              path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
          GoRoute(path: '/audit', builder: (_, __) => const AuditScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen())
        ])
      ]);
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
      title: 'ACG · Merchant Console',
      debugShowCheckedModeBanner: false,
      theme: gatewayTheme(),
      routerConfig: router);
}
