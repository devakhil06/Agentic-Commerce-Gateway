import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/checkout.dart';
import '../core/theme.dart';
import 'catalog.dart';

class BuyerScreen extends ConsumerStatefulWidget {
  const BuyerScreen({super.key});
  @override
  ConsumerState<BuyerScreen> createState() => _BuyerScreenState();
}

class _BuyerScreenState extends ConsumerState<BuyerScreen> {
  final prompt = TextEditingController(
      text:
          'I need wireless headphones under ₹8,000 for gaming and office meetings. Battery life is important.');
  bool busy = false, structured = false;
  String? error;
  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  Future<void> discover() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final previous = ref.read(buyerStateProvider);
      final body = <String, dynamic>{
        if (previous['session_id'] != null)
          'session_id': previous['session_id'],
        if (structured)
          'intent': jsonDecode(prompt.text)
        else
          'message': prompt.text
      };
      final result =
          await ref.read(apiProvider).post('commerce/discover', body);
      ref.read(buyerStateProvider.notifier).state = result;
      ref.read(revisionProvider.notifier).state++;
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(buyerStateProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeading('Buyer simulator',
          'Explore, negotiate, and test the complete purchase journey.',
          action: OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      try {
                        if (data['session_id'] != null) {
                          await ref
                              .read(apiProvider)
                              .delete('sessions/${data['session_id']}');
                        }
                        ref.read(buyerStateProvider.notifier).state = {};
                      } catch (e) {
                        if (context.mounted) {
                          toast(context, errorMessage(e), error: true);
                        }
                      }
                    },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New session'))),
      GlassCard(
          accent: true,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_awesome, color: mint, size: 22),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('What is your buyer looking for?',
                      style: TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w600))),
              Switch(
                  value: structured,
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                            structured = v;
                            prompt.text = v
                                ? ' {"category":"headphones","budget":800000,"quantity":1,"attributes":{"wireless":true}}'
                                : 'I need wireless headphones under ₹8,000 for gaming and office meetings.';
                          })),
              const Text('JSON', style: TextStyle(color: muted, fontSize: 13))
            ]),
            const SizedBox(height: 20),
            TextField(
                controller: prompt,
                maxLines: 4,
                decoration: InputDecoration(
                    hintText: structured
                        ? 'Structured intent; budget in paise'
                        : 'Describe products, budget, quantity, and delivery needs')),
            const SizedBox(height: 18),
            Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(
                  onPressed: busy ? null : discover,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  label: Text(busy ? 'Agents are working…' : 'Find products')),
              OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            structured = false;
                            prompt.text =
                                'I need 30 monitors for our office, delivered within 5 days.';
                          }),
                  child: const Text('Try a bulk purchase')),
              if (data['session_id'] != null) const Tag('Session memory active')
            ]),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Text(error!, style: const TextStyle(color: danger)))
          ])),
      const SizedBox(height: 24),
      if (data.isEmpty)
        const GlassCard(
            child: EmptyState('Your first discovery starts here',
                'Buyer intent → discovery → recommendations → negotiation → protected checkout',
                icon: Icons.route_outlined))
      else ...[
        Wrap(spacing: 10, runSpacing: 10, children: [
          Tag(
              (data['model'] as String).startsWith('local')
                  ? 'Local fallback · NVIDIA not invoked'
                  : data['model'],
              color:
                  (data['model'] as String).startsWith('local') ? amber : mint),
          ...(data['stages'] as List).map((s) => Tag(s, color: muted))
        ]),
        const SizedBox(height: 24),
        Text(
            '${(data['candidates'] as List).length} products match your constraints',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        if ((data['candidates'] as List).isEmpty)
          const GlassCard(
              child: EmptyState('No compliant products',
                  'Adjust the intent or inspect the rejection reasons below.'))
        else
          ResponsiveGrid(
              minWidth: 300,
              children: (data['candidates'] as List)
                  .map<Widget>((p) => GlassCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Icon(categoryIcon(p['category']),
                                  color: mint, size: 32),
                              const Spacer(),
                              Tag('${((p['match_score'] as num) * 100).round()}% match')
                            ]),
                            const SizedBox(height: 22),
                            Text(p['name'],
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text(
                                '${p['available']} in stock · ${p['delivery_days'] ?? '—'} day delivery',
                                style: const TextStyle(
                                    color: muted, fontSize: 12)),
                            const SizedBox(height: 18),
                            Text(money(p['price']),
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 14),
                            Text(p['reason'],
                                style: const TextStyle(
                                    color: muted, fontSize: 13)),
                            const SizedBox(height: 18),
                            SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                    onPressed: () => negotiateDialog(
                                        context,
                                        ref,
                                        data['session_id'],
                                        [
                                          {
                                            'product_id': p['id'],
                                            'quantity': data['intent']
                                                ['quantity'],
                                            'kind': 'baseline'
                                          }
                                        ],
                                        (p['price'] as num).toInt() *
                                            (data['intent']['quantity'] as num)
                                                .toInt()),
                                    child:
                                        const Text('Negotiate this product')))
                          ])))
                  .toList()),
        const SizedBox(height: 28),
        const Text('Growth opportunities',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
            'Conversion estimates use a versioned heuristic. Every offer still passes merchant policy.',
            style: TextStyle(color: muted, fontSize: 13)),
        const SizedBox(height: 18),
        ...(data['offers'] as List).map((o) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: GlassCard(
                child: Wrap(
                    spacing: 24,
                    runSpacing: 18,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                  Tag(human(o['type'])),
                  SizedBox(width: 260, child: Text(o['reason'])),
                  Text(money(o['total']),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w600)),
                  Text(
                      '${((o['conversion_probability'] as num) * 100).round()}% estimated conversion',
                      style: const TextStyle(color: muted, fontSize: 13)),
                  OutlinedButton(
                      onPressed: () => negotiateDialog(
                          context,
                          ref,
                          data['session_id'],
                          (o['lines'] as List)
                              .map((l) => Map<String, dynamic>.from(l))
                              .toList(),
                          o['total']),
                      child: const Text('Negotiate offer'))
                ])))),
        const SizedBox(height: 18),
        GlassCard(
            child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                    '${(data['rejected'] as List).length} products excluded'),
                subtitle: const Text('Inspect hard constraint decisions',
                    style: TextStyle(color: muted, fontSize: 13)),
                children: (data['rejected'] as List)
                    .map<Widget>((p) => ListTile(
                        title: Text(p['name']),
                        trailing: Text(p['reason'],
                            style:
                                const TextStyle(color: amber, fontSize: 12))))
                    .toList()))
      ]
    ]);
  }
}

