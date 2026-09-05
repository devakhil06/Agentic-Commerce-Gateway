import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/data_view.dart';
import '../core/theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) => DataView(
      path: 'analytics/revenue',
      builder: (data, refresh) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PageHeading('Commerce overview',
                'A clear view of your agent-powered business.',
                action: FilledButton.icon(
                    onPressed: () => context.go('/buyer'),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Launch buyer simulator'))),
            ResponsiveGrid(children: [
              Metric(
                  'Total revenue',
                  money(data['revenue']),
                  'Verified captured payments',
                  Icons.account_balance_wallet_outlined),
              Metric(
                  'AI incremental revenue',
                  money(data['attribution']['incremental']),
                  'After discounts and add-ons',
                  Icons.auto_awesome_outlined,
                  highlight: true),
              Metric(
                  'Average order value',
                  money(data['aov']),
                  '${data['orders']} confirmed orders',
                  Icons.shopping_bag_outlined),
              Metric('Buyer conversion', '${data['conversion']}%',
                  '${data['searches']} discovery requests', Icons.trending_up)
            ]),
            const SizedBox(height: 26),
            LayoutBuilder(builder: (_, box) {
              final activity = GlassCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Your commerce pipeline',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w600))),
                      Tag('Last 30 days', color: muted)
                    ]),
                    const SizedBox(height: 8),
                    const Text('From buyer intent to a verified order.',
                        style: TextStyle(color: muted, fontSize: 14)),
                    const SizedBox(height: 32),
                    ...[
                      (Icons.search, 'Discoveries', data['searches'], mint),
                      (
                        Icons.forum_outlined,
                        'Negotiations',
                        data['negotiations'],
                        const Color(0xFFADD0F7)
                      ),
                      (
                        Icons.fact_check_outlined,
                        'Awaiting approval',
                        data['approvals'],
                        amber
                      ),
                      (
                        Icons.verified_outlined,
                        'Confirmed orders',
                        data['orders'],
                        mint
                      )
                    ].map((row) => Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: Row(children: [
                          Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                  color: row.$4.withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(13)),
                              child: Icon(row.$1, color: row.$4, size: 20)),
                          const SizedBox(width: 16),
                          Expanded(child: Text(row.$2)),
                          Text('${row.$3}',
                              style: const TextStyle(
                                  fontSize: 24, fontWeight: FontWeight.w600))
                        ])))
                  ]));
              final readiness = DataView(
                  path: 'catalog/readiness',
                  builder: (readiness, _) => GlassCard(
                      accent: true,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.radar, color: mint, size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                  child: Text('AI commerce readiness',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 18)))
                            ]),
                            const SizedBox(height: 28),
                            Center(
                                child: SizedBox(
                                    width: 145,
                                    height: 145,
                                    child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          SizedBox.expand(
                                              child: CircularProgressIndicator(
                                                  value: (readiness['score']
                                                          as num) /
                                                      100,
                                                  strokeWidth: 9,
                                                  color: mint,
                                                  backgroundColor:
                                                      Colors.white10,
                                                  strokeCap: StrokeCap.round)),
                                          Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text('${readiness['score']}',
                                                    style: const TextStyle(
                                                        fontSize: 48,
                                                        fontWeight:
                                                            FontWeight.w600)),
                                                const Text('OUT OF 100',
                                                    style: TextStyle(
                                                        color: muted,
                                                        fontSize: 12,
                                                        letterSpacing: 1.5))
                                              ])
                                        ]))),
                            const SizedBox(height: 28),
                            Text(
                                '${readiness['product_count']} products in your agent-readable catalog.',
                                style: const TextStyle(
                                    color: muted, fontSize: 14)),
                            const SizedBox(height: 20),
                            OutlinedButton(
                                onPressed: () => context.go('/readiness'),
                                child: const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('View improvement plan'),
                                      Icon(Icons.arrow_forward, size: 18)
                                    ]))
                          ])));
              return box.maxWidth > 850
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Expanded(flex: 3, child: activity),
                          const SizedBox(width: 22),
                          Expanded(flex: 2, child: readiness)
                        ])
                  : Column(children: [
                      activity,
                      const SizedBox(height: 20),
                      readiness
                    ]);
            }),
            const SizedBox(height: 26),
            GlassCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Recent transactions',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600))),
                    TextButton(
                        onPressed: () => context.go('/transactions'),
                        child: const Text('View all →'))
                  ]),
                  if ((data['recent_orders'] as List).isEmpty)
                    EmptyState('Ready for your first agent order',
                        'Run a buyer session, agree on an offer, then complete Razorpay test checkout.',
                        icon: Icons.receipt_long_outlined,
                        action: OutlinedButton(
                            onPressed: () => context.go('/buyer'),
                            child: const Text('Start a buyer session')))
                  else
                    ...(data['recent_orders'] as List).map((order) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title:
                            Text((order['product_names'] as List).join(', ')),
                        subtitle: Text(timestamp(order['created_at']),
                            style: const TextStyle(color: muted)),
                        trailing: Text(money(order['amount'])),
                        onTap: () => context.go('/transactions')))
                ])),
            const SizedBox(height: 24),
            Wrap(spacing: 20, runSpacing: 12, children: [
              Tag('${data['failures']} transaction exceptions',
                  color: data['failures'] == 0 ? mint : amber),
              const Tag('Deterministic payment protection'),
              const Tag('Razorpay test environment', color: muted)
            ])
          ]));
}
