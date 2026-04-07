import 'package:flutter/material.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/discover/providers/discover_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

class EventDetailScreen extends StatefulWidget {
  final String eventId;
  const EventDetailScreen({super.key, required this.eventId});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final DiscoverProvider _provider = DiscoverProvider();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onUpdate);
    _provider.loadEventDetail(widget.eventId);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final event = _provider.selectedEvent;

    return Scaffold(
      body: _provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : event == null
              ? const Center(child: Text('Event not found'))
              : CustomScrollView(
                  slivers: [
                    // Cover image
                    SliverAppBar(
                      expandedHeight: 250,
                      pinned: true,
                      flexibleSpace: FlexibleSpaceBar(
                        background: event.coverImageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: event.coverImageUrl!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                decoration: const BoxDecoration(
                                  gradient: AppTheme.primaryGradient),
                                child: Center(
                                  child: Icon(event.category.icon,
                                    size: 64, color: Colors.white54),
                                ),
                              ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Category chip
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(event.category.icon, size: 14,
                                    color: AppTheme.primaryColor),
                                  const SizedBox(width: 4),
                                  Text(event.category.displayName,
                                    style: const TextStyle(
                                      fontSize: 12, color: AppTheme.primaryColor)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Title
                            Text(event.title,
                              style: const TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),
                            // Date & Time
                            _InfoRow(
                              icon: Icons.calendar_today,
                              title: DateFormat('EEEE, MMMM d, y').format(event.startDate),
                              subtitle: '${DateFormat('h:mm a').format(event.startDate)} - ${DateFormat('h:mm a').format(event.endDate)}',
                            ),
                            const SizedBox(height: 12),
                            // Location
                            _InfoRow(
                              icon: Icons.location_on,
                              title: event.location.name,
                              subtitle: event.location.address,
                            ),
                            const SizedBox(height: 12),
                            // Organizer
                            _InfoRow(
                              icon: Icons.person,
                              title: 'Organized by ${event.organizer.name}',
                              subtitle: event.organizer.isVerified ? 'Verified' : null,
                            ),
                            const SizedBox(height: 12),
                            // Attendees
                            _InfoRow(
                              icon: Icons.people,
                              title: '${event.attendeeCount} attending',
                              subtitle: event.maxAttendees > 0
                                  ? '${event.maxAttendees - event.attendeeCount} spots left'
                                  : null,
                            ),
                            // Price
                            if (!event.isFree) ...[
                              const SizedBox(height: 12),
                              _InfoRow(
                                icon: Icons.attach_money,
                                title: '${event.currency ?? '£'}${event.price?.toStringAsFixed(2) ?? '0.00'}',
                                subtitle: null,
                              ),
                            ],
                            const SizedBox(height: 24),
                            // Description
                            const Text('About',
                              style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text(event.description,
                              style: const TextStyle(
                                color: AppTheme.textSecondary, height: 1.5)),
                            // Tags
                            if (event.tags.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8, runSpacing: 8,
                                children: event.tags.map((tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceColor,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text('#$tag',
                                    style: const TextStyle(
                                      fontSize: 12, color: AppTheme.textSecondary)),
                                )).toList(),
                              ),
                            ],
                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
      // Attend button
      bottomNavigationBar: event != null
          ? Container(
              padding: EdgeInsets.only(
                left: 16, right: 16, top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: const BoxDecoration(
                color: AppTheme.cardColor,
                border: Border(
                  top: BorderSide(color: AppTheme.surfaceColor, width: 0.5)),
              ),
              child: Row(
                children: [
                  if (!event.isFree)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Price',
                            style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted)),
                          Text(
                            '${event.currency ?? '£'}${event.price?.toStringAsFixed(2) ?? ''}',
                            style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: event.isSoldOut
                          ? null
                          : () {
                              if (event.isAttending) {
                                _provider.cancelAttendance(event.id);
                              } else {
                                _provider.attendEvent(event.id);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: event.isAttending
                            ? AppTheme.surfaceColor
                            : AppTheme.primaryColor,
                      ),
                      child: Text(
                        event.isSoldOut
                            ? 'Sold Out'
                            : event.isAttending
                                ? 'Cancel Attendance'
                                : 'Attend Event',
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _InfoRow({
    required this.icon, required this.title, this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              if (subtitle != null)
                Text(subtitle!,
                  style: const TextStyle(
                    fontSize: 13, color: AppTheme.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}
