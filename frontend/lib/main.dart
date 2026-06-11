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
import 'models/models.dart';
import 'services/api_service.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_list_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/provider_screen.dart';
import 'screens/tool_screen.dart';
import 'screens/user_management_screen.dart';

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

  // Auth
  String? _token;
  AppUser? _user;
  bool _initializing = true;

  String? _currentChatId;
  int _navIndex = 0;

  // Für Chat-Liste Refresh
  int _chatListRefreshKey = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _backendUrl = widget.prefs.getString('backend_url') ?? _defaultBackendUrl();
    _token = widget.prefs.getString('auth_token');
    _api = ApiService(baseUrl: _backendUrl, token: _token);

    // Gespeichertes Token validieren
    if (_token != null && _token!.isNotEmpty) {
      try {
        final me = await _api.getMe();
        _user = me;
      } catch (_) {
        // Token ungültig/abgelaufen → verwerfen
        _token = null;
        _api = _api.withToken(null);
        await widget.prefs.remove('auth_token');
      }
    }
    if (mounted) setState(() => _initializing = false);
  }

  String _defaultBackendUrl() {
    const bool isWeb = bool.fromEnvironment('dart.library.html');
    return isWeb ? '' : 'http://localhost:8099';
  }

  void _onAuthenticated(String token, AppUser user) {
    widget.prefs.setString('auth_token', token);
    setState(() {
      _token = token;
      _user = user;
      _api = _api.withToken(token);
      _navIndex = 0;
      _currentChatId = null;
    });
  }

  void _logout() {
    widget.prefs.remove('auth_token');
    setState(() {
      _token = null;
      _user = null;
      _api = _api.withToken(null);
      _currentChatId = null;
      _navIndex = 0;
    });
  }

  void _onBackendUrlChanged(String url) {
    setState(() {
      _backendUrl = url;
      _api = ApiService(baseUrl: url, token: _token);
      widget.prefs.setString('backend_url', url);
    });
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
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Nicht angemeldet → Login/Setup
    if (_user == null) {
      return AuthScreen(api: _api, onAuthenticated: _onAuthenticated);
    }

    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 800;

    return isWide ? _WideLayout(
      navIndex: _navIndex,
      currentChatId: _currentChatId,
      api: _api,
      backendUrl: _backendUrl,
      token: _token,
      user: _user!,
      chatListRefreshKey: _chatListRefreshKey,
      onNavChanged: (i) => setState(() => _navIndex = i),
      onChatSelected: (id) => setState(() {
        _currentChatId = id;
        _navIndex = 0;
      }),
      onNewChat: _createNewChat,
      onToggleTheme: widget.onToggleTheme,
      onBackendUrlChanged: _onBackendUrlChanged,
      onLogout: _logout,
    ) : _NarrowLayout(
      navIndex: _navIndex,
      currentChatId: _currentChatId,
      api: _api,
      backendUrl: _backendUrl,
      token: _token,
      user: _user!,
      chatListRefreshKey: _chatListRefreshKey,
      onNavChanged: (i) => setState(() => _navIndex = i),
      onChatSelected: (id) => setState(() {
        _currentChatId = id;
        _navIndex = 0;
      }),
      onNewChat: _createNewChat,
      onToggleTheme: widget.onToggleTheme,
      onBackendUrlChanged: _onBackendUrlChanged,
      onLogout: _logout,
    );
  }
}


/// Eine Navigationsregisterkarte (rollenabhängig zusammengestellt).
class _NavSpec {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavSpec(this.icon, this.selectedIcon, this.label);
}

/// Baut die sichtbaren Tabs je nach Rolle. Reihenfolge ist stabil
/// (Chats zuerst, Einstellungen zuletzt), Admin-Tabs in der Mitte.
List<_NavSpec> _navSpecsFor(AppUser user) => [
      const _NavSpec(Icons.chat_bubble_outline, Icons.chat_bubble, 'Chats'),
      if (user.isAdmin) ...[
        const _NavSpec(Icons.cloud_outlined, Icons.cloud, 'Provider'),
        const _NavSpec(Icons.build_outlined, Icons.build, 'Tools'),
        const _NavSpec(Icons.people_outline, Icons.people, 'Benutzer'),
      ],
      const _NavSpec(Icons.settings_outlined, Icons.settings, 'Einstellungen'),
    ];


// ── Breites Layout (Desktop/Web) ─────────────────────────────────────────

class _WideLayout extends StatelessWidget {
  final int navIndex;
  final String? currentChatId;
  final ApiService api;
  final String backendUrl;
  final String? token;
  final AppUser user;
  final int chatListRefreshKey;
  final ValueChanged<int> onNavChanged;
  final ValueChanged<String> onChatSelected;
  final VoidCallback onNewChat;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onBackendUrlChanged;
  final VoidCallback onLogout;

