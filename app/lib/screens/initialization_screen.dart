import 'package:flutter/material.dart';
import 'dart:async';
import '../application_api.dart';
import '../main.dart';
import '../models/node_info.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/feedback.dart';
import '../widgets/peer_display.dart';

import '../services/embedded_node_service.dart';

class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  int _currentBootStep = 0;
  bool _isBootComplete = false;
  bool _joining = false;
  final TextEditingController _handleController = TextEditingController();
  final ApplicationAPI api = ApplicationAPI();
  NodeInfo? _liveNodeInfo;

  final List<String> _bootSteps = [
    'Reading local vault',
    'Starting P2P transport',
    'Seeding DHT peer table',
    'Restoring message queue'
  ];

  @override
  void initState() {
    super.initState();
    _startBootSequence();
  }

  void _startBootSequence() async {
    // Ensure embedded Go service is running
    await EmbeddedNodeService().ensureStarted();

    // Load the saved handle and contacts, start Bluetooth discovery
    await api.initialize();

    // Fetch persistent node identity
    try {
      final info = await api.getNode();
      if (mounted) {
        setState(() {
          _liveNodeInfo = info;
          // Returning user: the handle saved for this peer ID
          if (_handleController.text.isEmpty) _handleController.text = api.myHandle ?? '';
        });
      }
    } catch (_) {}

    // Step through the boot sequence
    for (int i = 0; i <= _bootSteps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        setState(() {
          _currentBootStep = i;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isBootComplete = true;
      });
    }
  }

  String? get _handleError => ApplicationAPI.validateHandle(_handleController.text);

  bool get _canJoin => _isBootComplete && !_joining && _handleError == null;

  Future<void> _joinMesh() async {
    setState(() => _joining = true);
    try {
      // Binds the handle to this node's peer ID and shares it with peers
      await api.setMyHandle(_handleController.text);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      showNotice(context, 'Could not save your handle: $e', tone: NoticeTone.error);
    }
  }

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return AnnotatedRegion(
      value: AppTheme.overlayStyle(theme.brightness),
      child: Scaffold(
        body: SafeArea(
          // Scroll instead of overflowing when the keyboard shrinks the viewport
          // on smaller screens; IntrinsicHeight keeps the Spacers working otherwise
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  // Centred in a 480px column on wide screens. Done with padding
                  // because IntrinsicHeight measures at the full width, and a
                  // max-width box would make the text wrap more than measured
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      ((constraints.maxWidth - 480) / 2).clamp(0.0, double.infinity) + 28,
                      40,
                      ((constraints.maxWidth - 480) / 2).clamp(0.0, double.infinity) + 28,
                      28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const BrandMark(size: 56),
                        const SizedBox(height: 20),
                        Text('Chatter', style: theme.textTheme.displayLarge),
                        const SizedBox(height: 12),
                        Text(
                          'Messages that travel from phone to phone. No towers, no servers, no account.',
                          style: theme.textTheme.bodyLarge!.copyWith(color: cs.onSurfaceVariant),
                        ),

                        const SizedBox(height: 40),
                        const Spacer(),

                        AnimatedSwitcher(
                          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
                          child: _isBootComplete ? _buildProfileSetup() : _buildBootChecklist(),
                        ),

                        const SizedBox(height: 32),
                        const Spacer(flex: 2),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _canJoin ? _joinMesh : null,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                            child: Text(_joining ? 'Joining…' : 'Join the mesh'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBootChecklist() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = ChatterColors.of(context);

    // The boot steps as a path through the mesh: each node lights up ember
    // as its step finishes, and the link to the next one fills in
    return Column(
      key: const ValueKey('booting'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Starting your node', style: theme.textTheme.titleSmall),
        const SizedBox(height: 16),
        ...List.generate(_bootSteps.length, (index) {
          final isCompleted = _currentBootStep > index;
          final isActive = _currentBootStep == index;

          return Semantics(
            liveRegion: isActive,
            label: '${_bootSteps[index]}, ${isCompleted ? 'done' : isActive ? 'in progress' : 'waiting'}',
            excludeSemantics: true,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 22,
                    child: CustomPaint(
                      painter: _StepPainter(
                        done: isCompleted,
                        active: isActive,
                        last: index == _bootSteps.length - 1,
                        lit: AppTheme.ember,
                        faint: colors.faint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(
                        _bootSteps[index],
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: isActive || isCompleted ? cs.onSurface : cs.onSurfaceVariant,
                          fontWeight: isActive ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildProfileSetup() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final peerDisplay = _liveNodeInfo != null
        ? 'Your peer ID is ${compactPeerId(_liveNodeInfo!.id)}, created on this phone. Your handle is tied to it.'
        : 'Your peer ID is unavailable because the local node is not running.';

    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _handleController,
          style: theme.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w600),
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Your handle',
            hintText: 'river_k',
            prefixText: '@ ',
            prefixStyle: theme.textTheme.headlineSmall!.copyWith(color: cs.onSurfaceVariant),
            floatingLabelBehavior: FloatingLabelBehavior.always,
            helperText: 'How nearby people see you. 3–20 letters, numbers, dots, dashes or underscores.',
            helperMaxLines: 3,
            errorMaxLines: 3,
            // Only complain once the user has started typing
            errorText: _handleController.text.isEmpty ? null : _handleError,
          ),
          onChanged: (val) => setState(() {}),
          onSubmitted: (_) {
            if (_canJoin) _joinMesh();
          },
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.fingerprint, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                peerDisplay,
                style: theme.textTheme.bodySmall!.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One stop on the boot path: a node, and the link down to the next step.
class _StepPainter extends CustomPainter {
  final bool done;
  final bool active;
  final bool last;
  final Color lit;
  final Color faint;

  _StepPainter({required this.done, required this.active, required this.last, required this.lit, required this.faint});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 12);
    if (!last) {
      canvas.drawLine(
        center + const Offset(0, 9),
        Offset(center.dx, size.height),
        Paint()
          ..color = done ? lit : faint
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    if (done) {
      canvas.drawCircle(center, 8, Paint()..color = lit);
    } else if (active) {
      canvas.drawCircle(center, 10, Paint()..color = lit.withValues(alpha: 0.22));
      canvas.drawCircle(center, 7, Paint()
        ..color = lit
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
    } else {
      canvas.drawCircle(center, 7, Paint()
        ..color = faint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_StepPainter old) =>
      old.done != done || old.active != active || old.last != last || old.lit != lit || old.faint != faint;
}
