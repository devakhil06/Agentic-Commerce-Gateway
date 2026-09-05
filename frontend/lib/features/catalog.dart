import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/data_view.dart';
import '../core/theme.dart';

IconData categoryIcon(String category) => switch (category) {
      'headphones' => Icons.headphones_outlined,
      'monitors' => Icons.desktop_windows_outlined,
      'keyboards' => Icons.keyboard_outlined,
      'laptops' => Icons.laptop_mac_outlined,
      'chargers' => Icons.bolt_outlined,
      _ => Icons.devices_other_outlined
    };

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});
  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  String search = '', category = 'All categories';
  bool busy = false;
  Json? report;
  Future<void> upload() async {
    final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json'],
        withData: true);
    if (selected == null) return;
    final file = selected.files.single;
    if (file.size > 5 * 1024 * 1024) {
      if (mounted) toast(context, 'File must be under 5 MB', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final result = await ref.read(apiProvider).post(
          'catalog/import',
          FormData.fromMap({
            'file': MultipartFile.fromBytes(file.bytes!, filename: file.name)
          }));
      if (mounted) setState(() => report = result);
      ref.read(revisionProvider.notifier).state++;
    } catch (e) {
      if (mounted) toast(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeading('Product catalog', 'Structured for agents. Managed by you.',
            action: FilledButton.icon(
                onPressed: busy ? null : upload,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(busy ? 'Importing…' : 'Import CSV / JSON'))),
        if (report != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: GlassCard(
                  accent: true,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${report!['accepted']} accepted · ${report!['rejected']} rejected · ${report!['duplicates']} duplicates · ${report!['warnings']} quality warnings',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        const Text(
                            'Embedding enrichment is queued. Refresh to see readiness changes.',
                            style: TextStyle(color: muted)),
                        ...(report!['errors'] as List).take(20).map((e) => Text(
                            'Row ${e['row']} · ${e['field']}: ${e['message']}',
                            style: const TextStyle(color: amber, fontSize: 13)))
                      ]))),
        DataView(
            path: 'catalog/products',
            builder: (data, refresh) {
              final all = (data['products'] as List).cast<Map>();
              final categories = [
                'All categories',
                ...all.map((p) => p['category'].toString()).toSet().toList()
                  ..sort()
              ];
              final rows = all
                  .where((p) =>
                      (category == 'All categories' ||
                          p['category'] == category) &&
                      '${p['name']} ${p['sku']}'
                          .toLowerCase()
                          .contains(search.toLowerCase()))
                  .toList();
              return Column(children: [
                ResponsiveGrid(children: [
                  Metric(
                      'Catalog products',
                      '${all.length}',
                      'Across ${categories.length - 1} categories',
                      Icons.inventory_2_outlined),
                  Metric(
                      'Available inventory',
                      '${all.fold<int>(0, (sum, p) => sum + (p['available'] as num).toInt())}',
                      'After active reservations',
                      Icons.layers_outlined),
                  Metric(
                      'Needs attention',
                      '${all.where((p) => (p['issues'] as List).isNotEmpty).length}',
                      'Products with data-quality gaps',
                      Icons.fact_check_outlined)
                ]),
                const SizedBox(height: 24),
                GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Wrap(spacing: 16, runSpacing: 12, children: [
                        SizedBox(
                            width: 280,
                            child: TextField(
                                onChanged: (v) => setState(() => search = v),
                                decoration: const InputDecoration(
                                    hintText: 'Search products or SKU',
                                    prefixIcon: Icon(Icons.search, size: 20)))),
                        SizedBox(
                            width: 230,
                            child: DropdownButtonFormField<String>(
                                value: category,
                                items: categories
                                    .map((c) => DropdownMenuItem(
                                        value: c, child: Text(c)))
                                    .toList(),
                                onChanged: (v) => setState(() => category = v!),
                                decoration: const InputDecoration(
                                    labelText: 'Category')))
                      ]),
                      const SizedBox(height: 24),
                      if (rows.isEmpty)
                        EmptyState('No products found',
                            'Import a catalog with SKU, name, category, price, cost and stock. Prices in uploads are rupees.',
                            action: OutlinedButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(apiProvider)
                                        .post('catalog/seed');
                                    refresh();
                                  } catch (e) {
                                    if (context.mounted) {
                                      toast(context, errorMessage(e),
                                          error: true);
                                    }
                                  }
                                },
                                child: const Text('Load 100 sample products')))
                      else
                        ...rows.map((p) => Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(color: Colors.white10))),
                            child: LayoutBuilder(
                                builder: (_, box) => Row(children: [
                                      Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                              color:
                                                  mint.withValues(alpha: .06),
                                              borderRadius:
                                                  BorderRadius.circular(13)),
                                          child: Icon(
                                              categoryIcon(p['category']),
                                              color: mint,
                                              size: 25)),
                                      const SizedBox(width: 16),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(p['name'],
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            const SizedBox(height: 5),
                                            Text(
                                                '${p['sku']} · ${p['category']} · ${p['available']} available',
                                                style: const TextStyle(
                                                    color: muted, fontSize: 12))
                                          ])),
                                      if (box.maxWidth > 640)
                                        Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20),
                                            child: Tag(
                                                (p['issues'] as List).isEmpty
                                                    ? 'Agent ready'
                                                    : '${(p['issues'] as List).length} data gaps',
                                                color: (p['issues'] as List)
                                                        .isEmpty
                                                    ? mint
                                                    : amber)),
                                      Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(money(p['price']),
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            TextButton(
                                                onPressed: () => editProduct(
                                                    context,
                                                    ref,
                                                    Map<String, dynamic>.from(
                                                        p),
                                                    refresh),
                                                child: const Text('Details'))
                                          ])
                                    ])))),
                      const SizedBox(height: 12),
                      Text(
                          '${rows.length} products · CSV / JSON uploads use rupees; API amounts use paise.',
                          style: const TextStyle(color: muted, fontSize: 12))
                    ]))
              ]);
            })
      ]);
}

