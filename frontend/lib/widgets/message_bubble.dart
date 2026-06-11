/// MessageBubble – rendert eine einzelne Chat-Nachricht.
/// - Nutzer-Nachrichten: rechtsbündig, primäre Farbe
/// - Assistent-Nachrichten: linksbündig, Surface-Farbe mit Markdown
/// - <think>...</think> Blöcke: aufklappbarer Reasoning-Bereich
/// - Tool-Calls: aufklappbare Sub-Widgets

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:markdown/markdown.dart' as md;
import '../models/models.dart';
import '../theme.dart';
import 'tool_call_widget.dart';

// ── Think-Block Parsing ────────────────────────────────────────────────────

class _Segment {
  final bool isThink;
  final String content;
  const _Segment({required this.isThink, required this.content});
}

// [\s\S]*? statt dotAll – zuverlässiger in Dart Web (JavaScript RegExp-Engine)
final _thinkRe = RegExp(r'<think>([\s\S]*?)</think>', caseSensitive: false);

List<_Segment> _parseSegments(String raw) {
  final segments = <_Segment>[];
  int lastEnd = 0;
  for (final m in _thinkRe.allMatches(raw)) {
    if (m.start > lastEnd) {
      final text = raw.substring(lastEnd, m.start).trim();
      if (text.isNotEmpty) segments.add(_Segment(isThink: false, content: text));
    }
    final think = (m.group(1) ?? '').trim();
    if (think.isNotEmpty) segments.add(_Segment(isThink: true, content: think));
    lastEnd = m.end;
  }
  if (lastEnd < raw.length) {
    final text = raw.substring(lastEnd).trim();
    if (text.isNotEmpty) segments.add(_Segment(isThink: false, content: text));
  }
  return segments;
}

/// Prüft ob gerade ein offener <think>-Block gestreamt wird (noch kein </think>)
bool _hasOpenThinkBlock(String content) {
  final lower = content.toLowerCase();
  final opens = RegExp(r'<think>').allMatches(lower).length;
  final closes = RegExp(r'</think>').allMatches(lower).length;
  return opens > closes;
}


// ── MessageBubble ──────────────────────────────────────────────────────────

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onEdit;        // nur Nutzernachrichten
  final VoidCallback? onRegenerate;  // nur letzte Assistentennachricht

  const MessageBubble({
    super.key,
    required this.message,
    this.onEdit,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _Avatar(isUser: false),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                _BubbleContent(message: message, isUser: isUser),
                if (message.toolCalls.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...buildToolCallWidgets(message.toolCalls, message.toolResults),
                ],
                _MessageActions(
                  isUser: isUser,
                  content: message.content,
                  onEdit: onEdit,
                  onRegenerate: onRegenerate,
                ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _Avatar(isUser: true),
          ],
        ],
      ),
    );
  }
}


/// Aktionsleiste unter einer Nachricht: Kopieren, Bearbeiten, Neu generieren.
class _MessageActions extends StatelessWidget {
  final bool isUser;
  final String content;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;

  const _MessageActions({
    required this.isUser,
    required this.content,
    this.onEdit,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
          icon: Icon(icon, size: 15),
          tooltip: tip,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(),
          color: cs.onSurfaceVariant,
          onPressed: onTap,
        );

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          btn(Icons.copy_outlined, 'Kopieren', () {
            Clipboard.setData(ClipboardData(text: content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Kopiert'), duration: Duration(seconds: 1)),
            );
          }),
          if (isUser && onEdit != null) btn(Icons.edit_outlined, 'Bearbeiten', onEdit!),
          if (!isUser && onRegenerate != null)
            btn(Icons.refresh, 'Neu generieren', onRegenerate!),
        ],
      ),
    );
  }
}


// ── Bubble-Inhalt ──────────────────────────────────────────────────────────

class _BubbleContent extends StatelessWidget {
  final ChatMessage message;
  final bool isUser;

  const _BubbleContent({required this.message, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final textColor = isUser ? Colors.white : colorScheme.onSurface;

    if (isUser) {
      return Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          gradient: NexusColors.accentGradient,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(6),
          ),
          boxShadow: [
            BoxShadow(
              color: NexusColors.seed.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SelectableText(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(color: textColor, height: 1.4),
        ),
      );
    }

    // Assistent: Think-Blöcke parsen und aufklappbar rendern
    final segments = _parseSegments(message.content);

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(6),
          bottomRight: Radius.circular(18),
        ),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: segments.isEmpty
          ? Text('...', style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < segments.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  if (segments[i].isThink)
                    _ThinkBlock(content: segments[i].content)
                  else
                    _MarkdownSegment(
                      content: segments[i].content,
                      textColor: textColor,
                      theme: theme,
                      colorScheme: colorScheme,
                    ),
                ],
              ],
            ),
    );
  }
}


// ── Aufklappbarer Think-Block ──────────────────────────────────────────────

