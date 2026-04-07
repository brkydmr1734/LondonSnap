import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> save(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> get(String key) async {
    return _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> deleteAll() async {
    await _storage.deleteAll();
  }

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await save('access_token', accessToken);
    await save('refresh_token', refreshToken);
  }

  Future<String?> get accessToken => get('access_token');
  Future<String?> get refreshToken => get('refresh_token');

  Future<void> clearTokens() async {
    await delete('access_token');
    await delete('refresh_token');
  }

  Future<bool> get hasToken async {
    final token = await accessToken;
    return token != null;
  }
}
