import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:app/application_api.dart';
import 'package:app/main.dart';
import 'package:app/models/chat_message.dart';
import 'package:app/services/local_store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  LocalStore.isTestMode = true;

  Future<void> run(WidgetTester tester, Duration d) async {
    final sw = Stopwatch()..start();
    while (sw.elapsed < d) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('tab and theme switching', (tester) async {
    final api = ApplicationAPI()..stopPolling();
    for (var i = 0; i < 12; i++) {
      api.receiveFromNode(ChatMessage(
        id: 0, from: '12D3KooWPerfPeer$i', content: 'message number $i from a friend nearby',
        timestamp: DateTime.now().subtract(Duration(minutes: i * 7)), msgId: 'perf-$i', handle: 'friend_$i'));
    }
    await tester.pumpWidget(const ProviderScope(child: P2PChatApp(home: MainNavigationScreen())));
    await run(tester, const Duration(seconds: 2));

    await binding.traceAction(() async {
      for (var i = 0; i < 3; i++) {
        for (final tab in ['Discover', 'Settings', 'Chats']) {
          await tester.tap(find.text(tab).last);
          await run(tester, const Duration(milliseconds: 900));
        }
      }
    }, reportKey: 'tabs');

    await tester.tap(find.text('Settings').last);
    await run(tester, const Duration(seconds: 1));
    await binding.traceAction(() async {
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Light'));
        await run(tester, const Duration(milliseconds: 700));
        await tester.tap(find.text('Dark'));
        await run(tester, const Duration(milliseconds: 700));
      }
    }, reportKey: 'theme');
  });
}
