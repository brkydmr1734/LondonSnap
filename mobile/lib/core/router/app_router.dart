import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/features/auth/presentation/login_screen.dart';
import 'package:londonsnaps/features/auth/presentation/register_screen.dart';
import 'package:londonsnaps/features/auth/presentation/welcome_screen.dart';
import 'package:londonsnaps/features/camera/presentation/camera_screen.dart';
import 'package:londonsnaps/features/chat/presentation/chats_screen.dart';
import 'package:londonsnaps/features/chat/presentation/chat_detail_screen.dart';
import 'package:londonsnaps/features/discover/presentation/discover_screen.dart';
import 'package:londonsnaps/features/discover/presentation/event_detail_screen.dart';
import 'package:londonsnaps/features/map/presentation/snap_map_screen.dart';
import 'package:londonsnaps/features/notifications/presentation/notification_screen.dart';
import 'package:londonsnaps/features/profile/presentation/profile_screen.dart';
import 'package:londonsnaps/features/stories/presentation/stories_screen.dart';
import 'package:londonsnaps/features/social/presentation/friends_screen.dart';
import 'package:londonsnaps/features/social/presentation/user_profile_screen.dart';
import 'package:londonsnaps/features/chat/presentation/new_chat_screen.dart';
import 'package:londonsnaps/features/profile/presentation/settings_screen.dart';
import 'package:londonsnaps/features/ai/presentation/ai_chat_screen.dart';
import 'package:londonsnaps/features/auth/presentation/university_verification_screen.dart';
import 'package:londonsnaps/features/auth/presentation/reset_password_screen.dart';
import 'package:londonsnaps/features/memories/presentation/memories_screen.dart';
import 'package:londonsnaps/features/memories/presentation/memory_detail_screen.dart';
import 'package:londonsnaps/features/profile/presentation/saved_content_screen.dart';
import 'package:londonsnaps/features/calls/presentation/incoming_call_screen.dart';
import 'package:londonsnaps/features/calls/presentation/active_call_screen.dart';
import 'package:londonsnaps/features/safety_walk/presentation/safety_walk_history_screen.dart';
import 'package:londonsnaps/shared/widgets/main_scaffold.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>();

// Smooth slide-up transition for detail screens
CustomTransitionPage<void> _slideUpTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween(begin: const Offset(0, 0.05), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic));
      final fadeTween = Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOut));
      return FadeTransition(
        opacity: animation.drive(fadeTween),
        child: SlideTransition(position: animation.drive(tween), child: child),
      );
    },
  );
}

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/welcome',
  refreshListenable: AuthProvider(),  // Re-evaluate redirects when auth state changes
  redirect: (context, state) {
    final authProvider = AuthProvider();
    final isAuthenticated = authProvider.isAuthenticated;
    final currentPath = state.uri.path;

    // Auth screens that logged-in users should not reach
    const authPaths = ['/welcome', '/login', '/register', '/reset-password'];

    // If authenticated and trying to reach login/register, redirect to camera
    if (isAuthenticated && authPaths.contains(currentPath)) {
      return '/camera';
    }

    // If NOT authenticated and trying to reach a protected screen, redirect to welcome
    if (!isAuthenticated && !authPaths.contains(currentPath)) {
      return '/welcome';
    }

    return null; // No redirect
  },
  routes: [
    // Welcome screen (before login)
    GoRoute(
      path: '/welcome',
      builder: (context, state) => const WelcomeScreen(),
    ),

    // Auth routes
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/university-verification',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const UniversityVerificationScreen()),
    ),
    GoRoute(
      path: '/reset-password',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final email = state.extra as String?;
        return _slideUpTransition(state, ResetPasswordScreen(email: email));
      },
    ),

    // Main app with bottom navigation
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(
          path: '/camera',
          builder: (context, state) => const CameraScreen(),
        ),
        GoRoute(
          path: '/chats',
          builder: (context, state) => const ChatsScreen(),
        ),
        GoRoute(
          path: '/stories',
          builder: (context, state) => const StoriesScreen(),
        ),
        GoRoute(
          path: '/map',
          builder: (context, state) => const SnapMapScreen(),
        ),
        GoRoute(
          path: '/discover',
          builder: (context, state) => const DiscoverScreen(),
        ),
      ],
    ),

    // Profile route (outside shell so it gets its own screen without bottom nav conflict)
    GoRoute(
      path: '/profile',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const ProfileScreen()),
    ),

    // Detail routes (outside shell so no bottom nav) with smooth transitions
    GoRoute(
      path: '/chats/:chatId',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final chatId = state.pathParameters['chatId']!;
        return _slideUpTransition(state, ChatDetailScreen(chatId: chatId));
      },
    ),
    GoRoute(
      path: '/discover/event/:eventId',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final eventId = state.pathParameters['eventId']!;
        return _slideUpTransition(state, EventDetailScreen(eventId: eventId));
      },
    ),
    GoRoute(
      path: '/friends',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const FriendsScreen()),
    ),
    GoRoute(
      path: '/chats/new',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const NewChatScreen()),
    ),
    GoRoute(
      path: '/settings',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const SettingsScreen()),
    ),
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const NotificationScreen()),
    ),
    GoRoute(
      path: '/profile/:userId',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final userId = state.pathParameters['userId']!;
        return _slideUpTransition(state, UserProfileScreen(userId: userId));
      },
    ),
    GoRoute(
      path: '/ai-chat',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const AIChatScreen()),
    ),
    GoRoute(
      path: '/memories',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const MemoriesScreen()),
    ),
    GoRoute(
      path: '/memories/:memoryId',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) {
        final memoryId = state.pathParameters['memoryId']!;
        final extra = state.extra as Map<String, dynamic>?;
        final isVault = extra?['isVault'] as bool? ?? false;
        return _slideUpTransition(state, MemoryDetailScreen(memoryId: memoryId, isVault: isVault));
      },
    ),
    GoRoute(
      path: '/saved-content',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const SavedContentScreen()),
    ),

    // Call routes
    GoRoute(
      path: '/incoming-call',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const IncomingCallScreen()),
    ),
    GoRoute(
      path: '/active-call',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const ActiveCallScreen()),
    ),

    // Safety Walk routes
    GoRoute(
      path: '/safety-walk/history',
      parentNavigatorKey: _rootNavigatorKey,
      pageBuilder: (context, state) => _slideUpTransition(state, const SafetyWalkHistoryScreen()),
    ),
  ],
);
