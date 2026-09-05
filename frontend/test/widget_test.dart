import 'package:acg_console/core/api.dart';
import 'package:acg_console/core/data_view.dart';
import 'package:acg_console/core/theme.dart';
import 'package:acg_console/features/operations.dart';
import 'package:acg_console/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApi extends GatewayApi {
  Json? decision;
  VoidCallback? event;
  bool fail = false;
  @override
  Future<Json> get(String path) async {
    if (fail) throw Exception('Connection unavailable');
    if (path == 'analytics/revenue') {
      return {
        'revenue': 0,
        'attribution': {'incremental': 0},
        'orders': 0,
        'aov': 0,
        'conversion': 0,
        'searches': 0,
        'negotiations': 0,
        'approvals': 0,
        'failures': 0,
        'recent_orders': []
      };
    }
    if (path == 'catalog/readiness') return {'score': 90, 'product_count': 100};
    return {'value': 'Loaded'};
  }

  @override
  Future<Json> post(String path, [dynamic data]) async {
    if (path == 'auth/demo') {
      return {
        'access_token': 'test-session',
        'user': {'id': 'u1', 'role': 'owner'},
        'merchant': {'id': 'm1', 'name': 'Test shop'}
      };
    }
    decision = Map<String, dynamic>.from(data);
    return {'status': 'APPROVE'};
  }

  @override
  void subscribe(VoidCallback refresh) {
    event = refresh;
  }
}

void main() {
  testWidgets('Workspace updates survive leaving the login screen',
      (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: const GatewayApp()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Explore a sample workspace'));
    await tester.tap(find.text('Explore a sample workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Commerce overview'), findsOneWidget);
    api.event!();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Authentication is usable on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: GatewayApp()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mobile approval retains economics and submits a reason',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi();
    final approval = <String, dynamic>{
      'id': 'approval-1',
      'status': 'PENDING',
      'reason': 'Strategic bulk opportunity',
      'product_names': ['Office monitor'],
      'economics': {
        'standard_total': 37500000,
        'offered_total': 33000000,
        'discount_percent': 12,
        'margin_percent': 29,
        'expected_profit': 9600000,
        'quantity': 30
      },
      'minimum_margin': 20,
      'delivery_days': 3,
      'conversion_probability': .74,
      'inventory': {'Office monitor': 40},
      'recommended_total': 33300000,
      'expires_at': 2000000000
    };
    await tester.pumpWidget(ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: MaterialApp(
            theme: gatewayTheme(),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ApprovalCard(
                            approval: approval, onChanged: () {})))))));
    await tester.pumpAndSettle();
    expect(find.text('Resulting margin'), findsOneWidget);
    expect(find.text('Expected profit'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Approve offer'));
    await tester.tap(find.text('Approve offer'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'Approved office procurement');
    await tester.tap(find.text('Confirm decision'));
    await tester.pumpAndSettle();
    expect(api.decision?['decision'], 'approve');
    expect(api.decision?['reason'], 'Approved office procurement');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Failed data loads offer a working retry', (tester) async {
    final api = FakeApi()..fail = true;
    await tester.pumpWidget(ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: MaterialApp(
            theme: gatewayTheme(),
            home: Scaffold(
                body: DataView(
                    path: 'test',
                    builder: (data, _) => Text(data['value']))))));
    await tester.pumpAndSettle();
    expect(find.text('Could not load this view'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Loaded'), findsOneWidget);
  });
}
