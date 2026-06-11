/// Chat-Liste – alle Gespräche mit Suche und Navigation.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../theme.dart';
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
  List<Map<String, dynamic>> _msgHits = []; // Treffer im Nachrichtentext
  bool _loading = true;
  int _searchSeq = 0; // verwirft veraltete Such-Antworten
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
    _searchMessages(_searchCtrl.text.trim());
  }

  Future<void> _searchMessages(String query) async {
    final seq = ++_searchSeq;
    if (query.length < 2) {
      setState(() => _msgHits = []);
      return;
    }
    try {
      final hits = await widget.api.searchMessages(query);
      if (!mounted || seq != _searchSeq) return; // veraltet → verwerfen
      // Treffer ausblenden, die schon per Titel angezeigt werden
      final titleIds = _filtered.map((c) => c.id).toSet();
      setState(() => _msgHits = hits.where((h) => !titleIds.contains(h['id'])).toList());
    } catch (_) {
      if (mounted && seq == _searchSeq) setState(() => _msgHits = []);
    }
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
          padding: const EdgeInsets.fromLTRB(16, 18, 10, 10),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  gradient: NexusColors.accentGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text('NexusChat',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton.filledTonal(
                icon: const Icon(Icons.add, size: 20),
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Chat-Liste (+ Nachrichten-Treffer bei aktiver Suche)
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_filtered.isEmpty && _msgHits.isEmpty)
                  ? _EmptyChats(onNewChat: widget.onNewChat)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        children: [
                          for (final chat in _filtered)
                            _ChatTile(
                              chat: chat,
                              isSelected: chat.id == widget.selectedChatId,
                              onTap: () => widget.onChatSelected(chat.id),
                              onDelete: () => _deleteChat(chat),
                            ),
                          if (_msgHits.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
                              child: Text(
                                'Treffer in Nachrichten',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          for (final hit in _msgHits)
                            _MessageHitTile(
                              title: hit['title'] as String? ?? '',
                              snippet: hit['snippet'] as String? ?? '',
                              onTap: () => widget.onChatSelected(hit['id'] as String),
                            ),
                        ],
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
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected ? cs.primary.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 16,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? cs.onSurface : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDate(chat.updatedAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 17),
                  visualDensity: VisualDensity.compact,
                  color: cs.onSurfaceVariant,
                  onPressed: onDelete,
                  tooltip: 'Löschen',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Treffer im Nachrichtentext (Suche).
class _MessageHitTile extends StatelessWidget {
  final String title;
  final String snippet;
  final VoidCallback onTap;
  const _MessageHitTile({required this.title, required this.snippet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.search, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: Text(snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// Leerer Zustand der Chat-Liste.
class _EmptyChats extends StatelessWidget {
  final VoidCallback onNewChat;
  const _EmptyChats({required this.onNewChat});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined, size: 40, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text('Noch keine Gespräche', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onNewChat,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neuer Chat'),
          ),
        ],
      ),
    );
  }
}
