/// WebSocketService – Streaming-Verbindung zum Backend.
///
/// Empfängt Token für Token und Tool-Call-Events in Echtzeit.
/// Nutzt den broadcast-Stream damit mehrere Widgets gleichzeitig hören können.

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

  Stream<WsEvent> get events => _eventController.stream;

  /// Verbindet zum WebSocket-Endpunkt für einen Chat.
  /// backendUrl: z.B. "http://localhost:8099"
  void connect(String backendUrl, String chatId) {
    disconnect();

    // HTTP → WS URL konvertieren
    final wsUrl = backendUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    _state = WsConnectionState.connecting;

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$wsUrl/ws/chat/$chatId'),
      );
      _state = WsConnectionState.connected;

      _channel!.stream.listen(
        (rawData) {
          try {
            final json = jsonDecode(rawData as String) as Map<String, dynamic>;
            final event = WsEvent.fromJson(json);
            _eventController.add(event);
          } catch (e) {
            _eventController.addError('JSON-Fehler: $e');
          }
        },
        onError: (error) {
          _state = WsConnectionState.error;
          _eventController.addError(error);
        },
        onDone: () {
          _state = WsConnectionState.disconnected;
        },
      );
    } catch (e) {
      _state = WsConnectionState.error;
      _eventController.addError(e);
    }
  }

  /// Sendet eine Nachricht an den Chat.
  void sendMessage(String content) {
    if (_channel == null || _state != WsConnectionState.connected) {
      _eventController.addError('WebSocket nicht verbunden');
      return;
    }
    _channel!.sink.add(jsonEncode({'content': content}));
  }

  /// Trennt die WebSocket-Verbindung.
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _state = WsConnectionState.disconnected;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}
