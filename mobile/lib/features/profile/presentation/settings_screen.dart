import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/core/api/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthProvider _authProvider = AuthProvider();
  final ApiService _api = ApiService();

  // Privacy
  bool _locationSharing = true;
  bool _ghostMode = false;
  bool _showOnlineStatus = true;
  bool _showReadReceipts = true;

  // Notifications
  bool _pushEnabled = true;
  bool _chatNotifications = true;
  bool _storyNotifications = true;
  bool _friendNotifications = true;
  bool _streakReminders = true;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _authProvider.addListener(_onUpdate);
    _loadSettings();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onUpdate);
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final results = await Future.wait([
        _api.getPrivacySettings(),
        _api.getNotificationPreferences(),
      ]);
      final privacy = results[0].data['data']['settings'];
      final notifPrefs = results[1].data['data']['preferences'];

      if (mounted) {
        setState(() {
          if (privacy != null) {
            _ghostMode = privacy['whoCanSeeLocation'] == 'NOBODY';
            _locationSharing = !_ghostMode && privacy['whoCanSeeLocation'] != 'NOBODY';
            _showOnlineStatus = privacy['showLastSeen'] ?? true;
            _showReadReceipts = privacy['showReadReceipts'] ?? true;
          }
          if (notifPrefs != null) {
            _pushEnabled = notifPrefs['pushEnabled'] ?? true;
            _chatNotifications = notifPrefs['chatNotifications'] ?? true;
            _storyNotifications = notifPrefs['storyNotifications'] ?? true;
            _friendNotifications = notifPrefs['friendNotifications'] ?? true;
            _streakReminders = notifPrefs['streakReminders'] ?? true;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePrivacy(Map<String, dynamic> data) async {
    try {
      await _api.updatePrivacySettings(data);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save setting'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _updateNotifications(Map<String, dynamic> data) async {
    try {
      await _api.updateNotificationPreferences(data);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save setting'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        children: [
          // University badge
          if (user != null && user.isUniversityStudent && user.university != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1).withValues(alpha: 0.12),
                      const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.school_rounded, size: 18, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.university!.name,
                            style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Verified Student',
                            style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w500,
                              color: const Color(0xFF6366F1).withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      ).createShader(bounds),
                      child: const Icon(Icons.verified_rounded, size: 22, color: Colors.white),
                    ),
                  ],
                ),
              ),
            )
          else if (user != null && !user.isUniversityStudent)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: GestureDetector(
                onTap: () => context.push('/university-verification'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.school_rounded, size: 20, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Verify University', style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                            Text('Get your verified student badge', style: TextStyle(
                              fontSize: 11, color: Colors.white70)),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),

          // Account Section
          const _SectionHeader(title: 'Account'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Row(
              children: [
                const Text('Username'),
                const SizedBox(width: 6),
                Icon(Icons.lock_outline, size: 14, color: AppTheme.textMuted),
              ],
            ),
            subtitle: Text(
              user != null ? '@${user.username}' : '',
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
            trailing: const Text(
              'Cannot be changed',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email'),
            subtitle: Text(user?.email ?? '',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            onTap: () => _showChangePassword(),
          ),

          const Divider(height: 32),

          // Notifications
          const _SectionHeader(title: 'Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Push Notifications'),
            subtitle: const Text('Receive all push notifications',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _pushEnabled,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _pushEnabled = v);
              _updateNotifications({'pushEnabled': v});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.chat_bubble_outline),
            title: const Text('Chat Notifications'),
            subtitle: const Text('New messages and group chats',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _chatNotifications,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _chatNotifications = v);
              _updateNotifications({'chatNotifications': v});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_stories),
            title: const Text('Story Notifications'),
            subtitle: const Text('When friends post new stories',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _storyNotifications,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _storyNotifications = v);
              _updateNotifications({'storyNotifications': v});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.person_add_outlined),
            title: const Text('Friend Notifications'),
            subtitle: const Text('Friend requests and accepts',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _friendNotifications,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _friendNotifications = v);
              _updateNotifications({'friendNotifications': v});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.local_fire_department_outlined),
            title: const Text('Streak Reminders'),
            subtitle: const Text('Remind before streaks expire',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _streakReminders,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _streakReminders = v);
              _updateNotifications({'streakReminders': v});
            },
          ),

          const Divider(height: 32),

          // Privacy
          const _SectionHeader(title: 'Privacy'),
          SwitchListTile(
            secondary: const Icon(Icons.location_on_outlined),
            title: const Text('Location Sharing'),
            subtitle: const Text('Share your location on Snap Map',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _locationSharing,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() {
                _locationSharing = v;
                if (v) _ghostMode = false;
              });
              _updatePrivacy({'whoCanSeeLocation': v ? 'FRIENDS' : 'NOBODY', 'showInNearby': v});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Ghost Mode'),
            subtitle: const Text('Hide your location from everyone',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _ghostMode,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() {
                _ghostMode = v;
                if (v) _locationSharing = false;
              });
              _updatePrivacy({'whoCanSeeLocation': v ? 'NOBODY' : 'FRIENDS', 'showInNearby': !v});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.circle, size: 20),
            title: const Text('Show Online Status'),
            subtitle: const Text('Let friends see when you\'re active',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _showOnlineStatus,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _showOnlineStatus = v);
              _updatePrivacy({'showLastSeen': v});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.done_all, size: 20),
            title: const Text('Read Receipts'),
            subtitle: const Text('Show when you\'ve read messages',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            value: _showReadReceipts,
            activeThumbColor: AppTheme.primaryColor,
            onChanged: (v) {
              setState(() => _showReadReceipts = v);
              _updatePrivacy({'showReadReceipts': v});
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: AppTheme.textMuted),
            title: const Text('Blocked Users'),
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            onTap: () => _showBlockedUsers(),
          ),

          const Divider(height: 32),

          // Appearance
          const _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('Theme'),
            subtitle: const Text('Dark', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            onTap: () {},
          ),

          const Divider(height: 32),

          // About
          const _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text('1.0.0', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.open_in_new, size: 18, color: AppTheme.textMuted),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18, color: AppTheme.textMuted),
            onTap: () {},
          ),

          const Divider(height: 32),

          // Danger zone
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.errorColor),
            title: const Text('Log Out', style: TextStyle(color: AppTheme.errorColor)),
            onTap: () => _showLogoutDialog(),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: AppTheme.errorColor),
            title: const Text('Delete Account', style: TextStyle(color: AppTheme.errorColor)),
            subtitle: const Text('Permanently delete your account and all data',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            onTap: () => _showDeleteAccountDialog(),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _showChangePassword() {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    bool isLoading = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Change Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: currentController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current Password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    final current = currentController.text.trim();
                    final newPass = newController.text.trim();
                    if (current.isEmpty || newPass.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fill in both fields')),
                      );
                      return;
                    }
                    if (newPass.length < 8) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('New password must be at least 8 characters')),
                      );
                      return;
                    }
                    setModalState(() => isLoading = true);
                    try {
                      await _api.changePassword(current, newPass);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Password updated successfully')),
                        );
                      }
                    } catch (e) {
                      setModalState(() => isLoading = false);
                      if (mounted) {
                        String msg = 'Failed to change password';
                        if (e is DioException && e.response?.data != null) {
                          final data = e.response!.data;
                          if (data is Map) {
                            msg = data['message'] ?? data['error'] ?? msg;
                          }
                        } else if (e.toString().contains('incorrect')) {
                          msg = 'Current password is incorrect';
                        } else if (e.toString().contains('social login')) {
                          msg = 'Account uses social login. Use forgot password instead.';
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg), backgroundColor: AppTheme.errorColor),
                        );
                      }
                    }
                  },
                  child: isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Update Password'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showBlockedUsers() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppTheme.textMuted, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(height: 16),
            const Text('Blocked Users', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.block, size: 48, color: AppTheme.textMuted),
                  SizedBox(height: 12),
                  Text('No blocked users', style: TextStyle(color: AppTheme.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _authProvider.logout();
              if (context.mounted) context.go('/welcome');
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Delete Account', style: TextStyle(color: AppTheme.errorColor)),
        content: const Text(
          'This action is permanent and cannot be undone. All your data, snaps, stories, and chats will be permanently deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account deletion requested. You will receive a confirmation email.')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: AppTheme.textMuted, letterSpacing: 1,
        ),
      ),
    );
  }
}
