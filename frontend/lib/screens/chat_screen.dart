/// ChatScreen – Haupt-Chat-Interface mit Echtzeit-Streaming.
///
/// Features:
/// - Nachrichten mit Markdown-Rendering
/// - Token-für-Token Streaming
/// - Tool-Call Anzeige in Echtzeit
/// - Provider/Modell/Tools pro Chat konfigurierbar
/// - System-Prompt editierbar

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../theme.dart';
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

  // Ausstehende Tool-Bestätigung (name + arguments) – null wenn keine
  Map<String, dynamic>? _pendingConfirm;

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

        case WsEventType.toolConfirm:
          // Backend fragt ob das Tool ausgeführt werden darf
          _pendingConfirm = {
            'name': event.name ?? '',
            'arguments': event.arguments ?? {},
          };
          _scrollToBottom();

        case WsEventType.title:
          // Auto-Titel vom Backend → AppBar-Titel aktualisieren
          if (event.title != null && _chat != null) {
            _chat = _chat!.copyWith(title: event.title);
          }

        case WsEventType.done:
          // Streaming beendet → Chat neu laden für finale Nachricht
          _isStreaming = false;
          _streamingContent = '';
          _activeToolCalls = [];
          _pendingConfirm = null;
          _sending = false;
          _loadChat();
          _scrollToBottom();

        case WsEventType.error:
          _isStreaming = false;
          _streamingContent = '';
          _activeToolCalls = [];
          _pendingConfirm = null;
          _sending = false;
          _showError(event.message ?? 'Unbekannter Fehler');
      }
    });
  }

  void _respondConfirm(bool approved) {
    _ws.sendDecision(approved);
    setState(() => _pendingConfirm = null);
  }

  void _stopGeneration() {
    _ws.sendStop();
  }

  Future<void> _regenerate() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _streamingContent = '';
      _activeToolCalls = [];
      _isStreaming = true;
    });
    _ensureConnected();
    _ws.sendRegenerate();
    _scrollToBottom();
  }

  Future<void> _editMessage(ChatMessage msg) async {
    final ctrl = TextEditingController(text: msg.content);
    final newContent = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nachricht bearbeiten'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Speichern & neu generieren'),
          ),
        ],
      ),
    );
    if (newContent == null || newContent.isEmpty || newContent == msg.content) return;
    try {
      await widget.api.editMessage(widget.chatId, msg.id, newContent);
      await _loadChat();          // gekürzten Verlauf laden
      await _regenerate();        // neue Antwort anfordern
    } catch (e) {
      _showError('$e');
    }
  }

  void _exportMarkdown() {
    final messages = _chat?.messages ?? [];
    final buf = StringBuffer('# ${_chat?.title ?? "Chat"}\n\n');
    for (final m in messages) {
      final who = m.role == 'user' ? '**Du**' : '**Assistent**';
      buf.writeln('$who:\n\n${m.content}\n');
      buf.writeln('---\n');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat als Markdown in die Zwischenablage kopiert')),
    );
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
            icon: const Icon(Icons.ios_share),
            tooltip: 'Als Markdown exportieren',
            onPressed: _exportMarkdown,
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
                        final m = messages[i];
                        final isLastAssistant = m.role == 'assistant' &&
                            i == messages.length - 1 &&
                            !_isStreaming;
                        return MessageBubble(
                          message: m,
                          onEdit: (m.role == 'user' && !_sending)
                              ? () => _editMessage(m)
                              : null,
                          onRegenerate: (isLastAssistant && !_sending)
                              ? _regenerate
                              : null,
                        );
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

          // Tool-Bestätigung (wenn das Modell ein bestätigungspflichtiges Tool nutzen will)
          if (_pendingConfirm != null)
            _ToolConfirmCard(
              name: _pendingConfirm!['name'] as String,
              arguments: _pendingConfirm!['arguments'] as Map<String, dynamic>,
              onApprove: () => _respondConfirm(true),
              onReject: () => _respondConfirm(false),
            ),

          // Stop-Button während des Streamings
          if (_isStreaming && _pendingConfirm == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: OutlinedButton.icon(
                onPressed: _stopGeneration,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('Generierung stoppen'),
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


/// Karte die fragt ob ein bestätigungspflichtiges Tool ausgeführt werden darf.
class _ToolConfirmCard extends StatelessWidget {
  final String name;
  final Map<String, dynamic> arguments;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _ToolConfirmCard({
    required this.name,
    required this.arguments,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final argsText = const JsonEncoder.withIndent('  ').convert(arguments);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Aktion bestätigen: $name',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Die KI möchte folgendes ausführen:',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: SelectableText(
              argsText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onReject,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Ablehnen'),
                style: TextButton.styleFrom(foregroundColor: cs.error),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Ausführen'),
              ),
            ],
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
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Focus(
              // Enter = senden, Shift+Enter = Zeilenumbruch
              onKeyEvent: (node, event) {
                final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter;
                if (event is KeyDownEvent &&
                    isEnter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  if (enabled) onSend();
                  return KeyEventResult.handled; // verhindert Umbruch
                }
                return KeyEventResult.ignored; // Shift+Enter → normaler Umbruch
              },
              child: TextField(
                controller: controller,
                enabled: enabled,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: hint,
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: cs.primary, width: 1.6),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SendButton(enabled: enabled, onSend: onSend),
        ],
      ),
    );
  }
}

/// Runder Senden-Button mit Akzent-Verlauf (deaktiviert = flach).
class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onSend;
  const _SendButton({required this.enabled, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: enabled ? NexusColors.accentGradient : null,
            color: enabled ? null : cs.surfaceContainerHighest,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: NexusColors.seed.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: enabled ? onSend : null,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
            ),
          ),
        ),
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
