import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/application_api.dart';
import 'package:app/models/chat_message.dart';
import 'package:app/providers/theme_provider.dart';
import 'package:app/screens/chat_screen.dart';
import 'package:app/screens/discover_screen.dart';
import 'package:app/screens/initialization_screen.dart';
import 'package:app/screens/mesh_screen.dart';
import 'package:app/screens/node_settings_screen.dart';
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

  group('Discover', () {
    setUp(() {
      ApplicationAPI().stopPolling();
      // The camera permission request is answered with "denied"
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async => call.method == 'requestPermissions' ? {1: 0} : 0,
      );
    });

    testWidgets('explains a missing code and missing camera access instead of failing silently', (tester) async {
      await setScreen(tester, const Size(360, 720));
      await tester.pumpWidget(host(const DiscoverScreen(myBootstrapData: ''), textScale: 1.5));
      await tester.pump(const Duration(seconds: 1));

      // No node in tests, so there is no code to show
      expect(find.text('Your code isn\'t ready'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // The Nearby tab's search spinner never settles, so pump fixed steps
      await tester.tap(find.text('Scan'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Allow camera access to scan'), findsOneWidget);

      await tester.tap(find.text('Nearby'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Visible to nearby phones'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (size, scale) in [(const Size(390, 800), 1.0), (const Size(320, 640), 2.0)]) {
      testWidgets('the QR code says it needs Wi-Fi or a hotspot and points to Nearby (${scale}x text)',
          (tester) async {
        await setScreen(tester, size);
        // No node in tests: the code handed in stays on show
        await tester.pumpWidget(host(
          const DiscoverScreen(myBootstrapData: '{"id":"12D3KooWUiQrPeer","addrs":[]}'),
          textScale: scale,
        ));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Wi-Fi QR'), findsOneWidget);
        expect(find.text('Wi-Fi / hotspot connection code'), findsOneWidget);
        expect(find.textContaining('use the Bluetooth \'Nearby\' tab'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Nearby search filters phones by name, advertised ID or full peer ID', (tester) async {
      await setScreen(tester, const Size(390, 800));
      final api = ApplicationAPI()..stopPolling();
      // Known from an earlier message, so its full ID is behind the advertised prefix
      api.receiveFromNode(incoming('12D3KooWUiNearbyKnownXyz', 'n-1', 'hi', DateTime.now(), handle: 'bob_k'));

      await tester.pumpWidget(host(const DiscoverScreen(myBootstrapData: '')));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Nearby'));
      await tester.pump();
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