class _ThinkBlock extends StatefulWidget {
  final String content;
  const _ThinkBlock({required this.content});

  @override
  State<_ThinkBlock> createState() => _ThinkBlockState();
}

class _ThinkBlockState extends State<_ThinkBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header – klickbar zum Auf-/Zuklappen
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Reasoning',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            // Inhalt – nur wenn ausgeklappt
            if (_expanded) ...[
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.5)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: SelectableText(
                  widget.content,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ── Markdown-Segment ───────────────────────────────────────────────────────

class _MarkdownSegment extends StatelessWidget {
  final String content;
  final Color textColor;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _MarkdownSegment({
    required this.content,
    required this.textColor,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: content,
      builders: {'code': _CodeElementBuilder(theme)},
      styleSheet: MarkdownStyleSheet(
        p: theme.textTheme.bodyMedium?.copyWith(color: textColor),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: colorScheme.surfaceContainerHighest,
          color: colorScheme.onSurface,
        ),
        codeblockPadding: EdgeInsets.zero,
        codeblockDecoration: const BoxDecoration(),
        h1: theme.textTheme.titleLarge?.copyWith(color: textColor),
        h2: theme.textTheme.titleMedium?.copyWith(color: textColor),
        h3: theme.textTheme.titleSmall?.copyWith(color: textColor),
        blockquotePadding: const EdgeInsets.symmetric(horizontal: 12),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colorScheme.primary, width: 3),
          ),
        ),
      ),
      selectable: true,
    );
  }
}


// ── Code-Block mit Syntax-Highlighting + Copy ───────────────────────────────

class _CodeElementBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  _CodeElementBuilder(this.theme);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    final cls = element.attributes['class'];
    if (cls != null && cls.startsWith('language-')) {
      language = cls.substring('language-'.length);
    }
    final text = element.textContent;
    // Inline-Code (kein Block) → Standard-Rendering verwenden
    if (language.isEmpty && !text.contains('\n')) return null;
    return _CodeBlock(code: text.replaceAll(RegExp(r'\n$'), ''), language: language, theme: theme);
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  final String language;
  final ThemeData theme;
  const _CodeBlock({required this.code, required this.language, required this.theme});

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF15151C) : const Color(0xFFF4F2FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kopfzeile mit Sprache + Copy
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Text(
                  language.isEmpty ? 'Code' : language,
                  style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 15),
                  tooltip: 'Code kopieren',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  color: cs.onSurfaceVariant,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code kopiert'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
          ),
          // Code mit Highlighting (horizontal scrollbar)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              code,
              language: language.isEmpty ? 'plaintext' : language,
              theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
              padding: const EdgeInsets.all(12),
              textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}


// ── Avatar ─────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final bool isUser;
  const _Avatar({required this.isUser});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (isUser) {
      return CircleAvatar(
        radius: 15,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: Icon(Icons.person, size: 17, color: colorScheme.onSurfaceVariant),
      );
    }
    // KI-Avatar mit Marken-Verlauf
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        gradient: NexusColors.accentGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: NexusColors.seed.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
    );
  }
}


// ── Streaming-Bubble ───────────────────────────────────────────────────────

class StreamingMessageBubble extends StatelessWidget {
  final String partialContent;
  final List<ActiveToolCall> activeToolCalls;

  const StreamingMessageBubble({
    super.key,
    required this.partialContent,
    this.activeToolCalls = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isThinking = _hasOpenThinkBlock(partialContent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(isUser: false),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: isThinking
                      ? _ThinkingIndicator()
                      : _StreamingContent(content: partialContent, theme: theme, cs: cs),
                ),
              ),
            ],
          ),
        ),
        // Laufende Tool-Calls
        for (final tc in activeToolCalls)
          Padding(
            padding: const EdgeInsets.only(left: 38, right: 16, bottom: 4),
            child: ToolCallWidget(
              toolName: tc.name,
              arguments: tc.arguments,
              result: tc.result,
              isRunning: tc.result == null,
            ),
          ),
      ],
    );
  }
}

class _ThinkingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 12, height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 8),
        Text(
          'Reasoning...',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _StreamingContent extends StatelessWidget {
  final String content;
  final ThemeData theme;
  final ColorScheme cs;

  const _StreamingContent({required this.content, required this.theme, required this.cs});

  @override
  Widget build(BuildContext context) {
    // Bereits abgeschlossene Think-Blöcke parsen und aufklappbar zeigen
    final segments = _parseSegments(content);
    if (segments.isEmpty) {
      return Text('▌', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          if (segments[i].isThink)
            _ThinkBlock(content: segments[i].content)
          else
            Text(
              segments[i].content,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
            ),
        ],
      ],
    );
  }
}


/// Hilfsklasse für laufende Tool-Calls während des Streamings
class ActiveToolCall {
  final String name;
  final Map<String, dynamic>? arguments;
  String? result;

  ActiveToolCall({required this.name, this.arguments, this.result});
}