Future<void> negotiateDialog(BuildContext context, WidgetRef ref,
    String session, List<Json> lines, int total,
    {String? negotiationId}) async {
  final amount = TextEditingController(text: (total / 100).toStringAsFixed(2)),
      quantity = TextEditingController(text: '${lines.first['quantity']}'),
      delivery = TextEditingController();
  bool busy = false, rescue = false;
  String? error;
  Json? result;
  await showSafeDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
                  backgroundColor: surface,
                  title: const Text('Make a buyer offer'),
                  content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Catalog total ${money(total)}',
                                style: const TextStyle(color: muted)),
                            const SizedBox(height: 20),
                            TextField(
                                controller: amount,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Your total offer (₹)')),
                            const SizedBox(height: 14),
                            if (lines.length == 1) ...[
                              TextField(
                                  controller: quantity,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Quantity')),
                              const SizedBox(height: 14)
                            ],
                            TextField(
                                controller: delivery,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText:
                                        'Maximum delivery days (optional)')),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: rescue,
                                onChanged: (v) => set(() => rescue = v),
                                title: const Text(
                                    'Simulate high abandonment risk',
                                    style: TextStyle(fontSize: 14)),
                                subtitle: const Text(
                                    '80% probability · rescue discount remains policy bounded',
                                    style: TextStyle(fontSize: 12))),
                            if (error != null)
                              Text(error!,
                                  style: const TextStyle(color: danger)),
                            if (result != null) ...[
                              const Divider(height: 28),
                              Tag(human(result!['status']),
                                  color: result!['status'] == 'OFFER_CREATED'
                                      ? mint
                                      : amber),
                              const SizedBox(height: 14),
                              Text(
                                  'Merchant offer ${preciseMoney(result!['total'])}',
                                  style: const TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(
                                  'Final policy floor ${preciseMoney(result!['floor'])}',
                                  style: const TextStyle(color: muted)),
                              const SizedBox(height: 14),
                              Text((result!['rounds'] as List).last['reason']),
                              const SizedBox(height: 8),
                              if (result!['final_offer'] == true)
                                const Tag(
                                    'Final authorized acceptance boundary',
                                    color: amber)
                            ]
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: busy ? null : () => Navigator.pop(ctx),
                        child: const Text('Close')),
                    if (result == null)
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  set(() => busy = true);
                                  try {
                                    final response = await ref
                                        .read(apiProvider)
                                        .post('commerce/negotiate', {
                                      'session_id': session,
                                      if (negotiationId != null)
                                        'negotiation_id': negotiationId,
                                      'lines': [
                                        for (final l in lines)
                                          {
                                            ...l,
                                            if (lines.length == 1)
                                              'quantity':
                                                  int.parse(quantity.text)
                                          }
                                      ],
                                      'offered_total':
                                          (double.parse(amount.text) * 100)
                                              .round(),
                                      'abandonment_probability':
                                          rescue ? 0.8 : 0,
                                      'delivery_days':
                                          int.tryParse(delivery.text)
                                    });
                                    set(() => result = response);
                                    ref.read(revisionProvider.notifier).state++;
                                  } catch (e) {
                                    set(() => error = errorMessage(e));
                                  } finally {
                                    set(() => busy = false);
                                  }
                                },
                          child: Text(busy ? 'Evaluating…' : 'Send offer'))
                    else if (result!['status'] == 'OFFER_CREATED')
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  set(() => busy = true);
                                  try {
                                    await acceptAndCheckout(
                                        ctx, ref, result!['id']);
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  } catch (e) {
                                    set(() {
                                      error = errorMessage(e);
                                      busy = false;
                                    });
                                  }
                                },
                          child: Text(busy
                              ? 'Preparing checkout…'
                              : 'Accept & checkout'))
                    else if (result!['status'] == 'AWAITING_APPROVAL')
                      FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            context.go('/approvals');
                          },
                          child: const Text('Open approval center'))
                  ])));
  amount.dispose();
  quantity.dispose();
  delivery.dispose();
}

