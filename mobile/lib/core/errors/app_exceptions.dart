/// Custom exception hierarchy mirroring backend's AppError classes.
library;

/// Each carries a user-friendly [message], HTTP [statusCode], and optional [details].

class AppException implements Exception {
  final String message;
  final int statusCode;
  final dynamic details;

  const AppException({
    this.message = 'Something went wrong',
    this.statusCode = 500,
    this.details,
  });

  @override
  String toString() => message;
}

/// 400 — Bad request / invalid input
class BadRequestException extends AppException {
  const BadRequestException({super.message = 'Invalid request', super.details})
      : super(statusCode: 400);
}

/// 401 — Token expired / not authenticated
class UnauthorizedException extends AppException {
  const UnauthorizedException({super.message = 'Session expired. Please log in again.', super.details})
      : super(statusCode: 401);
}

/// 403 — Forbidden / insufficient permissions
class ForbiddenException extends AppException {
  const ForbiddenException({super.message = 'You don\'t have permission for this action', super.details})
      : super(statusCode: 403);
}

/// 404 — Resource not found
class NotFoundException extends AppException {
  const NotFoundException({super.message = 'Not found', super.details})
      : super(statusCode: 404);
}

/// 409 — Conflict (duplicate record)
class ConflictException extends AppException {
  const ConflictException({super.message = 'This already exists', super.details})
      : super(statusCode: 409);
}

/// 422 — Validation error with field-level details
class ValidationException extends AppException {
  final List<Map<String, dynamic>> fieldErrors;

  const ValidationException({
    super.message = 'Please check your input',
    this.fieldErrors = const [],
    super.details,
  }) : super(statusCode: 422);
}

/// 429 — Rate limited
class TooManyRequestsException extends AppException {
  const TooManyRequestsException({super.message = 'Too many requests. Please wait a moment.', super.details})
      : super(statusCode: 429);
}

/// 5xx — Server error
class ServerException extends AppException {
  const ServerException({super.message = 'Server error. Please try again later.', super.details})
      : super(statusCode: 500);
}

/// Network unreachable / no internet
class NetworkException extends AppException {
  const NetworkException({super.message = 'No internet connection. Please check your network.'})
      : super(statusCode: 0);
}

/// Request timed out
class TimeoutException extends AppException {
  const TimeoutException({super.message = 'Request timed out. Please try again.'})
      : super(statusCode: 0);
}
