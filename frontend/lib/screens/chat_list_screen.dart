/// Chat-Liste – alle Gespräche mit Suche und Navigation.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class ChatListScreen extends StatefulWidget {
  final ApiService api;
  final String? selectedChatId;
  final ValueChanged<String> onChatSelected;
  final VoidCallback onNewChat;

  const ChatListScreen({
    super.key,
    required this.api,
    this.selectedChatId,
    required this.onChatSelected,
    required this.onNewChat,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatModel> _chats = [];
  List<ChatModel> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final chats = await widget.api.getChats();
      if (mounted) setState(() {
        _chats = chats;
        _filtered = chats;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() => _filtered = q.isEmpty
        ? _chats
        : _chats.where((c) => c.title.toLowerCase().contains(q)).toList());
  }

  Future<void> _deleteChat(ChatModel chat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Chat löschen'),
        content: Text('"${chat.title}" wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Löschen')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.api.deleteChat(chat.id);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Text('NexusChat',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: 'Neuer Chat',
                onPressed: widget.onNewChat,
              ),
            ],
          ),
        ),

        // Suche
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Suchen...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),

        const Divider(height: 16),

        // Chat-Liste
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? const Center(child: Text('Keine Gespräche'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final chat = _filtered[i];
                          final isSelected = chat.id == widget.selectedChatId;
                          return _ChatTile(
                            chat: chat,
                            isSelected: isSelected,
                            onTap: () => widget.onChatSelected(chat.id),
                            onDelete: () => _deleteChat(chat),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}


class _ChatTile extends StatelessWidget {
  final ChatModel chat;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ChatTile({
    required this.chat,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        return DateFormat('HH:mm').format(dt);
      }
      return DateFormat('dd.MM.yy').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withOpacity(0.3),
      title: Text(
        chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isSelected ? FontWeight.w600 : null,
        ),
      ),
      subtitle: Text(
        _formatDate(chat.updatedAt),
        style: theme.textTheme.bodySmall,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: onDelete,
        tooltip: 'Löschen',
      ),
      onTap: onTap,
    );
  }
}
