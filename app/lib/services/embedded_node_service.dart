import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

typedef _StartNodeC = ffi.Int32 Function(
  ffi.Pointer<Utf8> dataDir,
  ffi.Int32 httpPort,
  ffi.Int32 p2pPort,
);
typedef _StartNodeDart = int Function(
  ffi.Pointer<Utf8> dataDir,
  int httpPort,
  int p2pPort,
);

typedef _StopNodeC = ffi.Int32 Function();
typedef _StopNodeDart = int Function();

/// EmbeddedNodeService boots and manages the Go libp2p background node
/// directly inside the mobile app process as a unified service.
class EmbeddedNodeService {
  static final EmbeddedNodeService _instance = EmbeddedNodeService._internal();
  factory EmbeddedNodeService() => _instance;
  EmbeddedNodeService._internal();

  static bool isTestMode = false;

  bool _isStarted = false;
  ffi.DynamicLibrary? _dylib;
  _StartNodeDart? _startNodeFunc;
  _StopNodeDart? _stopNodeFunc;

  /// Ensures the Go background service is up and serving HTTP requests.
  /// Resolves when the node is verified healthy on [httpPort].
  Future<bool> ensureStarted({
    int httpPort = 8080,
    int p2pPort = 4001,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (isTestMode || Platform.environment.containsKey('FLUTTER_TEST')) {
      _isStarted = true;
      return true;
    }

    // 1. Fast check if service is already responding
    if (await isHealthy(httpPort: httpPort)) {
      _isStarted = true;
      return true;
    }

    // 2. Launch the native embedded service on Android
    if (Platform.isAndroid) {
      _startAndroidNative(httpPort: httpPort, p2pPort: p2pPort);
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await _startDesktopFallback(httpPort: httpPort, p2pPort: p2pPort);
    }

    // 3. Poll /health until the service confirms readiness
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await isHealthy(httpPort: httpPort)) {
        _isStarted = true;
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    debugPrint('EmbeddedNodeService: health check timed out on port $httpPort');
    return false;
  }

  Future<void> _startAndroidNative({
    required int httpPort,
    required int p2pPort,
  }) async {
    try {
      _dylib ??= ffi.DynamicLibrary.open('libchatter.so');
      _startNodeFunc ??= _dylib!.lookupFunction<_StartNodeC, _StartNodeDart>('StartNode');
      _stopNodeFunc ??= _dylib!.lookupFunction<_StopNodeC, _StopNodeDart>('StopNode');

      final docsDir = await getApplicationDocumentsDirectory();
      final dataDirPtr = docsDir.path.toNativeUtf8();

      final result = _startNodeFunc!(dataDirPtr, httpPort, p2pPort);
      calloc.free(dataDirPtr);

      if (result != 0) {
        debugPrint('EmbeddedNodeService: native StartNode returned code $result');
      } else {
        debugPrint('EmbeddedNodeService: native StartNode called successfully');
      }
    } catch (e) {
      debugPrint('EmbeddedNodeService: error loading libchatter.so: $e');
    }
  }

  Future<void> _startDesktopFallback({
    required int httpPort,
    required int p2pPort,
  }) async {
    // For desktop environments, attempt to find or spawn the service binary if present
    try {
      final docsDir = await getApplicationSupportDirectory();
      final binaryCandidates = [
        '../service/chatter.exe',
        '../../service/chatter.exe',
        'service/chatter.exe',
        'chatter.exe',
      ];
      for (final candidate in binaryCandidates) {
        final f = File(candidate);
        if (await f.exists()) {
          await Process.start(f.absolute.path, [
            '-port',
            httpPort.toString(),
            '-p2p-port',
            p2pPort.toString(),
            '-data-dir',
            docsDir.path,
          ], mode: ProcessStartMode.detached);
          break;
        }
      }
    } catch (_) {}
  }

  /// Pings the local HTTP /health endpoint to verify the service is running.
  Future<bool> isHealthy({int httpPort = 8080}) async {
    try {
      final client = http.Client();
      final uri = Uri.parse('http://127.0.0.1:$httpPort/health');
      final response = await client.get(uri).timeout(const Duration(milliseconds: 600));
      client.close();
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Stops the embedded node service.
  void stop() {
    if (_stopNodeFunc != null) {
      try {
        _stopNodeFunc!();
      } catch (_) {}
    }
    _isStarted = false;
  }

  bool get isStarted => _isStarted;
}
