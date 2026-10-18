import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/providers.dart';
import '../services/api_service.dart';

/// Two-tab screen: show own QR code (from live backend data) and scan peers.
class QRConnectScreen extends ConsumerStatefulWidget {
  const QRConnectScreen({super.key});

  @override
  ConsumerState<QRConnectScreen> createState() => _QRConnectScreenState();
}

class _QRConnectScreenState extends ConsumerState<QRConnectScreen> {
  bool _scanHandled = false;

  Future<void> _handleScannedAddress(String address) async {
    if (_scanHandled) return;
    setState(() => _scanHandled = true);

    final api = ref.read(apiServiceProvider);
    try {
      await api.connectPeer(address);
      // Refresh peers list after connecting
      await ref.read(peersProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Connected to peer!\n${_truncate(address, 40)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${e.message}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      // Allow scanning again after 4 seconds
      Future.delayed(
        const Duration(seconds: 4),
        () => mounted ? setState(() => _scanHandled = false) : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add / Connect Peer'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.qr_code), text: 'My Code'),
              Tab(icon: Icon(Icons.camera_alt), text: 'Scan Peer'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _MyQRTab(),
            _ScanTab(
              onDetect: _handleScannedAddress,
              handled: _scanHandled,
            ),
          ],
        ),
      ),
    );
  }
}

// ── My QR Tab ─────────────────────────────────────────────────────────────────

class _MyQRTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeAsync = ref.watch(nodeInfoProvider);

    return nodeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Could not load node info',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              err.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => ref.refresh(nodeInfoProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (nodeInfo) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              QrImageView(
                data: nodeInfo.qrPayload,
                version: QrVersions.auto,
                size: 220.0,
              ),
              const SizedBox(height: 20),
              const Text(
                'Have your peer scan this code to connect',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: nodeInfo.qrPayload));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Address copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _truncate(nodeInfo.qrPayload, 50),
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap to copy',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Scan Tab ──────────────────────────────────────────────────────────────────

class _ScanTab extends StatelessWidget {
  final Future<void> Function(String address) onDetect;
  final bool handled;

  const _ScanTab({required this.onDetect, required this.handled});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          onDetect: handled
              ? (_) {}
              : (capture) {
                  for (final barcode in capture.barcodes) {
                    final raw = barcode.rawValue;
                    if (raw != null && raw.isNotEmpty) {
                      onDetect(raw);
                      break;
                    }
                  }
                },
        ),
        if (handled)
          Container(
            color: Colors.black45,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Connecting…',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        // Viewfinder overlay hint
        if (!handled)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Point camera at peer\'s QR code',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _truncate(String s, int max) =>
    s.length > max ? '${s.substring(0, max)}…' : s;
