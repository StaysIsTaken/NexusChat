/// NexusChat – Flutter Frontend.
///
/// Layout:
/// - Desktop/Web: 3-Panel-Layout (Chat-Liste | Chat | -)
/// - Schmal: Navigation via Drawer
///
/// Backend-URL:
/// - Web/Docker: relativ (leer), nginx proxied /api und /ws
/// - Desktop: konfigurierbar in Einstellungen (Standard: http://localhost:8099)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_service.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/provider_screen.dart';
import 'screens/tool_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(NexusChatApp(prefs: prefs));
}

class NexusChatApp extends StatefulWidget {
  final SharedPreferences prefs;
  const NexusChatApp({super.key, required this.prefs});

  @override
  State<NexusChatApp> createState() => _NexusChatAppState();
}

class _NexusChatAppState extends State<NexusChatApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    final saved = widget.prefs.getString('theme') ?? 'dark';
    _themeMode = saved == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  void _toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      widget.prefs.setString(
          'theme', _themeMode == ThemeMode.dark ? 'dark' : 'light');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NexusChat',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: AppShell(prefs: widget.prefs, onToggleTheme: _toggleTheme),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'Inter',
    );
  }
}


// ── Haupt-Shell ─────────────────────────────────────────────────────────────

class AppShell extends StatefulWidget {
  final SharedPreferences prefs;
  final VoidCallback onToggleTheme;

  const AppShell({super.key, required this.prefs, required this.onToggleTheme});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Backend-URL (für Desktop konfigurierbar, für Web leer = gleicher Origin)
  late String _backendUrl;
  late ApiService _api;

  String? _currentChatId;
  int _navIndex = 0; // 0=Chat, 1=Provider, 2=Tools, 3=Settings

  // Für Chat-Liste Refresh
  int _chatListRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    _initBackendUrl();
  }

  void _initBackendUrl() {
    // Web: gleicher Origin (nginx proxied) → leere URL
    // Desktop: gespeicherte URL oder Standard
    final isWeb = identical(0, 0.0); // Plattform-unabhängig prüfen
    _backendUrl = widget.prefs.getString('backend_url') ?? _defaultBackendUrl();
    _api = ApiService(baseUrl: _backendUrl);
  }

  String _defaultBackendUrl() {
    // Auf Web: leere String (relativer Pfad via nginx)
    // Auf Desktop/Mobile: localhost
    const bool isWeb = bool.fromEnvironment('dart.library.html');
    return isWeb ? '' : 'http://localhost:8099';
  }

  Future<void> _createNewChat() async {
    try {
      final chat = await _api.createChat();
      setState(() {
        _currentChatId = chat.id;
        _navIndex = 0;
        _chatListRefreshKey++;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 800;

    return isWide ? _WideLayout(
      navIndex: _navIndex,
      currentChatId: _currentChatId,
      api: _api,
      backendUrl: _backendUrl,
      chatListRefreshKey: _chatListRefreshKey,
      onNavChanged: (i) => setState(() => _navIndex = i),
      onChatSelected: (id) => setState(() {
        _currentChatId = id;
        _navIndex = 0;
      }),
      onNewChat: _createNewChat,
      onToggleTheme: widget.onToggleTheme,
      onBackendUrlChanged: (url) {
        setState(() {
          _backendUrl = url;
          _api = ApiService(baseUrl: url);
          widget.prefs.setString('backend_url', url);
        });
      },
    ) : _NarrowLayout(
      navIndex: _navIndex,
      currentChatId: _currentChatId,
      api: _api,
      backendUrl: _backendUrl,
      chatListRefreshKey: _chatListRefreshKey,
      onNavChanged: (i) => setState(() => _navIndex = i),
      onChatSelected: (id) => setState(() {
        _currentChatId = id;
        _navIndex = 0;
      }),
      onNewChat: _createNewChat,
      onToggleTheme: widget.onToggleTheme,
    );
  }
}


// ── Breites Layout (Desktop/Web) ─────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final int navIndex;
  final String? currentChatId;
  final ApiService api;
  final String backendUrl;
  final int chatListRefreshKey;
  final ValueChanged<int> onNavChanged;
  final ValueChanged<String> onChatSelected;
  final VoidCallback onNewChat;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onBackendUrlChanged;

  const _WideLayout({
    required this.navIndex,
    required this.currentChatId,
    required this.api,
    required this.backendUrl,
    required this.chatListRefreshKey,
    required this.onNavChanged,
    required this.onChatSelected,
    required this.onNewChat,
    required this.onToggleTheme,
    required this.onBackendUrlChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          // NavigationRail – linke Seite
          NavigationRail(
            selectedIndex: navIndex,
            onDestinationSelected: onNavChanged,
            labelType: NavigationRailLabelType.selected,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: Text('Chats'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cloud_outlined),
                selectedIcon: Icon(Icons.cloud),
                label: Text('Provider'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.build_outlined),
                selectedIcon: Icon(Icons.build),
                label: Text('Tools'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Einstellungen'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.brightness_6_outlined),
                    onPressed: onToggleTheme,
                    tooltip: 'Theme wechseln',
                  ),
                ),
              ),
            ),
          ),

          const VerticalDivider(width: 1),

          // Chat-Liste (nur bei Chat-Tab)
          if (navIndex == 0) ...[
            SizedBox(
              width: 260,
              child: ChatListScreen(
                key: ValueKey(chatListRefreshKey),
                api: api,
                selectedChatId: currentChatId,
                onChatSelected: onChatSelected,
                onNewChat: onNewChat,
              ),
            ),
            const VerticalDivider(width: 1),
          ],

          // Haupt-Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() => switch (navIndex) {
        0 => currentChatId != null
            ? ChatScreen(
                key: ValueKey(currentChatId),
                chatId: currentChatId!,
                api: api,
                backendUrl: backendUrl,
              )
            : const _NoChatSelected(),
        1 => ProviderScreen(api: api),
        2 => ToolScreen(api: api),
        3 => _SettingsScreen(
            backendUrl: backendUrl,
            onBackendUrlChanged: onBackendUrlChanged,
          ),
        _ => const SizedBox.shrink(),
      };
}


