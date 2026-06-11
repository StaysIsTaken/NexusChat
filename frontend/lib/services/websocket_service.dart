/// WebSocketService – Streaming-Verbindung zum Backend.
///
/// Empfängt Token für Token und Tool-Call-Events in Echtzeit.
/// Nutzt den broadcast-Stream damit mehrere Widgets gleichzeitig hören können.
///
/// Der Lebenszyklus wird NICHT vom ChatScreen-Widget bestimmt, sondern vom
/// [ChatSocketManager]. Dadurch bleibt die Verbindung offen während die KI
/// streamt – auch wenn der Nutzer kurz auf einen anderen Tab navigiert.

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

enum WsConnectionState { disconnected, connecting, connected, error }

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<WsEvent> _eventController =
      StreamController<WsEvent>.broadcast();

  WsConnectionState _state = WsConnectionState.disconnected;
  WsConnectionState get state => _state;

  // True von "Nachricht gesendet" bis "done"/"error" – also solange die KI antwortet.
  bool _streaming = false;
  bool get isStreaming => _streaming;

  Stream<WsEvent> get events => _eventController.stream;

  /// Verbindet zum WebSocket-Endpunkt für einen Chat.
  /// Ist bereits eine Verbindung offen (oder wird gerade aufgebaut), passiert nichts.
  /// backendUrl: z.B. "http://localhost:8099"
  /// token: JWT zur Authentifizierung (als Query-Parameter angehängt)
  void connect(String backendUrl, String chatId, {String? token}) {
    if (_state == WsConnectionState.connected ||
        _state == WsConnectionState.connecting) {
      return; // schon verbunden – nicht neu aufbauen (würde laufenden Stream killen)
    }

    // HTTP → WS URL konvertieren
    final wsUrl = backendUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    final query = (token != null && token.isNotEmpty)
        ? '?token=${Uri.encodeQueryComponent(token)}'
        : '';

    _state = WsConnectionState.connecting;

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/ws/chat/$chatId$query'),
      );
      _state = WsConnectionState.connected;

      _channel!.stream.listen(
        (rawData) {
          try {
            final json = jsonDecode(rawData as String) as Map<String, dynamic>;
            final event = WsEvent.fromJson(json);
            // Stream-Ende erkennen
            if (event.type == WsEventType.done ||
                event.type == WsEventType.error) {
              _streaming = false;
            }
            _eventController.add(event);
          } catch (e) {
            _eventController.addError('JSON-Fehler: $e');
          }
        },
        onError: (error) {
          _state = WsConnectionState.error;
          _streaming = false;
          _eventController.addError(error);
        },
        onDone: () {
          _state = WsConnectionState.disconnected;
          _streaming = false;
        },
      );
    } catch (e) {
      _state = WsConnectionState.error;
      _streaming = false;
      _eventController.addError(e);
    }
  }

  /// Sendet eine Nachricht an den Chat.
  void sendMessage(String content) {
    if (_channel == null || _state != WsConnectionState.connected) {
      _eventController.addError('WebSocket nicht verbunden');
      return;
    }
    _streaming = true;
    _channel!.sink.add(jsonEncode({'content': content}));
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_channel == null || _state != WsConnectionState.connected) return;
    _channel!.sink.add(jsonEncode(data));
  }

  /// Bricht die laufende Generierung ab.
  void sendStop() => _sendJson({'type': 'stop'});

  /// Fordert eine neue Antwort an (ohne neue Nutzernachricht).
  void sendRegenerate() {
    if (_channel == null || _state != WsConnectionState.connected) {
      _eventController.addError('WebSocket nicht verbunden');
      return;
    }
    _streaming = true;
    _sendJson({'type': 'regenerate'});
  }

  /// Antwortet auf eine Tool-Bestätigungsanfrage.
  void sendDecision(bool approved) =>
      _sendJson({'type': 'tool_decision', 'approved': approved});

  /// Trennt die WebSocket-Verbindung.
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _state = WsConnectionState.disconnected;
    _streaming = false;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}


/// ChatSocketManager – hält WebSocket-Verbindungen pro Chat am Leben.
///
/// Singleton, lebt oberhalb der Navigation. Dadurch überlebt eine laufende
/// KI-Antwort den Wechsel auf andere Tabs (Provider, Tools, …).
///
/// Regeln:
/// - [attach] holt/erzeugt die Verbindung für einen Chat und markiert ihn als sichtbar.
/// - [detach] beim Verlassen des ChatScreens: schließt die Verbindung NUR, wenn
///   gerade nicht gestreamt wird. Läuft ein Stream, bleibt sie offen und schließt
///   sich selbst sobald "done"/"error" eintrifft.
class ChatSocketManager {
  ChatSocketManager._();
  static final ChatSocketManager instance = ChatSocketManager._();

  final Map<String, WebSocketService> _services = {};
  final Map<String, StreamSubscription> _monitors = {};
  final Set<String> _viewing = {};

  /// Verbindung für [chatId] holen/aufbauen und als sichtbar markieren.
  WebSocketService attach(String backendUrl, String chatId, {String? token}) {
    var svc = _services[chatId];
    if (svc == null) {
      svc = WebSocketService();
      _services[chatId] = svc;
      // Eigener Monitor: schließt die Verbindung nach Stream-Ende,
      // falls der Chat dann nicht (mehr) sichtbar ist.
      _monitors[chatId] = svc.events.listen(
        (event) {
          if ((event.type == WsEventType.done ||
                  event.type == WsEventType.error) &&
              !_viewing.contains(chatId)) {
            _close(chatId);
          }
        },
        onError: (_) {},
      );
    }
    svc.connect(backendUrl, chatId, token: token);
    _viewing.add(chatId);
    return svc;
  }

  /// ChatScreen verlassen: Verbindung freigeben, wenn kein Stream läuft.
  void detach(String chatId) {
    _viewing.remove(chatId);
    final svc = _services[chatId];
    if (svc != null && !svc.isStreaming) {
      _close(chatId);
    }
    // Läuft ein Stream: offen lassen – der Monitor schließt nach "done".
  }

  void _close(String chatId) {
    _monitors.remove(chatId)?.cancel();
    _services.remove(chatId)?.dispose();
    _viewing.remove(chatId);
  }
}
