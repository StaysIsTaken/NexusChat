/// Tool-Verwaltung – MCP-Server und REST-APIs konfigurieren.

import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ToolScreen extends StatefulWidget {
  final ApiService api;
  const ToolScreen({super.key, required this.api});

  @override
  State<ToolScreen> createState() => _ToolScreenState();
}

class _ToolScreenState extends State<ToolScreen> {
  List<ToolServer> _servers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final servers = await widget.api.getToolServers();
      if (mounted) setState(() { _servers = servers; _loading = false; });
    } catch (e) {
      if (mounted) { setState(() => _loading = false); _showError(e.toString()); }
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red));

  Future<void> _delete(ToolServer s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tool-Server löschen'),
        content: Text('${s.name} wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteToolServer(s.id);
      _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _test(ToolServer s) async {
    try {
      final result = await widget.api.testToolServer(s.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] as String? ?? ''),
          backgroundColor: result['success'] == true ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _showTools(ToolServer s) async {
    showDialog(
      context: context,
      builder: (_) => _ToolsListDialog(api: widget.api, server: s),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools & MCP-Server'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Server hinzufügen'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? _EmptyState(onAdd: _showAddDialog)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _servers.length,
                  itemBuilder: (_, i) => _ToolServerCard(
                    server: _servers[i],
                    onEdit: () => _showEditDialog(_servers[i]),
                    onDelete: () => _delete(_servers[i]),
                    onTest: () => _test(_servers[i]),
                    onShowTools: () => _showTools(_servers[i]),
                  ),
                ),
    );
  }

  void _showAddDialog() => showDialog(
        context: context,
        builder: (_) => _AddServerDialog(api: widget.api),
      ).then((_) => _load());

  void _showEditDialog(ToolServer s) => showDialog(
        context: context,
        builder: (_) => _AddServerDialog(api: widget.api, existing: s),
      ).then((_) => _load());
}


class _ToolServerCard extends StatelessWidget {
  final ToolServer server;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;
  final VoidCallback onShowTools;

  const _ToolServerCard({
    required this.server,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
    required this.onShowTools,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.tertiaryContainer,
          child: Icon(_typeIcon(server.type),
              color: theme.colorScheme.onTertiaryContainer, size: 20),
        ),
        title: Row(
          children: [
            Flexible(child: Text(server.name, overflow: TextOverflow.ellipsis)),
            if (server.requiresConfirmation) ...[
              const SizedBox(width: 6),
              Icon(Icons.shield_outlined, size: 15, color: theme.colorScheme.primary),
            ],
          ],
        ),
        subtitle: Text(
          '${server.type.toUpperCase()}${server.url != null ? " · ${server.url}" : ""}'
          '${server.requiresConfirmation ? " · Bestätigung erforderlich" : ""}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.list_alt, size: 20), onPressed: onShowTools,
                tooltip: 'Tools anzeigen'),
            IconButton(icon: const Icon(Icons.wifi_tethering, size: 20), onPressed: onTest,
                tooltip: 'Verbindung testen'),
            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: onEdit,
                tooltip: 'Bearbeiten'),
            IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: onDelete,
                tooltip: 'Löschen'),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(String type) => switch (type) {
        'mcp' => Icons.extension_outlined,
        'rest' => Icons.api,
        _ => Icons.build_outlined,
      };
}


class _ToolsListDialog extends StatefulWidget {
  final ApiService api;
  final ToolServer server;
  const _ToolsListDialog({required this.api, required this.server});

  @override
  State<_ToolsListDialog> createState() => _ToolsListDialogState();
}

class _ToolsListDialogState extends State<_ToolsListDialog> {
  List<Map<String, dynamic>>? _tools;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tools = await widget.api.getServerTools(widget.server.id);
      if (mounted) setState(() => _tools = tools);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Tools: ${widget.server.name}'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _error != null
            ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
            : _tools == null
                ? const Center(child: CircularProgressIndicator())
                : _tools!.isEmpty
                    ? const Center(child: Text('Keine Tools gefunden'))
                    : ListView.builder(
                        itemCount: _tools!.length,
                        itemBuilder: (_, i) {
                          final t = _tools![i];
                          return ListTile(
                            leading: const Icon(Icons.build_outlined, size: 18),
                            title: Text(t['name'] as String? ?? ''),
                            subtitle: Text(t['description'] as String? ?? ''),
                            dense: true,
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
      ],
    );
  }
}


class _AddServerDialog extends StatefulWidget {
  final ApiService api;
  final ToolServer? existing;
  const _AddServerDialog({required this.api, this.existing});

  @override
  State<_AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<_AddServerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _configCtrl = TextEditingController();
  String _type = 'mcp';
  bool _saving = false;
  bool _requiresConfirmation = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final s = widget.existing!;
      _nameCtrl.text = s.name;
      _urlCtrl.text = s.url ?? '';
      _apiKeyCtrl.text = s.apiKey ?? '';
      _configCtrl.text = const JsonEncoder.withIndent('  ').convert(s.config);
      _type = s.type;
      _requiresConfirmation = s.requiresConfirmation;
    } else {
      _configCtrl.text = '{}';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _urlCtrl.dispose();
    _apiKeyCtrl.dispose(); _configCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    Map<String, dynamic> config = {};
    try {
      config = jsonDecode(_configCtrl.text) as Map<String, dynamic>;
    } catch (_) {}

    final body = {
      'name': _nameCtrl.text.trim(),
      'type': _type,
      'url': _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
      'api_key': _apiKeyCtrl.text.trim().isEmpty ? null : _apiKeyCtrl.text.trim(),
      'config': config,
      'requires_confirmation': _requiresConfirmation,
    };

    try {
      if (widget.existing != null) {
        await widget.api.updateToolServer(widget.existing!.id, body);
      } else {
        await widget.api.createToolServer(body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Server hinzufügen' : 'Server bearbeiten'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) => v?.isEmpty == true ? 'Pflichtfeld' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(labelText: 'Typ'),
                  items: const [
                    DropdownMenuItem(value: 'mcp', child: Text('MCP-Server (Streamable HTTP)')),
                    DropdownMenuItem(value: 'rest', child: Text('REST-API')),
                  ],
                  onChanged: (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _urlCtrl,
                  decoration: InputDecoration(
                    labelText: 'URL',
                    hintText: _type == 'mcp'
                        ? 'http://localhost:8080'
                        : 'https://api.example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apiKeyCtrl,
                  decoration: InputDecoration(
                    labelText: 'API Key (optional)',
                    helperText: (widget.existing?.hasApiKey ?? false)
                        ? 'Schlüssel gesetzt – leer lassen zum Beibehalten'
                        : null,
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bestätigung vor Ausführung'),
                  subtitle: const Text(
                    'Der Nutzer muss jeden Aufruf dieses Tools manuell bestätigen.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _requiresConfirmation,
                  onChanged: (v) => setState(() => _requiresConfirmation = v),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _configCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Konfiguration (JSON)',
                    helperText: 'Für REST-APIs: {"endpoints": [...]}',
                  ),
                  maxLines: 6,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  validator: (v) {
                    try {
                      jsonDecode(v ?? '{}');
                      return null;
                    } catch (_) {
                      return 'Ungültiges JSON';
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.existing == null ? 'Erstellen' : 'Speichern'),
        ),
      ],
    );
  }
}


class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.build_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Noch keine Tools konfiguriert',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Füge MCP-Server oder REST-APIs als Tools hinzu.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Server hinzufügen'),
            ),
          ],
        ),
      );
}
