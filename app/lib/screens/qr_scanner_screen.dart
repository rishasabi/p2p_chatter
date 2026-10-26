import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';

/// The camera viewfinder for someone's connection code. Pops with the first
/// code it reads (or nothing, if the user backs out).
///
/// The camera is owned by this route alone: started once permission is
/// granted, stopped whenever the app leaves the foreground, and released when
/// the route closes, so nothing keeps the sensor (or its privacy light) on
/// after the user leaves.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  /// Opens the scanner and returns the code it read, if any.
  static Future<String?> scan(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _hasPermission = false;
  bool _permanentlyDenied = false;
  bool _checkingPermission = true;
  bool _torchEnabled = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    // Once permanently denied, only the system settings can grant it; the
    // result is picked up when the user comes back (didChangeAppLifecycleState)
    if (_permanentlyDenied) {
      await openAppSettings();
      return;
    }
    setState(() => _checkingPermission = true);
    PermissionStatus status;
    try {
      status = await Permission.camera.request();
    } catch (e) {
      // No permission service (e.g. desktop): show the ask-again state, not an endless spinner
      debugPrint('Camera permission request failed: $e');
      status = PermissionStatus.denied;
    }
    if (!mounted) return;
    setState(() {
      _hasPermission = status.isGranted;
      _permanentlyDenied = status.isPermanentlyDenied;
      _checkingPermission = false;
    });
    _startCamera();
  }

  void _startCamera() {
    if (!mounted || !_hasPermission || _done) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    unawaited(_controller.start().catchError((Object e) => debugPrint('Camera start failed: $e')));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_permanentlyDenied) {
          Permission.camera.status.then((status) {
            if (mounted && status.isGranted) {
              setState(() {
                _hasPermission = true;
                _permanentlyDenied = false;
              });
              _startCamera();
            }
          });
        } else {
          _startCamera();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Not on screen: the camera goes off, it doesn't idle
        unawaited(_controller.stop());
    }
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes
        .map((b) => b.rawValue?.trim())
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    _done = true; // later frames of the same code are ignored
    unawaited(_controller.stop());
    Navigator.of(context).pop(code);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a code')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_checkingPermission) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasPermission) {
      return StateMessage(
        icon: Icons.no_photography_outlined,
        title: 'Allow camera access to scan',
        body: _permanentlyDenied
            ? 'Camera access is turned off for Chatter. Turn it on in system settings, then come back.'
            : 'Chatter only uses the camera to read other people\'s connection codes.',
        action: FilledButton(
          onPressed: _checkPermission,
          child: Text(_permanentlyDenied ? 'Open settings' : 'Allow camera'),
        ),
      );
    }

    final textTheme = Theme.of(context).textTheme;

    // The camera feed is always dark, so the overlay uses fixed light-on-dark
    // colours rather than the theme's
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = math.min(constraints.biggest.shortestSide * 0.68, 280.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _handleDetect),

            // Viewfinder
            IgnorePointer(
              child: Center(
                child: Container(
                  width: box,
                  height: box,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.ember, width: 3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),

            // Torch
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                tooltip: _torchEnabled ? 'Turn flashlight off' : 'Turn flashlight on',
                isSelected: _torchEnabled,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.square(48),
                ),
                icon: const Icon(Icons.flash_off),
                selectedIcon: const Icon(Icons.flash_on, color: AppTheme.ember),
                onPressed: () {
                  _controller.toggleTorch();
                  setState(() => _torchEnabled = !_torchEnabled);
                },
              ),
            ),

            // Hint
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Point camera at someone\'s Wi-Fi connection code',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium!.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
