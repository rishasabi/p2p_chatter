// import 'package:flutter/material.dart';
// import 'package:qr_flutter/qr_flutter.dart';
// import 'package:mobile_scanner/mobile_scanner.dart';

// class DiscoverScreen extends StatelessWidget {
//   final String myBootstrapData;
//   const DiscoverScreen({super.key, required this.myBootstrapData});

//   @override
//   Widget build(BuildContext context) {
//     return DefaultTabController(
//       length: 2,
//       child: Scaffold(
//         appBar: AppBar(
//           title: const Text('Add / Connect Peer'),
//           bottom: const TabBar(
//             indicatorColor: Color(0xFF935F32),
//             labelColor: Color(0xFF935F32),
//             unselectedLabelColor: Colors.grey,
//             tabs: [
//               Tab(icon: Icon(Icons.qr_code), text: 'My Code'),
//               Tab(icon: Icon(Icons.camera_alt), text: 'Scan Peer'),
//             ],
//           ),
//         ),
//         body: TabBarView(
//           children: [
//             // Tab 1: Show Own QR Code
//             Center(
//               child: Padding(
//                 padding: const EdgeInsets.all(24.0),
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Container(
//                       padding: const EdgeInsets.all(16),
//                       decoration: BoxDecoration(
//                         color: Colors.white, // QR must be black/white for reliable scanning
//                         borderRadius: BorderRadius.circular(16),
//                       ),
//                       child: QrImageView(
//                         data: myBootstrapData,
//                         version: QrVersions.auto,
//                         size: 220.0,
//                         backgroundColor: Colors.white,
//                       ),
//                     ),
//                     const SizedBox(height: 32),
//                     const Text(
//                       'Have your peer scan this code to link devices to your DHT node.',
//                       textAlign: TextAlign.center,
//                       style: TextStyle(color: Colors.grey),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             // Tab 2: Scan Peer's QR Code
//             MobileScanner(
//               onDetect: (capture) {
//                 final List<Barcode> barcodes = capture.barcodes;
//                 for (final barcode in barcodes) {
//                   final rawValue = barcode.rawValue;
//                   if (rawValue != null) {
//                     ScaffoldMessenger.of(context).showSnackBar(
//                       SnackBar(
//                         backgroundColor: const Color(0xFF935F32),
//                         content: Text('Discovered Peer:\n$rawValue'),
//                         duration: const Duration(seconds: 3),
//                       ),
//                     );
//                     break;
//                   }
//                 }
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class DiscoverScreen extends StatelessWidget {
  final String myBootstrapData;
  const DiscoverScreen({super.key, required this.myBootstrapData});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3, // Increased to 3 tabs
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discover'),
          bottom: const TabBar(
            indicatorColor: Color(0xFF935F32),
            labelColor: Color(0xFF935F32),
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.qr_code), text: 'My Code'),
              Tab(icon: Icon(Icons.camera_alt), text: 'Scan'),
              Tab(icon: Icon(Icons.bluetooth_searching), text: 'Nearby'),
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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: QrImageView(
                        data: myBootstrapData,
                        version: QrVersions.auto,
                        size: 220.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text('Have your peer scan this code to link devices to your DHT node.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: const Color(0xFF935F32), content: Text('Discovered Peer:\n$rawValue'), duration: const Duration(seconds: 3)),
                    );
                    break;
                  }
                }
              },
            ),

            // Tab 3: Nearby BLE Nodes for Pairing
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 16.0),
                  child: Text('NEARBY NODES', style: TextStyle(color: Colors.grey, letterSpacing: 2, fontSize: 12)),
                ),
                _buildNodeTile('nomad-7', 'aa41·6f02·17cd · -38 dBm'),
                _buildNodeTile('pier-station', '5b90·d3e8·2201 · -57 dBm'),
                _buildNodeTile('unknown-c4', 'c4ff·0a19·77be · -81 dBm'),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildNodeTile(String title, String sub) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: const Icon(Icons.signal_cellular_alt, color: Color(0xFF4ADE80)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      trailing: TextButton(
        onPressed: () {},
        style: TextButton.styleFrom(backgroundColor: const Color(0xFF1E1A17), foregroundColor: Colors.grey),
        child: const Text('PAIR'),
      ),
    );
  }
}