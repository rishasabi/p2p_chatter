import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:app/application_api.dart';
import 'package:app/main.dart';
import 'package:app/models/chat_message.dart';
import 'package:app/providers/theme_provider.dart';
import 'package:app/screens/chat_screen.dart';
import 'package:app/screens/help_screen.dart';
import 'package:app/screens/initialization_screen.dart';
import 'package:app/screens/mesh_screen.dart';
import 'package:app/screens/nearby_screen.dart';
import 'package:app/screens/node_settings_screen.dart';
import 'package:app/screens/theme_editor_screen.dart';
import 'package:app/screens/wifi_qr_screen.dart';
import 'package:app/services/api_service.dart';
import 'package:app/services/ble_service.dart';
import 'package:app/services/custom_theme_store.dart';
import 'package:app/services/draft_store.dart';
import 'package:app/services/embedded_node_service.dart';
import 'package:app/services/link_preview_service.dart';
import 'package:app/services/local_store.dart';
import 'package:app/services/settings_store.dart';
import 'package:app/theme/app_theme.dart';
import 'package:app/theme/custom_theme.dart';
import 'package:app/widgets/link_preview_card.dart';
import 'package:app/widgets/mesh_map.dart';
import 'package:app/widgets/message_text.dart';
import 'package:app/widgets/time_format.dart';

