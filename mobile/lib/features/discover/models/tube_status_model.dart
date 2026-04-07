import 'dart:ui';

class TubeLineStatus {
  final String id;
  final String name;
  final String color; // hex color string like "#B36305"
  final String status;
  final int severity;
  final String? reason;

  TubeLineStatus({
    required this.id,
    required this.name,
    required this.color,
    required this.status,
    required this.severity,
    this.reason,
  });

  factory TubeLineStatus.fromJson(Map<String, dynamic> json) {
    return TubeLineStatus(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String,
      status: json['status'] as String,
      severity: json['severity'] as int,
      reason: json['reason'] as String?,
    );
  }

  /// Converts hex color string to Color
  Color get lineColor {
    final hex = color.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  /// Good service when severity >= 10
  bool get isGoodService => severity >= 10;

  /// Minor delays when severity is between 6 and 9 (inclusive)
  bool get isMinorDelays => severity >= 6 && severity < 10;

  /// Severe delays or closure when severity < 6
  bool get isSevereDelays => severity < 6;

  /// Gets appropriate status color based on severity
  Color get statusColor {
    if (isGoodService) return const Color(0xFF10B981); // green
    if (isMinorDelays) return const Color(0xFFF59E0B); // amber
    return const Color(0xFFEF4444); // red
  }
}

class TubeStatusResponse {
  final List<TubeLineStatus> lines;
  final DateTime updatedAt;

  TubeStatusResponse({
    required this.lines,
    required this.updatedAt,
  });

  factory TubeStatusResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final linesList = data['lines'] as List;
    return TubeStatusResponse(
      lines: linesList.map((l) => TubeLineStatus.fromJson(l as Map<String, dynamic>)).toList(),
      updatedAt: DateTime.parse(data['updatedAt'] as String),
    );
  }
}
