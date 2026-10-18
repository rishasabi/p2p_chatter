import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app/application_api.dart';
import 'package:app/main.dart';
import 'package:app/models/chat_message.dart';
import 'package:app/models/node_info.dart';
import 'package:app/models/peer.dart';
import 'package:app/providers/providers.dart';
import 'package:app/services/api_service.dart';
import 'package:app/services/embedded_node_service.dart';

ChatterApiService mockApiService({
  String? healthBody,
  String? nodeBody,
  String? peersBody,
  String? messagesBody,
  int statusCode = 200,
}) {
  final client = MockClient((request) async {
    final path = request.url.path;
    String body;
    if (path == '/health') {
      body = healthBody ?? jsonEncode({'status': 'ok'});
    } else if (path == '/node') {
      body = nodeBody ??
          jsonEncode({
            'id': '12D3KooWTestPeerID',
            'addrs': ['/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWTestPeerID'],
          });
    } else if (path == '/peers') {
      body = peersBody ??
          jsonEncode({
            'peers': [
              {'id': '12D3KooWRemotePeer1'},
              {'id': '12D3KooWRemotePeer2'},
            ],
          });
    } else if (path == '/messages') {
      body = messagesBody ??
          jsonEncode({
            'messages': [
              {
                'id': 1,
                'from': '12D3KooWRemotePeer1',
                'content': 'Hello world',
                'timestamp': '2026-01-01T12:00:00Z',
              }
            ],
          });
    } else if (path == '/peers/connect') {
      body = jsonEncode({'status': 'connected', 'address': 'test'});
    } else if (path == '/message') {
      body = jsonEncode({'status': 'sent', 'peer_id': 'test', 'content': 'test'});
    } else {
      return http.Response('not found', 404);
    }
    return http.Response(body, statusCode,
        headers: {'content-type': 'application/json'});
  });

  return ChatterApiService(client: client);
}

void main() {
  group('Models', () {
    test('NodeInfo parses JSON correctly', () {
      final info = NodeInfo.fromJson({
        'id': '12D3KooWABC',
        'addrs': ['/ip4/1.2.3.4/tcp/4001/p2p/12D3KooWABC'],
      });
      expect(info.id, '12D3KooWABC');
      expect(info.addrs.length, 1);
      expect(info.qrPayload, '/ip4/1.2.3.4/tcp/4001/p2p/12D3KooWABC');
    });

    test('Peer parses JSON correctly', () {
      final peer = Peer.fromJson({'id': '12D3KooWXYZ'});
      expect(peer.id, '12D3KooWXYZ');
    });

    test('ChatMessage parses JSON correctly', () {
      final msg = ChatMessage.fromJson({
        'id': 1,
        'from': '12D3KooWPeer',
        'content': 'hello mesh',
        'timestamp': '2026-10-13T12:00:00Z',
      });
      expect(msg.content, 'hello mesh');
      expect(msg.isOutgoing, isFalse);
    });
  });

  group('ChatterApiService', () {
    test('checkHealth returns true on ok response', () async {
      final svc = mockApiService();
      expect(await svc.checkHealth(), isTrue);
      svc.dispose();
    });

    test('getNode returns NodeInfo', () async {
      final svc = mockApiService();
      final info = await svc.getNode();
      expect(info.id, '12D3KooWTestPeerID');
      svc.dispose();
    });

    test('getPeers returns list of Peer', () async {
      final svc = mockApiService();
      final peers = await svc.getPeers();
      expect(peers.length, 2);
      svc.dispose();
    });

    test('sendMessage posts correct JSON body', () async {
      String? capturedBody;
      final client = MockClient((request) async {
        capturedBody = request.body;
        return http.Response(
          jsonEncode({'status': 'sent', 'peer_id': 'abc', 'content': 'hi'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = ChatterApiService(client: client);
      await svc.sendMessage('12D3KooWPeer', 'hello peer');
      final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(body['peer_id'], '12D3KooWPeer');
      expect(body['content'], 'hello peer');
      svc.dispose();
    });
  });

  group('Widget tests', () {
    setUp(() {
      EmbeddedNodeService.isTestMode = true;
      ApplicationAPI().stopPolling();
    });

    tearDown(() {
      ApplicationAPI().stopPolling();
    });

    testWidgets('P2PChatApp boots and renders without crashing', (tester) async {
      final svc = mockApiService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiServiceProvider.overrideWithValue(svc)],
          child: const P2PChatApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('MainNavigationScreen displays Chats, Discover, and Config tabs', (tester) async {
      final svc = mockApiService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiServiceProvider.overrideWithValue(svc)],
          child: const MaterialApp(
            home: MainNavigationScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Config'), findsOneWidget);
    });

    testWidgets('Tapping Config tab navigates to Node Configuration', (tester) async {
      final svc = mockApiService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiServiceProvider.overrideWithValue(svc)],
          child: const MaterialApp(
            home: MainNavigationScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Config'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Node Configuration'), findsOneWidget);
      expect(find.text('Dark Theme'), findsOneWidget);
    });
  });
}
