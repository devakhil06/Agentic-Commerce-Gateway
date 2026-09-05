import 'dart:convert';
import 'dart:js_interop';

@JS('acgCheckout')
external JSPromise<JSString> _checkout(JSString options);
Future<Map<String, dynamic>> openCheckout(Map<String, dynamic> order) async {
  final result = await _checkout(jsonEncode({
    'key': order['key_id'],
    'amount': order['amount'],
    'currency': 'INR',
    'order_id': order['razorpay_order_id'],
    'name': 'Agentic Commerce Gateway',
    'description': 'Test-mode checkout',
    'theme': {'color': '#27895B'}
  }).toJS)
      .toDart;
  return Map<String, dynamic>.from(jsonDecode(result.toDart));
}
