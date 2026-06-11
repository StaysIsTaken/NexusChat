/// Provider-Verwaltung – KI-Provider hinzufügen, bearbeiten, löschen.

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ProviderScreen extends StatefulWidget {
  final ApiService api;
  const ProviderScreen({super.key, required this.api});

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  List<AppProvider> _providers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final providers = await widget.api.getProviders();
      if (mounted) setState(() { _providers = providers; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError(e.toString());
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _delete(AppProvider p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Provider löschen'),
        content: Text('${p.name} wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteProvider(p.id);
      _load();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _test(AppProvider p) async {
    try {
      final result = await widget.api.testProvider(p.id);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProviderDialog(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Provider hinzufügen'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _providers.isEmpty
              ? _EmptyState(onAdd: () => _showProviderDialog(context, null))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _providers.length,
                  itemBuilder: (_, i) => _ProviderCard(
                    provider: _providers[i],
                    onEdit: () => _showProviderDialog(context, _providers[i]),
                    onDelete: () => _delete(_providers[i]),
                    onTest: () => _test(_providers[i]),
                    onShowModels: () => _showModelsDialog(_providers[i]),
                  ),
                ),
    );
  }

  Future<void> _showProviderDialog(BuildContext context, AppProvider? existing) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ProviderDialog(api: widget.api, existing: existing),
    );
    if (result == true) _load();
  }

  void _showModelsDialog(AppProvider p) {
    showDialog(
      context: context,
      builder: (_) => _ModelsDialog(api: widget.api, provider: p),
    );
  }
}


class _ProviderCard extends StatelessWidget {
  final AppProvider provider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTest;
  final VoidCallback onShowModels;

  const _ProviderCard({
    required this.provider,
    required this.onEdit,
    required this.onDelete,
    required this.onTest,
    required this.onShowModels,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(_typeIcon(provider.type),
              color: theme.colorScheme.onPrimaryContainer, size: 20),
        ),
        title: Text(provider.name),
        subtitle: Text(
          '${provider.type}${provider.baseUrl != null ? " · ${provider.baseUrl}" : ""}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.list_alt, size: 20), onPressed: onShowModels,
                tooltip: 'Verfügbare Modelle anzeigen'),
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
        'ollama' => Icons.computer,
        'openai' => Icons.auto_awesome,
        'anthropic' => Icons.psychology,
        _ => Icons.cloud_outlined,
      };
}


class _ProviderDialog extends StatefulWidget {
  final ApiService api;
  final AppProvider? existing;
  const _ProviderDialog({required this.api, this.existing});

  @override
  State<_ProviderDialog> createState() => _ProviderDialogState();
}

class _ProviderDialogState extends State<_ProviderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _defaultModelCtrl = TextEditingController();
  String _type = 'ollama';
  bool _saving = false;

  // Modell-Auswahl für bestehende Provider
  List<String> _models = [];
  bool _loadingModels = false;
  String? _modelsError;
  String? _selectedDefaultModel;

  final _types = [
    ('ollama', 'Ollama (Lokal)'),
    ('openai', 'OpenAI (GPT)'),
    ('anthropic', 'Anthropic (Claude)'),
    ('openai_compatible', 'OpenAI-Kompatibel'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final p = widget.existing!;
      _nameCtrl.text = p.name;
      _baseUrlCtrl.text = p.baseUrl ?? '';
      _apiKeyCtrl.text = p.apiKey ?? '';
      _defaultModelCtrl.text = p.defaultModel ?? '';
      _selectedDefaultModel = p.defaultModel;
      _type = p.type;
      // Modelle sofort laden wenn Provider schon existiert
      _fetchModels();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _defaultModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    if (widget.existing == null) return;
    setState(() { _loadingModels = true; _modelsError = null; });
    try {
      final models = await widget.api.getProviderModels(widget.existing!.id);
      if (!mounted) return;
      setState(() {
        _models = models;
        _loadingModels = false;
        // Gespeichertes Standard-Modell beibehalten falls es in der Liste ist
        if (_selectedDefaultModel != null && !models.contains(_selectedDefaultModel)) {
          // Trotzdem behalten – Nutzer kann es manuell überschreiben
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadingModels = false; _modelsError = e.toString(); });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Standard-Modell: Dropdown-Auswahl hat Vorrang vor manueller Eingabe
    final defaultModel = _models.isNotEmpty
        ? _selectedDefaultModel
        : (_defaultModelCtrl.text.trim().isEmpty ? null : _defaultModelCtrl.text.trim());

    final body = {
      'name': _nameCtrl.text.trim(),
      'type': _type,
      'base_url': _baseUrlCtrl.text.trim().isEmpty ? null : _baseUrlCtrl.text.trim(),
      'api_key': _apiKeyCtrl.text.trim().isEmpty ? null : _apiKeyCtrl.text.trim(),
      'default_model': defaultModel,
    };

    try {
      if (widget.existing != null) {
        await widget.api.updateProvider(widget.existing!.id, body);
      } else {
        await widget.api.createProvider(body);
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
      title: Text(widget.existing == null ? 'Provider hinzufügen' : 'Provider bearbeiten'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
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
                decoration: const InputDecoration(labelText: 'Typ *'),
                items: _types.map((t) => DropdownMenuItem(
                  value: t.$1,
                  child: Text(t.$2),
                )).toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _baseUrlCtrl,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: _defaultUrlHint(_type),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apiKeyCtrl,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  helperText: (widget.existing?.hasApiKey ?? false)
                      ? 'Schlüssel gesetzt – leer lassen zum Beibehalten'
                      : null,
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              // Standard-Modell: Dropdown wenn Modelle geladen, sonst Textfeld
              _buildDefaultModelField(),
            ],
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

  Widget _buildDefaultModelField() {
    // Neu-Erstellung oder Modelle noch nicht geladen: Textfeld
    if (widget.existing == null || (_models.isEmpty && !_loadingModels && _modelsError == null)) {
      return TextFormField(
        controller: _defaultModelCtrl,
        decoration: InputDecoration(
          labelText: 'Standard-Modell',
          hintText: 'z.B. llama3.2 oder gpt-4o',
          helperText: widget.existing == null
              ? 'Nach dem Erstellen werden verfügbare Modelle geladen.'
              : null,
        ),
      );
    }

    // Lädt gerade
    if (_loadingModels) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Standard-Modell',
          border: OutlineInputBorder(),
        ),
        child: const Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Modelle werden geladen...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    // Fehler beim Laden
    if (_modelsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _defaultModelCtrl,
            decoration: InputDecoration(
              labelText: 'Standard-Modell',
              hintText: 'z.B. llama3.2 oder gpt-4o',
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _fetchModels,
                tooltip: 'Modelle laden',
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Modellliste nicht verfügbar: $_modelsError',
            style: const TextStyle(color: Colors.orange, fontSize: 11),
          ),
        ],
      );
    }

    // Modelle geladen → Dropdown
    return DropdownButtonFormField<String>(
      value: _selectedDefaultModel,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Standard-Modell',
        border: const OutlineInputBorder(),
        suffixText: '${_models.length} verfügbar',
        suffixStyle: const TextStyle(fontSize: 11, color: Colors.grey),
      ),
      hint: const Text('Modell auswählen'),
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
      onChanged: (v) => setState(() => _selectedDefaultModel = v),
    );
  }

  String _defaultUrlHint(String type) => switch (type) {
        'ollama' => 'http://localhost:11434',
        'openai' => 'https://api.openai.com/v1',
        'anthropic' => 'https://api.anthropic.com',
        _ => 'http://localhost:1234/v1',
      };
}


/// Dialog der alle verfügbaren Modelle eines Providers anzeigt.
class _ModelsDialog extends StatefulWidget {
  final ApiService api;
  final AppProvider provider;
  const _ModelsDialog({required this.api, required this.provider});

  @override
  State<_ModelsDialog> createState() => _ModelsDialogState();
}

class _ModelsDialogState extends State<_ModelsDialog> {
  List<String> _models = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final models = await widget.api.getProviderModels(widget.provider.id);
      if (mounted) setState(() { _models = models; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.list_alt, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Modelle: ${widget.provider.name}')),
          IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 350,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Erneut versuchen'),
                        ),
                      ],
                    ),
                  )
                : _models.isEmpty
                    ? const Center(child: Text('Keine Modelle gefunden.'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_models.length} Modell(e) verfügbar',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _models.length,
                              itemBuilder: (_, i) => ListTile(
                                leading: const Icon(Icons.smart_toy_outlined, size: 18),
                                title: SelectableText(
                                  _models[i],
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                  ),
                                ),
                                dense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
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
            Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Noch keine Provider konfiguriert',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Füge Ollama, OpenAI oder andere Provider hinzu.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Provider hinzufügen'),
            ),
          ],
        ),
      );
}
