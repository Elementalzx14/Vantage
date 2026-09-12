


import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'services/prefs.dart';
import 'services/core_manager.dart';
import 'services/theme_service.dart';
import 'models/nasa_theme.dart';
import 'screens/login_screen.dart';
import 'screens/library_screen.dart';
import 'screens/cores_screen.dart';
import 'screens/emulator_screen.dart';
import 'services/path_service.dart';
import 'services/log_service.dart';
import 'services/protocol_handler_windows.dart';
import 'services/deep_link_service.dart';
import 'services/launch_service.dart';
import 'screens/item_details_screen.dart';
import 'models/jellyfin_models.dart';
import 'screens/input_manager_screen.dart';
import 'screens/ios_preview_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  
  await PathService.instance.init();
  await LogService.instance.init();
  
  if (Platform.isAndroid) {
    try {
      final abi = await const MethodChannel('com.retrostream.vantage/emulator').invokeMethod<String>('getAbi');
      if (abi != null) {
        CoreManager.setAndroidAbi(abi);
        vLog('DEVICE ABI DETECTED: $abi');
      }
    } catch (e) {
      vError('FAILED TO DETECT ABI', e);
    }
  }

  await CoreManager.instance.init();
  await ThemeService.instance.init();
  
  if (Platform.isWindows) {
    await ProtocolHandlerWindows.register('vantage');
  }

  runApp(const VantageApp());
}

final _prefs = Prefs();

final router = GoRouter(
  initialLocation: '/loading',
  routes: [
    GoRoute(
      path: '/loading',
      builder: (_, __) => const _SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: '/library',
      builder: (_, __) => const LibraryScreen(),
    ),
    GoRoute(
      path: '/cores',
      builder: (_, __) => Platform.isIOS
          ? const IosPreviewScreen()
          : const CoresScreen(),
    ),
    GoRoute(
      path: '/ios-preview',
      builder: (_, __) => const IosPreviewScreen(),
    ),
    GoRoute(
      path: '/inputs',
      builder: (_, __) => const InputManagerScreen(),
    ),
    GoRoute(
      path: '/emulator',
      builder: (_, state) {
        if (Platform.isIOS) return const IosPreviewScreen();
        final args = state.extra as Map<String, dynamic>;
        return EmulatorScreen(
          romPath: args['romPath'] as String,
          corePath: args['corePath'] as String,
          title: args['title'] as String,
          itemId: args['itemId'] as String?,
          serverUrl: args['serverUrl'] as String,
          token: args['token'] as String,
          userId: args['userId'] as String,
        );
      },
    ),
    GoRoute(
      path: '/details',
      builder: (_, state) {
        final args = state.extra as Map<String, dynamic>;
        return ItemDetailsScreen(
          item: args['item'] as JfItem,
          serverUrl: args['serverUrl'] as String,
          token: args['token'] as String,
          userId: args['userId'] as String,
        );
      },
    ),
  ],
);

class VantageApp extends StatefulWidget {
  const VantageApp({super.key});

  @override
  State<VantageApp> createState() => _VantageAppState();
}

class _VantageAppState extends State<VantageApp> {
  @override
  void initState() {
    super.initState();
    DeepLinkService.instance.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        final nasaTheme = ThemeService.instance.currentTheme;
        
        return MaterialApp.router(
          title: 'Vantage',
          debugShowCheckedModeBanner: false,
          theme: _buildDynamicNasaTheme(nasaTheme),
          routerConfig: router,
          builder: (context, child) {
            return Stack(
              children: [
                if (child != null) child,
                _GlobalLaunchOverlay(),
              ],
            );
          },
        );
      },
    );
  }

  ThemeData _buildDynamicNasaTheme(NasaTheme nt) {
    return ThemeData(
      useMaterial3: true,
      brightness: nt.brightness,
      scaffoldBackgroundColor: nt.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: nt.primary,
        brightness: nt.brightness,
        primary: nt.primary,
        surface: nt.surface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: nt.brightness == Brightness.dark ? const Color(0xFF1A1A1A).withOpacity(0.5) : Colors.white.withOpacity(0.5),
        foregroundColor: nt.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: nt.text,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
      cardTheme: CardThemeData(
        color: nt.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: nt.text.withOpacity(0.05)),
        ),
      ),
      dividerColor: nt.text.withOpacity(0.1),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: nt.text),
        bodyMedium: TextStyle(color: nt.text),
        bodySmall: TextStyle(color: nt.text.withOpacity(0.6)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: nt.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      ),
    );
  }
}

class _GlobalLaunchOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LaunchService.instance.statusMessage,
      builder: (context, _) {
        final msg = LaunchService.instance.statusMessage.value;
        if (msg == null) return const SizedBox.shrink();

        return Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0xFFFF5C00).withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFFF5C00).withOpacity(0.1), blurRadius: 40, spreadRadius: 10),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rocket_launch, size: 48, color: Color(0xFFFF5C00)),
                  const SizedBox(height: 24),
                  Text(
                    msg,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ValueListenableBuilder<int?>(
                    valueListenable: LaunchService.instance.downloadProgress,
                    builder: (context, pct, _) {
                      if (pct == null) return const SizedBox.shrink();
                      return Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct < 0 ? null : pct / 100.0,
                              backgroundColor: Colors.white10,
                              color: const Color(0xFFFF5C00),
                              minHeight: 6,
                            ),
                          ),
                          if (pct >= 0) ...[
                            const SizedBox(height: 12),
                            Text(
                              '$pct%',
                              style: const TextStyle(color: Color(0xFFFF5C00), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    final loggedIn = await _prefs.isLoggedIn;
    if (!mounted) return;
    if (loggedIn) {
      context.go('/library');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final nasaTheme = ThemeService.instance.currentTheme;
    return Scaffold(
      backgroundColor: nasaTheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rocket_launch, size: 72, color: nasaTheme.primary),
            const SizedBox(height: 24),
            CircularProgressIndicator(color: nasaTheme.primary.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }
}

