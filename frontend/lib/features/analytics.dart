import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/data_view.dart';
import '../core/theme.dart';
import 'operations.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int days = 30;
  String category = '';
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeading('Revenue intelligence',
            'Attribute the impact of every agent-assisted order.',
            action: Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<int>(
                      value: days,
                      items: [7, 30, 90, 365]
                          .map((d) => DropdownMenuItem(
                              value: d, child: Text('Last $d days')))
                          .toList(),
                      onChanged: (v) => setState(() => days = v!),
                      decoration: const InputDecoration(labelText: 'Period'))),
              SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                      value: category,
                      items: [
                        '',
                        'headphones',
                        'monitors',
                        'laptops',
                        'adapters',
                        'keyboards',
                        'chargers'
                      ]
                          .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.isEmpty ? 'All categories' : c)))
                          .toList(),
                      onChanged: (v) => setState(() => category = v!),
                      decoration: const InputDecoration(labelText: 'Category')))
            ])),
        DataView(
            path: 'analytics/revenue?days=$days&category=$category',
            builder: (d, refresh) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ResponsiveGrid(children: [
                    Metric(
                        'Verified revenue',
                        money(d['revenue']),
                        '${d['orders']} completed payments',
                        Icons.payments_outlined),
                    Metric(
                        'Net AI increment',
                        money(d['attribution']['incremental']),
                        'Final revenue minus baseline',
                        Icons.auto_awesome,
                        highlight: true),
                    Metric(
                        'Bulk revenue',
                        money(d['bulk_revenue']),
                        '${d['bulk_opportunities']} opportunities surfaced',
                        Icons.business_outlined),
                    Metric('Average discount', '${d['average_discount']}%',
                        'Across negotiated offers', Icons.percent)
                  ]),
                  const SizedBox(height: 24),
                  GlassCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Revenue over time',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 30),
                        if ((d['daily'] as List).isEmpty)
                          const EmptyState('No captured revenue in this period',
                              'Your chart will populate from verified orders.',
                              icon: Icons.stacked_line_chart)
                        else
                          SizedBox(
                              height: 260,
                              child: BarChart(BarChartData(
                                  gridData: const FlGridData(
                                      show: true, drawVerticalLine: false),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                      topTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                      rightTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                      bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 32,
                                              getTitlesWidget: (value, meta) {
                                                final i = value.toInt();
                                                return i < 0 ||
                                                        i >=
                                                            (d['daily'] as List)
                                                                .length
                                                    ? const SizedBox()
                                                    : Text(
                                                        d['daily'][i]['date']
                                                            .toString()
                                                            .substring(5),
                                                        style: const TextStyle(
                                                            color: muted,
                                                            fontSize: 12));
                                              })),
                                      leftTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                              showTitles: true,
                                              reservedSize: 50))),
                                  barGroups: List.generate(
                                      (d['daily'] as List).length,
                                      (i) => BarChartGroupData(x: i, barRods: [
                                            BarChartRodData(
                                                toY: (d['daily'][i]['revenue']
                                                        as num) /
                                                    100,
                                                color: mint,
                                                width: 20,
                                                borderRadius:
                                                    BorderRadius.circular(5))
                                          ])))))
                      ])),
                  const SizedBox(height: 24),
                  GlassCard(
                      accent: true,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Exact revenue attribution',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 24),
                            ResponsiveGrid(minWidth: 180, children: [
                              detail('Baseline cart value',
                                  money(d['attribution']['baseline'])),
                              detail('+ Upsell value',
                                  money(d['attribution']['upsell'])),
                              detail('+ Cross-sell value',
                                  money(d['attribution']['cross_sell'])),
                              detail('− Discount cost',
                                  money(d['attribution']['discount'])),
                              detail('= Final revenue', money(d['revenue']))
                            ]),
                            const SizedBox(height: 20),
                            const Text(
                                'Net AI incremental revenue = upsell + cross-sell − discounts. Only confirmed orders are counted.',
                                style: TextStyle(color: muted, fontSize: 13))
                          ])),
                  const SizedBox(height: 24),
                  ResponsiveGrid(minWidth: 340, children: [
                    GlassCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Negotiation performance',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 20),
                          for (final pair in [
                            ('Started', d['negotiations']),
                            ('Average rounds', d['average_rounds']),
                            ('Abandoned', d['abandoned']),
                            ('Rescue discounts', d['rescue_discounts']),
                            ('Median discount', d['median_discount'])
                          ])
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(pair.$1),
                                trailing: Text('${pair.$2}',
                                    style: const TextStyle(
                                        color: mint, fontSize: 20)))
                        ])),
                    GlassCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Discovery rejection reasons',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          if ((d['rejections'] as Map).isEmpty)
                            const EmptyState('No rejection data',
                                'Run a discovery request to inspect catalog gaps.')
                          else
                            ...(d['rejections'] as Map).entries.map((e) =>
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(e.key),
                                    trailing: Tag('${e.value}', color: amber)))
                        ]))
                  ])
                ]))
      ]);
}
