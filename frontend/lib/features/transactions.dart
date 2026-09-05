import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../core/data_view.dart';
import '../core/theme.dart';
import 'buyer.dart';
import 'operations.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DataView(
      path: 'transactions',
      builder: (data, refresh) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PageHeading('Transactions',
                'Verified payment state, from quote to confirmation.'),
            if ((data['transactions'] as List).isEmpty)
              const GlassCard(
                  child: EmptyState('No transactions yet',
                      'Accept a negotiated offer to reserve stock and prepare checkout.',
                      icon: Icons.receipt_long_outlined))
            else
              ...(data['transactions'] as List).map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: GlassCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Wrap(spacing: 16, runSpacing: 12, children: [
                          Text((t['product_names'] as List).join(' + '),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w600)),
                          Tag(human(t['state']),
                              color: t['state'] == 'ORDER_CONFIRMED'
                                  ? mint
                                  : amber)
                        ]),
                        const SizedBox(height: 20),
                        Wrap(spacing: 30, runSpacing: 16, children: [
                          detail('Order value', preciseMoney(t['amount'])),
                          detail('Created', timestamp(t['created_at'])),
                          detail('Razorpay order',
                              t['razorpay_order_id'] ?? 'Awaiting reference')
                        ]),
                        const SizedBox(height: 12),
                        SelectableText('Internal order ${t['id']}',
                            style: const TextStyle(color: muted, fontSize: 12)),
                        if (t['failure_reason'] != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: Text(t['failure_reason'],
                                  style: const TextStyle(color: amber))),
                        if (t['attribution'] != null) ...[
                          const Divider(height: 32),
                          Wrap(spacing: 26, runSpacing: 16, children: [
                            detail('Baseline',
                                money(t['attribution']['baseline'])),
                            detail('Upsell', money(t['attribution']['upsell'])),
                            detail('Cross-sell',
                                money(t['attribution']['cross_sell'])),
                            detail('Discount cost',
                                money(t['attribution']['discount'])),
                            detail('AI incremental',
                                money(t['attribution']['incremental']))
                          ])
                        ],
                        const SizedBox(height: 20),
                        Wrap(spacing: 12, runSpacing: 12, children: [
                          if ([
                            'PAYMENT_PENDING',
                            'PAYMENT_FAILED',
                            'RECONCILIATION_REQUIRED',
                            'ORDER_CREATED'
                          ].contains(t['state']))
                            OutlinedButton.icon(
                                onPressed: () async {
                                  try {
                                    final response = await ref
                                        .read(apiProvider)
                                        .post(
                                            'transactions/${t['id']}/reconcile');
                                    refresh();
                                    if (context.mounted) {
                                      toast(
                                          context,
                                          response['action_required'] ??
                                              'Verified state: ${human(response['state'])}');
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      toast(context, errorMessage(e),
                                          error: true);
                                    }
                                  }
                                },
                                icon: const Icon(Icons.sync, size: 18),
                                label: const Text('Reconcile status')),
                          if (t['state'] == 'PAYMENT_PENDING' ||
                              t['state'] == 'PAYMENT_FAILED')
                            FilledButton(
                                onPressed: () async {
                                  try {
                                    final order = await ref
                                        .read(apiProvider)
                                        .post('transactions/${t['id']}/retry');
                                    if (context.mounted) {
                                      await payOrder(context, ref, order);
                                    }
                                    refresh();
                                  } catch (e) {
                                    if (context.mounted) {
                                      toast(context, errorMessage(e),
                                          error: true);
                                    }
                                  }
                                },
                                child: Text(t['state'] == 'PAYMENT_FAILED'
                                    ? 'Revalidate & retry'
                                    : 'Open test checkout')),
                          if (t['razorpay_order_id'] == null)
                            OutlinedButton(
                                onPressed: () => recoverDialog(
                                    context, ref, t['id'], refresh),
                                child:
                                    const Text('Recover provider reference')),
                          TextButton(
                              onPressed: () => showSafeDialog(
                                  context: context,
                                  builder: (ctx) =>
                                      AlertDialog(
                                          backgroundColor: surface,
                                          title: const Text(
                                              'Transaction timeline'),
                                          content: SizedBox(
                                              width: 700,
                                              height: 520,
                                              child: SingleChildScrollView(
                                                  child: AuditScreen(
                                                      orderId: t['id']))),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx),
                                                child: const Text('Close'))
                                          ])),
                              child: const Text('View timeline'))
                        ])
                      ]))))
          ]));
}

Future<void> recoverDialog(BuildContext context, WidgetRef ref, String id,
    VoidCallback refresh) async {
  final controller = TextEditingController();
  final value = await showSafeDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
              backgroundColor: surface,
              title: const Text('Recover Razorpay reference'),
              content: SizedBox(
                  width: 450,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SelectableText(
                        'In Razorpay Test Dashboard, find the order with receipt $id. The server will verify receipt, amount and currency.'),
                    const SizedBox(height: 20),
                    TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                            labelText: 'Razorpay order ID'))
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: const Text('Verify reference'))
              ]));
  controller.dispose();
  if (value == null) return;
  try {
    await ref.read(apiProvider).post(
        'transactions/$id/recover-reference', {'razorpay_order_id': value});
    refresh();
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e), error: true);
  }
}

class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key, this.orderId});
  final String? orderId;
  @override
  Widget build(BuildContext context) => DataView(
      path: orderId == null ? 'audit' : 'transactions/$orderId/timeline',
      builder: (data, refresh) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (orderId == null)
              const PageHeading('Audit timeline',
                  'Reconstruct every agent decision and commercial action.'),
            GlassCard(
                child: (data['events'] as List).isEmpty
                    ? const EmptyState('Your audit trail starts here',
                        'Significant actions will be appended automatically.',
                        icon: Icons.history)
                    : Column(
                        children: (data['events'] as List)
                            .map<Widget>((event) => ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    leading: Icon(
                                        event['event']
                                                .toString()
                                                .startsWith('transaction')
                                            ? Icons.receipt_long_outlined
                                            : Icons.fingerprint,
                                        color: mint,
                                        size: 22),
                                    title: Text(event['event'].toString().replaceAll('.', ' / '),
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                        '${timestamp(event['created_at'])} · ${event['actor']}',
                                        style: const TextStyle(color: muted, fontSize: 12)),
                                    children: [
                                      Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                              padding: const EdgeInsets.all(14),
                                              child: SelectableText(
                                                  const JsonEncoder.withIndent(
                                                          '  ')
                                                      .convert(event['data']),
                                                  style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 13,
                                                      color: muted))))
                                    ]))
                            .toList()))
          ]));
}
