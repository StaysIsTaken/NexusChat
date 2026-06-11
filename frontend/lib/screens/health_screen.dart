/// HealthScreen – Admin-Übersicht: welche Provider/Tools sind erreichbar.

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class HealthScreen extends StatefulWidget {
  final ApiService api;
  const HealthScreen({super.key, required this.api});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

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
      final items = await widget.api.getSystemHealth();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    final providers = _items.where((i) => i['kind'] == 'provider').toList();
    final tools = _items.where((i) => i['kind'] == 'tool').toList();
    final onlineCount = _items.where((i) => i['online'] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Neu prüfen',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Verbindungen werden geprüft…'),
                ],
              ),
            )
          : _error != null
              ? Center(child: Text('Fehler: $_error'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _Summary(online: onlineCount, total: _items.length),
                      const SizedBox(height: 20),
                      if (providers.isNotEmpty) ...[
                        _SectionHeader(icon: Icons.cloud_outlined, label: 'Provider'),
                        ...providers.map((i) => _HealthTile(item: i)),
                        const SizedBox(height: 16),
                      ],
                      if (tools.isNotEmpty) ...[
                        _SectionHeader(icon: Icons.build_outlined, label: 'Tools'),
                        ...tools.map((i) => _HealthTile(item: i)),
                      ],
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(child: Text('Keine Provider oder Tools konfiguriert.')),
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _Summary extends StatelessWidget {
  final int online;
  final int total;
  const _Summary({required this.online, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allOk = total > 0 && online == total;
    final color = total == 0
        ? theme.colorScheme.onSurfaceVariant
        : (allOk ? Colors.green : (online == 0 ? theme.colorScheme.error : Colors.orange));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(allOk ? Icons.check_circle : Icons.monitor_heart_outlined, color: color, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$online von $total erreichbar', style: theme.textTheme.titleMedium),
                Text(
                  total == 0 ? 'Nichts konfiguriert' : (allOk ? 'Alle Dienste online' : 'Einige Dienste offline'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _HealthTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _HealthTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = item['online'] == true;
    final enabled = item['enabled'] != false;
    final color = !enabled
        ? theme.colorScheme.onSurfaceVariant
        : (online ? Colors.green : theme.colorScheme.error);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        title: Text(item['name'] as String? ?? ''),
        subtitle: Text(
          '${(item['type'] as String? ?? '').toUpperCase()} · ${item['message'] ?? ''}'
          '${enabled ? '' : ' · deaktiviert'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Text(
          !enabled ? 'Aus' : (online ? 'Online' : 'Offline'),
          style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
