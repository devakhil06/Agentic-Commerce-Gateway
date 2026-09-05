import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/data_view.dart';
import '../core/theme.dart';
import 'buyer.dart';

class NegotiationsScreen extends ConsumerWidget {
  const NegotiationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DataView(
      path: 'negotiations',
      builder: (data, refresh) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PageHeading('Negotiation center',
                'Every round, every boundary, every opportunity.',
                action: FilledButton.icon(
                    onPressed: () => context.go('/buyer'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Start negotiation'))),
            if ((data['negotiations'] as List).isEmpty)
              const GlassCard(
                  child: EmptyState('No negotiations yet',
                      'Launch the buyer simulator to create your first offer.',
                      icon: Icons.forum_outlined))
            else
              ...(data['negotiations'] as List).map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: GlassCard(
                      accent: n['bulk'] == true,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text((n['product_names'] as List).join(' + '),
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600)),
                                  Tag(human(n['status']),
                                      color: n['status'] == 'AWAITING_APPROVAL'
                                          ? amber
                                          : mint),
                                  if (n['bulk'] == true)
                                    const Tag('Bulk opportunity', color: amber)
                                ]),
                            const SizedBox(height: 18),
                            Wrap(spacing: 28, runSpacing: 16, children: [
                              detail(
                                  'Merchant offer', preciseMoney(n['total'])),
                              detail('Policy floor', preciseMoney(n['floor'])),
                              detail('Margin',
                                  '${n['economics']['margin_percent'] ?? 'Unknown'}%'),
                              detail(
                                  'Quantity', '${n['economics']['quantity']}'),
                              detail(
                                  'Rounds', '${(n['rounds'] as List).length}'),
                              detail('Expires', timestamp(n['expires_at']))
                            ]),
                            const SizedBox(height: 18),
                            ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text('Decision history',
                                    style: TextStyle(fontSize: 15)),
                                children: (n['rounds'] as List)
                                    .map<Widget>((r) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                            backgroundColor:
                                                mint.withValues(alpha: .1),
                                            child: Text('${r['round']}',
                                                style: const TextStyle(
                                                    color: mint))),
                                        title: Text(
                                            'Buyer ${preciseMoney(r['buyer_offer'])} → merchant ${preciseMoney(r['merchant_offer'])}'),
                                        subtitle: Text(
                                            '${r['reason']}\n${r['model']}',
                                            style: const TextStyle(
                                                fontSize: 13, color: muted))))
                                    .toList()),
                            const SizedBox(height: 12),
                            Wrap(spacing: 12, runSpacing: 12, children: [
                              if (n['status'] == 'AWAITING_APPROVAL')
                                FilledButton(
                                    onPressed: () => context.go('/approvals'),
                                    child: const Text('Review approval')),
                              if (n['status'] == 'OFFER_CREATED' ||
                                  n['status'] == 'QUOTED')
                                FilledButton(
                                    onPressed: () async {
                                      try {
                                        await acceptAndCheckout(
                                            context, ref, n['id']);
                                        refresh();
                                      } catch (e) {
                                        if (context.mounted) {
                                          toast(context, errorMessage(e),
                                              error: true);
                                        }
                                      }
                                    },
                                    child: const Text('Accept & checkout')),
                              if (n['status'] == 'OFFER_CREATED' &&
                                  n['final_offer'] != true)
                                OutlinedButton(
                                    onPressed: () => negotiateDialog(
                                        context,
                                        ref,
                                        n['session_id'],
                                        (n['lines'] as List)
                                            .map((l) =>
                                                Map<String, dynamic>.from(l))
                                            .toList(),
                                        n['total'],
                                        negotiationId: n['id']),
                                    child: const Text('Counteroffer'))
                            ])
                          ]))))
          ]));
}

Widget detail(String label, String value) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 6),
      Text(value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))
    ]);

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});
  @override
  Widget build(BuildContext context) => DataView(
      path: 'approvals',
      builder: (data, refresh) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PageHeading('Approval center',
                'The context you need. The control you keep.'),
            if ((data['approvals'] as List).isEmpty)
              const GlassCard(
                  child: EmptyState('You’re all caught up',
                      'Exceptional discounts and strategic bulk deals will appear here.',
                      icon: Icons.task_alt))
            else
              ...(data['approvals'] as List).map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ApprovalCard(
                      approval: Map<String, dynamic>.from(a),
                      onChanged: refresh)))
          ]));
}

