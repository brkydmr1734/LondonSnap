import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/discover/models/discover_models.dart';
import 'package:londonsnaps/features/discover/providers/discover_provider.dart';
import 'package:londonsnaps/features/discover/widgets/tube_status_widget.dart';
import 'package:londonsnaps/features/social/providers/social_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:londonsnaps/shared/widgets/notification_bell.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final DiscoverProvider _provider = DiscoverProvider();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onUpdate);
    _provider.loadDiscoverFeed();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showCategoryFilter,
          ),
          const NotificationBell(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/ai-chat'),
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.auto_awesome, color: Colors.white),
      ),
      body: _provider.isLoading && _provider.events.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _provider.loadDiscoverFeed(),
              child: CustomScrollView(
                slivers: [
                    // Tube Status Widget - Live London Underground status
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: TubeStatusWidget(),
                      ),
                    ),
                    // Search bar
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search users, events, places...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      _provider.setSearchQuery('');
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: AppTheme.surfaceColor,
                          ),
                          onChanged: (q) => _provider.setSearchQuery(q),
                        ),
                      ),
                    ),
                    // Category chips
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            _CategoryChip(
                              label: 'All',
                              icon: Icons.apps,
                              isSelected: _provider.selectedCategory == null,
                              onTap: () => _provider.setSelectedCategory(null),
                            ),
                            ...EventCategory.values.map((cat) => _CategoryChip(
                              label: cat.displayName,
                              icon: cat.icon,
                              isSelected: _provider.selectedCategory == cat,
                              onTap: () => _provider.setSelectedCategory(cat),
                            )),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    // Events section
                    if (_provider.events.isNotEmpty) ...[
                      SliverToBoxAdapter(child: _SectionHeader(
                        title: 'Events Near You',
                        onSeeAll: () => _showAllEvents(),
                      )),
                      SliverToBoxAdapter(child: SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _provider.events.length,
                          itemBuilder: (context, index) {
                            final event = _provider.events[index];
                            return _EventCard(
                              event: event,
                              onTap: () => context.push('/discover/event/${event.id}'),
                            );
                          },
                        ),
                      )),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                    // Nearby users
                    if (_provider.nearbyUsers.isNotEmpty) ...[
                      SliverToBoxAdapter(child: _SectionHeader(
                        title: 'People Nearby',
                        onSeeAll: () => _showAllNearby(),
                      )),
                      SliverToBoxAdapter(child: SizedBox(
                        height: 110,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _provider.nearbyUsers.length,
                          itemBuilder: (context, index) {
                            final user = _provider.nearbyUsers[index];
                            return _NearbyUserItem(
                              user: user,
                              onTap: () => context.push('/profile/${user.id}'),
                            );
                          },
                        ),
                      )),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                    // Match profiles
                    if (_provider.matches.isNotEmpty) ...[
                      SliverToBoxAdapter(child: _SectionHeader(
                        title: 'People You May Know',
                        onSeeAll: () => context.push('/friends'),
                      )),
                      SliverToBoxAdapter(child: SizedBox(
                        height: 180,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _provider.matches.length,
                          itemBuilder: (context, index) {
                            final match = _provider.matches[index];
                            return _MatchCard(match: match);
                          },
                        ),
                      )),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    ],
                    // London areas - using SliverGrid instead of shrinkWrap GridView
                    SliverToBoxAdapter(child: _SectionHeader(title: 'Explore London', onSeeAll: () => context.go('/map'))),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 1.5,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final area = LondonAreaInfo.popularAreas[index];
                            return _AreaCard(area: area);
                          },
                          childCount: LondonAreaInfo.popularAreas.length,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
    );
  }

  void _showAllEvents() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8, minChildSize: 0.4, maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppTheme.textMuted, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('All Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _provider.events.length,
                itemBuilder: (context, index) {
                  final event = _provider.events[index];
                  return ListTile(
                    leading: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor, borderRadius: BorderRadius.circular(8)),
                      child: Icon(event.category.icon, color: AppTheme.primaryColor),
                    ),
                    title: Text(event.title),
                    subtitle: Text('${DateFormat('MMM d').format(event.startDate)} · ${event.location.name}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    trailing: Text('${event.attendeeCount} going',
                        style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor)),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/discover/event/${event.id}');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllNearby() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppTheme.textMuted, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('People Nearby', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _provider.nearbyUsers.length,
                itemBuilder: (context, index) {
                  final user = _provider.nearbyUsers[index];
                  return ListTile(
                    leading: Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceColor, shape: BoxShape.circle),
                      child: user.avatarUrl != null
                          ? ClipOval(child: CachedNetworkImage(imageUrl: user.avatarUrl!, fit: BoxFit.cover))
                          : const Icon(Icons.person, color: AppTheme.textMuted),
                    ),
                    title: Text(user.displayName),
                    subtitle: Text('${user.formattedDistance} away',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/profile/${user.id}');
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCategoryFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4, decoration: BoxDecoration(
              color: AppTheme.textMuted, borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(height: 16),
            const Text('Filter by Category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.apps),
              title: const Text('All'),
              trailing: _provider.selectedCategory == null
                  ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
              onTap: () { _provider.setSelectedCategory(null); Navigator.pop(ctx); },
            ),
            ...EventCategory.values.map((cat) => ListTile(
              leading: Icon(cat.icon),
              title: Text(cat.displayName),
              trailing: _provider.selectedCategory == cat
                  ? const Icon(Icons.check, color: AppTheme.primaryColor) : null,
              onTap: () { _provider.setSelectedCategory(cat); Navigator.pop(ctx); },
            )),
            const SizedBox(height: 16),
          ],
        ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label, required this.icon,
    required this.isSelected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14,
              color: isSelected ? Colors.white : AppTheme.textMuted),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
        selected: isSelected,
        onSelected: (_) => onTap(),
        backgroundColor: AppTheme.surfaceColor,
        selectedColor: AppTheme.primaryColor,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppTheme.textSecondary,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;

  const _SectionHeader({required this.title, required this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final DiscoverEvent event;
  final VoidCallback onTap;

  const _EventCard({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: event.coverImageUrl == null ? AppTheme.primaryGradient : null,
        ),
        child: Stack(
          children: [
            if (event.coverImageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: event.coverImageUrl!,
                  fit: BoxFit.cover,
                  width: 260,
                  height: 200,
                ),
              ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(event.category.icon, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(event.category.displayName,
                              style: const TextStyle(fontSize: 11, color: Colors.white)),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          DateFormat('MMM d').format(event.startDate),
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white,
                    ),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 12, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(event.location.name,
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.people, size: 12, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text('${event.attendeeCount}',
                        style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                  if (!event.isFree) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${event.currency ?? '£'}${event.price?.toStringAsFixed(2) ?? ''}',
                      style: const TextStyle(
                        fontSize: 13, color: AppTheme.warningColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyUserItem extends StatelessWidget {
  final NearbyUser user;
  final VoidCallback onTap;

  const _NearbyUserItem({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 60, height: 60,
                  decoration: const BoxDecoration(
                    color: AppTheme.surfaceColor, shape: BoxShape.circle,
                  ),
                  child: user.avatarUrl != null
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: user.avatarUrl!, fit: BoxFit.cover))
                      : const Icon(Icons.person, color: AppTheme.textMuted),
                ),
                if (user.isOnline)
                  Positioned(
                    right: 2, bottom: 2,
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
            const SizedBox(height: 4),
            SizedBox(
              width: 64,
              child: Text(
                user.displayName.split(' ').first,
                style: const TextStyle(fontSize: 11),
                maxLines: 1, textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              user.formattedDistance,
              style: const TextStyle(fontSize: 10, color: AppTheme.textMuted),
            ),
            if (user.mutualFriends > 0)
              Text(
                '${user.mutualFriends} mutual',
                style: const TextStyle(fontSize: 9, color: AppTheme.primaryColor),
              ),
          ],
        ),
      ),
    );
  }
}

class _MatchCard extends StatefulWidget {
  final MatchProfile match;
  const _MatchCard({required this.match});

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  bool _sent = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56, height: 56,
            decoration: const BoxDecoration(
              color: AppTheme.surfaceColor, shape: BoxShape.circle,
            ),
            child: widget.match.avatarUrl != null
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: widget.match.avatarUrl!, fit: BoxFit.cover))
                : const Icon(Icons.person, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            widget.match.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          if (widget.match.university != null)
            Text(
              widget.match.university!,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 6),
          if (widget.match.mutualFriends > 0)
            Text(
              '${widget.match.mutualFriends} mutual friends',
              style: const TextStyle(fontSize: 10, color: AppTheme.primaryColor),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 28,
            child: ElevatedButton(
              onPressed: _sent
                  ? null
                  : () async {
                      final social = SocialProvider();
                      await social.sendFriendRequest(widget.match.id);
                      if (mounted) setState(() => _sent = true);
                    },
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontSize: 11),
              ),
              child: Text(_sent ? 'Sent' : 'Add Friend'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AreaCard extends StatelessWidget {
  final LondonAreaInfo area;
  const _AreaCard({required this.area});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(area.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(area.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            Text(
              area.description,
              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
