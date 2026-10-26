import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'application_api.dart';
import 'providers/theme_provider.dart';
import 'screens/chat_screen.dart';
import 'screens/initialization_screen.dart';
import 'screens/mesh_screen.dart';
import 'screens/nearby_screen.dart';
import 'screens/node_settings_screen.dart';
import 'services/alert_sounds.dart';
import 'services/ble_service.dart';
import 'services/custom_theme_store.dart';
import 'services/draft_store.dart';
import 'services/embedded_node_service.dart';
import 'services/settings_store.dart';
import 'theme/app_theme.dart';
import 'widgets/feedback.dart';
import 'widgets/message_text.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled typefaces' licences, listed on the platform licences page
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Unbounded', 'Figtree']) {
      yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/OFL-$font.txt'));
    }
  });
  // Saved settings (theme etc.) must be in place before the first frame
  await SettingsStore().load();
  await CustomThemeStore().load();
  await DraftStore().load();
  // Ensure the embedded background Go service runs with the app as a single unit
  await EmbeddedNodeService().ensureStarted();
  runApp(const ProviderScope(child: P2PChatApp()));
}

class P2PChatApp extends ConsumerWidget {
  /// The first screen; the startup flow unless a test starts elsewhere.
  final Widget home;

  const P2PChatApp({super.key, this.home = const InitializationScreen()});

  static const title = 'Chatter';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    // A custom palette, while on, stands in for both
    final custom = ref.watch(customThemeDataProvider);

    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: custom ?? AppTheme.light(),
      darkTheme: custom ?? AppTheme.dark(),
      themeMode: themeMode,
      // Switch in one frame: cross-fading rebuilds every screen ~12 times
      themeAnimationDuration: Duration.zero,
      home: home,
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
  // Back on Chats asks once more before leaving the app
  bool _exitArmed = false;
  Timer? _exitTimer;
  final _api = ApplicationAPI();
  // Tabs are built on first visit and then kept, so switching back is instant
  // and doesn't reload anything
  final _visited = <int>{0};

  late final List<Widget> _screens;

  static const _destinations = [
    (icon: Icons.forum_outlined, selected: Icons.forum, label: 'Chats'),
    (icon: Icons.bluetooth_searching, selected: Icons.bluetooth_searching, label: 'Nearby'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _screens = [
      const MeshScreen(),
      const NearbyScreen(),
      const NodeSettingsScreen(),
    ];
    _api.onMessage(_notify);
    // Android 13+ asks once; elsewhere this is already granted
    Permission.notification.request().then((_) {}, onError: (Object e) => debugPrint('Notification permission: $e'));
  }

  @override
  void dispose() {
    _api.removeOnMessage(_notify);
    _exitTimer?.cancel();
    super.dispose();
  }

  // Back from Nearby or Settings goes to Chats rather than out of the app;
  // on Chats, a second press within two seconds leaves
  Widget _withBackHandling(Widget child) => PopScope(
        canPop: _currentIndex == 0 && _exitArmed,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_currentIndex != 0) {
            _select(0);
            return;
          }
          setState(() => _exitArmed = true);
          showNotice(context, 'Press back again to exit', duration: const Duration(seconds: 2));
          _exitTimer?.cancel();
          _exitTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) setState(() => _exitArmed = false);
          });
        },
        child: child,
      );

  // A message notification, unless that conversation is on screen right now
  void _notify(Map<String, dynamic> message) {
    final from = message['from'] as String;
    final looking = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        ChatScreen.visiblePeerId == from;
    if (looking) return;
    // The chosen alert sound, with the notification's vibration; neither
    // waits on the other, so nothing on screen is held up
    final sound = AlertSound.current;
    BleService().showMessageNotification(
      peerId: from,
      title: _api.displayName(from),
      body: markdownToPlain(message['content'] as String),
      silent: sound.notificationSilent,
    );
    sound.play();
  }

  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus(); // a hidden tab keeps no keyboard up
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Tablets and desktop windows get a side rail instead of a bottom bar
    final wide = MediaQuery.sizeOf(context).width >= 720;
    // Hidden tabs keep their state but have their animations paused. The
    // camera never runs in a tab: only the QR scanner route opens it
    final body = IndexedStack(
      index: _currentIndex,
      children: [
        for (var i = 0; i < _screens.length; i++)
          TickerMode(
            enabled: i == _currentIndex,
            child: _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
          ),
      ],
    );

    if (wide) {
      return _withBackHandling(Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _currentIndex,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      ));
    }

    return _withBackHandling(Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected),
              label: d.label,
            ),
        ],
      ),
    ));
  }
}