class ApprovalCard extends ConsumerStatefulWidget {
  const ApprovalCard(
      {super.key, required this.approval, required this.onChanged});
  final Json approval;
  final VoidCallback onChanged;
  @override
  ConsumerState<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<ApprovalCard> {
  bool busy = false;
  Future<void> decide(String decision) async {
    final a = widget.approval;
    final reason = TextEditingController(),
        amount = TextEditingController(
            text: ((a['recommended_total'] as num) / 100).toStringAsFixed(2));
    String? error;
    final payload = await showSafeDialog<Json>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => AlertDialog(
                    backgroundColor: surface,
                    title: Text(decision == 'modify'
                        ? 'Custom offer'
                        : decision == 'approve'
                            ? 'Approve offer'
                            : 'Reject offer'),
                    content: SizedBox(
                        width: 420,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          if (decision == 'modify') ...[
                            TextField(
                                controller: amount,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Approved total (₹)')),
                            const SizedBox(height: 16)
                          ],
                          TextField(
                              controller: reason,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                  labelText: 'Decision reason')),
                          if (error != null)
                            Text(error!, style: const TextStyle(color: danger))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () {
                            if (reason.text.trim().length < 3) {
                              set(() => error = 'Add a decision reason.');
                              return;
                            }
                            final price = double.tryParse(amount.text);
                            if (decision == 'modify' &&
                                (price == null ||
                                    !price.isFinite ||
                                    price <= 0)) {
                              set(() =>
                                  error = 'Enter a valid positive price.');
                              return;
                            }
                            Navigator.pop(ctx, {
                              'decision': decision,
                              'reason': reason.text.trim(),
                              if (decision == 'modify')
                                'total': (price! * 100).round()
                            });
                          },
                          child: const Text('Confirm decision'))
                    ])));
    reason.dispose();
    amount.dispose();
    if (payload == null) return;
    setState(() => busy = true);
    try {
      await ref
          .read(apiProvider)
          .post('approvals/${a['id']}/decision', payload);
      widget.onChanged();
      ref.read(revisionProvider.notifier).state++;
      if (mounted) {
        toast(context, 'Decision saved. Global policy is unchanged.');
      }
    } catch (e) {
      if (mounted) toast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.approval, e = a['economics'];
    return GlassCard(
        accent: a['status'] == 'PENDING',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 14, runSpacing: 12, children: [
            Tag(human(a['status']),
                color: a['status'] == 'PENDING' ? amber : muted),
            Text(a['reason'],
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))
          ]),
          const SizedBox(height: 10),
          Text((a['product_names'] as List).join(' + '),
              style: const TextStyle(color: muted)),
          const SizedBox(height: 26),
          ResponsiveGrid(minWidth: 160, children: [
            detail('Standard value', preciseMoney(e['standard_total'])),
            detail('Buyer offer', preciseMoney(e['offered_total'])),
            detail('Requested discount', '${e['discount_percent']}%'),
            detail('Resulting margin', '${e['margin_percent'] ?? 'Unknown'}%'),
            detail('Expected profit', preciseMoney(e['expected_profit'])),
            detail('Minimum margin', '${a['minimum_margin']}%'),
            detail('Quantity', '${e['quantity']}'),
            detail('Delivery', '${a['delivery_days']} days'),
            detail('Est. conversion',
                '${((a['conversion_probability'] as num) * 100).round()}%')
          ]),
          const SizedBox(height: 22),
          Text(
              'Available stock: ${(a['inventory'] as Map).entries.map((e) => '${e.key}: ${e.value}').join(' · ')}',
              style: const TextStyle(color: muted, fontSize: 13)),
          const SizedBox(height: 16),
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: mint.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(14)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Recommended offer ${preciseMoney(a['recommended_total'])}',
                        style: const TextStyle(
                            color: mint, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                        'Quote-specific approval · expires ${timestamp(a['expires_at'])}',
                        style: const TextStyle(color: muted, fontSize: 13))
                  ])),
          if (a['status'] == 'PENDING') ...[
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, children: [
              FilledButton.icon(
                  onPressed: busy ? null : () => decide('approve'),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(busy ? 'Saving…' : 'Approve offer')),
              OutlinedButton(
                  onPressed: busy ? null : () => decide('modify'),
                  child: const Text('Custom offer')),
              TextButton(
                  onPressed: busy ? null : () => decide('reject'),
                  child: const Text('Reject', style: TextStyle(color: danger)))
            ])
          ]
        ]));
  }
}

class PoliciesScreen extends StatelessWidget {
  const PoliciesScreen({super.key});
  @override
  Widget build(BuildContext context) => DataView(
      path: 'policies',
      builder: (data, refresh) => PolicyEditor(
          key: ValueKey(data['version']), data: data, refresh: refresh));
}

class PolicyEditor extends ConsumerStatefulWidget {
  const PolicyEditor({super.key, required this.data, required this.refresh});
  final Json data;
  final VoidCallback refresh;
  @override
  ConsumerState<PolicyEditor> createState() => _PolicyEditorState();
}

