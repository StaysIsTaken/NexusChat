/// MessageBubble – rendert eine einzelne Chat-Nachricht.
/// - Nutzer-Nachrichten: rechtsbündig, primäre Farbe
/// - Assistent-Nachrichten: linksbündig, Surface-Farbe mit Markdown
/// - <think>...</think> Blöcke: aufklappbarer Reasoning-Bereich
/// - Tool-Calls: aufklappbare Sub-Widgets

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/models.dart';
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

  const MessageBubble({super.key, required this.message});

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


// ── Bubble-Inhalt ──────────────────────────────────────────────────────────

class _BubbleContent extends StatelessWidget {
  final ChatMessage message;
  final bool isUser;

  const _BubbleContent({required this.message, required this.isUser});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bgColor = isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerHigh;
    final textColor = isUser
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    if (isUser) {
      return Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: SelectableText(
          message.content,
          style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
        ),
      );
    }

    // Assistent: Think-Blöcke parsen und aufklappbar rendern
    final segments = _parseSegments(message.content);

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(16),
        ),
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
      styleSheet: MarkdownStyleSheet(
        p: theme.textTheme.bodyMedium?.copyWith(color: textColor),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: colorScheme.surface.withOpacity(0.5),
          color: colorScheme.onSurface,
        ),
        codeblockDecoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
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


// ── Avatar ─────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final bool isUser;
  const _Avatar({required this.isUser});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 14,
      backgroundColor: isUser ? colorScheme.primaryContainer : colorScheme.secondaryContainer,
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy_outlined,
        size: 16,
        color: isUser ? colorScheme.onPrimaryContainer : colorScheme.onSecondaryContainer,
      ),
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
