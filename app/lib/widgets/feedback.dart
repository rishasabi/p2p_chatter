import 'package:flutter/material.dart';

enum NoticeTone { info, success, error }

/// Shows a short status message at the bottom of the screen, replacing any
/// that is still showing. The icon carries the tone, so it never depends on
/// colour alone.
void showNotice(
  BuildContext context,
  String message, {
  NoticeTone tone = NoticeTone.info,
  Duration duration = const Duration(seconds: 3),
}) {
  final cs = Theme.of(context).colorScheme;
  final isError = tone == NoticeTone.error;
  final fg = isError ? cs.onErrorContainer : cs.onInverseSurface;
  final icon = switch (tone) {
    NoticeTone.info => Icons.info_outline,
    NoticeTone.success => Icons.check_circle_outline,
    NoticeTone.error => Icons.error_outline,
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: duration,
      backgroundColor: isError ? cs.errorContainer : null,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: fg),
            ),
          ),
        ],
      ),
    ));
}

/// Centered icon, title, explanation and optional action for empty, loading
/// and error states. Scrolls rather than clipping at large text sizes.
class StateMessage extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String title;
  final String? body;
  final Widget? action;

  /// False to sit inline in a scroll view (e.g. under the mesh map) instead
  /// of filling and centring in the space it's given.
  final bool fill;

  const StateMessage({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.body,
    this.action,
    this.fill = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final content = _content(theme, cs);
    if (!fill) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), child: Center(child: content));
    }

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        // Lets a RefreshIndicator above work even when there's nothing to scroll
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity)),
          child: Center(child: content),
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, ColorScheme cs) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null)
              leading!
            else if (icon != null)
              Icon(icon, size: 40, color: cs.onSurfaceVariant),
            if (leading != null || icon != null) const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium!.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      );
}
