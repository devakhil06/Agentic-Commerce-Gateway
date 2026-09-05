import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef Json = Map<String, dynamic>;
const configuredApiUrl = String.fromEnvironment('API_BASE_URL');
final apiProvider = Provider((ref) => GatewayApi());
final sessionProvider = StateProvider<Json?>((ref) => null);
final revisionProvider = StateProvider<int>((ref) => 0);
final buyerStateProvider = StateProvider<Json>((ref) => {});

class GatewayApi {
  GatewayApi()
      : dio = Dio(BaseOptions(
            baseUrl: configuredApiUrl.isNotEmpty
                ? configuredApiUrl
                : (Uri.base.scheme.startsWith('http')
                    ? Uri.base.origin
                    : 'http://127.0.0.1:8000'),
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 90)));
  final Dio dio;
  String? token;
  WebSocketChannel? channel;
  void authenticate(String value) {
    token = value;
    dio.options.headers['Authorization'] = 'Bearer $value';
  }

  void logout() {
    channel?.sink.close();
    token = null;
    dio.options.headers.remove('Authorization');
  }

  void subscribe(void Function() refresh) {
    channel?.sink.close();
    final uri = Uri.parse(dio.options.baseUrl);
    channel = WebSocketChannel.connect(uri.replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws', path: '/api/v1/events'));
    channel!.sink.add(jsonEncode({'token': token}));
    channel!.stream.listen((_) => refresh(), onError: (_) {}, onDone: () {});
  }

  Future<Json> get(String path) async =>
      Map<String, dynamic>.from((await dio.get('/api/v1/$path')).data as Map);
  Future<Json> post(String path, [dynamic data]) async =>
      Map<String, dynamic>.from(
          (await dio.post('/api/v1/$path', data: data)).data as Map);
  Future<Json> put(String path, Json data) async => Map<String, dynamic>.from(
      (await dio.put('/api/v1/$path', data: data)).data as Map);
  Future<void> delete(String path) async {
    await dio.delete('/api/v1/$path');
  }
}

String errorMessage(Object error) {
  if (error is DioException) {
    final detail =
        error.response?.data is Map ? error.response?.data['detail'] : null;
    if (detail is String) return detail;
    if (detail is Map) {
      return (detail['message'] ??
              (detail['reasons'] as List?)?.join('. ') ??
              'The request could not pass validation.')
          .toString();
    }
    if (detail is List) {
      return detail
          .map((e) => '${(e['loc'] as List).last}: ${e['msg']}')
          .join('\n');
    }
    return 'Could not reach the gateway. Check that the server is running, then retry.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}
