import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/api.dart';
import '../core/theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      store = TextEditingController();
  bool registering = false, busy = false;
  String type = 'custom';
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    store.dispose();
    super.dispose();
  }

  Future<void> submit({bool demo = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final response = await api.post(
          demo
              ? 'auth/demo'
              : registering
                  ? 'auth/register'
                  : 'auth/login',
          demo
              ? null
              : {
                  'email': email.text.trim(),
                  'password': password.text,
                  if (registering) 'merchant_name': store.text.trim(),
                  if (registering) 'store_type': type
                });
      api.authenticate(response['access_token']);
      ref.read(sessionProvider.notifier).state = response;
      ref.read(buyerStateProvider.notifier).state = {};
      final revisions = ref.read(revisionProvider.notifier);
      api.subscribe(() => revisions.state++);
      if (mounted) context.go('/dashboard');
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: Container(
          decoration: const BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment(-.6, -.8),
                  radius: 1.5,
                  colors: [Color(0xFF234339), background])),
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1050),
                      child: LayoutBuilder(builder: (_, box) {
                        final intro = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(children: [
                                Icon(Icons.hub_rounded, color: mint, size: 32),
                                SizedBox(width: 12),
                                Text('ACG',
                                    style: TextStyle(
                                        fontSize: 25,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 3))
                              ]),
                              const SizedBox(height: 70),
                              const Tag('AGENTIC COMMERCE GATEWAY'),
                              const SizedBox(height: 24),
                              const Text('Commerce,\nunder your\ncontrol.',
                                  style: TextStyle(
                                      fontSize: 60,
                                      height: 1.08,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -2.5)),
                              const SizedBox(height: 28),
                              const Text(
                                  'Your products. Your policies.\nA new way for AI agents to buy.',
                                  style: TextStyle(
                                      color: muted,
                                      fontSize: 18,
                                      height: 1.65)),
                              const SizedBox(height: 46),
                              Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: const [
                                    Tag('NVIDIA Nemotron'),
                                    Tag('Razorpay test mode'),
                                    Tag('Policy protected')
                                  ])
                            ]);
                        final form = GlassCard(
                            padding: 32,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                      registering
                                          ? 'Create your workspace'
                                          : 'Welcome back',
                                      style: const TextStyle(
                                          fontSize: 27,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 10),
                                  Text(
                                      registering
                                          ? 'Start with your catalog. Stay in control.'
                                          : 'Sign in to your merchant console.',
                                      style: const TextStyle(color: muted)),
                                  const SizedBox(height: 28),
                                  if (registering) ...[
                                    TextField(
                                        controller: store,
                                        decoration: const InputDecoration(
                                            labelText: 'Store name')),
                                    const SizedBox(height: 14),
                                    DropdownButtonFormField<String>(
                                        value: type,
                                        items: [
                                          'custom',
                                          'shopify',
                                          'woocommerce'
                                        ]
                                            .map((s) => DropdownMenuItem(
                                                value: s, child: Text(s)))
                                            .toList(),
                                        onChanged: (v) =>
                                            setState(() => type = v!),
                                        decoration: const InputDecoration(
                                            labelText: 'Store platform')),
                                    const SizedBox(height: 14)
                                  ],
                                  TextField(
                                      controller: email,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                          labelText: 'Email address')),
                                  const SizedBox(height: 14),
                                  TextField(
                                      controller: password,
                                      obscureText: true,
                                      onSubmitted: (_) {
                                        if (!busy) submit();
                                      },
                                      decoration: const InputDecoration(
                                          labelText: 'Password',
                                          helperText:
                                              'At least 10 characters for a new account')),
                                  const SizedBox(height: 24),
                                  if (error != null) ...[
                                    Text(error!,
                                        style: const TextStyle(color: danger)),
                                    const SizedBox(height: 18)
                                  ],
                                  FilledButton(
                                      onPressed: busy ? null : submit,
                                      child: Text(busy
                                          ? 'Preparing your workspace…'
                                          : registering
                                              ? 'Create workspace'
                                              : 'Sign in')),
                                  const SizedBox(height: 12),
                                  TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => setState(() {
                                                registering = !registering;
                                                error = null;
                                              }),
                                      child: Text(registering
                                          ? 'Already have an account? Sign in'
                                          : 'New merchant? Create a workspace')),
                                  const Divider(height: 30),
                                  OutlinedButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () => submit(demo: true),
                                      icon: const Icon(Icons.science_outlined,
                                          size: 18),
                                      label: const Text(
                                          'Explore a sample workspace')),
                                  const SizedBox(height: 12),
                                  const Text(
                                      '100 sample products · No real payments\nAvailable on the local development server',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: muted,
                                          height: 1.6))
                                ]));
                        return box.maxWidth > 800
                            ? Row(children: [
                                Expanded(child: intro),
                                const SizedBox(width: 60),
                                SizedBox(width: 420, child: form)
                              ])
                            : Column(children: [
                                const Icon(Icons.hub_rounded,
                                    color: mint, size: 40),
                                const SizedBox(height: 28),
                                form
                              ]);
                      }))))));
}