Future<void> editProduct(BuildContext context, WidgetRef ref, Json product,
    VoidCallback refresh) async {
  final name = TextEditingController(text: product['name']),
      price = TextEditingController(
          text: ((product['price'] as num) / 100).toString()),
      cost = TextEditingController(
          text: product['cost'] == null
              ? ''
              : ((product['cost'] as num) / 100).toString()),
      stock = TextEditingController(text: '${product['stock']}'),
      description = TextEditingController(text: product['description']),
      attributes = TextEditingController(
          text: const JsonEncoder.withIndent('  ')
              .convert(product['attributes'])),
      compatibility = TextEditingController(
          text: (product['compatibility'] as List).join(',')),
      delivery = TextEditingController(
          text: product['delivery_days']?.toString() ?? ''),
      returns =
          TextEditingController(text: product['return_days']?.toString() ?? ''),
      warranty = TextEditingController(text: product['warranty']);
  bool saving = false;
  String? error;
  await showSafeDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
                  backgroundColor: surface,
                  title: Text(product['name']),
                  content: SizedBox(
                      width: 560,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('${product['sku']} · ${product['category']}',
                                style: const TextStyle(color: muted)),
                            const SizedBox(height: 14),
                            for (final pair in [
                              (name, 'Product name'),
                              (price, 'Selling price (₹)'),
                              (cost, 'Cost (₹)'),
                              (stock, 'Stock quantity'),
                              (description, 'Description'),
                              (attributes, 'Attributes (JSON object)'),
                              (
                                compatibility,
                                'Compatible SKUs (comma separated)'
                              ),
                              (delivery, 'Delivery days'),
                              (returns, 'Return days'),
                              (warranty, 'Warranty')
                            ])
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: TextField(
                                      controller: pair.$1,
                                      minLines: 1,
                                      maxLines: pair.$1 == attributes ? 5 : 2,
                                      decoration:
                                          InputDecoration(labelText: pair.$2))),
                            if (error != null)
                              Text(error!,
                                  style: const TextStyle(color: danger))
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                set(() => saving = true);
                                try {
                                  await ref.read(apiProvider).put(
                                      'catalog/products/${product['id']}', {
                                    'sku': product['sku'],
                                    'name': name.text,
                                    'category': product['category'],
                                    'price': (double.parse(price.text) * 100)
                                        .round(),
                                    'cost': cost.text.isEmpty
                                        ? null
                                        : (double.parse(cost.text) * 100)
                                            .round(),
                                    'stock': int.parse(stock.text),
                                    'description': description.text,
                                    'attributes': jsonDecode(attributes.text),
                                    'compatibility': compatibility.text
                                        .split(',')
                                        .map((s) => s.trim())
                                        .where((s) => s.isNotEmpty)
                                        .toList(),
                                    'delivery_days':
                                        int.tryParse(delivery.text),
                                    'return_days': int.tryParse(returns.text),
                                    'warranty': warranty.text,
                                    'variants': product['variants'] ?? [],
                                    'image_url': product['image_url'] ?? ''
                                  });
                                  refresh();
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  set(() {
                                    error = errorMessage(e);
                                    saving = false;
                                  });
                                }
                              },
                        child: Text(saving ? 'Saving…' : 'Save product'))
                  ])));
  for (final c in [
    name,
    price,
    cost,
    stock,
    description,
    attributes,
    compatibility,
    delivery,
    returns,
    warranty
  ]) {
    c.dispose();
  }
}

class ReadinessScreen extends ConsumerWidget {
  const ReadinessScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DataView(
      path: 'catalog/readiness',
      builder: (data, refresh) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            PageHeading('AI commerce readiness',
                'Every deduction has a clear next step.',
                action: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await ref.read(apiProvider).post('catalog/enrich');
                        if (context.mounted) {
                          toast(context,
                              'Catalog enrichment queued. Readiness will update when complete.');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          toast(context, errorMessage(e), error: true);
                        }
                      }
                    },
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: const Text('Enrich catalog'))),
            GlassCard(
                accent: true,
                child: Row(children: [
                  Text('${data['score']}',
                      style: const TextStyle(
                          fontSize: 68,
                          fontWeight: FontWeight.w600,
                          color: mint)),
                  const SizedBox(width: 24),
                  const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Your readiness score',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w600)),
                        SizedBox(height: 8),
                        Text(
                            'Weighted across 10 commerce capabilities.\nBased on your current catalog and configuration.',
                            style: TextStyle(color: muted))
                      ]))
                ])),
            const SizedBox(height: 24),
            ResponsiveGrid(
                minWidth: 330,
                children: (data['components'] as List)
                    .map<Widget>((c) => GlassCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                    child: Text(c['name'],
                                        style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w600))),
                                Tag('${c['score']} / 100',
                                    color: c['score'] == 100 ? mint : amber)
                              ]),
                              const SizedBox(height: 22),
                              LinearProgressIndicator(
                                  value: (c['score'] as num) / 100,
                                  color: mint,
                                  backgroundColor: Colors.white10,
                                  minHeight: 5,
                                  borderRadius: BorderRadius.circular(4)),
                              const SizedBox(height: 14),
                              Text(
                                  'Weight ${c['weight']}% · ${c['deduction']} points deducted',
                                  style: const TextStyle(
                                      color: muted, fontSize: 12)),
                              const SizedBox(height: 14),
                              TextButton(
                                  onPressed: () => context.go('/${c['route']}'),
                                  child: Text('${c['action']} →'))
                            ])))
                    .toList())
          ]));
}
