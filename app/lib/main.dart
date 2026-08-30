import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  runApp(const P2PChatApp());
}

class P2PChatApp extends StatelessWidget {
  const P2PChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'P2P Mesh Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // Placeholder data representing this node's Multiaddr + PeerID from the Go backend
  final String myBootstrapString =
      "/ip4/127.0.0.1/tcp/4001/p2p/12D3KooWDpJ7As7BWAwEMxVu179YnuTBqc6g5spW5u78XYZ";

  final List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _screens.addAll([
      const ChatsScreen(),
      QRConnectScreen(myBootstrapData: myBootstrapString),
      const NetworkStatusScreen(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Connect',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: 'Mesh Network',
          ),
        ],
      ),
    );
  }
}

// ------------------- SCREEN 1: CHATS LIST -------------------
class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Direct Messages'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speaker_phone, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'No peers connected yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a QR code from a nearby peer to join the mesh',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------- SCREEN 2: QR CONNECT SCREEN -------------------
class QRConnectScreen extends StatelessWidget {
  final String myBootstrapData;
  const QRConnectScreen({super.key, required this.myBootstrapData});

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
            // Tab 1: Show Own QR Code
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    QrImageView(
                      data: myBootstrapData,
                      version: QrVersions.auto,
                      size: 220.0,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Have your peer scan this code to link devices',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            // Tab 2: Scan Peer's QR Code
            MobileScanner(
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final rawValue = barcode.rawValue;
                  if (rawValue != null) {
                    // Show a quick popup when a QR is detected
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Discovered Peer:\n$rawValue'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                    break;
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------- SCREEN 3: MESH STATUS -------------------
class NetworkStatusScreen extends StatelessWidget {
  const NetworkStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Health'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          Card(
            child: ListTile(
              leading: Icon(Icons.wifi_tethering, color: Colors.green),
              title: Text('Mesh Status: Active'),
              subtitle: Text('Listening for nearby relay nodes'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.people_outline, color: Colors.blue),
              title: Text('Direct Connected Peers'),
              subtitle: Text('0 nodes'),
            ),
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.alt_route, color: Colors.orange),
              title: Text('Known Multi-Hop Routes'),
              subtitle: Text('0 nodes in DHT table'),
            ),
          ),
        ],
      ),
    );
  }
}