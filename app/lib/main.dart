import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/theme_provider.dart';
import 'screens/discover_screen.dart';
import 'screens/initialization_screen.dart';
import 'screens/mesh_screen.dart';
import 'screens/node_settings_screen.dart';
import 'services/embedded_node_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure the embedded background Go service runs with the app as a single unit
  await EmbeddedNodeService().ensureStarted();
  runApp(const ProviderScope(child: P2PChatApp()));
}

class P2PChatApp extends ConsumerWidget {
  const P2PChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    // Minimal Dark Theme (Ember Signature)
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF14110F),
      primaryColor: const Color(0xFF935F32),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF14110F),
        elevation: 0,
      ),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF935F32),
        secondary: Color(0xFF4ADE80),
        surface: Color(0xFF1E1A17),
      ),
      fontFamily: 'Courier',
      useMaterial3: true,
    );

    // Minimal Light Theme (Clean Paper / Sand aesthetic)
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF9F7F5),
      primaryColor: const Color(0xFF935F32),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF9F7F5),
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF935F32),
        secondary: Color(0xFF16A34A),
        surface: Color(0xFFEFECE9),
      ),
      fontFamily: 'Courier',
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Ember Mesh Chat',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: const InitializationScreen(),
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
  
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const MeshScreen(),
      const DiscoverScreen(myBootstrapData: ''),
      const NodeSettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF14110F),
        indicatorColor: const Color(0xFF935F32).withValues(alpha: 0.3),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.forum_outlined, color: Colors.grey),
            selectedIcon: Icon(Icons.forum, color: Color(0xFF4ADE80)),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner, color: Colors.grey),
            selectedIcon: Icon(Icons.qr_code_scanner, color: Color(0xFF4ADE80)),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune, color: Colors.grey),
            selectedIcon: Icon(Icons.tune, color: Color(0xFF4ADE80)),
            label: 'Config',
          ),
        ],
      ),
    );
  }
}
