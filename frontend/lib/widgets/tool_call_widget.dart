/// Tool-Call-Widget – zeigt einen Tool-Aufruf aufklappbar an.
/// Erscheint in der Nachrichtenansicht wenn das Modell Tools verwendet.

import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/models.dart';

class ToolCallWidget extends StatefulWidget {
  final String toolName;
  final Map<String, dynamic>? arguments;
  final String? result;
  final bool isRunning; // Tool wird gerade ausgeführt

  const ToolCallWidget({
    super.key,
    required this.toolName,
    this.arguments,
    this.result,
    this.isRunning = false,
  });

  @override
  State<ToolCallWidget> createState() => _ToolCallWidgetState();
}

class _ToolCallWidgetState extends State<ToolCallWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header – immer sichtbar
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.build_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.toolName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.isRunning)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  else if (widget.result != null)
                    Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.green.shade600),

                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Aufgeklappter Bereich: Argumente + Ergebnis
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.arguments != null && widget.arguments!.isNotEmpty) ...[
                    _SectionLabel('Argumente'),
                    const SizedBox(height: 4),
                    _CodeBlock(
                      const JsonEncoder.withIndent('  ')
                          .convert(widget.arguments),
                    ),
                  ],
                  if (widget.result != null) ...[
                    const SizedBox(height: 8),
                    _SectionLabel('Ergebnis'),
                    const SizedBox(height: 4),
                    _CodeBlock(widget.result!),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
      );
}

class _CodeBlock extends StatelessWidget {
  final String code;
  const _CodeBlock(this.code);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: SelectableText(
        code,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}


/// Baut eine Liste von Tool-Call-Widgets aus den gespeicherten Tool-Daten.
List<Widget> buildToolCallWidgets(
  List<ToolCall> toolCalls,
  List<ToolResult> toolResults,
) {
  final resultMap = {for (final r in toolResults) r.name: r.result};

  return toolCalls
      .map(
        (tc) => ToolCallWidget(
          toolName: tc.name,
          arguments: tc.arguments,
          result: resultMap[tc.name],
        ),
      )
      .toList();
}
