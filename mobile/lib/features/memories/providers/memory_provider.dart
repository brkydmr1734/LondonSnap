import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';
import 'package:londonsnaps/features/memories/models/memory_models.dart';

class MemoryProvider extends ChangeNotifier {
  static final MemoryProvider _instance = MemoryProvider._internal();
  factory MemoryProvider() => _instance;
  MemoryProvider._internal();

  final ApiService _api = ApiService();

  // State
  List<Memory> _memories = [];
  List<MemoryAlbum> _albums = [];
  MemoryPagination? _pagination;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;

  // Vault state
  bool _isVaultUnlocked = false;
  bool get isVaultUnlocked => _isVaultUnlocked;

  bool _hasVault = false;
  bool get hasVault => _hasVault;

  String? _vaultToken;
  Timer? _vaultAutoLockTimer;

  List<Memory> _vaultMemories = [];
  List<Memory> get vaultMemories => _vaultMemories;

  bool _isLoadingVault = false;
  bool get isLoadingVault => _isLoadingVault;

  String? _vaultError;
  String? get vaultError => _vaultError;

  // Getters
  List<Memory> get memories => _memories;
  List<MemoryAlbum> get albums => _albums;
  MemoryPagination? get pagination => _pagination;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _pagination?.hasMore ?? false;
  int get totalMemories => _pagination?.total ?? _memories.length;

  /// Group memories by month/year for display
  Map<String, List<Memory>> get memoriesByMonth {
    final grouped = <String, List<Memory>>{};
    for (final memory in _memories) {
      final key = _formatMonthYear(memory.takenAt);
      grouped.putIfAbsent(key, () => []).add(memory);
    }
    return grouped;
  }

