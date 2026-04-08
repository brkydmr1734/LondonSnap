import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/features/calls/providers/call_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';
import 'package:intl/intl.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final ApiService _api = ApiService();
  final AuthProvider _auth = AuthProvider();
  final CallProvider _callProvider = CallProvider();
  List<dynamic> _calls = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _offset = 0;
  static const _limit = 30;

  @override
  void initState() {
    super.initState();
    _loadCalls();
  }

  Future<void> _loadCalls({bool refresh = false}) async {
    if (refresh) {
      _offset = 0;
      _hasMore = true;
    }

    try {
      final response = await _api.getCallHistory(limit: _limit, offset: _offset);
      final data = response.data['data'];
      final calls = data['calls'] as List;
      final total = data['total'] as int;

      setState(() {
        if (refresh) {
          _calls = calls;
        } else {
          _calls.addAll(calls);
        }
        _offset = _calls.length;
        _hasMore = _calls.length < total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load call history'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatTime(String dateStr) {
    final date = DateTime.parse(dateStr).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return DateFormat.jm().format(date);
    if (diff.inDays < 7) return DateFormat.E().add_jm().format(date);
    return DateFormat.MMMd().add_jm().format(date);
  }

  void _callBack(Map<String, dynamic> otherUser, bool isVideo) {
    _callProvider.initiateCall(
      targetUserId: otherUser['id'],
      targetUserName: otherUser['displayName'] ?? otherUser['username'] ?? 'Unknown',
      targetUserAvatar: otherUser['avatarUrl'],
      isVideo: isVideo,
    );
    context.push('/active-call');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Calls',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _calls.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: () => _loadCalls(refresh: true),
                  color: AppTheme.primaryColor,
                  child: ListView.builder(
                    itemCount: _calls.length + (_hasMore ? 1 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      if (index == _calls.length) {
                        _loadCalls();
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor, strokeWidth: 2)),
                        );
                      }
                      return _buildCallTile(_calls[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_outlined, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'No calls yet',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a voice or video call from a chat',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildCallTile(Map<String, dynamic> call) {
    final currentUserId = _auth.currentUser?.id;
    final isCaller = call['callerId'] == currentUserId;
    final otherUser = isCaller ? call['receiver'] : call['caller'];
    final status = call['status'] as String;
    final callType = call['callType'] as String;
    final duration = call['duration'] as int? ?? 0;
    final isVideo = callType == 'VIDEO';
    final isMissed = status == 'MISSED' || status == 'DECLINED';
    final isFailed = status == 'FAILED';

    // Determine status display
    Color statusColor;
    IconData directionIcon;
    String statusText;

    if (isMissed) {
      statusColor = Colors.red;
      directionIcon = isCaller ? Icons.call_made : Icons.call_received;
      statusText = isCaller ? 'No answer' : 'Missed';
    } else if (isFailed) {
      statusColor = Colors.orange;
      directionIcon = Icons.call_missed;
      statusText = 'Failed';
    } else {
      statusColor = Colors.green;
      directionIcon = isCaller ? Icons.call_made : Icons.call_received;
      statusText = _formatDuration(duration);
    }

    return InkWell(
      onTap: () => _callBack(otherUser, isVideo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            AvatarWidget(
              avatarUrl: otherUser['avatarUrl'],
              radius: 24,
            ),
            const SizedBox(width: 12),

            // Name + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherUser['displayName'] ?? otherUser['username'] ?? 'Unknown',
                    style: TextStyle(
                      color: isMissed && !isCaller ? Colors.red : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(directionIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Icon(isVideo ? Icons.videocam : Icons.phone, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        statusText.isNotEmpty ? statusText : status,
                        style: TextStyle(color: statusColor, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(call['startedAt']),
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Call back button
            IconButton(
              icon: Icon(
                isVideo ? Icons.videocam_outlined : Icons.phone_outlined,
                color: AppTheme.primaryColor,
                size: 22,
              ),
              onPressed: () => _callBack(otherUser, isVideo),
            ),
          ],
        ),
      ),
    );
  }
}