/// WCAG contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Hosts [child] the way the app does, at a given size, text scale and theme.
/// With no [mode], it follows the saved theme choice (custom palette
/// included) like the real app.
Widget host(Widget child, {ThemeMode? mode, double textScale = 1}) => ProviderScope(
      child: Consumer(builder: (context, ref, _) => MaterialApp(
        theme: (mode == null ? ref.watch(customThemeDataProvider) : null) ?? AppTheme.light(),
        darkTheme: (mode == null ? ref.watch(customThemeDataProvider) : null) ?? AppTheme.dark(),
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
  LinkPreviewService.isTestMode = true;

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

  group('Custom themes', () {
    // The example a team would pass around, exactly as written
    const tacticalJson = '''
{
  "name": "Tactical Red Night",
  "version": 1,
  "colors": {
    "primary": "#E11D48",
    "surface": "#0F172A",
    "cardBackground": "#1E293B",
    "appBar": "#090D16",
    "myBubble": "#BE123C",
    "myBubbleText": "#FFFFFF",
    "peerBubble": "#334155",
    "peerBubbleText": "#F8FAFC",
    "reachIndicator": "#22C55E",
    "accentEmber": "#F43F5E"
  }
}''';

    setUp(() => ApplicationAPI().stopPolling());
    // A test that applies a theme mustn't leave it on for the next one
    tearDown(() => CustomThemeStore().save((config: null, enabled: false)));

    // Scrolls [finder] to mid-screen, clear of the Apply bar at the bottom
    Future<void> centre(WidgetTester tester, Finder finder) async {
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
      await tester.pump();
    }

    test('a shared theme file reads back exactly, and survives a round trip', () {
      final config = CustomThemeConfig.decode(tacticalJson);
      expect(config, CustomThemeConfig.tacticalRedNight);
      expect(CustomThemeConfig.decode(config.encode()), config);
      expect(jsonDecode(config.encode())['colors']['appBar'], '#090D16');
    });

    test('broken or foreign theme files are refused with a reason', () {
      String reason(String text) {
        try {
          CustomThemeConfig.decode(text);
        } on FormatException catch (e) {
          return e.message;
        }
        fail('accepted $text');
      }

      expect(reason('not json'), contains('valid JSON'));
      expect(reason('[1, 2]'), contains('JSON object'));
      expect(reason('{"version": 2, "colors": {"primary": "#000000"}}'), contains('newer Chatter'));
      expect(reason('{"version": 1, "colors": {"primary": "red"}}'), contains('"primary"'));
      expect(reason('{"version": 1, "colors": {"sparkles": "#FFFFFF"}}'), contains('none of its colors'));
      // A partial theme takes the rest from the default
      final partial = CustomThemeConfig.decode('{"version": 1, "colors": {"myBubble": "#123456"}}');
      expect(partial[ThemeColorRole.myBubble], const Color(0xFF123456));
      expect(partial[ThemeColorRole.surface], CustomThemeConfig.lanternNight[ThemeColorRole.surface]);
      expect(partial.name, 'Custom theme');
    });

    test('a palette reaches every component, with readable text on its colours', () {
      for (final preset in CustomThemeConfig.presets) {
        final theme = AppTheme.custom(preset);
        final cs = theme.colorScheme;
        final chatter = theme.extension<ChatterColors>()!;
        expect(cs.surface, preset[ThemeColorRole.surface]);
        expect(cs.primary, preset[ThemeColorRole.primary]);
        expect(cs.surfaceContainerLow, preset[ThemeColorRole.cardBackground]);
        expect(theme.appBarTheme.backgroundColor, preset[ThemeColorRole.appBar]);
        expect(chatter.bubbleOut, preset[ThemeColorRole.myBubble]);
        expect(chatter.onBubbleOut, preset[ThemeColorRole.myBubbleText]);
        expect(chatter.bubbleIn, preset[ThemeColorRole.peerBubble]);
        expect(chatter.onBubbleIn, preset[ThemeColorRole.peerBubbleText]);
        expect(chatter.reach, preset[ThemeColorRole.reachIndicator]);
        expect(chatter.accent, preset[ThemeColorRole.accentEmber]);
        expect(theme.brightness, preset.isDark ? Brightness.dark : Brightness.light);
        // Colours the app works out for itself always read
        for (final (what, fg, bg) in [
          ('body text', cs.onSurface, cs.surface),
          ('button label', cs.onPrimary, cs.primary),
          ('top bar title', theme.appBarTheme.foregroundColor!, preset[ThemeColorRole.appBar]),
          ('accent icon', chatter.onAccent, chatter.accent),
        ]) {
          expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5), reason: '${preset.name}: $what');
        }
        // Bubble text, as picked, reads in every preset
        expect(preset.lowContrast().where((p) => p.what.contains('message text')), isEmpty, reason: preset.name);
      }
      // A clash is pointed out
      final unreadable = CustomThemeConfig.oledBlack.withColor(ThemeColorRole.myBubbleText, const Color(0xFFFFE066));
      expect(unreadable.lowContrast().single.what, 'Your message text');
    });

    testWidgets('colours are edited with a live preview, then applied to the whole app', (tester) async {
      await setScreen(tester, const Size(390, 900));
      await tester.pumpWidget(host(const NodeSettingsScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('Customize theme'), 200);
      await tester.tap(find.text('Customize theme'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemePreview), findsOneWidget);
      ChatterColors preview() => ChatterColors.of(tester.element(find.text('On my way, 10 min')));

      // Start from a preset, then change one colour by its hex value
      await centre(tester, find.text('OLED black'));
      await tester.tap(find.text('OLED black'));
      await tester.pump();
      await centre(tester, find.byType(ThemePreview));
      expect(preview().bubbleIn, CustomThemeConfig.oledBlack[ThemeColorRole.peerBubble]);
      await tester.scrollUntilVisible(find.text('Your messages'), 200, scrollable: find.byType(Scrollable).first);
      await centre(tester, find.text('Your messages'));
      await tester.tap(find.text('Your messages'));
      await tester.pumpAndSettle();
      final hex = find.widgetWithText(TextField, 'Hex colour');
      await tester.enterText(hex, 'nope');
      await tester.pump();
      expect(find.text('Use six hex digits, like #E11D48'), findsOneWidget);
      await tester.enterText(hex, '#2563EB');
      await tester.pump();
      await tester.tap(find.text('Use colour'));
      await tester.pumpAndSettle();
      expect(find.text('#2563EB'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000)); // back up to the preview
      await tester.pumpAndSettle();
      expect(preview().bubbleOut, const Color(0xFF2563EB));
      // Not applied yet: the app around the editor is unchanged
      expect(ChatterColors.of(tester.element(find.text('Customize theme'))).bubbleOut, isNot(const Color(0xFF2563EB)));

      await tester.tap(find.text('Apply theme'));
      await tester.pumpAndSettle();
      final app = ChatterColors.of(tester.element(find.text('Customize theme')));
      expect(app.bubbleOut, const Color(0xFF2563EB));
      expect(Theme.of(tester.element(find.text('Customize theme'))).colorScheme.surface, const Color(0xFF000000));
      expect(find.text('Applied'), findsOneWidget);

      // Back in Settings, it's named; picking Light goes back to the standard theme
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Using "OLED black"'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Light'), -200);
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.text('Theme'))).colorScheme.surface, AppTheme.light().colorScheme.surface);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4)); // the notice times out
    });

    testWidgets('leaving with unapplied colours asks first', (tester) async {
      await setScreen(tester, const Size(390, 900));
      await tester.pumpWidget(host(const NodeSettingsScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('Customize theme'), 200);
      await tester.tap(find.text('Customize theme'));
      await tester.pumpAndSettle();
      await centre(tester, find.text('Sunlight'));
      await tester.tap(find.text('Sunlight'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemePreview), findsNothing);
    });

    testWidgets('a pasted theme is checked, then applied at once; the current one copies as JSON', (tester) async {
      await setScreen(tester, const Size(390, 900));
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(host(const ThemeEditorScreen()));
      await tester.pump();

      await tester.tap(find.byTooltip('Import theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste theme JSON'));
      await tester.pumpAndSettle();
      final field = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(field, '{"version": 1, "colors": {"surface": "dark"}}');
      await tester.tap(find.text('Import and apply'));
      await tester.pump();
      expect(find.textContaining('"surface" should be a colour'), findsOneWidget);
      await tester.enterText(field, tacticalJson);
      await tester.tap(find.text('Import and apply'));
      await tester.pumpAndSettle();

      // On straight away, everywhere
      final theme = Theme.of(tester.element(find.text('Customize theme')));
      expect(theme.colorScheme.surface, const Color(0xFF0F172A));
      expect(theme.appBarTheme.backgroundColor, const Color(0xFF090D16));
      expect(find.text('"Tactical Red Night" is on'), findsOneWidget);
      // Its red primary is a little dim on navy, and the editor says so
      expect(find.textContaining('Buttons and links on the background is hard to read'), findsOneWidget);

      await tester.tap(find.byTooltip('Export theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy theme JSON'));
      await tester.pumpAndSettle();
      expect(CustomThemeConfig.decode(copied!), CustomThemeConfig.tacticalRedNight);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4)); // the notice times out
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the editor lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        await tester.pumpWidget(host(const ThemeEditorScreen(), mode: mode, textScale: 2));
        await tester.pump();
        await tester.scrollUntilVisible(find.text('Accent: you, Send, selection'), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Accent: you, Send, selection'));
        await tester.pumpAndSettle();
        expect(find.text('Use colour'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
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
      expect(ApplicationAPI().historyFor('12D3KooWUiEmptyPeer').last['content'], 'Shelter B\n  - water\n  - blankets');
      expect(find.textContaining('blankets', findRichText: true), findsOneWidget); // now in the thread
      expect(field().controller!.text, isEmpty);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pump(const Duration(seconds: 5)); // let the failure notice time out
    });

    const triage = '# Triage update\n'
        '**Warning:** road to the *north gate* is ~~open~~ closed\n\n'
        '1. Saline\n2. Blankets\n\n'
        '- [x] water\n- [ ] torches\n\n'
        '> Bring ID if you have it\n\n'
        'Meet at `51.5072,-0.1276`\n\n'
        '```\nGRID 4Q FJ 12345 67890 and a long line that would not fit in a bubble without wrapping\n```\n\n'
        '| Item | Qty |\n|---|---|\n| Saline | 2 |\n\n'
        '![map](https://example.org/map.png) and [the form](https://example.org/form)';

    for (final (size, scale) in [(const Size(390, 800), 1.0), (const Size(320, 640), 2.0)]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('Markdown messages lay out in both bubbles (${scale}x text, ${mode.name})', (tester) async {
          await setScreen(tester, size);
          final api = ApplicationAPI()..stopPolling();
          final peer = '12D3KooWUiMarkdown${mode.name}${scale.toInt()}';
          api.receiveFromNode(incoming(peer, 'md-$peer', triage, DateTime.now(), handle: 'medic'));
          // Ours too: ember bubble (failed in tests, which has its own colours)
          await expectLater(api.sendMessage(triage, peer), throwsA(isA<ApiException>()));
          await tester.pumpWidget(host(ChatScreen(peerName: 'medic', peerId: peer), mode: mode, textScale: scale));
          await tester.pump();
          expect(find.byType(MarkdownBody), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }

    testWidgets('Markdown is formatted, images aren\'t fetched, and links ask first', (tester) async {
      await setScreen(tester, const Size(390, 2000));
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiMarkdownLinks';
      api.receiveFromNode(incoming(peer, 'mdl-1', triage, DateTime.now(), handle: 'medic'));
      api.receiveFromNode(incoming(peer, 'mdl-2', 'plain words, nothing to format', DateTime.now(), handle: 'medic'));
      await tester.pumpWidget(host(const ChatScreen(peerName: 'medic', peerId: peer)));
      await tester.pump();

      // Plain messages skip the Markdown renderer
      expect(find.text('plain words, nothing to format'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget);
      // Formatted, without the punctuation that asked for it
      expect(find.textContaining('**', findRichText: true), findsNothing);
      expect(find.textContaining('Triage update', findRichText: true), findsOneWidget);
      expect(find.text('[image: map]'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.textContaining('the form', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Open link?'), findsOneWidget);
      expect(find.text('https://example.org/form'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Open link?'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    test('previews drop Markdown punctuation', () {
      expect(markdownToPlain('**Warning:** road *closed*\n- bring `ID`'), 'Warning: road closed bring ID');
      expect(markdownToPlain('> see [the form](https://x.org)'), 'see the form');
      expect(markdownToPlain('# Status\n- [x] water'), 'Status water');
      expect(markdownToPlain('ask medic_triage'), 'ask medic_triage');
    });

    testWidgets('an unsent draft survives leaving the chat, shows in the list, and goes once sent', (tester) async {
      await setScreen(tester, const Size(390, 800));
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiDraftPeer';
      api.receiveFromNode(incoming(peer, 'dr-1', 'how many boxes?', DateTime.now(), handle: 'station4'));

      await tester.pumpWidget(host(const ChatScreen(peerName: 'station4', peerId: peer)));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Need 2 boxes of saline\nat Station 4');
      await tester.pump();

      // Away to the Chats list: the draft is shown there, ahead of the last message
      await tester.pumpWidget(host(const MeshScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'station4'); // other tests' chats are listed too
      await tester.pump();
      expect(find.textContaining('Draft: Need 2 boxes of saline at Station 4'), findsOneWidget);
      expect(find.text('how many boxes?'), findsNothing);

      // Back in the chat, exactly as typed
      await tester.pumpWidget(host(const ChatScreen(peerName: 'station4', peerId: peer)));
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Need 2 boxes of saline\nat Station 4');

      await tester.tap(find.widgetWithIcon(IconButton, Icons.arrow_upward));
      await tester.pump();
      expect(DraftStore().hasDraft(peer), isFalse);

      await tester.pumpWidget(host(const MeshScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Draft:'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5)); // failure notice, save timers
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

  group('Link previews', () {
    setUp(() => ApplicationAPI().stopPolling());
    tearDown(() {
      LinkPreviewService.debugClient = null;
      LinkPreviewService.debugLookup = null;
    });

    // Every name resolves to a public address unless [dns] says otherwise
    void fakeInternet(Future<http.Response> Function(http.Request request) handler,
        {Map<String, String> dns = const {}, List<Uri>? requested}) {
      LinkPreviewService.debugClient = MockClient((request) {
        requested?.add(request.url);
        return handler(request);
      });
      LinkPreviewService.debugLookup = (host) async => [InternetAddress(dns[host] ?? '93.184.216.34')];
    }

    const page = '''<html><head>
      <title>Ignored when OpenGraph has one</title>
      <meta property="og:title" content="Shelters &amp; water points">
      <meta property="og:site_name" content="Relief Map">
      <meta name="description" content="Fallback description">
      <meta property="og:description" content='Open now: school gym, &quot;Hall B&quot;, the library.'>
      <meta property="og:image" content="/img/map.png">
      </head><body>...</body></html>''';

    test('the first web link is found, in Markdown or written out, without trailing punctuation', () {
      expect(firstWebLink('Shelter map: https://relief.example/map?zone=4.')!.url.toString(),
          'https://relief.example/map?zone=4');
      expect(firstWebLink('see www.redcross.org, now')!.url.toString(), 'https://www.redcross.org');
      final md = firstWebLink('read [the guide](https://civil.example/guide) and https://second.example')!;
      expect(md.url.host, 'civil.example');
      expect(md.text, 'the guide');
      expect(firstWebLink('(https://en.wikipedia.org/wiki/Mesh_(network))')!.url.path, '/wiki/Mesh_(network)');
      expect(firstWebLink('ftp://files.example/x or mailto:a@b.example'), isNull);
      expect(firstWebLink('no links here'), isNull);
    });

    test('links whose words name another site, or that use look-alike characters, are caught', () {
      expect(firstWebLink('[redcross.org](https://evil.example/donate)')!.claimedHost, 'redcross.org');
      expect(firstWebLink('[https://redcross.org/x](https://redcross.org.evil.example)')!.claimedHost, 'redcross.org');
      expect(firstWebLink('[redcross.org](https://www.redcross.org/donate)')!.claimedHost, isNull);
      expect(firstWebLink('[the form](https://evil.example)')!.claimedHost, isNull);
      expect(isUnusualHost('xn--pple-43d.com'), isTrue);
      expect(isUnusualHost(Uri.parse('https://аpple.com').host), isTrue); // a Cyrillic a
      expect(isUnusualHost('apple.com'), isFalse);
    });

    test('only public internet addresses are fetched from', () {
      for (final local in [
        '127.0.0.1', '10.1.2.3', '172.20.0.1', '192.168.43.1', '100.64.0.1', '169.254.1.1', '0.0.0.0', //
        '::1', 'fd00::1', 'fe80::1', '::ffff:192.168.0.1',
      ]) {
        expect(isPublicAddress(InternetAddress(local)), isFalse, reason: local);
      }
      for (final public in ['93.184.216.34', '1.1.1.1', '2606:4700:4700::1111']) {
        expect(isPublicAddress(InternetAddress(public)), isTrue, reason: public);
      }
    });

    test('OpenGraph tags are read, with entities decoded and the image made absolute', () {
      final preview = parseLinkPreview(page, Uri.parse('https://relief.example/map'));
      expect(preview.title, 'Shelters & water points');
      expect(preview.description, 'Open now: school gym, "Hall B", the library.');
      expect(preview.siteName, 'Relief Map');
      expect(preview.image.toString(), 'https://relief.example/img/map.png');

      // No OpenGraph: the title, the meta description and the page icon
      final plain = parseLinkPreview(
        '<title> Civil  defence\n guide </title><meta name="description" content="Steps to take">'
        '<link rel="icon" href="favicon.png">',
        Uri.parse('https://civil.example/guide/'),
      );
      expect(plain.title, 'Civil defence guide');
      expect(plain.description, 'Steps to take');
      expect(plain.image.toString(), 'https://civil.example/guide/favicon.png');
    });

    test('a preview is fetched once, then served from the cache', () async {
      final requested = <Uri>[];
      fakeInternet((r) async => http.Response(page, 200, headers: {'content-type': 'text/html; charset=utf-8'}),
          requested: requested);
      final url = Uri.parse('https://relief.example/cache-test');
      expect((await LinkPreviewService().preview(url)).title, 'Shelters & water points');
      expect((await LinkPreviewService().preview(url)).title, 'Shelters & water points');
      expect(requested, [url]);
    });

    test('redirects are followed hop by hop and a change of site is reported', () async {
      fakeInternet((r) async => r.url.host == 'short.example'
          ? http.Response('', 302, headers: {'location': 'https://landing.example/page'})
          : http.Response(page, 200, headers: {'content-type': 'text/html'}));
      final preview = await LinkPreviewService().preview(Uri.parse('https://short.example/abc'));
      expect(preview.redirectHost, 'landing.example');
    });

    test('nothing on this phone or its network is ever requested, even through a redirect', () async {
      final requested = <Uri>[];
      fakeInternet(
        (r) async => r.url.host == 'hop.example'
            ? http.Response('', 302, headers: {'location': 'http://router.example/admin'})
            : http.Response(page, 200, headers: {'content-type': 'text/html'}),
        dns: {'router.example': '192.168.1.1'},
        requested: requested,
      );
      for (final url in [
        'http://127.0.0.1:8080/messages', // this phone's own node
        'http://localhost/',
        'https://printer.local/',
        'https://relief.example:8443/',
        'https://hop.example/go',
      ]) {
        await expectLater(LinkPreviewService().preview(Uri.parse(url)), throwsA(LinkPreviewFailure.none), reason: url);
      }
      expect(requested.map((u) => u.host), ['hop.example']);
    });

    testWidgets('a link in a chat gets a card naming its site, filled in once fetched, that asks before opening',
        (tester) async {
      await setScreen(tester, const Size(390, 900));
      const pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      fakeInternet((r) async => r.url.path.endsWith('.png')
          ? http.Response.bytes(base64Decode(pixel), 200, headers: {'content-type': 'image/png'})
          : http.Response(page, 200, headers: {'content-type': 'text/html'}));
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiLinkPreview';
      api.receiveFromNode(
          incoming(peer, 'lp-1', 'Water points: https://relief.example/chat-card', DateTime.now(), handle: 'medic'));
      await tester.pumpWidget(host(const ChatScreen(peerName: 'medic', peerId: peer)));
      await tester.pump();

      // The site shows at once, before anything is fetched
      final card = find.byType(LinkPreviewCard);
      expect(find.descendant(of: card, matching: find.text('relief.example')), findsOneWidget);
      // The mock's response body arrives on the real event loop, page then picture
      for (var i = 0; i < 2; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(find.text('Shelters & water points'), findsOneWidget);
      expect(find.text('Open now: school gym, "Hall B", the library.'), findsOneWidget);
      expect(find.descendant(of: card, matching: find.byType(Image)), findsOneWidget);

      await tester.tap(find.text('Shelters & water points'));
      await tester.pumpAndSettle();
      expect(find.text('Open link?'), findsOneWidget);
      expect(find.text('Goes to'), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('relief.example')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('offline, the card says so after the 5-second limit and still names the site', (tester) async {
      await setScreen(tester, const Size(390, 900));
      fakeInternet((r) => Completer<http.Response>().future); // a connection that never answers
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiLinkOffline';
      api.receiveFromNode(
          incoming(peer, 'lo-1', 'Guide: https://civil.example/guide/evacuation', DateTime.now(), handle: 'medic'));
      await tester.pumpWidget(host(const ChatScreen(peerName: 'medic', peerId: peer)));
      await tester.pump();
      expect(find.text('Loading preview…'), findsOneWidget);
      expect(find.text('civil.example'), findsOneWidget);

      await tester.pump(LinkPreviewService.timeout + const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('Offline preview unavailable'), findsOneWidget);
      expect(find.text('/guide/evacuation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a link whose words name another site is flagged on the card and in the dialog', (tester) async {
      await setScreen(tester, const Size(390, 900));
      // With previews off, nothing is fetched at all
      SettingsStore().set(SettingsStore.linkPreviews, false);
      addTearDown(() => SettingsStore().set(SettingsStore.linkPreviews, true));
      final requested = <Uri>[];
      fakeInternet((r) async => http.Response(page, 200, headers: {'content-type': 'text/html'}), requested: requested);
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiLinkPhish';
      api.receiveFromNode(incoming(peer, 'ph-1', 'Donate here: [redcross.org](https://evil.example/pay)', DateTime.now()));
      await tester.pumpWidget(host(const ChatScreen(peerName: 'stranger', peerId: peer)));
      await tester.pumpAndSettle();

      expect(find.text('Web link'), findsOneWidget);
      expect(find.text('The link says redcross.org but goes to evil.example'), findsOneWidget);
      expect(requested, isEmpty);

      await tester.tap(find.descendant(of: find.byType(LinkPreviewCard), matching: find.text('evil.example')));
      await tester.pumpAndSettle();
      expect(find.text('Open link?'), findsOneWidget);
      expect(find.text('The link says redcross.org, but it goes to evil.example.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('cards lay out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        final api = ApplicationAPI()..stopPolling();
        final peer = '12D3KooWUiLinkLayout${mode.name}';
        api.receiveFromNode(incoming(peer, 'll-${mode.name}',
            'https://a-rather-long-subdomain.relief-coordination.example/shelters/north?zone=4', DateTime.now()));
        await tester.pumpWidget(host(ChatScreen(peerName: 'medic', peerId: peer), mode: mode, textScale: 2));
        await tester.pump();
        expect(find.byType(LinkPreviewCard), findsOneWidget);
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

  group('Channels', () {
    setUp(() => ApplicationAPI().stopPolling());

    ChatMessage post(String from, String id, String content, String handle, {String room = 'general'}) =>
        ChatMessage(id: 0, from: from, content: content, timestamp: DateTime.now(), msgId: id, handle: handle, room: room);

    testWidgets('the Chats list has a Channels view, and a channel shows who wrote each post', (tester) async {
      await setScreen(tester, const Size(390, 900));
      final api = ApplicationAPI()..stopPolling();
      const medic = '12D3KooWUiChanMedicA1';
      const fake = '12D3KooWUiChanFakeZ9x8Q7';
      api.receiveFromNode(post(medic, 'cp-1', 'Triage moved to **tent 4**', 'chan_medic'));
      api.receiveFromNode(post(fake, 'cp-2', 'Everyone to the bridge', 'Chan_Medic'));

      await tester.pumpWidget(host(const MeshScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('Channels'));
      await tester.pump();
      expect(find.text('#general'), findsOneWidget);
      expect(find.textContaining('Everyone to the bridge'), findsOneWidget);

      await tester.tap(find.text('#general'));
      await tester.pumpAndSettle();
      expect(find.text('Open: every phone in range can read it'), findsOneWidget);
      // Two devices go by lookalike handles: both get the end of their peer
      // ID and a warning, the later one as a possible impersonator
      final realName = '@chan_medic (#${medic.substring(medic.length - 4)})';
      expect(find.text(realName), findsOneWidget);
      expect(find.text('@Chan_Medic (#${fake.substring(fake.length - 4)})'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
      // and a screen reader hears which is which, as part of each post
      expect(find.bySemanticsLabel(RegExp(r'^@Chan_Medic .*, impersonation warning,')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^@chan_medic .*, another device uses this handle,')), findsOneWidget);

      // Tapping an author opens their identity
      await tester.tap(find.text(realName));
      await tester.pumpAndSettle();
      expect(find.text(medic), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('an author with a handle of their own shows just @handle; an alias shows instead', (tester) async {
      await setScreen(tester, const Size(390, 900));
      final api = ApplicationAPI()..stopPolling();
      await api.joinChannel('clean-names');
      const sarah = '12D3KooWUiCleanSarah7f3a';
      api.receiveFromNode(post(sarah, 'cn-1', 'Clinic opens at 8', 'dr_sarah', room: 'clean-names'));
      await tester.pumpWidget(host(const ChatScreen(peerName: 'clean-names', peerId: 'room:clean-names')));
      await tester.pump();

      expect(find.text('@dr_sarah'), findsOneWidget);
      expect(find.textContaining('7f3a'), findsNothing); // no peer ID clutter
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      // The full ID is a tap away
      await tester.tap(find.text('@dr_sarah'));
      await tester.pumpAndSettle();
      expect(find.text(sarah), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();

      api.setAlias(sarah, 'Sarah (clinic)');
      await tester.pump();
      expect(find.text('Sarah (clinic)'), findsOneWidget);
      api.setAlias(sarah, null);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('join or create a channel, with its name checked', (tester) async {
      await setScreen(tester, const Size(390, 900));
      await tester.pumpWidget(host(const MeshScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('Channels'));
      await tester.pump();
      await tester.tap(find.text('Join or create a channel'));
      await tester.pumpAndSettle();

      final nameField = find.widgetWithText(TextField, 'Channel name');
      await tester.enterText(nameField, 'Legal Aid');
      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(find.text('Lowercase letters, numbers and single dashes only'), findsOneWidget);

      // Private needs a real passphrase
      await tester.tap(find.text('Private'));
      await tester.pump();
      await tester.enterText(nameField, 'legal-aid');
      await tester.enterText(find.widgetWithText(TextField, 'Passphrase'), 'short');
      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(find.text('Use at least 8 characters'), findsOneWidget);

      // An open one is joined at once and opened
      await tester.tap(find.text('Private'));
      await tester.pump();
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.text('#legal-aid'), findsOneWidget);
      expect(find.text('Nothing in #legal-aid yet'), findsOneWidget);

      // And can be left again
      await tester.tap(find.byTooltip('Channel options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave & delete channel'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Leave & delete'));
      await tester.pumpAndSettle();
      expect(ApplicationAPI().channelStatus(ApplicationAPI.channelConversation('legal-aid')), isNull);
      expect(find.text('#legal-aid'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('a channel lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        final api = ApplicationAPI()..stopPolling();
        api.receiveFromNode(post('12D3KooWUiChanLong${mode.name}', 'cl-${mode.name}', 'A long post ' * 15, 'someone_long_name'));
        await tester.pumpWidget(host(
          ChatScreen(peerName: 'general', peerId: ApplicationAPI.channelConversation('general')),
          mode: mode,
          textScale: 2,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });

  group('Deleting conversations', () {
    setUp(() => ApplicationAPI().stopPolling());

    ChatMessage post(String from, String id, String content, String room) =>
        ChatMessage(id: 0, from: from, content: content, timestamp: DateTime.now(), msgId: id, room: room);

    test('a deleted chat loses its messages and draft, and a carried copy can\'t bring one back', () async {
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiDeleteApi';
      api.receiveFromNode(incoming(peer, 'del-1', 'location of the safe house', DateTime.now(), handle: 'ally'));
      api.receiveFromNode(incoming(peer, 'del-2', 'bring the radios', DateTime.now(), handle: 'ally'));
      DraftStore().setDraft(peer, 'half-typed reply');
      expect(api.historyFor(peer), hasLength(2));

      await api.deleteConversation(peer);
      expect(api.historyFor(peer), isEmpty);
      expect(DraftStore().getDraft(peer), '');
      expect(api.unreadCount(peer), 0);

      // Another phone offers the same message again later: still gone
      api.receiveFromNode(incoming(peer, 'del-1', 'location of the safe house', DateTime.now(), handle: 'ally'));
      expect(api.historyFor(peer), isEmpty);
      // New messages still arrive
      api.receiveFromNode(incoming(peer, 'del-3', 'are you ok?', DateTime.now(), handle: 'ally'));
      expect(api.historyFor(peer).single['content'], 'are you ok?');
    });

    testWidgets('a chat is deleted from its menu, only after confirming', (tester) async {
      await setScreen(tester, const Size(390, 800));
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiDeleteChat';
      api.receiveFromNode(incoming(peer, 'dc-1', 'incident report: north gate', DateTime.now(), handle: 'scout_7'));
      await tester.pumpWidget(host(Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ChatScreen(peerName: 'scout_7', peerId: peer))),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      Future<void> askToDelete() async {
        await tester.tap(find.byTooltip('Chat options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete chat'));
        await tester.pumpAndSettle();
      }

      await askToDelete();
      expect(
        find.text('Delete conversation with @scout_7? This will permanently remove all messages from your '
            'device\'s local storage. This action cannot be undone.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.historyFor(peer), hasLength(1));
      expect(find.byType(ChatScreen), findsOneWidget);

      await askToDelete();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.historyFor(peer), isEmpty);
      expect(find.byType(ChatScreen), findsNothing); // back to where it was opened from
      expect(find.text('Chat deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a channel is left and deleted from the Chats list with a long press', (tester) async {
      await setScreen(tester, const Size(390, 900));
      final api = ApplicationAPI()..stopPolling();
      await api.joinChannel('night-shift');
      const room = 'room:night-shift';
      api.receiveFromNode(post('12D3KooWUiDeleteChan', 'dch-1', 'gate code 4471', 'night-shift'));
      DraftStore().setDraft(room, 'unsent');
      expect(api.historyFor(room), hasLength(1));

      await tester.pumpWidget(host(const MeshScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.textContaining('Channels'));
      await tester.pump();
      await tester.longPress(find.text('#night-shift'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave & delete channel'));
      await tester.pumpAndSettle();
      expect(find.text('Leave and delete #night-shift?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Leave & delete'));
      await tester.pumpAndSettle();

      expect(find.text('#night-shift'), findsNothing);
      expect(api.channelStatus(room), isNull);
      expect(api.historyFor(room), isEmpty);
      expect(DraftStore().getDraft(room), '');
      // Posts that keep arriving for it aren't shown or kept
      api.receiveFromNode(post('12D3KooWUiDeleteChan', 'dch-2', 'still here?', 'night-shift'));
      expect(api.historyFor(room), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a direct chat\'s long press offers its identity or deleting it', (tester) async {
      await setScreen(tester, const Size(390, 900));
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWUiDeleteRow';
      api.receiveFromNode(incoming(peer, 'drow-1', 'meet by the fountain', DateTime.now(), handle: 'rowan'));
      await tester.pumpWidget(host(const MeshScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'rowan'); // other tests' contacts are listed too
      await tester.pump();
      expect(find.text('meet by the fountain'), findsOneWidget);

      await tester.longPress(find.text('meet by the fountain'));
      await tester.pumpAndSettle();
      expect(find.text('Peer identity'), findsOneWidget);
      await tester.tap(find.text('Delete chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('meet by the fountain'), findsNothing);
      expect(api.historyFor(peer), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
    });
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
          expect(find.text('Choose your handle'), findsOneWidget);
          expect(find.text('Your handle'), findsOneWidget);
          expect(find.text('Join the mesh'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a returning user with a handle goes straight to the app, without the prompt', (tester) async {
      await setScreen(tester, const Size(390, 800));
      ApplicationAPI().setMyHandleForTesting('river_k');
      addTearDown(() => ApplicationAPI().setMyHandleForTesting(null));

      await tester.pumpWidget(host(const InitializationScreen()));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500)); // the route transition
      expect(find.byType(MainNavigationScreen), findsOneWidget);
      expect(find.text('Choose your handle'), findsNothing);
      expect(find.text('Join the mesh'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });
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
    setUp(() => ApplicationAPI().stopPolling());

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        await tester.pumpWidget(host(const NodeSettingsScreen(), mode: mode, textScale: 2));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.scrollUntilVisible(find.text('Help & guides'), 200);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Help & guides lays out at 320px wide with 2x text in ${mode.name} mode', (tester) async {
        await setScreen(tester, const Size(320, 640));
        await tester.pumpWidget(host(const HelpScreen(), mode: mode, textScale: 2));
        await tester.pump();
        await tester.scrollUntilVisible(find.text('Impersonation warning'), 300);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the icon legend lives on its own Help page, not in the settings list', (tester) async {
      await setScreen(tester, const Size(390, 800));
      await tester.pumpWidget(host(const NodeSettingsScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.scrollUntilVisible(find.text('Help & guides'), 200);
      expect(find.text('Not delivered'), findsNothing);
      expect(find.text('Understand delivery icons, mesh hops, and receipts'), findsOneWidget);

      await tester.ensureVisible(find.text('Help & guides'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help & guides'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpScreen), findsOneWidget);
      final help = find.descendant(of: find.byType(HelpScreen), matching: find.byType(Scrollable)).first;
      Future<void> scrollTo(String text) => tester.scrollUntilVisible(find.text(text), 200, scrollable: help);
      // Every delivery state the chat can show, with the icon it shows
      for (final (icon, word) in [
        (Icons.schedule, 'Sending'),
        (Icons.hourglass_empty, 'Waiting'),
        (Icons.check, 'Sent'),
        (Icons.done_all, 'Delivered'),
        (Icons.visibility_outlined, 'Read'),
        (Icons.error_outline, 'Not delivered'),
      ]) {
        await scrollTo(word);
        expect(find.byIcon(icon), findsOneWidget, reason: word);
      }
      for (final link in ['Wi-Fi', 'Bluetooth', 'Via mesh relay']) {
        await scrollTo(link);
      }
      expect(find.byType(MeshLinkSample), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the handle can be changed, with a warning when a known peer already uses it', (tester) async {
      await setScreen(tester, const Size(390, 800));
      final api = ApplicationAPI()..stopPolling();
      api.setMyHandleForTesting('river_k');
      addTearDown(() => api.setMyHandleForTesting(null));
      api.receiveFromNode(incoming('12D3KooWUiHandleTaken', 'ht-1', 'hi', DateTime.now(), handle: 'medic_lead'));

      await tester.pumpWidget(host(const NodeSettingsScreen()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('@river_k'), findsOneWidget);
      await tester.tap(find.byTooltip('Change handle'));
      await tester.pumpAndSettle();
      expect(find.text('Change your handle'), findsOneWidget);
      final field = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      FilledButton button(String label) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

      // Unchanged, too short, then a fresh name
      expect(button('Save').onPressed, isNull);
      await tester.enterText(field, 'ab');
      await tester.pump();
      expect(find.text('Use at least 3 characters'), findsOneWidget);
      expect(button('Save').onPressed, isNull);
      await tester.enterText(field, 'fresh_name');
      await tester.pump();
      expect(button('Save').onPressed, isNotNull);
      expect(find.textContaining('Caution', findRichText: true), findsNothing);

      // A lookalike of a known peer's handle needs the confirm button, not Enter
      await tester.enterText(field, 'Medic-Lead');
      await tester.pump();
      expect(find.textContaining('already using the handle @Medic-Lead', findRichText: true), findsOneWidget);
      expect(find.text('Confirm & Use Handle'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Change your handle'), findsOneWidget);
      expect(api.myHandle, 'river_k');

      // No node in tests to bind it to, so saving reports why it couldn't
      await tester.tap(find.text('Confirm & Use Handle'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Couldn\'t change your handle'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Change your handle'), findsNothing);

      // A new handle shows up at once
      api.setMyHandleForTesting('dawn_patrol');
      await tester.pump();
      expect(find.text('@dawn_patrol'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

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
