import 'dart:async';

class ApplicationAPI {
  static final ApplicationAPI _instance = ApplicationAPI._internal();
  factory ApplicationAPI() => _instance;
  ApplicationAPI._internal();

  /// Compose and send messages
  void sendMessage(String msg, String peerId) {
    print("API: sendMessage(msg: \$msg, peerId: \$peerId)");
  }

  /// Manage chats / rooms
  void joinRoom(String roomId) {
    print("API: joinRoom(roomId: \$roomId)");
  }

  /// Show peer status / Contacts list
  Future<List<Map<String, dynamic>>> getPeers() async {
    print("API: getPeers() executed");
    return [
      {"id": "9f2a..7d0e", "name": "Kite", "type": "DIRECT BLE", "online": true},
      {"id": "a4b1..92ca", "name": "Harbor Node", "type": "MULTI-HOP", "online": false},
    ];
  }

  /// Handle incoming messages
  void onMessage(Function(Map<String, dynamic>) callback) {
    print("API: onMessage() listener registered");
  }

  /// Handle peer connection state changes
  void onPeerUpdate(Function(Map<String, dynamic>) callback) {
    print("API: onPeerUpdate() listener registered");
  }
}