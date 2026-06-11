/// ChatScreen – Haupt-Chat-Interface mit Echtzeit-Streaming.
///
/// Features:
/// - Nachrichten mit Markdown-Rendering
/// - Token-für-Token Streaming
/// - Tool-Call Anzeige in Echtzeit
/// - Provider/Modell/Tools pro Chat konfigurierbar
/// - System-Prompt editierbar

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final ApiService api;
  final String backendUrl;
  final String? token;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.api,
    required this.backendUrl,
    this.token,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  ChatModel? _chat;
  bool _loading = true;
  bool _sending = false;

  // Streaming-State
  String _streamingContent = '';
  List<ActiveToolCall> _activeToolCalls = [];
  bool _isStreaming = false;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late WebSocketService _ws; // gehört dem ChatSocketManager, nicht diesem Widget
  StreamSubscription? _wsSub;

  // Provider/Modell-Auswahl
  List<AppProvider> _providers = [];
  String? _selectedProviderId;
  String? _selectedModel;

  // Tool-Auswahl
  List<ToolServer> _toolServers = [];
  List<String> _activeToolIds = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.wait([_loadChat(), _loadProviders(), _loadToolServers()]);
    _connectWebSocket();
  }

  Future<void> _loadChat() async {
    try {
      final chat = await widget.api.getChat(widget.chatId);
      if (mounted) {
        setState(() {
          _chat = chat;
          _selectedProviderId = chat.providerId;
          _selectedModel = chat.modelName;
          _activeToolIds = List.from(chat.activeToolIds);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProviders() async {
    try {
      final providers = await widget.api.getProviders();
      if (mounted) setState(() => _providers = providers);
    } catch (_) {}
  }

  Future<void> _loadToolServers() async {
    try {
      final servers = await widget.api.getToolServers();
      if (mounted) setState(() => _toolServers = servers);
    } catch (_) {}
  }

  void _connectWebSocket() {
    // Persistente Verbindung über den Manager holen (überlebt Tab-Wechsel)
    _ws = ChatSocketManager.instance.attach(widget.backendUrl, widget.chatId, token: widget.token);
    _wsSub = _ws.events.listen(_handleWsEvent, onError: (e) {
      if (mounted) {
        setState(() { _isStreaming = false; _sending = false; });
        _showError('WebSocket-Fehler: $e');
      }
    });
    // Falls beim Zurückkehren noch ein Stream läuft: UI-Status angleichen
    if (_ws.isStreaming) {
      setState(() {
        _isStreaming = true;
        _sending = true;
      });
    }
  }

  void _handleWsEvent(WsEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case WsEventType.token:
          _streamingContent += event.content ?? '';
          _isStreaming = true;
          _scrollToBottom();

        case WsEventType.toolStart:
          _activeToolCalls.add(ActiveToolCall(
            name: event.name ?? '',
            arguments: event.arguments,
          ));

        case WsEventType.toolEnd:
          final idx = _activeToolCalls.indexWhere((t) => t.name == event.name);
          if (idx >= 0) _activeToolCalls[idx].result = event.result;

        case WsEventType.done:
          // Streaming beendet → Chat neu laden für finale Nachricht
          _isStreaming = false;
          _streamingContent = '';
          _activeToolCalls = [];
          _sending = false;
          _loadChat();
          _scrollToBottom();

        case WsEventType.error:
          _isStreaming = false;
          _streamingContent = '';
          _activeToolCalls = [];
          _sending = false;
          _showError(event.message ?? 'Unbekannter Fehler');
      }
    });
  }

  Future<void> _send() async {
    final content = _inputCtrl.text.trim();
    if (content.isEmpty || _sending) return;

    // Chat-Einstellungen aktualisieren bevor wir senden
    if (_selectedProviderId != _chat?.providerId ||
        _selectedModel != _chat?.modelName ||
        !_listEquals(_activeToolIds, _chat?.activeToolIds ?? [])) {
      await widget.api.updateChat(widget.chatId, {
        'provider_id': _selectedProviderId,
        'model_name': _selectedModel,
        'active_tool_ids': _activeToolIds,
      });
    }

    setState(() {
      _sending = true;
      _streamingContent = '';
      _activeToolCalls = [];
      // Optimistic UI: Nutzernachricht sofort anzeigen, bevor Backend antwortet
      if (_chat != null) {
        _chat = _chat!.copyWith(
          messages: [
            ..._chat!.messages,
            ChatMessage(
              id: 'pending-${DateTime.now().millisecondsSinceEpoch}',
              chatId: widget.chatId,
              role: 'user',
              content: content,
            ),
          ],
        );
      }
    });
    _inputCtrl.clear();
    _ensureConnected();
    _ws.sendMessage(content);
    _scrollToBottom();
  }

  /// Stellt vor dem Senden sicher, dass eine lebendige Verbindung besteht.
  /// Hat der Manager den Socket zwischenzeitlich geschlossen, wird neu verbunden
  /// und das Event-Abo erneuert.
  void _ensureConnected() {
    final svc = ChatSocketManager.instance.attach(widget.backendUrl, widget.chatId, token: widget.token);
    if (!identical(svc, _ws)) {
      _wsSub?.cancel();
      _ws = svc;
      _wsSub = _ws.events.listen(_handleWsEvent, onError: (e) {
        if (mounted) {
          setState(() { _isStreaming = false; _sending = false; });
          _showError('WebSocket-Fehler: $e');
        }
      });
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChatSettingsSheet(
        chat: _chat,
        providers: _providers,
        toolServers: _toolServers,
        selectedProviderId: _selectedProviderId,
        selectedModel: _selectedModel,
        activeToolIds: _activeToolIds,
        // Parent-State nach Provider-/Modell-Wechsel synchron halten (für AppBar-Chip)
        onProviderChanged: (id) => setState(() {
          _selectedProviderId = id;
          _selectedModel = null;
        }),
        onModelChanged: (m) => setState(() => _selectedModel = m),
        onToolsChanged: (ids) => setState(() => _activeToolIds = ids),
        onSystemPromptChanged: (sp) async {
          await widget.api.updateChat(widget.chatId, {'system_prompt': sp});
          _loadChat();
        },
        api: widget.api,
      ),
    );
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    // Verbindung NICHT schließen – der Manager hält sie offen falls ein
    // Stream läuft, damit die KI-Antwort beim Wegnavigieren nicht verloren geht.
    ChatSocketManager.instance.detach(widget.chatId);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final messages = _chat?.messages ?? [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_chat?.title ?? 'Chat'),
        actions: [
          // Provider/Modell Kurzinfo
          if (_selectedModel != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Chip(
                label: Text(_selectedModel!,
                    style: theme.textTheme.labelSmall),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Chat-Einstellungen',
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          // Nachrichten-Liste
          Expanded(
            child: messages.isEmpty && !_isStreaming
                ? _WelcomeView(onSettings: _showSettings)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length + (_isStreaming ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i < messages.length) {
                        return MessageBubble(message: messages[i]);
                      }
                      // Streaming-Bubble am Ende
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: StreamingMessageBubble(
                          partialContent: _streamingContent,
                          activeToolCalls: _activeToolCalls,
                        ),
                      );
                    },
                  ),
          ),

          // Eingabe-Bereich
          _InputBar(
            controller: _inputCtrl,
            enabled: !_sending && _selectedProviderId != null && _selectedModel != null,
            onSend: _send,
            hint: _selectedProviderId == null
                ? 'Bitte erst einen Provider konfigurieren...'
                : _selectedModel == null
                    ? 'Bitte ein Modell auswählen...'
                    : 'Nachricht eingeben...',
          ),
        ],
      ),
    );
  }
}


