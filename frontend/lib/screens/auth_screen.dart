/// AuthScreen – Anmeldung bzw. einmalige Admin-Einrichtung.
///
/// Fragt beim Backend ab ob noch kein Admin existiert (needs_setup).
/// - Kein Admin: Einrichtungsformular (erstellt den Admin).
/// - Sonst: normales Login.
/// Bei Erfolg wird (token, user) per Callback nach oben gereicht.

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class AuthScreen extends StatefulWidget {
  final ApiService api;
  final void Function(String token, AppUser user) onAuthenticated;

  const AuthScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loadingStatus = true;
  bool _needsSetup = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _loadingStatus = true;
      _error = null;
    });
    try {
      final needsSetup = await widget.api.authNeedsSetup();
      if (!mounted) return;
      setState(() {
        _needsSetup = needsSetup;
        _loadingStatus = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStatus = false;
        _error = 'Backend nicht erreichbar.\nURL prüfen und erneut versuchen.\n\n$e';
      });
    }
  }

  Future<void> _submit() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Bitte Benutzername und Passwort eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (token, user) = _needsSetup
          ? await widget.api.setupAdmin(username, password)
          : await widget.api.login(username, password);
      if (!mounted) return;
      widget.onAuthenticated(token, user);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
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
            child: _loadingStatus
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.hub, size: 56, color: cs.primary),
                      const SizedBox(height: 16),
                      Text('NexusChat',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                        _needsSetup
                            ? 'Administrator einrichten'
                            : 'Anmelden',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if (_needsSetup) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Dies ist die einmalige Einrichtung. Der erste Account wird zum Administrator.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 24),
                      TextField(
                        controller: _userCtrl,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Benutzername',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        enabled: !_busy,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passCtrl,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        decoration: const InputDecoration(
                          labelText: 'Passwort',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        enabled: !_busy,
                        onSubmitted: (_) => _busy ? null : _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(color: cs.error, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_needsSetup ? 'Admin erstellen' : 'Anmelden'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _checkStatus,
                        child: const Text('Verbindung erneut prüfen'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
