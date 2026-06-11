/// UserManagementScreen – nur für den Admin.
///
/// - Benutzer anlegen / löschen / Passwort zurücksetzen
/// - Pro Benutzer festlegen welche Provider und Tools er nutzen darf
///   (Häkchen werden sofort gespeichert)

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class UserManagementScreen extends StatefulWidget {
  final ApiService api;
  const UserManagementScreen({super.key, required this.api});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  bool _loading = true;
  String? _error;
  List<AppUser> _users = [];
  List<AppProvider> _providers = [];
  List<ToolServer> _tools = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.api.getUsers(),
        widget.api.getProviders(),
        widget.api.getToolServers(),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0] as List<AppUser>;
        _providers = results[1] as List<AppProvider>;
        _tools = results[2] as List<ToolServer>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _createUser() async {
    final result = await showDialog<({String username, String password})>(
      context: context,
      builder: (_) => const _CreateUserDialog(),
    );
    if (result == null) return;
    try {
      await widget.api.createUser(result.username, result.password);
      _snack('Benutzer "${result.username}" erstellt');
      _load();
    } catch (e) {
      _snack('Fehler: $e');
    }
  }

  Future<void> _deleteUser(AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Benutzer "${user.username}" löschen?'),
        content: const Text('Alle Chats dieses Benutzers werden ebenfalls gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteUser(user.id);
      _snack('Benutzer gelöscht');
      _load();
    } catch (e) {
      _snack('Fehler: $e');
    }
  }

  Future<void> _resetPassword(AppUser user) async {
    final pw = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (pw == null || pw.isEmpty) return;
    try {
      await widget.api.resetUserPassword(user.id, pw);
      _snack('Passwort von "${user.username}" zurückgesetzt');
    } catch (e) {
      _snack('Fehler: $e');
    }
  }

  Future<void> _toggleProvider(AppUser user, String providerId, bool enabled) async {
    final ids = List<String>.from(user.providerIds);
    if (enabled) {
      if (!ids.contains(providerId)) ids.add(providerId);
    } else {
      ids.remove(providerId);
    }
    await _updateUserLocal(user, providerIds: ids);
    try {
      await widget.api.setUserProviders(user.id, ids);
    } catch (e) {
      _snack('Fehler beim Speichern: $e');
      _load();
    }
  }

  Future<void> _toggleTool(AppUser user, String toolId, bool enabled) async {
    final ids = List<String>.from(user.toolIds);
    if (enabled) {
      if (!ids.contains(toolId)) ids.add(toolId);
    } else {
      ids.remove(toolId);
    }
    await _updateUserLocal(user, toolIds: ids);
    try {
      await widget.api.setUserTools(user.id, ids);
    } catch (e) {
      _snack('Fehler beim Speichern: $e');
      _load();
    }
  }

  Future<void> _updateUserLocal(AppUser user, {List<String>? providerIds, List<String>? toolIds}) async {
    setState(() {
      final idx = _users.indexWhere((u) => u.id == user.id);
      if (idx >= 0) {
        _users[idx] = AppUser(
          id: user.id,
          username: user.username,
          role: user.role,
          providerIds: providerIds ?? user.providerIds,
          toolIds: toolIds ?? user.toolIds,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Benutzerverwaltung'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createUser,
        icon: const Icon(Icons.person_add),
        label: const Text('Benutzer'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Fehler: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final user in _users) _buildUserCard(user, theme),
                    const SizedBox(height: 80),
                  ],
                ),
    );
  }

  Widget _buildUserCard(AppUser user, ThemeData theme) {
    final cs = theme.colorScheme;
    final isAdmin = user.isAdmin;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: isAdmin
          ? ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.shield, color: cs.onPrimaryContainer),
              ),
              title: Text(user.username),
              subtitle: const Text('Administrator · Vollzugriff'),
            )
          : ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: cs.secondaryContainer,
                child: Icon(Icons.person, color: cs.onSecondaryContainer),
              ),
              title: Text(user.username),
              subtitle: Text(
                '${user.providerIds.length} Provider · ${user.toolIds.length} Tools',
                style: theme.textTheme.bodySmall,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.password, size: 18),
                      label: const Text('Passwort'),
                      onPressed: () => _resetPassword(user),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                      label: Text('Löschen', style: TextStyle(color: cs.error)),
                      onPressed: () => _deleteUser(user),
                    ),
                  ],
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Provider', style: theme.textTheme.labelLarge),
                ),
                if (_providers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Keine Provider vorhanden.', style: TextStyle(color: Colors.grey)),
                  )
                else
                  for (final p in _providers)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: Text(p.type, style: theme.textTheme.bodySmall),
                      value: user.providerIds.contains(p.id),
                      onChanged: (v) => _toggleProvider(user, p.id, v ?? false),
                    ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Tools', style: theme.textTheme.labelLarge),
                ),
                if (_tools.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Keine Tools vorhanden.', style: TextStyle(color: Colors.grey)),
                  )
                else
                  for (final t in _tools)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.name),
                      subtitle: Text(t.type.toUpperCase(), style: theme.textTheme.bodySmall),
                      value: user.toolIds.contains(t.id),
                      onChanged: (v) => _toggleTool(user, t.id, v ?? false),
                    ),
              ],
            ),
    );
  }
}


// ── Dialoge ──────────────────────────────────────────────────────────────────

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();
  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neuer Benutzer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _userCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Benutzername', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Passwort', border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () {
            final u = _userCtrl.text.trim();
            final p = _passCtrl.text;
            if (u.isEmpty || p.isEmpty) return;
            Navigator.pop(context, (username: u, password: p));
          },
          child: const Text('Erstellen'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort zurücksetzen'),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Neues Passwort', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
