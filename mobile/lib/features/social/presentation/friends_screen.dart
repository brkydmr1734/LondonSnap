import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/chat/providers/chat_provider.dart';
import 'package:londonsnaps/features/social/models/social_models.dart';
import 'package:londonsnaps/features/social/providers/social_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final SocialProvider _provider = SocialProvider();
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _provider.addListener(_onUpdate);
    // Wire chat provider so accepting friend requests refreshes the chat list
    _provider.setChatProvider(ChatProvider());
    // Load all data in parallel
    Future.wait([
      _provider.loadFriends(),
      _provider.loadFriendRequests(),
      _provider.loadSuggestions(),
    ]);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Friends (${_provider.friends.length})'),
            Tab(text: 'Requests (${_provider.friendRequests.length})'),
            const Tab(text: 'Discover'),
          ],
          indicatorColor: AppTheme.primaryColor,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textMuted,
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search friends...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppTheme.surfaceColor,
              ),
              onChanged: (q) => _provider.searchUsers(q),
            ),
          ),
          // Search results
          if (_provider.searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _provider.searchResults.length,
                itemBuilder: (context, index) {
                  final user = _provider.searchResults[index];
                  final alreadySent = _provider.hasSentRequest(user.id);
                  return ListTile(
                    leading: _Avatar(url: user.avatarUrl),
                    title: Text(user.displayName),
                    subtitle: Text('@${user.username}',
                      style: const TextStyle(color: AppTheme.textMuted)),
                    trailing: ElevatedButton(
                      onPressed: alreadySent
                          ? null
                          : () async {
                              final ok = await _provider.sendFriendRequest(user.id);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(ok
                                    ? 'Friend request sent to ${user.displayName}'
                                    : _provider.error ?? 'Could not send request'),
                                duration: const Duration(seconds: 2),
                              ));
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        backgroundColor: alreadySent ? Colors.grey : null,
                      ),
                      child: Text(alreadySent ? 'Sent' : 'Add',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    onTap: () => context.push('/profile/${user.id}'),
                  );
                },
              ),
            )
          else
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _FriendsTab(provider: _provider),
                  _RequestsTab(provider: _provider),
                  _SuggestionsTab(provider: _provider),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FriendsTab extends StatelessWidget {
  final SocialProvider provider;
  const _FriendsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading && provider.friends.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.friends.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text('No friends yet', style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
          ],
        ),
      );
    }

    // Best friends section
    final bestFriends = provider.bestFriends;
    final otherFriends = provider.friends.where((f) => !f.isBestFriend).toList();

    return RefreshIndicator(
      onRefresh: () => provider.loadFriends(),
      child: ListView(
        children: [
          if (bestFriends.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Best Friends ⭐',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.warningColor)),
            ),
            ...bestFriends.map((f) => _FriendTile(friend: f, provider: provider)),
            const Divider(height: 16),
          ],
          if (otherFriends.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('All Friends',
                style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            ),
            ...otherFriends.map((f) => _FriendTile(friend: f, provider: provider)),
          ],
        ],
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final SocialFriend friend;
  final SocialProvider provider;

  const _FriendTile({required this.friend, required this.provider});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        children: [
          _Avatar(url: friend.user.avatarUrl),
          if (friend.user.isOnline)
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.successColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.backgroundColor, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          if (friend.emoji != null) ...[
            Text(friend.emoji!, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
          ],
          Expanded(child: Text(friend.user.displayName)),
          if (friend.isBestFriend)
            const Text('⭐', style: TextStyle(fontSize: 14)),
          if (friend.streak != null) ...[
            const SizedBox(width: 4),
            Text('${friend.streak!.count}', style: const TextStyle(fontSize: 12)),
            Text(friend.streak!.emoji, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
      subtitle: Text('@${friend.user.username}',
        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      onTap: () => context.push('/profile/${friend.user.id}'),
      onLongPress: () => _showFriendOptions(context),
    );
  }

  void _showFriendOptions(BuildContext context) {
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
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppTheme.textMuted, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(friend.isBestFriend ? Icons.star_border : Icons.star),
              title: Text(friend.isBestFriend ? 'Remove Best Friend' : 'Add Best Friend'),
              onTap: () {
                provider.updateFriend(friend.id, isBestFriend: !friend.isBestFriend);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: AppTheme.errorColor),
              title: const Text('Remove Friend', style: TextStyle(color: AppTheme.errorColor)),
              onTap: () {
                provider.removeFriend(friend.id);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: AppTheme.errorColor),
              title: const Text('Block', style: TextStyle(color: AppTheme.errorColor)),
              onTap: () {
                provider.blockUser(friend.user.id);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  final SocialProvider provider;
  const _RequestsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.friendRequests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline, size: 64, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text('No friend requests', style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadFriendRequests(),
      child: ListView.builder(
        itemCount: provider.friendRequests.length,
        itemBuilder: (context, index) {
          final request = provider.friendRequests[index];
          return ListTile(
            leading: _Avatar(url: request.fromUser.avatarUrl),
            title: Text(request.fromUser.displayName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${request.fromUser.username}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                if (request.mutualFriends > 0)
                  Text('${request.mutualFriends} mutual friends',
                    style: const TextStyle(color: AppTheme.primaryColor, fontSize: 11)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: AppTheme.successColor),
                  onPressed: () => provider.acceptFriendRequest(request.id),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: AppTheme.errorColor),
                  onPressed: () => provider.declineFriendRequest(request.id),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SuggestionsTab extends StatelessWidget {
  final SocialProvider provider;
  const _SuggestionsTab({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.suggestions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: AppTheme.textMuted),
            SizedBox(height: 16),
            Text('No suggestions', style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadSuggestions(),
      child: ListView.builder(
        itemCount: provider.suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = provider.suggestions[index];
          final alreadySent = provider.hasSentRequest(suggestion.user.id);
          return ListTile(
            leading: _Avatar(url: suggestion.user.avatarUrl),
            title: Text(suggestion.user.displayName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suggestion.reason.displayText,
                  style: const TextStyle(color: AppTheme.primaryColor, fontSize: 12)),
                if (suggestion.mutualFriends > 0)
                  Text('${suggestion.mutualFriends} mutual friends',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: alreadySent
                  ? null
                  : () async {
                      final ok = await provider.sendFriendRequest(suggestion.user.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok
                            ? 'Friend request sent to ${suggestion.user.displayName}'
                            : provider.error ?? 'Could not send request'),
                        duration: const Duration(seconds: 2),
                      ));
                    },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                backgroundColor: alreadySent ? Colors.grey : null,
              ),
              child: Text(alreadySent ? 'Sent' : 'Add',
                  style: const TextStyle(fontSize: 12)),
            ),
            onTap: () => context.push('/profile/${suggestion.user.id}'),
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  const _Avatar({this.url});

  @override
  Widget build(BuildContext context) {
    return AvatarWidget(avatarUrl: url, radius: 24);
  }
}
