import 'package:dio/dio.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';

/// Parses Dio errors into typed [AppException] instances.
/// Extracts backend's `{success, error, message, details}` response structure.
class ErrorHandler {
  const ErrorHandler._();

  /// Convert any error into an [AppException].
  static AppException handle(dynamic error) {
    if (error is AppException) return error;

    if (error is DioException) return _handleDioError(error);

    if (error is Exception) {
      return AppException(message: error.toString().replaceAll('Exception: ', ''));
    }

    // Handle Dart Errors (TypeError, NoSuchMethodError, etc.)
    if (error is Error) {
      return AppException(message: 'Something went wrong: ${error.runtimeType}');
    }

    return AppException(message: error?.toString() ?? 'Something went wrong');
  }

  /// Extract user-friendly message from any error.
  static String getMessage(dynamic error) => handle(error).message;

  static AppException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
        return const NetworkException();

      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutException();

      case DioExceptionType.badResponse:
        return _handleResponse(error.response);

      case DioExceptionType.cancel:
        return const AppException(message: 'Request was cancelled');

      default:
        return const NetworkException();
    }
  }

  /// Parse the backend response body into a typed exception.
  static AppException _handleResponse(Response? response) {
    if (response == null) return const ServerException();

    final statusCode = response.statusCode ?? 500;
    final data = response.data;

    // Extract message from backend's standard response format
    String message = _extractMessage(data) ?? _defaultMessage(statusCode);

    switch (statusCode) {
      case 400:
        // Check for Zod validation errors from backend
        final details = _extractValidationErrors(data);
        if (details.isNotEmpty) {
          return ValidationException(
            message: details.first['message'] ?? message,
            fieldErrors: details,
          );
        }
        return BadRequestException(message: message, details: data);

      case 401:
        return UnauthorizedException(message: message);

      case 403:
        return ForbiddenException(message: message);

      case 404:
        return NotFoundException(message: message);

      case 409:
        return ConflictException(message: message);

      case 422:
        final details = _extractValidationErrors(data);
        return ValidationException(message: message, fieldErrors: details);

      case 429:
        return TooManyRequestsException(message: message);

      default:
        if (statusCode >= 500) {
          return ServerException(message: message);
        }
        return AppException(message: message, statusCode: statusCode);
    }
  }

  /// Extract message string from backend response.
  static String? _extractMessage(dynamic data) {
    if (data is! Map) return null;

    // Try 'message' field first (backend standard)
    if (data['message'] is String) return data['message'];

    // Try 'error' field
    if (data['error'] is String) return data['error'];

    return null;
  }

  /// Extract Zod validation error details from backend response.
  /// Backend sends: `{ details: [{ path: [...], message: "..." }] }`
  /// or: `{ errors: [{ message: "..." }] }`
  static List<Map<String, dynamic>> _extractValidationErrors(dynamic data) {
    if (data is! Map) return [];

    // Backend errorHandler sends Zod errors in 'details'
    if (data['details'] is List) {
      return (data['details'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    // Alternative 'errors' array
    if (data['errors'] is List) {
      return (data['errors'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return [];
  }

  static String _defaultMessage(int statusCode) {
    switch (statusCode) {
      case 400: return 'Invalid request';
      case 401: return 'Session expired. Please log in again.';
      case 403: return 'You don\'t have permission for this action';
      case 404: return 'Not found';
      case 409: return 'This already exists';
      case 422: return 'Please check your input';
      case 429: return 'Too many requests. Please wait a moment.';
      default:
        if (statusCode >= 500) return 'Server error. Please try again later.';
        return 'Something went wrong';
    }
  }
}
