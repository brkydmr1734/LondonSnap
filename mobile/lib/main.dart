import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:londonsnaps/core/router/app_router.dart';
import 'package:londonsnaps/core/services/connectivity_service.dart';
import 'package:londonsnaps/core/services/push_notification_service.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/calls/providers/call_provider.dart';
import 'package:londonsnaps/features/chat/providers/chat_provider.dart';
import 'package:londonsnaps/features/safety_walk/providers/safety_walk_provider.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize Firebase
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('[Firebase] Initialization failed: $e');
    }

    // Initialize connectivity monitoring
    ConnectivityService();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exception}');
    };

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    runApp(const ProviderScope(child: LondonSnapsApp()));

    // Initialize push notifications after UI is running (non-blocking)
    try {
      PushNotificationService().initialize();
    } catch (e) {
      debugPrint('[PushNotifications] Init skipped: $e');
    }
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint('Stack: $stack');
  });
}

class LondonSnapsApp extends StatefulWidget {
  const LondonSnapsApp({super.key});

  @override
  State<LondonSnapsApp> createState() => _LondonSnapsAppState();
}

class _LondonSnapsAppState extends State<LondonSnapsApp> with WidgetsBindingObserver {
  final CallProvider _callProvider = CallProvider();
  final ChatProvider _chatProvider = ChatProvider();
  final SafetyWalkProvider _safetyWalkProvider = SafetyWalkProvider();
  bool _navigatedToIncoming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize chat (connects socket) and call system early
    _chatProvider.init();
    _callProvider.addListener(_onCallStateChanged);
    
    // Initialize safety walk provider - load active walk if any
    _safetyWalkProvider.loadActiveWalk();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callProvider.removeListener(_onCallStateChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reconnect socket when app comes back to foreground
      _chatProvider.reconnectSocket();
    }
  }

  void _onCallStateChanged() {
    if (_callProvider.state == CallState.ringingIncoming && !_navigatedToIncoming) {
      _navigatedToIncoming = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appRouter.push('/incoming-call');
      });
    } else if (_callProvider.state != CallState.ringingIncoming) {
      _navigatedToIncoming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LondonSnaps',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
    );
  }
}
