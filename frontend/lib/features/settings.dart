import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api.dart';
import '../core/data_view.dart';
import '../core/theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final keyId = TextEditingController(),
      secret = TextEditingController(),
      webhook = TextEditingController();
  bool saving = false;
  @override
  void dispose() {
    keyId.dispose();
    secret.dispose();
    webhook.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataView(
      path: 'integrations',
      builder: (data, refresh) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const PageHeading('Integrations',
                'Connect your intelligence and payment infrastructure.'),
            ResponsiveGrid(minWidth: 390, children: [
              GlassCard(
                  accent: true,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.memory, color: mint, size: 32),
                          const SizedBox(width: 14),
                          const Expanded(
                              child: Text('NVIDIA Nemotron',
                                  style: TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w600))),
                          Tag(
                              data['nvidia']['configured']
                                  ? 'Configured'
                                  : 'Not connected',
                              color:
                                  data['nvidia']['configured'] ? mint : amber)
                        ]),
                        const SizedBox(height: 20),
                        const Text('Nemotron 3 Ultra',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        SelectableText(data['nvidia']['model'],
                            style: const TextStyle(color: muted, fontSize: 13)),
                        const SizedBox(height: 20),
                        const Text(
                            'Interprets buyer intent and explains negotiations using structured tool calls. Pricing and payment decisions remain in deterministic services.',
                            style: TextStyle(color: muted)),
                        const SizedBox(height: 22),
                        const Text('Server setup',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        const SelectableText(
                            'Set NVIDIA_API_KEY in the server .env file, then restart the backend. Optional: NVIDIA_MODEL and NVIDIA_BASE_URL.',
                            style: TextStyle(color: muted, fontSize: 14)),
                        const SizedBox(height: 20),
                        const Tag('Credentials never enter the app bundle')
                      ]))
            ]),
            const SizedBox(height: 24),
            GlassCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    const Icon(Icons.payment,
                        color: Color(0xFFADD0F7), size: 30),
                    const SizedBox(width: 14),
                    const Expanded(
                        child: Text('Razorpay',
                            style: TextStyle(
                                fontSize: 25, fontWeight: FontWeight.w600))),
                    Tag(
                        data['razorpay']['configured']
                            ? 'Test mode connected'
                            : 'Setup required',
                        color: data['razorpay']['configured'] ? mint : amber)
                  ]),
                  const SizedBox(height: 12),
                  const Text(
                      'Create real test orders, open checkout, verify signatures, and reconcile captures.',
                      style: TextStyle(color: muted)),
                  const SizedBox(height: 24),
                  ResponsiveGrid(minWidth: 280, children: [
                    TextField(
                        controller: keyId,
                        decoration: InputDecoration(
                            labelText: 'Test Key ID',
                            hintText: data['razorpay']['masked_key'] ??
                                'rzp_test_…')),
                    TextField(
                        controller: secret,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Test Key Secret')),
                    TextField(
                        controller: webhook,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Webhook secret (16+ characters)'))
                  ]),
                  const SizedBox(height: 22),
                  FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              setState(() => saving = true);
                              try {
                                await ref
                                    .read(apiProvider)
                                    .put('integrations/razorpay', {
                                  'key_id': keyId.text.trim(),
                                  'key_secret': secret.text.trim(),
                                  'webhook_secret': webhook.text.trim()
                                });
                                secret.clear();
                                webhook.clear();
                                keyId.clear();
                                refresh();
                                if (context.mounted) {
                                  toast(context,
                                      'Razorpay test credentials saved securely.');
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  toast(context, errorMessage(e), error: true);
                                }
                              } finally {
                                if (mounted) setState(() => saving = false);
                              }
                            },
                      child:
                          Text(saving ? 'Saving…' : 'Save test credentials')),
                  const SizedBox(height: 26),
                  const Text('Webhook endpoint',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SelectableText(
                      '${ref.read(apiProvider).dio.options.baseUrl}${data['razorpay']['webhook_path']}',
                      style: const TextStyle(color: mint, fontSize: 14)),
                  const SizedBox(height: 10),
                  const Text(
                      'In Razorpay Test Dashboard, use your public HTTPS backend URL and subscribe to payment.captured and payment.failed. Localhost webhooks require a tunnel.',
                      style: TextStyle(color: muted, fontSize: 13))
                ])),
            const SizedBox(height: 24),
            GlassCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Universal commerce API',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  const Text(
                      'Versioned JSON endpoints for external buyer agents. Authenticate using a workspace session bearer token. All API amounts are INR paise.',
                      style: TextStyle(color: muted)),
                  const SizedBox(height: 20),
                  SelectableText(
                      '${ref.read(apiProvider).dio.options.baseUrl}/docs',
                      style: const TextStyle(color: mint)),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text:
                                '${ref.read(apiProvider).dio.options.baseUrl}/docs'));
                        toast(context, 'API documentation link copied.');
                      },
                      icon: const Icon(Icons.copy, size: 17),
                      label: const Text('Copy API documentation link')),
                  const Divider(height: 32),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    Tag(data['database'], color: muted),
                    Tag(
                        data['redis']
                            ? 'Redis configured'
                            : 'Local task processing',
                        color: muted),
                    const Tag('Universal v1 active'),
                    const Tag('ACP / AP2 / MCP / x402: future adapters',
                        color: muted)
                  ])
                ]))
          ]));
}
