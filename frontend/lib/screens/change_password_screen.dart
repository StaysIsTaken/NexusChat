/// Passwort ändern – als Vollbild-Gate (erzwungen) und als Dialog (freiwillig).

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme.dart';
import '../services/api_service.dart';

/// Vollbild-Variante: erscheint wenn der Nutzer sein Passwort ändern MUSS.
class ChangePasswordScreen extends StatefulWidget {
  final ApiService api;
  final void Function(String token, AppUser user) onChanged;
  final VoidCallback onLogout;

  const ChangePasswordScreen({
    super.key,
    required this.api,
    required this.onChanged,
    required this.onLogout,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_newCtrl.text.length < 4) {
      setState(() => _error = 'Neues Passwort ist zu kurz (mind. 4 Zeichen).');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Die neuen Passwörter stimmen nicht überein.');
      return;
    }
    setState(() => _busy = true);
    try {
      final (token, user) = await widget.api.changeOwnPassword(_currentCtrl.text, _newCtrl.text);
      widget.onChanged(token, user);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: NexusColors.accentGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.lock_reset, size: 32, color: Colors.white),
                ),
                const SizedBox(height: 20),
                Text('Passwort ändern',
                    textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Aus Sicherheitsgründen musst du jetzt ein eigenes Passwort festlegen.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                _PasswordFields(
                  currentCtrl: _currentCtrl,
                  newCtrl: _newCtrl,
                  confirmCtrl: _confirmCtrl,
                  enabled: !_busy,
                  onSubmit: _submit,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: TextStyle(color: cs.error, fontSize: 13), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Passwort speichern'),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: _busy ? null : widget.onLogout, child: const Text('Abmelden')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Gemeinsame Eingabefelder.
class _PasswordFields extends StatelessWidget {
  final TextEditingController currentCtrl;
  final TextEditingController newCtrl;
  final TextEditingController confirmCtrl;
  final bool enabled;
  final VoidCallback onSubmit;

  const _PasswordFields({
    required this.currentCtrl,
    required this.newCtrl,
    required this.confirmCtrl,
    required this.enabled,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: currentCtrl,
          obscureText: true,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Aktuelles Passwort', prefixIcon: Icon(Icons.lock_outline)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: newCtrl,
          obscureText: true,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Neues Passwort', prefixIcon: Icon(Icons.lock)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: confirmCtrl,
          obscureText: true,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Neues Passwort bestätigen', prefixIcon: Icon(Icons.lock)),
          onSubmitted: (_) => enabled ? onSubmit() : null,
        ),
      ],
    );
  }
}


/// Dialog-Variante für die freiwillige Änderung in den Einstellungen.
/// Gibt (token, user) bei Erfolg zurück, sonst null.
Future<(String, AppUser)?> showChangePasswordDialog(BuildContext context, ApiService api) {
  return showDialog<(String, AppUser)>(
    context: context,
    builder: (_) => _ChangePasswordDialog(api: api),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  final ApiService api;
  const _ChangePasswordDialog({required this.api});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_newCtrl.text.length < 4) {
      setState(() => _error = 'Neues Passwort ist zu kurz.');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwörter stimmen nicht überein.');
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.api.changeOwnPassword(_currentCtrl.text, _newCtrl.text);
      if (mounted) Navigator.pop(context, result);
    } on ApiException catch (e) {
      if (mounted) setState(() { _busy = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort ändern'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PasswordFields(
              currentCtrl: _currentCtrl,
              newCtrl: _newCtrl,
              confirmCtrl: _confirmCtrl,
              enabled: !_busy,
              onSubmit: _submit,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}
