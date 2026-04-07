import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/chat/providers/chat_provider.dart';
import 'package:londonsnaps/features/social/models/social_models.dart';
import 'package:londonsnaps/features/social/providers/social_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final SocialProvider _socialProvider = SocialProvider();
  final ChatProvider _chatProvider = ChatProvider();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _socialProvider.addListener(_onUpdate);
    _socialProvider.loadFriends();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _socialProvider.removeListener(_onUpdate);
    _searchController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  List<SocialFriend> get _filteredFriends {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return _socialProvider.friends;
    return _socialProvider.friends.where((friend) {
      return friend.user.displayName.toLowerCase().contains(query) ||
          friend.user.username.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _startChat() async {
    if (_selectedIds.isEmpty) return;

    // For group chats, show name dialog first
    if (_selectedIds.length > 1) {
      final groupName = await _showGroupNameDialog();
      if (groupName == null) return; // User cancelled
      await _createChat(groupName.isEmpty ? null : groupName);
    } else {
      // Direct chat - navigate immediately
      await _createChat(null);
    }
  }

  Future<String?> _showGroupNameDialog() async {
    _groupNameController.clear();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Name Your Group',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show selected members
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedIds.take(5).map((id) {
                final friend = _socialProvider.friends.firstWhere(
                  (f) => f.user.id == id,
                  orElse: () => _socialProvider.friends.first,
                );
                return CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.surfaceColor,
                  child: AvatarWidget(avatarUrl: friend.user.avatarUrl, radius: 18),
                );
              }).toList(),
            ),
            if (_selectedIds.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '+${_selectedIds.length - 5} more',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _groupNameController,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Group name (optional)',
                hintStyle: const TextStyle(color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _groupNameController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createChat(String? groupName) async {
    setState(() => _isCreating = true);

    final chat = await _chatProvider.createChat(
      memberIds: _selectedIds.toList(),
      name: groupName,
    );

    if (mounted) {
      setState(() => _isCreating = false);
      if (chat != null) {
        context.go('/chats/${chat.id}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_chatProvider.error ?? 'Failed to create chat'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGroupMode = _selectedIds.length > 1;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: _buildAppBar(isGroupMode),
      body: Column(
        children: [
          // Selected friends chips
          if (_selectedIds.isNotEmpty) _buildSelectedChips(),
          // Search bar
          _buildSearchBar(),
          // Friends list
          Expanded(child: _buildFriendsList()),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isGroupMode) {
    return AppBar(
      backgroundColor: AppTheme.backgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close, color: AppTheme.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        isGroupMode ? 'New Group' : 'New Chat',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary,
        ),
      ),
      centerTitle: true,
      actions: [
        if (_selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isCreating
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _startChat,
                    child: Text(
                      isGroupMode ? 'Create' : 'Chat',
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _buildSelectedChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _selectedIds.map((id) {
            final friend = _socialProvider.friends.firstWhere(
              (f) => f.user.id == id,
              orElse: () => _socialProvider.friends.first,
            );
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SelectedFriendChip(
                friend: friend,
                onRemove: () => setState(() => _selectedIds.remove(id)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search friends...',
          hintStyle: const TextStyle(color: AppTheme.textMuted),
          prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppTheme.textMuted, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          filled: true,
          fillColor: AppTheme.surfaceColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildFriendsList() {
    if (_socialProvider.isLoading && _socialProvider.friends.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryColor),
      );
    }

    if (_filteredFriends.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _filteredFriends.length,
      itemBuilder: (context, index) {
        final friend = _filteredFriends[index];
        final isSelected = _selectedIds.contains(friend.user.id);
        return _FriendListItem(
          friend: friend,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedIds.remove(friend.user.id);
              } else {
                _selectedIds.add(friend.user.id);
              }
            });
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final hasSearchQuery = _searchController.text.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearchQuery ? Icons.search_off : Icons.people_outline,
                size: 40,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasSearchQuery ? 'No friends found' : 'No friends yet',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearchQuery
                  ? 'Try a different search term'
                  : 'Add friends to start chatting',
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            if (!hasSearchQuery) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.push('/friends'),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Find Friends'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Selected friend chip widget
class _SelectedFriendChip extends StatelessWidget {
  final SocialFriend friend;
  final VoidCallback onRemove;

  const _SelectedFriendChip({
    required this.friend,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWidget(avatarUrl: friend.user.avatarUrl, radius: 14),
          const SizedBox(width: 8),
          Text(
            friend.user.displayName,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// Friend list item widget
class _FriendListItem extends StatelessWidget {
  final SocialFriend friend;
  final bool isSelected;
  final VoidCallback onTap;

  const _FriendListItem({
    required this.friend,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Avatar with online indicator
              Stack(
                children: [
                  AvatarWidget(avatarUrl: friend.user.avatarUrl, radius: 24),
                  if (friend.user.isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.successColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.backgroundColor, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // Name and username
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.user.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${friend.user.username}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Selection indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryColor : AppTheme.textMuted,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
