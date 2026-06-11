/// Dart-Datenmodelle für die NexusChat API.
/// Spiegeln die Python-Modelle im Backend wider.

class AppProvider {
  final String id;
  final String name;
  final String type;
  final String? baseUrl;
  final String? apiKey;
  final bool hasApiKey;
  final String? defaultModel;
  final Map<String, dynamic> customHeaders;
  final bool isEnabled;
  final String? createdAt;

  const AppProvider({
    required this.id,
    required this.name,
    required this.type,
    this.baseUrl,
    this.apiKey,
    this.hasApiKey = false,
    this.defaultModel,
    this.customHeaders = const {},
    this.isEnabled = true,
    this.createdAt,
  });

  factory AppProvider.fromJson(Map<String, dynamic> json) => AppProvider(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        baseUrl: json['base_url'] as String?,
        apiKey: json['api_key'] as String?,
        hasApiKey: json['has_api_key'] as bool? ?? false,
        defaultModel: json['default_model'] as String?,
        customHeaders: (json['custom_headers'] as Map<String, dynamic>?) ?? {},
        isEnabled: json['is_enabled'] as bool? ?? true,
        createdAt: json['created_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'base_url': baseUrl,
        'api_key': apiKey,
        'default_model': defaultModel,
        'custom_headers': customHeaders,
        'is_enabled': isEnabled,
      };

  AppProvider copyWith({
    String? name,
    String? type,
    String? baseUrl,
    String? apiKey,
    String? defaultModel,
    bool? isEnabled,
  }) =>
      AppProvider(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        defaultModel: defaultModel ?? this.defaultModel,
        customHeaders: customHeaders,
        isEnabled: isEnabled ?? this.isEnabled,
        createdAt: createdAt,
      );
}


class ToolServer {
  final String id;
  final String name;
  final String type; // mcp | rest | custom
  final String? url;
  final String? apiKey;
  final bool hasApiKey;
  final Map<String, dynamic> config;
  final bool isEnabled;
  final bool requiresConfirmation;
  final String? createdAt;

  const ToolServer({
    required this.id,
    required this.name,
    required this.type,
    this.url,
    this.apiKey,
    this.hasApiKey = false,
    this.config = const {},
    this.isEnabled = true,
    this.requiresConfirmation = false,
    this.createdAt,
  });

  factory ToolServer.fromJson(Map<String, dynamic> json) => ToolServer(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        url: json['url'] as String?,
        apiKey: json['api_key'] as String?,
        hasApiKey: json['has_api_key'] as bool? ?? false,
        config: (json['config'] as Map<String, dynamic>?) ?? {},
        isEnabled: json['is_enabled'] as bool? ?? true,
        requiresConfirmation: json['requires_confirmation'] as bool? ?? false,
        createdAt: json['created_at'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'url': url,
        'api_key': apiKey,
        'config': config,
        'is_enabled': isEnabled,
      };
}


class ChatModel {
  final String id;
  final String title;
  final String? providerId;
  final String? modelName;
  final List<String> activeToolIds;
  final String? systemPrompt;
  final String? createdAt;
  final String? updatedAt;
  final List<ChatMessage> messages;

  const ChatModel({
    required this.id,
    required this.title,
    this.providerId,
    this.modelName,
    this.activeToolIds = const [],
    this.systemPrompt,
    this.createdAt,
    this.updatedAt,
    this.messages = const [],
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) => ChatModel(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'Neues Gespräch',
        providerId: json['provider_id'] as String?,
        modelName: json['model_name'] as String?,
        activeToolIds: List<String>.from(json['active_tool_ids'] as List? ?? []),
        systemPrompt: json['system_prompt'] as String?,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
        messages: (json['messages'] as List? ?? [])
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'provider_id': providerId,
        'model_name': modelName,
        'active_tool_ids': activeToolIds,
        'system_prompt': systemPrompt,
      };

  ChatModel copyWith({
    String? title,
    String? providerId,
    String? modelName,
    List<String>? activeToolIds,
    String? systemPrompt,
    List<ChatMessage>? messages,
  }) =>
      ChatModel(
        id: id,
        title: title ?? this.title,
        providerId: providerId ?? this.providerId,
        modelName: modelName ?? this.modelName,
        activeToolIds: activeToolIds ?? this.activeToolIds,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        messages: messages ?? this.messages,
      );
}


class ChatMessage {
  final String id;
  final String chatId;
  final String role; // user | assistant | system
  final String content;
  final String? timestamp;
  final List<ToolCall> toolCalls;
  final List<ToolResult> toolResults;

  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.role,
    required this.content,
    this.timestamp,
    this.toolCalls = const [],
    this.toolResults = const [],
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String? ?? '',
        chatId: json['chat_id'] as String? ?? '',
        role: json['role'] as String,
        content: json['content'] as String? ?? '',
        timestamp: json['timestamp'] as String?,
        toolCalls: (json['tool_calls'] as List? ?? [])
            .map((t) => ToolCall.fromJson(t as Map<String, dynamic>))
            .toList(),
        toolResults: (json['tool_results'] as List? ?? [])
            .map((t) => ToolResult.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}


class ToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({required this.name, required this.arguments});

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        name: json['name'] as String,
        arguments: (json['arguments'] as Map<String, dynamic>?) ?? {},
      );
}


class ToolResult {
  final String name;
  final String result;

  const ToolResult({required this.name, required this.result});

  factory ToolResult.fromJson(Map<String, dynamic> json) => ToolResult(
        name: json['name'] as String,
        result: json['result'] as String? ?? '',
      );
}


/// Benutzer (Auth)
class AppUser {
  final String id;
  final String username;
  final String role; // admin | user
  final bool mustChangePassword;
  final List<String> providerIds;
  final List<String> toolIds;

  const AppUser({
    required this.id,
    required this.username,
    required this.role,
    this.mustChangePassword = false,
    this.providerIds = const [],
    this.toolIds = const [],
  });

  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        username: json['username'] as String,
        role: json['role'] as String? ?? 'user',
        mustChangePassword: json['must_change_password'] as bool? ?? false,
        providerIds: List<String>.from(json['provider_ids'] as List? ?? []),
        toolIds: List<String>.from(json['tool_ids'] as List? ?? []),
      );
}


/// WebSocket-Event-Typen vom Backend
enum WsEventType { token, toolStart, toolEnd, toolConfirm, title, done, error }

class WsEvent {
  final WsEventType type;
  final String? content;   // für token
  final String? name;      // für tool_start / tool_end
  final Map<String, dynamic>? arguments;  // für tool_start
  final String? result;    // für tool_end
  final String? message;   // für error
  final List<dynamic>? toolCalls; // für done
  final String? title;     // für title

  const WsEvent({
    required this.type,
    this.content,
    this.name,
    this.arguments,
    this.result,
    this.message,
    this.toolCalls,
    this.title,
  });

  factory WsEvent.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = switch (typeStr) {
      'token' => WsEventType.token,
      'tool_start' => WsEventType.toolStart,
      'tool_end' => WsEventType.toolEnd,
      'tool_confirm' => WsEventType.toolConfirm,
      'title' => WsEventType.title,
      'done' => WsEventType.done,
      'error' => WsEventType.error,
      _ => WsEventType.error,
    };
    return WsEvent(
      type: type,
      content: json['content'] as String?,
      name: json['name'] as String?,
      arguments: json['arguments'] as Map<String, dynamic>?,
      result: json['result'] as String?,
      message: json['message'] as String?,
      toolCalls: json['tool_calls'] as List?,
      title: json['title'] as String?,
    );
  }
}
