import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:app/application_api.dart';
import 'package:app/main.dart';
import 'package:app/models/chat_message.dart';
import 'package:app/providers/theme_provider.dart';
import 'package:app/screens/chat_screen.dart';
import 'package:app/screens/initialization_screen.dart';
import 'package:app/screens/mesh_screen.dart';
import 'package:app/screens/nearby_screen.dart';
import 'package:app/screens/node_settings_screen.dart';
import 'package:app/screens/wifi_qr_screen.dart';
import 'package:app/services/api_service.dart';
import 'package:app/services/ble_service.dart';
import 'package:app/services/embedded_node_service.dart';
import 'package:app/services/local_store.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/widgets/time_format.dart';

/// WCAG contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Hosts [child] the way the app does, at a given size, text scale and theme.
/// With no [mode], it follows the saved theme choice like the real app.
Widget host(Widget child, {ThemeMode? mode, double textScale = 1}) => ProviderScope(
      child: Consumer(builder: (context, ref, _) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode ?? ref.watch(themeProvider),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: child,
      )),
    );

Future<void> setScreen(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

ChatMessage incoming(String from, String id, String content, DateTime at, {String? handle}) =>
    ChatMessage(id: 0, from: from, content: content, timestamp: at, msgId: id, handle: handle);

void main() {
  LocalStore.isTestMode = true;
  EmbeddedNodeService.isTestMode = true;

  group('Theme', () {
    for (final (name, theme) in [('light', AppTheme.light()), ('dark', AppTheme.dark())]) {
      test('$name text meets WCAG AA contrast', () {
        final cs = theme.colorScheme;
        final chatter = theme.extension<ChatterColors>()!;
        final pairs = {
          'body on background': (cs.onSurface, cs.surface),
          'secondary text on background': (cs.onSurfaceVariant, cs.surface),
          'secondary text on cards': (cs.onSurfaceVariant, cs.surfaceContainer),
          'primary text on background': (cs.primary, cs.surface),
          'button label': (cs.onPrimary, cs.primary),
          'outgoing bubble': (chatter.onBubbleOut, chatter.bubbleOut),
          'incoming bubble': (chatter.onBubbleIn, chatter.bubbleIn),
          'failed bubble': (cs.onErrorContainer, cs.errorContainer),
          'snackbar': (cs.onInverseSurface, cs.inverseSurface),
          'error text': (cs.error, cs.surface),
          'online status text': (chatter.reach, cs.surface),
          'nav selected icon': (cs.onPrimaryContainer, cs.primaryContainer),
          'verified badge': (chatter.verified, cs.surface),
          'impersonation warning text': (chatter.warning, cs.surface),
          'impersonation banner': (chatter.onWarningContainer, chatter.warningContainer),
        };
        pairs.forEach((what, pair) {
          expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5), reason: '$name: $what');
        });
        // Timestamps inside bubbles are drawn at 78% opacity
        final meta = Color.alphaBlend(chatter.onBubbleOut.withValues(alpha: 0.78), chatter.bubbleOut);
        expect(contrast(meta, chatter.bubbleOut), greaterThanOrEqualTo(4.5), reason: '$name: bubble time');
        // Field and control outlines need 3:1 against what's around them
        expect(contrast(cs.outline, cs.surface), greaterThanOrEqualTo(3), reason: '$name: outline');
      });
    }

    test('every theme uses the bundled typefaces', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(theme.textTheme.bodyLarge!.fontFamily, AppTheme.textFont);
        expect(theme.textTheme.headlineMedium!.fontFamily, AppTheme.displayFont);
        expect(theme.textTheme.labelLarge!.fontFamily, AppTheme.displayFont);
        expect(theme.textTheme.bodyLarge!.fontSize, greaterThanOrEqualTo(16));
        expect(theme.textTheme.bodySmall!.fontSize, greaterThanOrEqualTo(12));
      }
    });
  });

  group('Time labels', () {
    final now = DateTime(2026, 10, 25, 15);
    test('day headings read naturally', () {
      expect(formatDayHeading(DateTime(2026, 10, 25, 9), now: now), 'Today');
      expect(formatDayHeading(DateTime(2026, 10, 24, 23), now: now), 'Yesterday');
      expect(formatDayHeading(DateTime(2026, 10, 21), now: now), 'Wednesday');
      expect(formatDayHeading(DateTime(2026, 3, 2), now: now), 'Monday 2 March');
      expect(formatDayHeading(DateTime(2025, 3, 2), now: now), '2 March 2025');
    });
  });

  group('Chat screen', () {
    setUp(() => ApplicationAPI().stopPolling());

    testWidgets('shows the thread newest-last with day headings and delivery words', (tester) async {
      await setScreen(tester, const Size(390, 800));
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiThreadPeer';
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      api.receiveFromNode(incoming(peer, 'ui-1', 'older message', yesterday, handle: 'maya'));
      api.receiveFromNode(incoming(peer, 'ui-2', 'hello there', DateTime.now(), handle: 'maya'));
      // No node in tests, so this send fails and must be marked as such
      await expectLater(api.sendMessage('are you nearby?', peer), throwsA(isA<ApiException>()));

      await tester.pumpWidget(host(const ChatScreen(peerName: 'maya', peerId: peer)));
      await tester.pump();

      expect(find.text('older message'), findsOneWidget);
      expect(find.text('hello there'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Not delivered'), findsOneWidget);
      // Newest message sits lowest on screen
      expect(tester.getTopLeft(find.text('are you nearby?')).dy,
          greaterThan(tester.getTopLeft(find.text('hello there')).dy));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1)); // contact save timer
    });

    testWidgets('Enter starts a new line, only the Send button sends, and the keyboard stays up', (tester) async {
      await setScreen(tester, const Size(390, 800));
      await tester.pumpWidget(host(const ChatScreen(peerName: 'nobody', peerId: '12D3KooWUiEmptyPeer')));
      await tester.pump();

      // An unknown peer goes by its ID, not the name we were handed
      expect(find.textContaining('Start your conversation with'), findsOneWidget);
      final sendButton = find.widgetWithIcon(IconButton, Icons.arrow_upward);
      IconButton send() => tester.widget<IconButton>(sendButton);
      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(send().onPressed, isNull);
      expect(field().textInputAction, TextInputAction.newline);

      await tester.enterText(find.byType(TextField), '\nShelter B\n  - water\n  - blankets  \n\n');
      await tester.pump();
      expect(send().onPressed, isNotNull);

      // The keyboard's Enter key doesn't send
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();
      expect(find.textContaining('Start your conversation with'), findsOneWidget);
      expect(field().controller!.text, isNotEmpty);

      await tester.tap(sendButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Sent with its line breaks and indents, minus the blank edges
      expect(find.text('Shelter B\n  - water\n  - blankets'), findsOneWidget);
      expect(field().controller!.text, isEmpty);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pump(const Duration(seconds: 5)); // let the failure notice time out
    });

    testWidgets('an impostor is flagged, and the identity sheet copies the ID, verifies and renames', (tester) async {
      await setScreen(tester, const Size(390, 800));
      final api = ApplicationAPI()..stopPolling();
      const real = '12D3KooWUiRealCoordinator';
      const fake = '12D3KooWUiFakeCoordinatorK7pQ';
      api.receiveFromNode(incoming(real, 'id-1', 'water at the gym', DateTime.now(), handle: 'coordinator'));
      api.receiveFromNode(incoming(fake, 'id-2', 'everyone to the bridge', DateTime.now(), handle: 'Coordinator'));

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(host(const ChatScreen(peerName: 'Coordinator', peerId: fake)));
      await tester.pump();
      expect(find.text('Coordinator (#K7pQ)'), findsOneWidget);
      expect(find.textContaining('Impersonation warning'), findsOneWidget);

      await tester.tap(find.byTooltip('Peer identity'));
      await tester.pumpAndSettle();
      expect(find.text(fake), findsOneWidget); // the full ID, in the sheet
      expect(find.text('Advertised handle: @Coordinator'), findsOneWidget);

      await tester.tap(find.text('Copy peer ID'));
      await tester.pump();
      expect(copied, fake);
      expect(find.text('Copied'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Your name for them'), 'Stranger at the gym');
      await tester.pump();
      await tester.ensureVisible(find.text('Verified contact'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verified contact'));
      await tester.pump();
      expect(api.isVerified(fake), isTrue);

      // Back in the chat: the private name, a verified badge and no warning
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Stranger at the gym'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(find.textContaining('Impersonation warning'), findsNothing);
      expect(tester.takeException(), isNull);

      api.setVerified(fake, false);
      api.setAlias(fake, null);
      await tester.pump(const Duration(seconds: 3)); // save timer, copied label
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('identity sheet lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        final api = ApplicationAPI()..stopPolling();
        const peer = '12D3KooWUiSheetPeerWithAVeryLongIdentifier';
        api.receiveFromNode(incoming('12D3KooWUiSheetFirst', 'sh-0-${mode.name}', 'hi', DateTime.now(), handle: 'shelter_lead'));
        api.receiveFromNode(incoming(peer, 'sh-${mode.name}', 'hi', DateTime.now(), handle: 'Shelter.Lead'));
        await tester.pumpWidget(host(const ChatScreen(peerName: 'x', peerId: peer), mode: mode, textScale: 2));
        await tester.pump();
        expect(find.textContaining('Impersonation warning'), findsOneWidget);
        await tester.tap(find.textContaining('Impersonation warning'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Your name for them'), 200,
            scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 1));
      });
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        final api = ApplicationAPI()..stopPolling();
        const peer = '12D3KooWUiLongNamePeer';
        api.receiveFromNode(incoming(peer, 'big-${mode.name}', 'A long message ' * 20, DateTime.now(),
            handle: 'someone_with_a_long'));
        await tester.pumpWidget(host(const ChatScreen(peerName: 'x', peerId: peer), mode: mode, textScale: 2));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });

  group('Chats list', () {
    setUp(() => ApplicationAPI().stopPolling());

    testWidgets('lists conversations with a preview and filters by search', (tester) async {
      await setScreen(tester, const Size(390, 800));
      final api = ApplicationAPI()..stopPolling();
      api.receiveFromNode(incoming('12D3KooWUiListAlpha', 'l-1', 'see you at the gate', DateTime.now(), handle: 'alpha'));
      api.receiveFromNode(incoming('12D3KooWUiListBravo', 'l-2', 'battery low', DateTime.now(), handle: 'bravo'));

      await tester.pumpWidget(host(const MeshScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('see you at the gate'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzz-nobody');
      await tester.pump();
      expect(find.text('No one matches "zzz-nobody"'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.text('bravo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        await tester.pumpWidget(host(const MeshScreen(), mode: mode, textScale: 2));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Startup', () {
    setUp(() => ApplicationAPI().stopPolling());

    for (final (label, size, scale) in [('a 320px phone with 2x text', const Size(320, 640), 2.0), ('a desktop window', const Size(1280, 800), 1.0)]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('lays out on $label in ${mode.name} mode', (tester) async {
          await setScreen(tester, size);
          await tester.pumpWidget(host(const InitializationScreen(), mode: mode, textScale: scale));
          await tester.pump(const Duration(seconds: 3)); // boot steps finish
          await tester.pumpAndSettle();
          expect(find.text('Your handle'), findsOneWidget);
          expect(find.text('Join the mesh'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Wi-Fi QR', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
    const camera = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
    const cameraEvents = EventChannel('dev.steenbakker.mobile_scanner/scanner/event');

    // Camera permission: 1 = granted, 0 = denied
    void answerCameraPermission(int status) => messenger.setMockMethodCallHandler(
          permissions,
          (call) async => call.method == 'requestPermissions' ? {1: status} : status,
        );

    setUp(() {
      ApplicationAPI().stopPolling();
      answerCameraPermission(0);
    });
    tearDown(() {
      messenger.setMockMethodCallHandler(permissions, null);
      messenger.setMockMethodCallHandler(camera, null);
      messenger.setMockStreamHandler(cameraEvents, null);
    });

    testWidgets('explains a missing code and missing camera access instead of failing silently', (tester) async {
      await setScreen(tester, const Size(360, 720));
      await tester.pumpWidget(host(const WifiQrScreen(), textScale: 1.5));
      await tester.pump(const Duration(seconds: 1));

      // No node in tests, so there is no code to show
      expect(find.text('Your code isn\'t ready'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.ensureVisible(find.text('Scan a QR code'));
      await tester.tap(find.text('Scan a QR code'));
      await tester.pumpAndSettle();
      expect(find.text('Allow camera access to scan'), findsOneWidget);
      expect(find.byType(MobileScanner), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the camera runs only while the scanner is open, and a scanned code is used', (tester) async {
      await setScreen(tester, const Size(390, 800));
      answerCameraPermission(1);
      final cameraCalls = <String>[];
      messenger.setMockMethodCallHandler(camera, (call) async {
        cameraCalls.add(call.method);
        return switch (call.method) {
          'state' => 1, // authorised
          'start' => {'textureId': 7, 'numberOfCameras': 1, 'size': {'width': 640.0, 'height': 480.0}},
          _ => null,
        };
      });
      MockStreamHandlerEventSink? frames;
      messenger.setMockStreamHandler(
        cameraEvents,
        MockStreamHandler.inline(onListen: (_, sink) {
          frames = sink;
        }),
      );

      await tester.pumpWidget(host(const MainNavigationScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // From the Chats top bar: your code first, no camera yet
      await tester.tap(find.byTooltip('Wi-Fi QR connection'));
      await tester.pumpAndSettle();
      expect(find.text('My Wi-Fi code'), findsOneWidget);
      expect(cameraCalls, isEmpty);

      await tester.tap(find.text('Scan a QR code'));
      await tester.pumpAndSettle();
      expect(find.byType(MobileScanner), findsOneWidget);
      expect(cameraCalls, contains('start'));

      // Leaving the app turns the camera off; coming back turns it on again
      cameraCalls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(cameraCalls, ['stop']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(cameraCalls.last, 'start');

      // Backing out of the scanner releases the camera at once
      cameraCalls.clear();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(cameraCalls, contains('stop'));
      expect(find.byType(MobileScanner), findsNothing);

      // And back home, nothing starts it again
      cameraCalls.clear();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('My Wi-Fi code'), findsNothing);
      expect(find.byType(MobileScanner), findsNothing);
      expect(cameraCalls, isEmpty);

      // A code read by the scanner closes it (camera off) and is dialled
      await tester.tap(find.byTooltip('Wi-Fi QR connection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan a QR code'));
      await tester.pumpAndSettle();
      cameraCalls.clear();
      frames!.success({
        'name': 'barcode',
        'data': [
          {'rawValue': '{"id":"12D3KooWUiScannedPeer","name":"lena","addrs":["/ip4/192.168.43.9/tcp/4001"]}', 'format': 256},
        ],
      });
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(MobileScanner), findsNothing);
      expect(cameraCalls, contains('stop'));
      expect(find.text('My Wi-Fi code'), findsOneWidget);
      // No node in tests, so the dial fails, and says so
      expect(find.textContaining('Could not connect'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });

    for (final (size, scale) in [(const Size(390, 800), 1.0), (const Size(320, 640), 2.0)]) {
      testWidgets('the QR code says it needs Wi-Fi or a hotspot and points to Nearby (${scale}x text)',
          (tester) async {
        await setScreen(tester, size);
        // No node in tests: the code handed in stays on show
        await tester.pumpWidget(host(
          const WifiQrScreen(initialCode: '{"id":"12D3KooWUiQrPeer","addrs":[]}'),
          textScale: scale,
        ));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Wi-Fi QR'), findsOneWidget);
        expect(find.text('Wi-Fi / hotspot connection code'), findsOneWidget);
        expect(find.textContaining('use the Bluetooth \'Nearby\' tab'), findsOneWidget);

        // The full ID, for anyone verifying this phone, and a way to copy it
        expect(find.text('12D3KooWUiQrPeer'), findsOneWidget);
        await tester.ensureVisible(find.text('Copy my peer ID'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy my peer ID'));
        await tester.pump();
        expect(find.text('Peer ID copied to clipboard'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 3)); // let the notice time out
      });
    }
  });

  group('Nearby', () {
    setUp(() => ApplicationAPI().stopPolling());

    testWidgets('is a tab of its own, with the QR shortcut in its top bar', (tester) async {
      await setScreen(tester, const Size(390, 800));
      await tester.pumpWidget(host(const MainNavigationScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      // Its search spinner never settles, so pump fixed steps
      await tester.tap(find.text('Nearby'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Visible to nearby phones'), findsOneWidget);
      expect(find.text('Discover'), findsNothing);

      await tester.tap(find.byTooltip('Wi-Fi QR connection').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('My Wi-Fi code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        await tester.pumpWidget(host(const NearbyScreen(), mode: mode, textScale: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('search filters phones by name, advertised ID or full peer ID', (tester) async {
      await setScreen(tester, const Size(390, 800));
      final api = ApplicationAPI()..stopPolling();
      // Known from an earlier message, so its full ID is behind the advertised prefix
      api.receiveFromNode(incoming('12D3KooWUiNearbyKnownXyz', 'n-1', 'hi', DateTime.now(), handle: 'bob_k'));

      await tester.pumpWidget(host(const NearbyScreen()));
      await tester.pump(const Duration(seconds: 1));

      NearbyNode node(String name, String prefix) =>
          NearbyNode(id: prefix, name: name, rssi: -60, isChatterPeer: true, psm: 129, peerIdPrefix: prefix);
      BleService().emitNearbyForTest([
        node('Medic_Anna', '12D3KooWUiMedAnna'),
        node('ravi', '12D3KooWUiRavi0001'),
        node('bob_k', '12D3KooWUiNearbyKn'),
      ]);
      await tester.pump();
      expect(find.text('ravi'), findsOneWidget);

      Future<void> search(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump();
      }

      await search('medic');
      expect(find.text('Medic_Anna'), findsOneWidget);
      expect(find.text('ravi'), findsNothing);
      expect(find.text('1 of 3 phones nearby'), findsOneWidget);

      await search('Ravi0001'); // the advertised ID prefix
      expect(find.text('ravi'), findsOneWidget);
      expect(find.text('Medic_Anna'), findsNothing);

      await search('KnownXyz'); // only in the full peer ID
      expect(find.text('bob_k'), findsOneWidget);
      expect(find.text('ravi'), findsNothing);

      await search('nobody');
      expect(find.text('No nearby phones match \'nobody\''), findsOneWidget);
      await tester.tap(find.text('Clear search'));
      await tester.pump();
      expect(find.text('Medic_Anna'), findsOneWidget);
      expect(find.text('ravi'), findsOneWidget);
      expect(find.text('bob_k'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1)); // contact save timer
    });
  });

  group('Settings', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        await tester.pumpWidget(host(const NodeSettingsScreen(), mode: mode, textScale: 2));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.scrollUntilVisible(find.text('Not delivered'), 200);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('theme choice switches the whole app', (tester) async {
      await setScreen(tester, const Size(390, 800));
      await tester.pumpWidget(host(const NodeSettingsScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.text('Theme'))).brightness, Brightness.light);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.text('Theme'))).brightness, Brightness.dark);
    });
  });
}
