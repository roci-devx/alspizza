import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.message, [this.code]);

  final int status;
  final String message;
  final String? code;

  @override
  String toString() => message;
}

typedef Json = Map<String, dynamic>;

/// Thin JSON client for the Al's Pizza API. Every app screen goes through this.
class ApiClient {
  ApiClient({String? baseUrl, this.token}) : baseUrl = baseUrl ?? AppConfig.apiUrl;

  final String baseUrl;
  String? Function()? token;
  final _http = http.Client();

  Future<Json> get(String path, {Map<String, String?>? query}) => _send('GET', path, query: query);
  Future<Json> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<Json> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<Json> put(String path, Object body) => _send('PUT', path, body: body);
  Future<Json> delete(String path) => _send('DELETE', path);

  Future<Json> _send(String method, String path, {Object? body, Map<String, String?>? query}) async {
    final params = {
      for (final e in (query ?? const {}).entries)
        if (e.value != null) e.key: e.value!,
    };
    final uri = Uri.parse('$baseUrl/api$path').replace(queryParameters: params.isEmpty ? null : params);
    final request = http.Request(method, uri)..headers['Content-Type'] = 'application/json';
    final bearer = token?.call();
    if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
    if (body != null && method != 'GET') request.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 25)));
    } on TimeoutException {
      throw const ApiException(0, 'Al’s is taking too long to answer. Please try again.');
    } catch (_) {
      throw const ApiException(0, "Can't reach Al's right now. Check your connection and try again.");
    }
    final Json data = res.body.isEmpty ? {} : (jsonDecode(res.body) as Json);
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, (data['error'] as String?) ?? 'Something went wrong', data['code'] as String?);
    }
    return data;
  }
}