  String _formatMonthYear(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  /// Load memories (initial load or refresh)
  Future<void> loadMemories({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _memories = [];
      _pagination = null;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.getMemories(limit: 50, offset: 0);
      final data = response.data['data'] as Map<String, dynamic>;
      final memoriesList = data['memories'] as List<dynamic>;
      final paginationData = data['pagination'] as Map<String, dynamic>;

      _memories = memoriesList
          .map((json) => Memory.fromJson(json as Map<String, dynamic>))
          .toList();
      _pagination = MemoryPagination.fromJson(paginationData);
      _error = null;
    } catch (e) {
      _error = ErrorHandler.handle(e).message;
      debugPrint('Load memories error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load more memories for infinite scroll
  Future<void> loadMoreMemories() async {
    if (_isLoadingMore || !hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final offset = _memories.length;
      final response = await _api.getMemories(limit: 50, offset: offset);
      final data = response.data['data'] as Map<String, dynamic>;
      final memoriesList = data['memories'] as List<dynamic>;
      final paginationData = data['pagination'] as Map<String, dynamic>;

      final newMemories = memoriesList
          .map((json) => Memory.fromJson(json as Map<String, dynamic>))
          .toList();
      _memories.addAll(newMemories);
      _pagination = MemoryPagination.fromJson(paginationData);
    } catch (e) {
      debugPrint('Load more memories error: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Load albums
  Future<void> loadAlbums() async {
    try {
      final response = await _api.getMemoryAlbums();
      final data = response.data['data'] as Map<String, dynamic>;
      final albumsList = data['albums'] as List<dynamic>;

      _albums = albumsList
          .map((json) => MemoryAlbum.fromJson(json as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Load albums error: $e');
    }
  }

  /// Save a new memory
  Future<bool> saveMemory({
    required String mediaUrl,
    required String mediaType,
    String? thumbnailUrl,
    String? caption,
    String? location,
    double? latitude,
    double? longitude,
    String? originalSnapId,
    String? originalStoryId,
    String? albumId,
  }) async {
    try {
      final response = await _api.saveToMemories(
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl,
        caption: caption,
        location: location,
        latitude: latitude,
        longitude: longitude,
        originalSnapId: originalSnapId,
        originalStoryId: originalStoryId,
        albumId: albumId,
      );

      final data = response.data['data'] as Map<String, dynamic>;
      final newMemory = Memory.fromJson(data['memory'] as Map<String, dynamic>);
      
      // Add to beginning of list
      _memories.insert(0, newMemory);
      if (_pagination != null) {
        _pagination = MemoryPagination(
          total: _pagination!.total + 1,
          limit: _pagination!.limit,
          offset: _pagination!.offset,
          hasMore: _pagination!.hasMore,
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Save memory error: $e');
      return false;
    }
  }

  /// Delete a memory
  Future<bool> deleteMemory(String id) async {
    try {
      await _api.deleteMemory(id);
      
      _memories.removeWhere((m) => m.id == id);
      if (_pagination != null) {
        _pagination = MemoryPagination(
          total: _pagination!.total - 1,
          limit: _pagination!.limit,
          offset: _pagination!.offset,
          hasMore: _pagination!.hasMore,
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Delete memory error: $e');
      return false;
    }
  }

  /// Update a memory (caption and/or album)
  Future<Memory?> updateMemory(String id, {String? caption, String? albumId}) async {
    try {
      final response = await _api.updateMemory(id, caption: caption, albumId: albumId);
      final data = response.data['data'] as Map<String, dynamic>;
      final updatedMemory = Memory.fromJson(data['memory'] as Map<String, dynamic>);
      
      // Update in local list
      final index = _memories.indexWhere((m) => m.id == id);
      if (index >= 0) {
        _memories[index] = updatedMemory;
      }
      notifyListeners();
      return updatedMemory;
    } catch (e) {
      debugPrint('Update memory error: $e');
      return null;
    }
  }

  /// Reshare memory as story
  Future<bool> reshareMemory(String id) async {
    try {
      await _api.reshareMemory(id);
      return true;
    } catch (e) {
      debugPrint('Reshare memory error: $e');
      return false;
    }
  }

  /// Create a new album
  Future<MemoryAlbum?> createAlbum({
    required String name,
    String? coverUrl,
    bool? isPrivate,
  }) async {
    try {
      final response = await _api.createMemoryAlbum(
        name: name,
        coverUrl: coverUrl,
        isPrivate: isPrivate,
      );

      final data = response.data['data'] as Map<String, dynamic>;
      final newAlbum = MemoryAlbum.fromJson(data['album'] as Map<String, dynamic>);
      
      _albums.insert(0, newAlbum);
      notifyListeners();
      return newAlbum;
    } catch (e) {
      debugPrint('Create album error: $e');
      return null;
    }
  }

  /// Get a memory by ID
  Memory? getMemoryById(String id) {
    try {
      return _memories.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get index of memory in list
  int getMemoryIndex(String id) {
    return _memories.indexWhere((m) => m.id == id);
  }

  /// Clear all data (for logout)
  void clear() {
    _memories = [];
    _albums = [];
    _pagination = null;
    _error = null;
    lockVault();
    notifyListeners();
  }

  // ── My Eyes Only Vault ──

  String _handleError(dynamic e) {
    final appError = ErrorHandler.handle(e);
    return appError.message;
  }

  // Check vault status
  Future<void> checkVaultStatus() async {
    try {
      final response = await _api.getVaultStatus();
      final data = response.data['data'];
      _hasVault = data['hasVault'] ?? false;
      notifyListeners();
    } catch (e) {
      _hasVault = false;
    }
  }

  // Setup vault PIN
  Future<bool> setupVault(String pin) async {
    try {
      await _api.setupVaultPin(pin);
      _hasVault = true;
      notifyListeners();
      return true;
    } catch (e) {
      _vaultError = _handleError(e);
      notifyListeners();
      return false;
    }
  }

  // Verify PIN and unlock vault
  Future<bool> unlockVault(String pin) async {
    _vaultError = null;
    notifyListeners();
    try {
      final response = await _api.verifyVaultPin(pin);
      final data = response.data['data'];
      _vaultToken = data['vaultToken'] as String?;
      _isVaultUnlocked = true;
      
      // Store token
      _api.setVaultToken(_vaultToken);
      
      // Cache token securely
      const storage = FlutterSecureStorage();
      if (_vaultToken != null) {
        await storage.write(key: 'vault_token', value: _vaultToken);
      }
      
      // Auto-lock after 15 minutes
      _startAutoLockTimer();
      
      // Load vault memories
      await loadVaultMemories();
      
      notifyListeners();
      return true;
    } catch (e) {
      _vaultError = _handleError(e);
      notifyListeners();
      return false;
    }
  }

  // Lock vault
  void lockVault() {
    _isVaultUnlocked = false;
    _vaultToken = null;
    _vaultMemories = [];
    _vaultAutoLockTimer?.cancel();
    _api.setVaultToken(null);
    
    const storage = FlutterSecureStorage();
    storage.delete(key: 'vault_token');
    
    notifyListeners();
  }

  // Auto-lock timer
  void _startAutoLockTimer() {
    _vaultAutoLockTimer?.cancel();
    _vaultAutoLockTimer = Timer(const Duration(minutes: 15), () {
      lockVault();
    });
  }

  // Reset auto-lock timer (call on vault activity)
  void resetAutoLockTimer() {
    if (_isVaultUnlocked) _startAutoLockTimer();
  }

  // Load vault memories
  Future<void> loadVaultMemories({bool refresh = false}) async {
    if (!_isVaultUnlocked) return;
    
    _isLoadingVault = true;
    _vaultError = null;
    notifyListeners();
    
    try {
      final response = await _api.getMyEyesOnlyMemories(
        limit: 50,
        offset: refresh ? 0 : _vaultMemories.length,
      );
      final data = response.data['data'];
      final memoriesList = (data['memories'] as List? ?? [])
          .map((m) => Memory.fromJson(m as Map<String, dynamic>))
          .toList();
      
      if (refresh) {
        _vaultMemories = memoriesList;
      } else {
        _vaultMemories.addAll(memoriesList);
      }
    } catch (e) {
      _vaultError = _handleError(e);
    }
    
    _isLoadingVault = false;
    notifyListeners();
  }

  // Move memory to vault
  Future<bool> moveToVault(String memoryId) async {
    try {
      await _api.moveToVault(memoryId);
      // Remove from normal memories list
      _memories.removeWhere((m) => m.id == memoryId);
      // If vault is unlocked, reload vault memories
      if (_isVaultUnlocked) {
        await loadVaultMemories(refresh: true);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _vaultError = _handleError(e);
      notifyListeners();
      return false;
    }
  }

  // Move memory from vault
  Future<bool> moveFromVault(String memoryId) async {
    if (!_isVaultUnlocked) return false;
    try {
      await _api.moveFromVault(memoryId);
      _vaultMemories.removeWhere((m) => m.id == memoryId);
      // Refresh normal memories
      await loadMemories(refresh: true);
      notifyListeners();
      return true;
    } catch (e) {
      _vaultError = _handleError(e);
      notifyListeners();
      return false;
    }
  }

  // Change PIN
  Future<bool> changeVaultPin(String currentPin, String newPin) async {
    try {
      await _api.changeVaultPin(currentPin, newPin);
      return true;
    } catch (e) {
      _vaultError = _handleError(e);
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _vaultAutoLockTimer?.cancel();
    super.dispose();
  }
}