  const _WideLayout({
    required this.navIndex,
    required this.currentChatId,
    required this.api,
    required this.backendUrl,
    required this.token,
    required this.user,
    required this.chatListRefreshKey,
    required this.onNavChanged,
    required this.onChatSelected,
    required this.onNewChat,
    required this.onToggleTheme,
    required this.onBackendUrlChanged,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final specs = _navSpecsFor(user);
    final idx = navIndex.clamp(0, specs.length - 1);
    final label = specs[idx].label;
    final showChatList = label == 'Chats';

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: idx,
            onDestinationSelected: onNavChanged,
            labelType: NavigationRailLabelType.selected,
            destinations: [
              for (final s in specs)
                NavigationRailDestination(
                  icon: Icon(s.icon),
                  selectedIcon: Icon(s.selectedIcon),
                  label: Text(s.label),
                ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.brightness_6_outlined),
                        onPressed: onToggleTheme,
                        tooltip: 'Theme wechseln',
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: onLogout,
                        tooltip: 'Abmelden (${user.username})',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const VerticalDivider(width: 1),

          if (showChatList) ...[
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

          Expanded(
            child: _bodyFor(
              label: label,
              api: api,
              backendUrl: backendUrl,
              token: token,
              user: user,
              currentChatId: currentChatId,
              chatListRefreshKey: chatListRefreshKey,
              onChatSelected: onChatSelected,
              onNewChat: onNewChat,
              onBackendUrlChanged: onBackendUrlChanged,
              onLogout: onLogout,
              chatEmptyPlaceholder: const _NoChatSelected(),
            ),
          ),
        ],
      ),
    );
  }
}


// ── Schmales Layout (Mobile/kleines Fenster) ────────────────────────────

class _NarrowLayout extends StatelessWidget {
  final int navIndex;
  final String? currentChatId;
  final ApiService api;
  final String backendUrl;
  final String? token;
  final AppUser user;
  final int chatListRefreshKey;
  final ValueChanged<int> onNavChanged;
  final ValueChanged<String> onChatSelected;
  final VoidCallback onNewChat;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onBackendUrlChanged;
  final VoidCallback onLogout;

  const _NarrowLayout({
    required this.navIndex,
    required this.currentChatId,
    required this.api,
    required this.backendUrl,
    required this.token,
    required this.user,
    required this.chatListRefreshKey,
    required this.onNavChanged,
    required this.onChatSelected,
    required this.onNewChat,
    required this.onToggleTheme,
    required this.onBackendUrlChanged,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final specs = _navSpecsFor(user);
    final idx = navIndex.clamp(0, specs.length - 1);
    final label = specs[idx].label;

    return Scaffold(
      body: _bodyFor(
        label: label,
        api: api,
        backendUrl: backendUrl,
        token: token,
        user: user,
        currentChatId: currentChatId,
        chatListRefreshKey: chatListRefreshKey,
        onChatSelected: onChatSelected,
        onNewChat: onNewChat,
        onBackendUrlChanged: onBackendUrlChanged,
        onLogout: onLogout,
        // Im schmalen Layout zeigt der Chat-Tab ohne Auswahl die Liste
        chatEmptyPlaceholder: ChatListScreen(
          key: ValueKey(chatListRefreshKey),
          api: api,
          selectedChatId: currentChatId,
          onChatSelected: onChatSelected,
          onNewChat: onNewChat,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: onNavChanged,
        destinations: [
          for (final s in specs)
            NavigationDestination(icon: Icon(s.icon), label: s.label),
        ],
      ),
    );
  }
}


/// Gemeinsamer Inhalts-Builder für beide Layouts – wählt anhand des Tab-Labels.
Widget _bodyFor({
  required String label,
  required ApiService api,
  required String backendUrl,
  required String? token,
  required AppUser user,
  required String? currentChatId,
  required int chatListRefreshKey,
  required ValueChanged<String> onChatSelected,
  required VoidCallback onNewChat,
  required ValueChanged<String> onBackendUrlChanged,
  required VoidCallback onLogout,
  required Widget chatEmptyPlaceholder,
}) {
  switch (label) {
    case 'Chats':
      return currentChatId != null
          ? ChatScreen(
              key: ValueKey(currentChatId),
              chatId: currentChatId,
              api: api,
              backendUrl: backendUrl,
              token: token,
            )
          : chatEmptyPlaceholder;
    case 'Provider':
      return ProviderScreen(api: api);
    case 'Tools':
      return ToolScreen(api: api);
    case 'Benutzer':
      return UserManagementScreen(api: api);
    case 'Einstellungen':
      return _SettingsScreen(
        backendUrl: backendUrl,
        user: user,
        onBackendUrlChanged: onBackendUrlChanged,
        onLogout: onLogout,
      );
    default:
      return const SizedBox.shrink();
  }
}


// ── Einstellungen-Screen ───────────────────────────────────────────────────

class _SettingsScreen extends StatefulWidget {
  final String backendUrl;
  final AppUser user;
  final ValueChanged<String> onBackendUrlChanged;
  final VoidCallback onLogout;

  const _SettingsScreen({
    required this.backendUrl,
    required this.user,
    required this.onBackendUrlChanged,
    required this.onLogout,
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
          // Angemeldeter Benutzer
          Text('Konto', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(widget.user.isAdmin ? Icons.shield : Icons.person),
              title: Text(widget.user.username),
              subtitle: Text(widget.user.isAdmin ? 'Administrator' : 'Benutzer'),
              trailing: OutlinedButton.icon(
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Abmelden'),
                onPressed: widget.onLogout,
              ),
            ),
          ),
          const SizedBox(height: 32),
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