Future<void> acceptAndCheckout(
    BuildContext context, WidgetRef ref, String negotiationId) async {
  final api = ref.read(apiProvider);
  final quote =
      await api.post('commerce/quote', {'negotiation_id': negotiationId});
  final order = await api.post('commerce/checkout',
      {'quote_id': quote['id'], 'idempotency_key': 'checkout-${quote['id']}'});
  ref.read(revisionProvider.notifier).state++;
  if (context.mounted) await payOrder(context, ref, order);
}

Future<void> payOrder(BuildContext context, WidgetRef ref, Json order) async {
  if (order['state'] == 'ORDER_CONFIRMED') {
    if (context.mounted) toast(context, 'This order is already confirmed.');
    return;
  }
  if (order['state'] != 'PAYMENT_PENDING' ||
      order['razorpay_order_id'] == null) {
    throw Exception(order['failure_reason'] ??
        'Checkout needs reconciliation. Open Transactions.');
  }
  final payment = await openCheckout(order);
  if (payment['cancelled'] == true) {
    if (context.mounted) {
      toast(
          context, 'Checkout closed. Check the order status before retrying.');
    }
    return;
  }
  final result = await ref.read(apiProvider).post('payments/verify', {
    'order_id': order['id'],
    'razorpay_payment_id': payment['razorpay_payment_id'],
    'razorpay_signature': payment['razorpay_signature']
  });
  ref.read(revisionProvider.notifier).state++;
  if (context.mounted) {
    toast(
        context,
        result['state'] == 'ORDER_CONFIRMED'
            ? 'Payment verified. Your order is confirmed.'
            : 'Payment received; the transaction needs review.');
  }
}