class _PolicyEditorState extends ConsumerState<PolicyEditor> {
  late Json rules = Map<String, dynamic>.from(widget.data['rules']);
  late final advanced = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert({
    for (final key in [
      'allowed_categories',
      'blocked_categories',
      'blocked_products',
      'category_overrides',
      'product_overrides',
      'sku_overrides'
    ])
      key: rules[key]
  }));
  bool saving = false;
  String? error;
  @override
  void dispose() {
    advanced.dispose();
    super.dispose();
  }

  static const fields = <String, String>{
    'auto_discount_max': 'Automatic discount limit (%)',
    'absolute_discount_max': 'Absolute discount limit (%)',
    'minimum_margin_percent': 'Minimum margin (%)',
    'auto_transaction_limit': 'Automatic transaction limit (₹)',
    'human_approval_threshold': 'Human approval threshold (₹)',
    'max_rounds': 'Maximum negotiation rounds',
    'rescue_discount_max': 'Maximum rescue discount (%)',
    'abandonment_threshold': 'Abandonment probability (0–1)',
    'minimum_available': 'Minimum available stock',
    'reservation_ttl_minutes': 'Reservation duration (minutes)',
    'quote_ttl_minutes': 'Quote validity (minutes)',
    'max_estimated_days': 'Maximum delivery days',
    'max_products': 'Maximum bundle products',
    'bulk_min_quantity': 'Bulk quantity threshold',
    'bulk_min_order_value': 'Bulk order value (₹)',
    'bulk_opportunity_threshold': 'Bulk opportunity threshold (0–1)'
  };
  bool currency(String k) => [
        'auto_transaction_limit',
        'human_approval_threshold',
        'bulk_min_order_value'
      ].contains(k);
  void mode(String value) {
    setState(() {
      rules['mode'] = value;
      if (value == 'Conservative') {
        rules['auto_discount_max'] = 3;
        rules['absolute_discount_max'] = 8;
        rules['minimum_margin_percent'] = 25;
      }
      if (value == 'Balanced') {
        rules['auto_discount_max'] = 5;
        rules['absolute_discount_max'] = 10;
        rules['minimum_margin_percent'] = 20;
      }
      if (value == 'Aggressive Growth') {
        rules['auto_discount_max'] = 8;
        rules['absolute_discount_max'] = 15;
        rules['minimum_margin_percent'] = 20;
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeading('Merchant policies',
            'Give your agents room to negotiate. Keep the boundaries explicit.',
            action: FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final overrides = jsonDecode(advanced.text) as Map;
                          await ref
                              .read(apiProvider)
                              .put('policies', {...rules, ...overrides});
                          widget.refresh();
                          if (context.mounted) {
                            toast(context, 'New policy version saved.');
                          }
                        } catch (e) {
                          if (mounted) setState(() => error = errorMessage(e));
                        } finally {
                          if (mounted) setState(() => saving = false);
                        }
                      },
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(saving ? 'Saving…' : 'Save policy'))),
        if (error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(error!, style: const TextStyle(color: danger))),
        GlassCard(
            accent: true,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                    child: Text('Your autonomy mode',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600))),
                Tag('Version ${widget.data['version']}')
              ]),
              const SizedBox(height: 20),
              Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    'Conservative',
                    'Balanced',
                    'Aggressive Growth',
                    'Custom'
                  ]
                      .map((m) => ChoiceChip(
                          label: Text(m),
                          selected: rules['mode'] == m,
                          onSelected: (_) => mode(m),
                          selectedColor: mint.withValues(alpha: .2),
                          labelStyle: TextStyle(
                              color: rules['mode'] == m ? mint : muted)))
                      .toList()),
              const SizedBox(height: 20),
              const Text(
                  'Margin, inventory, delivery and approval checks run in deterministic code before payment.',
                  style: TextStyle(color: muted))
            ])),
        const SizedBox(height: 24),
        GlassCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Negotiation & transaction guardrails',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          ResponsiveGrid(
              minWidth: 280,
              children: fields.entries
                  .map((e) => TextFormField(
                      key: ValueKey('${e.key}-${rules['mode']}'),
                      initialValue:
                          '${currency(e.key) ? (rules[e.key] as num) / 100 : rules[e.key]}',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: e.value),
                      onChanged: (v) {
                        final n = num.tryParse(v);
                        if (n != null && n.isFinite) {
                          rules[e.key] =
                              currency(e.key) ? (n * 100).round() : n;
                        } else {
                          rules[e.key] = v;
                        }
                      }))
                  .toList()),
          const SizedBox(height: 24),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: rules['rescue_enabled'],
              onChanged: (v) => setState(() => rules['rescue_enabled'] = v),
              title: const Text('Enable rescue discounts'),
              subtitle: const Text(
                  'At most 5%, only above the abandonment threshold.',
                  style: TextStyle(color: muted, fontSize: 13))),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: rules['bundle_enabled'],
              onChanged: (v) => setState(() => rules['bundle_enabled'] = v),
              title: const Text('Enable compatible product bundles'))
        ])),
        const SizedBox(height: 24),
        GlassCard(
            child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Product, category & SKU overrides'),
                subtitle: const Text(
                    'Precedence: SKU → product → category → merchant. Prices use paise.',
                    style: TextStyle(color: muted, fontSize: 13)),
                children: [
              const SizedBox(height: 16),
              TextField(
                  controller: advanced,
                  maxLines: 16,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  decoration:
                      const InputDecoration(labelText: 'Scoped rules (JSON)'))
            ]))
      ]);
}