// ── Eingabe-Leiste ─────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final String hint;

  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: enabled ? onSend : null,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
            ),
            child: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}


// ── Chat-Einstellungen (Bottom Sheet) ──────────────────────────────────────

class _ChatSettingsSheet extends StatefulWidget {
  final ChatModel? chat;
  final List<AppProvider> providers;
  // Kein models-Parameter mehr – das Sheet lädt Modelle selbst von der API
  final List<ToolServer> toolServers;
  final String? selectedProviderId;
  final String? selectedModel;
  final List<String> activeToolIds;
  final ValueChanged<String?> onProviderChanged;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<List<String>> onToolsChanged;
  final ValueChanged<String> onSystemPromptChanged;
  final ApiService api;

  const _ChatSettingsSheet({
    this.chat,
    required this.providers,
    required this.toolServers,
    required this.selectedProviderId,
    required this.selectedModel,
    required this.activeToolIds,
    required this.onProviderChanged,
    required this.onModelChanged,
    required this.onToolsChanged,
    required this.onSystemPromptChanged,
    required this.api,
  });

  @override
  State<_ChatSettingsSheet> createState() => _ChatSettingsSheetState();
}

class _ChatSettingsSheetState extends State<_ChatSettingsSheet> {
  late TextEditingController _systemPromptCtrl;
  late List<String> _activeToolIds;

  // Modell-State – wird intern verwaltet, nicht vom Parent übergeben
  String? _currentProviderId;
  String? _selectedModel;
  List<String> _models = [];
  bool _loadingModels = false;
  String? _modelsError;

  @override
  void initState() {
    super.initState();
    _systemPromptCtrl = TextEditingController(text: widget.chat?.systemPrompt ?? '');
    _activeToolIds = List.from(widget.activeToolIds);
    _currentProviderId = widget.selectedProviderId;
    _selectedModel = widget.selectedModel;

    // Modelle sofort laden wenn schon ein Provider ausgewählt ist
    if (_currentProviderId != null) {
      _fetchModels(_currentProviderId!);
    }
  }

