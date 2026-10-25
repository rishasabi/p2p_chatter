import 'package:flutter/material.dart';
import 'dart:async';
import '../application_api.dart';
import '../main.dart';
import '../models/node_info.dart';

import '../services/embedded_node_service.dart';

class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  int _currentBootStep = 0;
  bool _isBootComplete = false;
  bool _joining = false;
  final TextEditingController _handleController = TextEditingController();
  final ApplicationAPI api = ApplicationAPI();
  NodeInfo? _liveNodeInfo;

  final List<String> _bootSteps = [
    'Reading local vault',
    'Starting P2P transport',
    'Seeding DHT peer table',
    'Restoring message queue'
  ];

  @override
  void initState() {
    super.initState();
    _startBootSequence();
  }

  void _startBootSequence() async {
    // Ensure embedded Go service is running
    await EmbeddedNodeService().ensureStarted();

    // Load the saved handle and contacts, start Bluetooth discovery
    await api.initialize();

    // Fetch persistent node identity
    try {
      final info = await api.getNode();
      if (mounted) {
        setState(() {
          _liveNodeInfo = info;
          // Returning user: the handle saved for this peer ID
          if (_handleController.text.isEmpty) _handleController.text = api.myHandle ?? '';
        });
      }
    } catch (_) {}

    // Step through the boot sequence
    for (int i = 0; i <= _bootSteps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        setState(() {
          _currentBootStep = i;
        });
      }
    }
    
    if (mounted) {
      setState(() {
        _isBootComplete = true;
      });
    }
  }

  String? get _handleError => ApplicationAPI.validateHandle(_handleController.text);

  bool get _canJoin => _isBootComplete && !_joining && _handleError == null;

  Future<void> _joinMesh() async {
    setState(() => _joining = true);
    try {
      // Binds the handle to this node's peer ID and shares it with peers
      await api.setMyHandle(_handleController.text);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('Could not save your handle: $e'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Scroll instead of overflowing when the keyboard shrinks the viewport
        // on smaller screens; IntrinsicHeight keeps the Spacers working otherwise
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- HEADER SECTION ---
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Color(0xFF4ADE80), blurRadius: 6, spreadRadius: 1)
                              ]
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text('NODE BOOTING', style: TextStyle(color: Colors.grey, letterSpacing: 3, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text('Chatter', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w400, color: Colors.white)),
                      const SizedBox(height: 16),
                      const Text(
                        'Messages that travel device to\ndevice. No towers, no servers,\nno account.',
                        style: TextStyle(color: Colors.grey, height: 1.5, fontSize: 14),
                      ),

                      const Spacer(),

                      // --- DYNAMIC MIDDLE SECTION ---
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        child: _isBootComplete ? _buildProfileSetup() : _buildBootChecklist(),
                      ),

                      const Spacer(flex: 2),

                      // --- BOTTOM BUTTON ---
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _canJoin ? _joinMesh : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF935F32),
                            disabledBackgroundColor: const Color(0xFF2A1C0E),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          ),
                          child: Text(
                            'JOIN THE MESH',
                            style: TextStyle(
                              letterSpacing: 2,
                              color: _canJoin ? Colors.black : Colors.white38,
                              fontWeight: FontWeight.bold
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBootChecklist() {
    return Column(
      key: const ValueKey('booting'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_bootSteps.length, (index) {
        bool isCompleted = _currentBootStep > index;
        bool isActive = _currentBootStep == index;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            children: [
              if (isCompleted)
                const Icon(Icons.circle, size: 14, color: Color(0xFF2A2420))
              else if (isActive)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF935F32)),
                )
              else
                const Icon(Icons.radio_button_unchecked, size: 14, color: Color(0xFF2A2420)),
              
              const SizedBox(width: 16),
              Text(
                _bootSteps[index],
                style: TextStyle(
                  color: isCompleted ? Colors.grey.shade700 : (isActive ? Colors.grey.shade300 : Colors.grey.shade800),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildProfileSetup() {
    final peerDisplay = _liveNodeInfo != null
        ? 'PeerID ${_liveNodeInfo!.shortId} — generated on this node'
        : 'PeerID unavailable — the local node is not running';

    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('LOCAL PROFILE', style: TextStyle(color: Color(0xFF935F32), letterSpacing: 2, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: _handleController,
          style: const TextStyle(fontSize: 28, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'pick a handle',
            hintStyle: const TextStyle(color: Colors.grey),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2420))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF935F32))),
            // Only complain once the user has started typing
            errorText: _handleController.text.isEmpty ? null : _handleError,
          ),
          onChanged: (val) => setState(() {}),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fingerprint, size: 16, color: Color(0xFF4ADE80)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$peerDisplay\nYour handle is bound to this PeerID and is how peers see you.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontFamily: 'monospace'),
              ),
            )
          ],
        )
      ],
    );
  }
}