// ── Schmales Layout (Mobile/kleines Fenster) ────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final int navIndex;
  final String? currentChatId;
  final ApiService api;
  final String backendUrl;
  final int chatListRefreshKey;
  final ValueChanged<int> onNavChanged;
  final ValueChanged<String> onChatSelected;
  final VoidCallback onNewChat;
  final VoidCallback onToggleTheme;

  const _NarrowLayout({
    required this.navIndex,
    required this.currentChatId,
    required this.api,
    required this.backendUrl,
    required this.chatListRefreshKey,
    required this.onNavChanged,
    required this.onChatSelected,
    required this.onNewChat,
    required this.onToggleTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildContent(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navIndex,
        onDestinationSelected: onNavChanged,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.cloud_outlined), label: 'Provider'),
          NavigationDestination(icon: Icon(Icons.build_outlined), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Einstellungen'),
        ],
      ),
    );
  }

  Widget _buildContent() => switch (navIndex) {
        0 => currentChatId != null
            ? ChatScreen(
                key: ValueKey(currentChatId),
                chatId: currentChatId!,
                api: api,
                backendUrl: backendUrl,
              )
            : ChatListScreen(
                key: ValueKey(chatListRefreshKey),
                api: api,
                selectedChatId: currentChatId,
                onChatSelected: onChatSelected,
                onNewChat: onNewChat,
              ),
        1 => ProviderScreen(api: api),
        2 => ToolScreen(api: api),
        3 => _SettingsScreen(
            backendUrl: backendUrl,
            onBackendUrlChanged: (_) {},
          ),
        _ => const SizedBox.shrink(),
      };
}


// ── Einstellungen-Screen ───────────────────────────────────────────────────

class _SettingsScreen extends StatefulWidget {
  final String backendUrl;
  final ValueChanged<String> onBackendUrlChanged;

  const _SettingsScreen({
    required this.backendUrl,
    required this.onBackendUrlChanged,
  });

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  late TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.backendUrl);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Backend', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Backend-URL',
              hintText: 'http://localhost:8099',
              border: OutlineInputBorder(),
              helperText: 'Für Docker/Web-Deployment: leer lassen',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              widget.onBackendUrlChanged(_urlCtrl.text.trim());
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Backend-URL gespeichert')),
              );
            },
            child: const Text('Speichern'),
          ),
          const SizedBox(height: 32),
          Text('Über NexusChat', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('Version 1.0.0'),
          const SizedBox(height: 4),
          const Text('Universelle, erweiterbare KI-Chat-Applikation.'),
          const SizedBox(height: 4),
          const Text('Plugin-System für Provider und Tools.'),
          const SizedBox(height: 4),
          const Text('Modell-unabhängiges Tool-Calling.'),
        ],
      ),
    );
  }
}


class _NoChatSelected extends StatelessWidget {
  const _NoChatSelected();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Kein Chat ausgewählt',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Wähle ein Gespräch aus der Liste oder starte ein neues.'),
          ],
        ),
      );
}
