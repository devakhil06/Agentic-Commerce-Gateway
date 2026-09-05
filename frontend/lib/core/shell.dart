import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'api.dart';
import 'theme.dart';

const destinations = <(String, String, IconData)>[
  ('/dashboard', 'Overview', Icons.grid_view_rounded),
  ('/catalog', 'Product catalog', Icons.inventory_2_outlined),
  ('/readiness', 'AI readiness', Icons.radar),
  ('/buyer', 'Buyer simulator', Icons.auto_awesome_outlined),
  ('/negotiations', 'Negotiations', Icons.forum_outlined),
  ('/approvals', 'Approval center', Icons.fact_check_outlined),
  ('/policies', 'Merchant policies', Icons.tune_rounded),
  ('/transactions', 'Transactions', Icons.receipt_long_outlined),
  ('/analytics', 'Revenue analytics', Icons.bar_chart_rounded),
  ('/audit', 'Audit timeline', Icons.history_rounded),
  ('/settings', 'Integrations', Icons.extension_outlined),
];

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path,
        session = ref.watch(sessionProvider);
    final compact = MediaQuery.sizeOf(context).width < 1000;
    final nav = Container(
        width: 244,
        decoration: const BoxDecoration(
            color: Color(0xE6162021),
            border: Border(right: BorderSide(color: Colors.white10))),
        child: SafeArea(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(28, 32, 24, 30),
              child: Row(children: [
                Icon(Icons.hub_rounded, color: mint, size: 30),
                SizedBox(width: 12),
                Text('ACG',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3))
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: GlassCard(
                  padding: 14,
                  child: Row(children: [
                    Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                            color: mint.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.storefront_outlined,
                            color: mint, size: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              session?['merchant']?['name'] ?? 'Your workspace',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                          const Text('Merchant workspace',
                              style: TextStyle(fontSize: 12, color: muted))
                        ]))
                  ]))),
          const SizedBox(height: 26),
          Expanded(
              child: ListView(children: [
            for (var i = 0; i < destinations.length; i++) ...[
              if (i == 0 || i == 3 || i == 7)
                Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 24, 12),
                    child: Text(
                        i == 0
                            ? 'WORKSPACE'
                            : i == 3
                                ? 'COMMERCE'
                                : 'INTELLIGENCE',
                        style: const TextStyle(
                            fontSize: 11,
                            color: muted,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600))),
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Material(
                      color: path == destinations[i].$1
                          ? mint.withValues(alpha: .12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          leading: Icon(destinations[i].$3,
                              size: 20,
                              color: path == destinations[i].$1 ? mint : muted),
                          title: Text(destinations[i].$2,
                              style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      path == destinations[i].$1 ? mint : muted,
                                  fontWeight: path == destinations[i].$1
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                          onTap: () {
                            if (compact) Navigator.of(context).pop();
                            context.go(destinations[i].$1);
                          })))
            ]
          ])),
          Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Tag('TEST ENVIRONMENT', color: amber),
                    const SizedBox(height: 14),
                    TextButton.icon(
                        onPressed: () {
                          ref.read(apiProvider).logout();
                          ref.read(buyerStateProvider.notifier).state = {};
                          ref.read(sessionProvider.notifier).state = null;
                          context.go('/login');
                        },
                        icon: const Icon(Icons.logout, size: 16, color: muted),
                        label: const Text('Sign out',
                            style: TextStyle(color: muted)))
                  ]))
        ])));
    return Scaffold(
        drawer: compact ? Drawer(child: nav) : null,
        body: Container(
            decoration: const BoxDecoration(
                gradient: RadialGradient(
                    center: Alignment(.8, -1),
                    radius: 1.4,
                    colors: [Color(0xFF1C302A), background])),
            child: Row(children: [
              if (!compact) nav,
              Expanded(
                  child: Column(children: [
                Container(
                    height: 78,
                    padding:
                        EdgeInsets.symmetric(horizontal: compact ? 18 : 36),
                    decoration: const BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: Colors.white10))),
                    child: Row(children: [
                      if (compact)
                        Builder(
                            builder: (ctx) => IconButton(
                                onPressed: () => Scaffold.of(ctx).openDrawer(),
                                icon: const Icon(Icons.menu))),
                      const Text('Merchant console',
                          style: TextStyle(color: muted, fontSize: 14)),
                      const Spacer(),
                      const Icon(Icons.shield_outlined, color: mint, size: 17),
                      const SizedBox(width: 8),
                      if (MediaQuery.sizeOf(context).width > 550)
                        const Text('Policy protected',
                            style: TextStyle(color: muted, fontSize: 13)),
                      const SizedBox(width: 20),
                      IconButton(
                          tooltip: 'Refresh workspace',
                          onPressed: () =>
                              ref.read(revisionProvider.notifier).state++,
                          icon: const Icon(Icons.refresh,
                              size: 20, color: muted)),
                      const SizedBox(width: 10),
                      const CircleAvatar(
                          radius: 18,
                          backgroundColor: Color(0xFF344D43),
                          child: Text('M',
                              style: TextStyle(color: mint, fontSize: 14)))
                    ])),
                Expanded(
                    child: SingleChildScrollView(
                        padding: EdgeInsets.all(compact ? 20 : 36),
                        child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1440),
                                child: child))))
              ]))
            ])));
  }
}
