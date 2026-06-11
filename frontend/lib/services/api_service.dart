/// ApiService – alle REST-API-Aufrufe zum NexusChat-Backend.
///
/// Verwendung:
///   final api = ApiService(baseUrl: 'http://localhost:8099');
///   final chats = await api.getChats();

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  final String baseUrl;
  final String? token;

  ApiService({required this.baseUrl, this.token});

  /// Erzeugt eine Kopie mit anderem Token (z.B. nach Login/Logout).
  ApiService withToken(String? token) =>
      ApiService(baseUrl: baseUrl, token: token);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _get(String path) async {
    final resp = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    _checkStatus(resp);
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final resp = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkStatus(resp);
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    final resp = await http.put(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkStatus(resp);
    if (resp.statusCode == 204) return null;
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<void> _delete(String path) async {
    final resp = await http.delete(Uri.parse('$baseUrl$path'), headers: _headers);
    _checkStatus(resp);
  }

  void _checkStatus(http.Response resp) {
    if (resp.statusCode >= 400) {
      String msg = 'HTTP ${resp.statusCode}';
      try {
        final body = jsonDecode(resp.body);
        msg = body['detail'] ?? body['message'] ?? msg;
      } catch (_) {}
      throw ApiException(resp.statusCode, msg);
    }
  }

  // ── Health ─────────────────────────────────────────────────────────────

  Future<bool> checkHealth() async {
    try {
      await _get('/health');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Providers ──────────────────────────────────────────────────────────

  Future<List<AppProvider>> getProviders() async {
    final data = await _get('/api/providers') as List;
    return data.map((e) => AppProvider.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Map<String, dynamic>>> getProviderTypes() async {
    final data = await _get('/api/providers/types') as List;
    return data.cast<Map<String, dynamic>>();
  }

  Future<AppProvider> createProvider(Map<String, dynamic> body) async {
    final data = await _post('/api/providers', body);
    return AppProvider.fromJson(data as Map<String, dynamic>);
  }

  Future<AppProvider> updateProvider(String id, Map<String, dynamic> body) async {
    final data = await _put('/api/providers/$id', body);
    return AppProvider.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteProvider(String id) => _delete('/api/providers/$id');

  Future<List<String>> getProviderModels(String id) async {
    final data = await _get('/api/providers/$id/models') as Map<String, dynamic>;
    return List<String>.from(data['models'] as List);
  }

  Future<Map<String, dynamic>> testProvider(String id) async {
    return await _post('/api/providers/$id/test', {}) as Map<String, dynamic>;
  }

  // ── Tool Servers ────────────────────────────────────────────────────────

  Future<List<ToolServer>> getToolServers() async {
    final data = await _get('/api/tools') as List;
    return data.map((e) => ToolServer.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ToolServer> createToolServer(Map<String, dynamic> body) async {
    final data = await _post('/api/tools', body);
    return ToolServer.fromJson(data as Map<String, dynamic>);
  }

  Future<ToolServer> updateToolServer(String id, Map<String, dynamic> body) async {
    final data = await _put('/api/tools/$id', body);
    return ToolServer.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteToolServer(String id) => _delete('/api/tools/$id');

  Future<List<Map<String, dynamic>>> getServerTools(String id) async {
    final data = await _get('/api/tools/$id/tools') as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['tools'] as List);
  }

  Future<Map<String, dynamic>> testToolServer(String id) async {
    return await _post('/api/tools/$id/test', {}) as Map<String, dynamic>;
  }

  // ── Chats ───────────────────────────────────────────────────────────────

  Future<List<ChatModel>> getChats() async {
    final data = await _get('/api/chats') as List;
    return data.map((e) => ChatModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ChatModel> createChat({
    String? providerId,
    String? modelName,
    List<String>? activeToolIds,
    String? systemPrompt,
  }) async {
    final data = await _post('/api/chats', {
      'provider_id': providerId,
      'model_name': modelName,
      'active_tool_ids': activeToolIds ?? [],
      'system_prompt': systemPrompt,
    });
    return ChatModel.fromJson(data as Map<String, dynamic>);
  }

  Future<ChatModel> getChat(String id) async {
    final data = await _get('/api/chats/$id');
    return ChatModel.fromJson(data as Map<String, dynamic>);
  }

  Future<ChatModel> updateChat(String id, Map<String, dynamic> body) async {
    final data = await _put('/api/chats/$id', body);
    return ChatModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteChat(String id) => _delete('/api/chats/$id');

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<bool> authNeedsSetup() async {
    final data = await _get('/api/auth/status') as Map<String, dynamic>;
    return data['needs_setup'] as bool? ?? false;
  }

  /// Gibt {token, user} zurück.
  Future<(String, AppUser)> setupAdmin(String username, String password) async {
    final data = await _post('/api/auth/setup', {
      'username': username,
      'password': password,
    }) as Map<String, dynamic>;
    return (data['token'] as String, AppUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<(String, AppUser)> login(String username, String password) async {
    final data = await _post('/api/auth/login', {
      'username': username,
      'password': password,
    }) as Map<String, dynamic>;
    return (data['token'] as String, AppUser.fromJson(data['user'] as Map<String, dynamic>));
  }

  Future<AppUser> getMe() async {
    final data = await _get('/api/auth/me') as Map<String, dynamic>;
    return AppUser.fromJson(data);
  }

  // ── User-Verwaltung (Admin) ────────────────────────────────────────────────

  Future<List<AppUser>> getUsers() async {
    final data = await _get('/api/users') as List;
    return data.map((e) => AppUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AppUser> createUser(String username, String password) async {
    final data = await _post('/api/users', {
      'username': username,
      'password': password,
    });
    return AppUser.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteUser(String id) => _delete('/api/users/$id');

  Future<void> resetUserPassword(String id, String password) async {
    await _put('/api/users/$id/password', {'password': password});
  }

  Future<void> setUserProviders(String id, List<String> providerIds) async {
    await _put('/api/users/$id/providers', {'ids': providerIds});
  }

  Future<void> setUserTools(String id, List<String> toolIds) async {
    await _put('/api/users/$id/tools', {'ids': toolIds});
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSettings() async {
    return await _get('/api/settings') as Map<String, dynamic>;
  }

  Future<void> updateSettings(Map<String, dynamic> settings) async {
    await _put('/api/settings', settings);
  }
}
