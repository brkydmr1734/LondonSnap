import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/notifications/providers/notification_provider.dart';
import 'package:londonsnaps/shared/widgets/connectivity_banner.dart';

// Import all tab screens for PageView
import 'package:londonsnaps/features/camera/presentation/camera_screen.dart';
import 'package:londonsnaps/features/chat/presentation/chats_screen.dart';
import 'package:londonsnaps/features/stories/presentation/stories_screen.dart';
import 'package:londonsnaps/features/map/presentation/snap_map_screen.dart';
import 'package:londonsnaps/features/discover/presentation/discover_screen.dart';

class MainScaffold extends StatefulWidget {
  final Widget child;

  const MainScaffold({
    super.key,
    required this.child,
  });

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  final NotificationProvider _notificationProvider = NotificationProvider();
  
  // PageController for swipe navigation - Camera (index 1) is the initial page
  late PageController _pageController;
  int _currentPage = 1; // Camera is default
  
  // Page order: Chat | Camera | Stories | Map | Discover
  static const List<String> _routes = [
    '/chats',
    '/camera',
    '/stories',
    '/map',
    '/discover',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1); // Start on Camera
    _notificationProvider.addListener(_onNotificationChange);
    // Defer fetch to avoid setState during build when NotificationBell listens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationProvider.fetchNotifications();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _notificationProvider.removeListener(_onNotificationChange);
    super.dispose();
  }

  void _onNotificationChange() {
    if (mounted) setState(() {});
  }

  /// Calculate the current page index from GoRouter location
  int _calculatePageIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/chats')) return 0;
    if (location.startsWith('/camera')) return 1;
    if (location.startsWith('/stories')) return 2;
    if (location.startsWith('/map')) return 3;
    if (location.startsWith('/discover')) return 4;
    // Profile is no longer in bottom nav, but if user navigates here, stay on chats
    if (location.startsWith('/profile')) return 0;
    return 1; // Default to camera
  }

  /// Called when user swipes to a new page
  void _onPageChanged(int index) {
    if (_currentPage != index) {
      setState(() => _currentPage = index);
      // Update GoRouter location to match
      context.go(_routes[index]);
    }
  }

  /// Called when user taps on bottom nav
  void _onNavTapped(int index) {
    if (_currentPage != index) {
      setState(() => _currentPage = index);
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      context.go(_routes[index]);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync PageController with GoRouter when location changes (e.g., deep links)
    final pageIndex = _calculatePageIndex(context);
    if (pageIndex != _currentPage) {
      _currentPage = pageIndex;
      // Jump without animation when coming from deep link
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients && _pageController.page?.round() != pageIndex) {
          _pageController.jumpToPage(pageIndex);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ConnectivityBanner(),
          // Swipeable PageView containing all tab screens
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: _onPageChanged,
              children: const [
                ChatsScreen(),    // 0 - Left
                CameraScreen(),   // 1 - Center (Home)
                StoriesScreen(),  // 2
                SnapMapScreen(),  // 3
                DiscoverScreen(), // 4 - Right
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildSnapchatBottomNav(),
    );
  }

  /// Snapchat-style minimal bottom navigation
  Widget _buildSnapchatBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        border: Border(
          top: BorderSide(
            color: AppTheme.surfaceColor.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SnapNavItem(
                    icon: Icons.chat_bubble_rounded,
                    isSelected: _currentPage == 0,
                    onTap: () => _onNavTapped(0),
                    badge: 3, // Chat badge
                  ),
                  _SnapNavItem(
                    icon: Icons.camera_alt_rounded,
                    isSelected: _currentPage == 1,
                    onTap: () => _onNavTapped(1),
                    isCenter: true,
                  ),
                  _SnapNavItem(
                    icon: Icons.auto_stories_rounded,
                    isSelected: _currentPage == 2,
                    onTap: () => _onNavTapped(2),
                  ),
                  _SnapNavItem(
                    icon: Icons.location_on_rounded,
                    isSelected: _currentPage == 3,
                    onTap: () => _onNavTapped(3),
                  ),
                  _SnapNavItem(
                    icon: Icons.explore_rounded,
                    isSelected: _currentPage == 4,
                    onTap: () => _onNavTapped(4),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Page indicator dots
              _buildPageIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the page indicator dots
  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryColor : AppTheme.textMuted.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

}

/// Snapchat-style minimal nav item (icon only, no label)
class _SnapNavItem extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badge;
  final bool isCenter;

  const _SnapNavItem({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.badge,
    this.isCenter = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Center camera icon gets a special ring when selected
            if (isCenter && isSelected)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryColor,
                    width: 2,
                  ),
                ),
              ),
            // Icon with selection effect
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                icon,
                color: isSelected 
                    ? AppTheme.primaryColor 
                    : AppTheme.textMuted,
                size: isCenter ? 26 : 24,
              ),
            ),
            // Badge
            if (badge != null && badge! > 0)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppTheme.errorColor,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    badge! > 9 ? '9+' : '$badge',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