  @override
  void dispose() {
    _systemPromptCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchModels(String providerId) async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final models = await widget.api.getProviderModels(providerId);
      if (!mounted) return;
      setState(() {
        _models = models;
        _loadingModels = false;
        // Aktuelles Modell zurücksetzen wenn es nicht mehr in der Liste ist
        if (_selectedModel != null && !models.contains(_selectedModel)) {
          _selectedModel = null;
          widget.onModelChanged(null);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingModels = false;
        _modelsError = e.toString();
      });
    }
  }

  void _onProviderChanged(String? id) {
    setState(() {
      _currentProviderId = id;
      _selectedModel = null;
      _models = [];
      _modelsError = null;
    });
    widget.onProviderChanged(id);
    widget.onModelChanged(null);
    if (id != null) _fetchModels(id);
  }

  void _onModelChanged(String? model) {
    setState(() => _selectedModel = model);
    widget.onModelChanged(model);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text('Chat-Einstellungen', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fertig'),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Provider ─────────────────────────────────────────
                  Text('Provider', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _currentProviderId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Provider auswählen',
                    ),
                    items: widget.providers.map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name),
                    )).toList(),
                    onChanged: _onProviderChanged,
                  ),
                  const SizedBox(height: 16),

                  // ── Modell ───────────────────────────────────────────
                  Row(
                    children: [
                      Text('Modell', style: theme.textTheme.labelLarge),
                      const Spacer(),
                      if (_loadingModels)
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (_currentProviderId != null)
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: () => _fetchModels(_currentProviderId!),
                          tooltip: 'Modelle neu laden',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildModelSelector(theme),
                  const SizedBox(height: 16),

                  // ── Tools ────────────────────────────────────────────
                  Text('Aktive Tools', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  if (widget.toolServers.isEmpty)
                    const Text('Keine Tool-Server konfiguriert.',
                        style: TextStyle(color: Colors.grey))
                  else
                    ...widget.toolServers.map((server) => CheckboxListTile(
                          title: Text(server.name),
                          subtitle: Text(server.type.toUpperCase(),
                              style: theme.textTheme.bodySmall),
                          value: _activeToolIds.contains(server.id),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _activeToolIds.add(server.id);
                              } else {
                                _activeToolIds.remove(server.id);
                              }
                            });
                            widget.onToolsChanged(_activeToolIds);
                          },
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        )),
                  const SizedBox(height: 16),

                  // ── System-Prompt ─────────────────────────────────────
                  Text('System-Prompt', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _systemPromptCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Optionaler System-Prompt für diesen Chat...',
                    ),
                    maxLines: 5,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        widget.onSystemPromptChanged(_systemPromptCtrl.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('System-Prompt gespeichert')),
                        );
                      },
                      child: const Text('System-Prompt speichern'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Baut den Modell-Auswahlbereich abhängig vom Lade-State.
  Widget _buildModelSelector(ThemeData theme) {
    // Kein Provider gewählt
    if (_currentProviderId == null) {
      return const Text(
        'Erst einen Provider auswählen.',
        style: TextStyle(color: Colors.grey),
      );
    }

    // Modelle werden geladen
    if (_loadingModels) {
      return const LinearProgressIndicator();
    }

    // Fehler beim Laden
    if (_modelsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fehler: $_modelsError',
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _fetchModels(_currentProviderId!),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Erneut versuchen'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
          ),
          const SizedBox(height: 8),
          // Manuell eingeben als Fallback
          TextFormField(
            initialValue: _selectedModel,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Modell-ID manuell eingeben',
              helperText: 'z.B. llama3.2 oder gpt-4o',
            ),
            onChanged: (v) => _onModelChanged(v.isEmpty ? null : v),
          ),
        ],
      );
    }

    // Modelle geladen → Dropdown
    if (_models.isNotEmpty) {
      return DropdownButtonFormField<String>(
        value: _selectedModel,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: 'Modell auswählen',
          suffixText: '${_models.length} verfügbar',
          suffixStyle: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        isExpanded: true,
        items: _models
            .map((m) => DropdownMenuItem(
                  value: m,
                  child: Text(
                    m,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        onChanged: _onModelChanged,
      );
    }

    // Provider antwortet aber gibt keine Modelle zurück → manuell eingeben
    return TextFormField(
      initialValue: _selectedModel,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        hintText: 'Modell-ID eingeben',
        helperText: 'Dieser Provider liefert keine Modellliste.',
      ),
      onChanged: (v) => _onModelChanged(v.isEmpty ? null : v),
    );
  }
}


// ── Welcome Screen wenn Chat noch leer ─────────────────────────────────────

class _WelcomeView extends StatelessWidget {
  final VoidCallback onSettings;
  const _WelcomeView({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('NexusChat',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Universeller KI-Chat mit modell-unabhängigem Tool-Calling'),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: onSettings,
            icon: const Icon(Icons.tune),
            label: const Text('Provider & Modell konfigurieren'),
          ),
        ],
      ),
    );
  }
}
