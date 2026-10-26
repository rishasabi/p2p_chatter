import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:app/services/draft_store.dart';
import 'package:app/services/embedded_node_service.dart';
import 'package:app/services/local_store.dart';

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
  // No real file I/O from tests (it would also hang widget tests)
  LocalStore.isTestMode = true;

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
      expect(peer.handle, isNull);
      expect(Peer.fromJson({'id': '12D3KooWXYZ', 'handle': 'dave'}).handle, 'dave');
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
      expect(msg.isRelayed, isFalse);

      final relayed = ChatMessage.fromJson({
        'id': 2,
        'from': '12D3KooWPeer',
        'content': 'via a friend',
        'timestamp': '2026-10-13T12:00:00Z',
        'msg_id': 'abc',
        'handle': 'erin',
        'via': '12D3KooWRelay',
      });
      expect(relayed.msgId, 'abc');
      expect(relayed.handle, 'erin');
      expect(relayed.isRelayed, isTrue);
      expect(relayed.room, isNull);

      final post = ChatMessage.fromJson({
        'id': 3,
        'from': '12D3KooWPeer',
        'content': 'to everyone',
        'timestamp': '2026-10-13T12:00:00Z',
        'room': 'general',
      });
      expect(post.room, 'general');
    });

    test('Receipt parses JSON correctly', () {
      final r = Receipt.fromJson({
        'id': 3,
        'from': '12D3KooWPeer',
        'ids': ['a', 'b'],
        'status': 'read',
        'timestamp': '2026-10-13T12:00:00Z',
      });
      expect(r.ids, ['a', 'b']);
      expect(r.status, 'read');
      expect(r.isRelayed, isFalse);
    });
  });

  group('DraftStore', () {
    test('keeps one draft per conversation, and blank text is no draft', () async {
      final drafts = DraftStore();
      var changes = 0;
      void listener() => changes++;
      drafts.addListener(listener);

      drafts.setDraft('12D3KooWDraftA', 'Need saline');
      drafts.setDraft('room:general', 'Water at the gym');
      expect(drafts.getDraft('12D3KooWDraftA'), 'Need saline');
      expect(drafts.getDraft('room:general'), 'Water at the gym');
      expect(drafts.getDraft('12D3KooWDraftNone'), '');

      drafts.setDraft('12D3KooWDraftA', '   \n ');
      expect(drafts.hasDraft('12D3KooWDraftA'), isFalse);
      drafts.clearDraft('room:general');
      expect(drafts.hasDraft('room:general'), isFalse);
      expect(changes, 4);

      drafts.removeListener(listener);
      await drafts.flush();
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

    test('getDiscoveredPeers reads peers learned from neighbours', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/peers/discovered');
        return http.Response(
          jsonEncode({
            'peers': [
              {
                'id': '12D3KooWHeardOf',
                'addrs': ['/ip4/192.168.43.7/tcp/4001/p2p/12D3KooWHeardOf'],
                'via': '12D3KooWNeighbour',
                'seen': '2026-10-26T10:00:00Z',
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final svc = ChatterApiService(client: client);
      final peers = await svc.getDiscoveredPeers();
      expect(peers.single.id, '12D3KooWHeardOf');
      expect(peers.single.addrs, ['/ip4/192.168.43.7/tcp/4001/p2p/12D3KooWHeardOf']);
      expect(peers.single.via, '12D3KooWNeighbour');
      svc.dispose();
    });

    test('channels: posts go to the room, and joining returns the room\'s ID', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final body = request.url.path == '/rooms'
            ? {'name': 'legal-aid', 'room': '~0a1b2c', 'private': true}
            : {'status': 'queued', 'room': 'general', 'id': 'p-1'};
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
      });
      final svc = ChatterApiService(client: client);

      expect(await svc.sendRoom('general', 'water at the gym', id: 'p-1'), 'queued');
      expect(jsonDecode(requests.last.body), {'room': 'general', 'content': 'water at the gym', 'id': 'p-1'});

      expect(await svc.joinRoom('legal-aid', passphrase: 'blue heron'), '~0a1b2c');
      expect(jsonDecode(requests.last.body), {'name': 'legal-aid', 'passphrase': 'blue heron'});

      await svc.leaveRoom('~0a1b2c');
      expect(requests.last.method, 'DELETE');
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

  group('ApplicationAPI', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Simulates MainActivity invoking a callback on the Bluetooth method channel
    Future<void> nativeCall(String method, Map<String, dynamic> args) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          'com.example.app/ble_advertiser',
          const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
          (_) {},
        );

    // A message as the node hands it over from GET /messages
    ChatMessage fromNode(String from, String msgId, String content, {String? via, String? handle}) =>
        ChatMessage(
          id: 0,
          from: from,
          content: content,
          timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
          msgId: msgId,
          via: via,
          handle: handle,
        );

    test('a reply in the same second as the message it answers sorts after it', () async {
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWOrderSameSecond';
      final sentAt = DateTime.utc(2026, 10, 26, 12, 0, 0, 800);
      ChatMessage reply(String id, String ts) => ChatMessage.fromJson(
          {'id': 0, 'from': peer, 'content': id, 'timestamp': ts, 'msg_id': id, 'via': peer});
      // The node's timestamps now carry milliseconds
      expect(reply('x', '2026-10-26T12:00:00.900Z').timestamp.millisecond, 900);

      api.receiveFromNode(reply('before', '2026-10-26T12:00:00.100Z'));
      api.receiveFromNode(reply('after', '2026-10-26T12:00:00.900Z'));
      // Our message went out at .800, between the two
      final mine = {
        'id': 'mine', 'peerId': peer, 'content': 'mine', 'isOutgoing': true, 'timestamp': sentAt, 'status': 'sent',
      };
      api.debugAddMessage(mine);
      expect(api.historyFor(peer).map((m) => m['id']), ['before', 'mine', 'after']);
    });

    test('the Chats list puts unread first, then the latest conversation, then names', () async {
      final api = ApplicationAPI()..stopPolling();
      final now = DateTime.now();
      ChatMessage msg(String from, String id, Duration ago) =>
          ChatMessage(id: 0, from: from, content: id, timestamp: now.subtract(ago), msgId: id, handle: id);
      api.receiveFromNode(msg('12D3KooWOrderOld', 'zed_old', const Duration(hours: 3)));
      api.receiveFromNode(msg('12D3KooWOrderNew', 'yan_new', const Duration(minutes: 5)));
      api.receiveFromNode(msg('12D3KooWOrderUnread', 'xu_unread', const Duration(hours: 9)));
      await api.markRead('12D3KooWOrderOld');
      await api.markRead('12D3KooWOrderNew');

      final order = api.peers.map((p) => p['id']).where((id) => (id as String).startsWith('12D3KooWOrder')).toList();
      expect(order.indexOf('12D3KooWOrderUnread'), lessThan(order.indexOf('12D3KooWOrderNew')));
      expect(order.indexOf('12D3KooWOrderNew'), lessThan(order.indexOf('12D3KooWOrderOld')));
    });

    test('channel posts caught up from history slot in by when they were written', () async {
      final api = ApplicationAPI()..stopPolling();
      await api.joinChannel('catch-up');
      const room = 'room:catch-up';
      const author = '12D3KooWHistoryAuthor';
      final now = DateTime.now().toUtc();
      ChatMessage post(String id, String content, DateTime at, {bool history = false}) => ChatMessage.fromJson({
            'id': 0,
            'from': author,
            'content': content,
            'timestamp': at.toIso8601String(),
            'msg_id': id,
            'handle': 'triage_lead',
            'via': '12D3KooWHistoryNeighbour',
            'room': 'catch-up',
            if (history) 'history': true,
          });

      api.receiveFromNode(post('cu-3', 'now: tent 4 full', now));
      api.receiveFromNode(post('cu-1', 'earlier: open tent 4', now.subtract(const Duration(hours: 2)), history: true));
      api.receiveFromNode(post('cu-2', 'later: tent 4 filling', now.subtract(const Duration(hours: 1)), history: true));
      api.receiveFromNode(post('cu-1', 'earlier: open tent 4', now.subtract(const Duration(hours: 2)), history: true));

      expect(api.historyFor(room).map((m) => m['id']), ['cu-1', 'cu-2', 'cu-3']); // once each, in order
      expect(post('x', '', now, history: true).isHistory, isTrue);
    });

    test('a post from history doesn\'t make its author look reachable', () async {
      final api = ApplicationAPI()..stopPolling();
      await api.joinChannel('old-news');
      const author = '12D3KooWHistoryAbsent';
      api.receiveFromNode(ChatMessage.fromJson({
        'id': 0,
        'from': author,
        'content': 'posted this morning',
        'timestamp': DateTime.now().subtract(const Duration(hours: 5)).toUtc().toIso8601String(),
        'msg_id': 'on-1',
        'via': '12D3KooWHistoryNeighbour',
        'room': 'old-news',
        'history': true,
      }));
      expect(api.historyFor('room:old-news'), hasLength(1));
      expect(api.peerStatus(author)['mesh'], isFalse);
    });

    test('message received with no chat open is kept in history, once', () {
      final api = ApplicationAPI()..stopPolling();
      api.receiveFromNode(fromNode('12D3KooWBtPeer', 'm-1', 'over the air', handle: 'dave'));
      api.receiveFromNode(fromNode('12D3KooWBtPeer', 'm-1', 'over the air')); // refetched

      final history = api.historyFor('12D3KooWBtPeer');
      expect(history, hasLength(1));
      expect(history.single['content'], 'over the air');
      expect(history.single['isOutgoing'], isFalse);
      expect(history.single['status'], 'received');
      expect(api.displayName('12D3KooWBtPeer'), 'dave'); // the sender's signed handle
      expect(api.unreadCount('12D3KooWBtPeer'), 1);
    });

    test('viewing a chat clears unread even if the read receipt has to wait', () async {
      final api = ApplicationAPI()..stopPolling();
      api.receiveFromNode(fromNode('12D3KooWReader', 'r-1', 'one'));
      api.receiveFromNode(fromNode('12D3KooWReader', 'r-2', 'two'));
      expect(api.unreadCount('12D3KooWReader'), 2);

      await api.markRead('12D3KooWReader'); // no node in tests, so the receipt can't go out
      expect(api.unreadCount('12D3KooWReader'), 0);
      expect(api.historyFor('12D3KooWReader').any((m) => m['readSent'] == true), isFalse,
          reason: 'unsent read receipts are retried later');
    });

    test('a relayed message shows the peer as reachable via mesh', () {
      final api = ApplicationAPI()..stopPolling();
      api.receiveFromNode(fromNode('12D3KooWFarPeer', 'f-1', 'hi from afar', via: '12D3KooWRelay'));
      final status = api.peerStatus('12D3KooWFarPeer');
      expect(status['type'], 'VIA MESH');
      expect(status['online'], isTrue);
    });

    test('receipts move a sent message forward, never back, and only from its recipient', () async {
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWReceiptPeer';
      // No node in tests, so the send itself fails
      await expectLater(api.sendMessage('anyone there?', peer), throwsA(isA<ApiException>()));
      final msg = api.historyFor(peer).last;
      final id = msg['id'] as String;
      expect(msg['content'], 'anyone there?');
      expect(msg['status'], 'failed');

      api.receiveReceiptFromNode(Receipt(id: 1, from: '12D3KooWSomeoneElse', ids: [id], status: 'read'));
      expect(msg['status'], 'failed');

      // A receipt from the recipient proves it arrived after all
      api.receiveReceiptFromNode(Receipt(id: 2, from: peer, ids: [id], status: 'delivered'));
      expect(msg['status'], 'delivered');
      api.receiveReceiptFromNode(Receipt(id: 3, from: peer, ids: [id], status: 'read'));
      expect(msg['status'], 'read');
      api.receiveReceiptFromNode(Receipt(id: 4, from: peer, ids: [id], status: 'delivered'));
      expect(msg['status'], 'read');
    });

    test('handles are validated', () {
      expect(ApplicationAPI.validateHandle('alice_01'), isNull);
      expect(ApplicationAPI.validateHandle('  bob.k  '), isNull);
      expect(ApplicationAPI.validateHandle('ab'), isNotNull);
      expect(ApplicationAPI.validateHandle('a' * 32), isNull); // the node's limit
      expect(ApplicationAPI.validateHandle('a' * 33), isNotNull);
      expect(ApplicationAPI.validateHandle('has space'), isNotNull);
    });

    test('a handle another known peer uses, or a lookalike, is found before taking it', () {
      final api = ApplicationAPI()..stopPolling();
      const owner = '12D3KooWCollisionOwner';
      api.receiveFromNode(fromNode(owner, 'col-1', 'hello', handle: 'relief_lead'));

      expect(api.peerUsingHandle('relief_lead'), owner);
      expect(api.peerUsingHandle(' Re1ief-Lead '), owner); // case, 1/l and separators
      expect(api.peerUsingHandle('relief_team'), isNull);
    });

    test('a later phone claiming a known handle, or a lookalike, is flagged and told apart', () {
      final api = ApplicationAPI()..stopPolling();
      const medic = '12D3KooWTrustRealMedic';
      const fake = '12D3KooWTrustFakeMedicQ9zX';
      api.receiveFromNode(fromNode(medic, 't-1', 'triage at tent 4', handle: 'Medic_Triage'));
      expect(api.hasHandleConflict(medic), isFalse);
      expect(api.displayName(medic), 'Medic_Triage');
      expect(api.firstSeen(medic), isNotNull);

      // Different case and separator, same look
      api.receiveFromNode(fromNode(fake, 't-2', 'come to the north gate', handle: 'medic-tr1age'));
      expect(api.hasHandleConflict(fake), isTrue);
      expect(api.peerStatus(fake)['handleConflict'], isTrue);
      expect(api.displayName(fake), 'medic-tr1age (#Q9zX)');
      expect(api.hasHandleConflict(medic), isFalse, reason: 'the first phone keeps the handle');

      // A Nearby phone not yet known, advertising the same handle
      expect(api.advertisedHandleConflicts('MEDIC_TRIAGE', '12D3KooWTrustOther'), isTrue);
      expect(api.advertisedHandleConflicts('Medic_Triage', '12D3KooWTrustRealMe'), isFalse);

      // Checking in person settles it: the verified phone owns the handle
      api.setVerified(fake, true);
      expect(api.hasHandleConflict(fake), isFalse);
      expect(api.hasHandleConflict(medic), isTrue);
      expect(api.displayName(fake), 'medic-tr1age');
      api.setVerified(fake, false);
      expect(api.hasHandleConflict(fake), isTrue);
      expect(api.hasHandleConflict(medic), isFalse);
    });

    test('peers heard of from a neighbour are remembered, but listed only once they speak', () {
      final api = ApplicationAPI()..stopPolling();
      const heard = '12D3KooWPexHeardOfPeer';
      api.receiveDiscoveredFromNode([
        (id: heard, addrs: ['/ip4/192.168.43.7/tcp/4001/p2p/$heard'], via: '12D3KooWPexNeighbour'),
      ]);
      // Known (so Wi-Fi reconnects and relays can reach it), but no bare ID in the list
      expect(api.peerIdForPrefix('12D3KooWPexHeard'), heard);
      expect(api.peers.map((p) => p['id']), isNot(contains(heard)));
      expect(api.handleOf(heard), isNull, reason: 'a neighbour cannot name someone else');

      api.receiveFromNode(fromNode(heard, 'pex-1', 'hi, I am on the same hotspot', handle: 'dana_pex'));
      expect(api.peers.map((p) => p['id']), contains(heard));
      expect(api.displayName(heard), 'dana_pex');
    });

    test('channel posts go to joined channels only, with their author kept apart from direct chats', () async {
      final api = ApplicationAPI()..stopPolling();
      const author = '12D3KooWChanAuthorPeer';
      ChatMessage post(String id, String room, String content) => ChatMessage(
          id: 0, from: author, content: content, timestamp: DateTime.now(), msgId: id, handle: 'medic_ana', room: room);

      expect(api.channels.map((c) => c['name']), contains(ApplicationAPI.defaultChannel));
      final general = ApplicationAPI.channelConversation('general');
      api.receiveFromNode(post('ch-1', 'general', 'triage at tent 4'));
      api.receiveFromNode(post('ch-2', 'not-joined', 'nobody here reads this'));

      final m = api.historyFor(general).single;
      expect(m['content'], 'triage at tent 4');
      expect(m['author'], author);
      expect(m['authorHandle'], 'medic_ana');
      expect(api.channelStatus(general)!['unread'], 1);
      expect(api.historyFor(ApplicationAPI.channelConversation('not-joined')), isEmpty);
      expect(api.historyFor(author), isEmpty, reason: 'a channel post is not a direct message');

      // Known by name (so impersonation checks work), but not a direct chat until they are one
      expect(api.displayName(author), 'medic_ana');
      expect(api.peers.map((p) => p['id']), isNot(contains(author)));
      api.receiveFromNode(fromNode(author, 'ch-3', 'hi, it\'s Ana', handle: 'medic_ana'));
      expect(api.peers.map((p) => p['id']), contains(author));

      // Open channels are joined locally; names are checked
      final shelter = await api.joinChannel('#Food-Shelter');
      expect(shelter['id'], ApplicationAPI.channelConversation('food-shelter'));
      expect(shelter['private'], isFalse);
      await expectLater(api.joinChannel('food shelter'), throwsArgumentError);
      await api.leaveChannel(shelter['id'] as String);
      expect(api.channelStatus(shelter['id'] as String), isNull);
    });

    test('a local alias replaces the handle and peers cannot change it', () {
      final api = ApplicationAPI()..stopPolling();
      const peer = '12D3KooWTrustAliasPeer';
      api.receiveFromNode(fromNode(peer, 'a-1', 'hi', handle: 'alice'));
      api.setAlias(peer, '  Alice (Verified Volunteer) ');
      expect(api.displayName(peer), 'Alice (Verified Volunteer)');
      expect(api.peerStatus(peer)['name'], 'Alice (Verified Volunteer)');

      // The peer renaming itself changes its handle, not our name for it
      api.receiveFromNode(fromNode(peer, 'a-2', 'new name', handle: 'coordinator'));
      expect(api.handleOf(peer), 'coordinator');
      expect(api.displayName(peer), 'Alice (Verified Volunteer)');

      api.setAlias(peer, ' ');
      expect(api.aliasOf(peer), isNull);
      expect(api.displayName(peer), 'coordinator');
    });

    test('peer status follows the Bluetooth link and keeps known peers', () async {
      final api = ApplicationAPI()..stopPolling();
      final updates = <Map<String, dynamic>>[];
      void listener(Map<String, dynamic> u) {
        if (u['id'] == '12D3KooWStatusPeer') updates.add(u);
      }
      api.onPeerUpdate(listener);

      await nativeCall('onBluetoothPeerConnected', {
        'peerId': '12D3KooWStatusPeer',
        'name': 'carol',
        'address': '11:22:33:44:55:66',
        'addrs': ['/ip4/192.168.1.9/tcp/4001/p2p/12D3KooWStatusPeer'],
      });
      var status = api.peerStatus('12D3KooWStatusPeer');
      expect(status['name'], 'carol'); // handle from the handshake
      expect(status['type'], 'BLUETOOTH');
      expect(status['online'], isTrue);

      await nativeCall('onBluetoothPeerDisconnected', {'peerId': '12D3KooWStatusPeer'});
      status = api.peerStatus('12D3KooWStatusPeer');
      expect(status['type'], 'OFFLINE');
      // Still a known contact, so it stays in the list and can be reconnected
      expect(api.peers.map((p) => p['id']), contains('12D3KooWStatusPeer'));

      // One notification per actual change
      expect(updates.map((u) => u['type']), ['BLUETOOTH', 'OFFLINE']);
      api.removeOnPeerUpdate(listener);
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

    testWidgets('MainNavigationScreen displays Chats, Nearby, and Settings tabs', (tester) async {
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
      expect(find.text('Nearby'), findsOneWidget);
      expect(find.text('Discover'), findsNothing);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('back from Nearby or Settings goes to Chats; on Chats it takes a second press to leave',
        (tester) async {
      var exits = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exits++;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      tester.view.physicalSize = const Size(390, 800); // a phone: the bottom bar, not the side rail
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(mockApiService())],
        child: const MaterialApp(home: MainNavigationScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      NavigationBar bar() => tester.widget<NavigationBar>(find.byType(NavigationBar));

      for (final tab in ['Settings', 'Nearby']) {
        await tester.tap(find.text(tab).last);
        await tester.pump(const Duration(milliseconds: 300));
        expect(bar().selectedIndex, isNot(0));
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 300));
        expect(bar().selectedIndex, 0, reason: 'back from $tab');
        expect(exits, 0);
      }

      // On Chats: the first press only warns; a second soon after leaves
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Press back again to exit'), findsOneWidget);
      expect(exits, 0);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exits, 1);

      // Too long after, it warns again
      await tester.pump(const Duration(seconds: 3));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exits, 1);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Tapping Settings tab opens the settings screen', (tester) async {
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
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // The nav label and the screen title
      expect(find.text('Settings'), findsNWidgets(2));
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });
  });
}
