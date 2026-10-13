import 'package:flutter/material.dart';
import 'dart:async';
import '../main.dart'; // Adjust path if needed to access MainNavigationScreen

class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  int _currentBootStep = 0;
  bool _isBootComplete = false;
  final TextEditingController _handleController = TextEditingController();

  final List<String> _bootSteps = [
    'Reading local vault',
    'Starting BLE service',
    'Seeding DHT peer table',
    'Restoring message queue'
  ];

  @override
  void initState() {
    super.initState();
    _startBootSequence();
  }

  void _startBootSequence() async {
    // Simulate the time it takes to boot the mesh node
    for (int i = 0; i <= _bootSteps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        setState(() {
          _currentBootStep = i;
        });
      }
    }
    
    // Transition to the login/profile state
    if (mounted) {
      setState(() {
        _isBootComplete = true;
      });
    }
  }

  void _joinMesh() {
    if (_handleController.text.isNotEmpty) {
      // In a real app, you would save the handle/PeerID to local storage here
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
                  onPressed: _isBootComplete ? _joinMesh : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF935F32),
                    disabledBackgroundColor: const Color(0xFF2A1C0E), // Dimmed brown when inactive
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: Text(
                    'JOIN THE MESH',
                    style: TextStyle(
                      letterSpacing: 2, 
                      color: _isBootComplete ? Colors.black : Colors.white38,
                      fontWeight: FontWeight.bold
                    ),
                  ),
                ),
              ),
            ],
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
    return Column(
      key: const ValueKey('profile'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('LOCAL PROFILE', style: TextStyle(color: Color(0xFF935F32), letterSpacing: 2, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: _handleController,
          style: const TextStyle(fontSize: 28, color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'pick a handle',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2420))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF935F32))),
          ),
          onChanged: (val) => setState(() {}), // Trigger rebuild to activate button if text isn't empty
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.fingerprint, size: 16, color: Color(0xFF4ADE80)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'PeerID 7c4e·f10b·92da — generated on this device',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            )
          ],
        )
      ],
    );
  }
}