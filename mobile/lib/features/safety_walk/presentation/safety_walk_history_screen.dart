import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/features/safety_walk/models/safety_walk_models.dart';
import 'package:londonsnaps/features/safety_walk/providers/safety_walk_provider.dart';
import 'package:londonsnaps/features/safety_walk/presentation/walk_rating_sheet.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';

/// Colors for the history screen
class _HistoryColors {
  static const background = Color(0xFF1C1C1E);
  static const card = Color(0xFF2C2C2E);
  static const textSecondary = Color(0xFF8E8E93);
  static const safetyGreen = Color(0xFF00C853);
  static const primaryColor = Color(0xFF6366F1);
  static const warningRed = Color(0xFFE63946);
}

/// Screen displaying the user's Safety Walk history
class SafetyWalkHistoryScreen extends StatefulWidget {
  const SafetyWalkHistoryScreen({super.key});

  @override
  State<SafetyWalkHistoryScreen> createState() => _SafetyWalkHistoryScreenState();
}

class _SafetyWalkHistoryScreenState extends State<SafetyWalkHistoryScreen> {
  final SafetyWalkProvider _provider = SafetyWalkProvider();
  final ScrollController _scrollController = ScrollController();
  bool _hasLoadedMore = false;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderUpdate);
    _loadHistory();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onProviderUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    await _provider.loadHistory();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_provider.isLoading &&
        _provider.walkHistory.length < _provider.historyTotal &&
        !_hasLoadedMore) {
      _hasLoadedMore = true;
      _provider.loadHistory(offset: _provider.walkHistory.length).then((_) {
        _hasLoadedMore = false;
      });
    }
  }

  void _showRatingSheet(SafetyWalk walk) {
    final companion = walk.companion ?? walk.requester;
    if (companion == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WalkRatingSheet(
        companion: companion,
        walkId: walk.id,
        onSubmitRating: (score, comment) async {
          final navigator = Navigator.of(ctx);
          await _provider.rateCompanion(
            companion.id,
            score,
            comment: comment,
            walkId: walk.id,
          );
          navigator.pop();
          if (mounted) {
            _loadHistory(); // Refresh after rating
          }
        },
        onSkip: () => Navigator.pop(ctx),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '--';
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[date.month - 1]} ${date.day}';
    }
  }

  String _formatDuration(SafetyWalk walk) {
    if (walk.startedAt == null) return '--';
    final endTime = walk.endedAt ?? DateTime.now();
    final duration = endTime.difference(walk.startedAt!);
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} min';
    }
    final hours = duration.inHours;
    final mins = duration.inMinutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  String _getTransportLabel(String mode) {
    switch (mode.toUpperCase()) {
      case 'WALKING':
        return 'Walking';
      case 'BUS':
        return 'Bus';
      case 'TUBE':
        return 'Tube';
      case 'MIXED':
        return 'Mixed';
      default:
        return 'Walking';
    }
  }

  IconData _getTransportIcon(String mode) {
    switch (mode.toUpperCase()) {
      case 'WALKING':
        return Icons.directions_walk;
      case 'BUS':
        return Icons.directions_bus;
      case 'TUBE':
        return Icons.subway;
      case 'MIXED':
        return Icons.transfer_within_a_station;
      default:
        return Icons.directions_walk;
    }
  }

  String _getStatusLabel(SafetyWalkStatus status) {
    switch (status) {
      case SafetyWalkStatus.completed:
        return 'Completed';
      case SafetyWalkStatus.cancelled:
        return 'Cancelled';
      case SafetyWalkStatus.sosTriggered:
        return 'SOS Triggered';
      default:
        return 'Done';
    }
  }

  Color _getStatusColor(SafetyWalkStatus status) {
    switch (status) {
      case SafetyWalkStatus.completed:
        return _HistoryColors.safetyGreen;
      case SafetyWalkStatus.cancelled:
        return _HistoryColors.textSecondary;
      case SafetyWalkStatus.sosTriggered:
        return _HistoryColors.warningRed;
      default:
        return _HistoryColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _HistoryColors.background,
      appBar: AppBar(
        backgroundColor: _HistoryColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Walk History',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_provider.isLoading && _provider.walkHistory.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: _HistoryColors.primaryColor,
          strokeWidth: 2,
        ),
      );
    }

    if (_provider.error != null && _provider.walkHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: _HistoryColors.textSecondary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              _provider.error!,
              style: const TextStyle(
                color: _HistoryColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _loadHistory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _HistoryColors.primaryColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_provider.walkHistory.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: _HistoryColors.primaryColor,
      backgroundColor: _HistoryColors.card,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _provider.walkHistory.length + (_provider.isLoading ? 1 : 0),
        separatorBuilder: (_, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= _provider.walkHistory.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: _HistoryColors.primaryColor,
                  strokeWidth: 2,
                ),
              ),
            );
          }
          return _buildWalkCard(_provider.walkHistory[index]);
        },
      ),
    );
  }

  Widget _buildEmptyState() {
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
                color: _HistoryColors.card,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shield_outlined,
                color: _HistoryColors.textSecondary.withValues(alpha: 0.5),
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Walk History',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your completed Safety Walks will appear here',
              style: TextStyle(
                color: _HistoryColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalkCard(SafetyWalk walk) {
    final companion = walk.companion ?? walk.requester;

    return GestureDetector(
      onTap: () {
        if (walk.status == SafetyWalkStatus.completed) {
          _showRatingSheet(walk);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _HistoryColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Top row: Avatar, name, duration, transport
            Row(
              children: [
                // Avatar
                AvatarWidget(
                  avatarUrl: companion?.avatarUrl,
                  radius: 22,
                  showBorder: true,
                  borderColor: _HistoryColors.primaryColor.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 12),
                // Name and transport mode
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companion?.displayName ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            _getTransportIcon(walk.transportMode),
                            color: _HistoryColors.textSecondary,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getTransportLabel(walk.transportMode),
                            style: const TextStyle(
                              color: _HistoryColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Duration
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        color: Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(walk),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Bottom row: Date, rating, status
            Row(
              children: [
                // Date
                Text(
                  _formatDate(walk.createdAt),
                  style: const TextStyle(
                    color: _HistoryColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                // Safety score if available
                if (walk.safetyScore != null) ...[
                  Icon(
                    Icons.shield,
                    color: _HistoryColors.safetyGreen.withValues(alpha: 0.8),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    walk.safetyScore!.toStringAsFixed(0),
                    style: TextStyle(
                      color: _HistoryColors.safetyGreen.withValues(alpha: 0.8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else if (walk.status == SafetyWalkStatus.completed) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _HistoryColors.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'View details',
                      style: TextStyle(
                        color: _HistoryColors.primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                // Status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(walk.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getStatusLabel(walk.status),
                    style: TextStyle(
                      color: _getStatusColor(walk.status),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
