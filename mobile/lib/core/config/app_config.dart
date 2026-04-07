/// Environment configuration for LondonSnaps.
library;

/// Switch [currentEnv] to change between dev/staging/production.

enum AppEnvironment { dev, staging, production }

class AppConfig {
  const AppConfig._();

  /// -------- SWITCH THIS FOR DEPLOYMENT --------
  static const AppEnvironment currentEnv = AppEnvironment.production;

  /// API base URL per environment.
  static String get baseUrl {
    switch (currentEnv) {
      case AppEnvironment.dev:
        return 'http://192.168.1.119:3000/api/v1';
      case AppEnvironment.staging:
        return 'https://staging-api.londonsnaps.com/api/v1';
      case AppEnvironment.production:
        return 'https://gq3dkjjz4m.eu-west-2.awsapprunner.com/api/v1';
    }
  }

  /// Whether we're in debug/dev mode.
  static bool get isDev => currentEnv == AppEnvironment.dev;

  /// HTTP timeouts — aggressive for production.
  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 12);
  static const Duration sendTimeout = Duration(seconds: 8);

  /// Retry configuration for transient errors (5xx, timeouts).
  static const int maxRetries = 2;
  static const Duration retryDelay = Duration(milliseconds: 500);
}
