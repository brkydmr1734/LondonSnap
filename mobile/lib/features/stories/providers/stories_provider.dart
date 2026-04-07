import 'package:flutter/material.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/features/stories/models/story_models.dart';

class StoriesProvider extends ChangeNotifier {
  final ApiService _api = ApiService();

  List<StoryRing> _storyRings = [];
  List<Story> _myStories = [];
  List<StoryHighlight> _highlights = [];
  int _currentStoryIndex = 0;
  int _currentRingIndex = 0;
  bool _isLoading = false;
  bool _isUploading = false;
  String? _error;
  bool _showStoryViewer = false;
  final Set<String> _viewedStoryIds = {};

  List<StoryRing> get storyRings => _storyRings;
  List<Story> get myStories => _myStories;
  List<StoryHighlight> get highlights => _highlights;
  int get currentStoryIndex => _currentStoryIndex;
  int get currentRingIndex => _currentRingIndex;
  bool get isLoading => _isLoading;
  bool get isUploading => _isUploading;
  String? get error => _error;
  bool get showStoryViewer => _showStoryViewer;
  bool get hasUnviewedStories => _storyRings.any((r) => r.hasUnviewed);

  StoryRing? get currentStoryRing {
    if (_currentRingIndex < 0 || _currentRingIndex >= _storyRings.length) return null;
    return _storyRings[_currentRingIndex];
  }

  Story? get currentStory {
    final ring = currentStoryRing;
    if (ring == null) return null;
    if (_currentStoryIndex < 0 || _currentStoryIndex >= ring.stories.length) return null;
    return ring.stories[_currentStoryIndex];
  }

  Future<void> loadStories() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await _api.getStories();
      final data = response.data;
      final storiesList = data['data']?['stories'] ?? data['stories'] ?? [];
      _storyRings = (storiesList as List).map((s) => StoryRing.fromJson(s)).toList();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMyStories() async {
    try {
      final response = await _api.getMyStories();
      final data = response.data;
      final storiesList = data['data']?['stories'] ?? data['stories'] ?? [];
      _myStories = (storiesList as List).map((s) => Story.fromJson(s)).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadHighlights(String userId) async {
    try {
      final response = await _api.getHighlights(userId);
      final data = response.data;
      final highlightsList = data['data']?['highlights'] ?? data['highlights'] ?? [];
      _highlights = (highlightsList as List).map((h) => StoryHighlight.fromJson(h)).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<Story?> createStory({required String mediaUrl, String? thumbnailUrl,
    required String mediaType, int duration = 5, String? caption,
    String privacy = 'FRIENDS', bool allowReplies = true}) async {
    _isUploading = true;
    notifyListeners();
    try {
      final response = await _api.createStory({
        'mediaUrl': mediaUrl, 'thumbnailUrl': thumbnailUrl,
        'mediaType': mediaType, 'duration': duration,
        'caption': caption, 'privacy': privacy, 'allowReplies': allowReplies,
      });
      final story = Story.fromJson(response.data['data']['story'] ?? response.data['data']);
      _myStories.insert(0, story);
      _isUploading = false;
      notifyListeners();
      return story;
    } catch (e) {
      _error = e.toString();
      _isUploading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> viewStory(Story story) async {
    if (_viewedStoryIds.contains(story.id)) return;
    _viewedStoryIds.add(story.id);
    try { await _api.viewStory(story.id); } catch (_) {}
  }

  Future<bool> replyToStory(String storyId, {required String content}) async {
    try {
      await _api.replyToStory(storyId, {'content': content});
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> reactToStory(String storyId, String emoji) async {
    try {
      await _api.reactToStory(storyId, emoji);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateStorySettings(String storyId, {String? privacy, bool? allowReplies}) async {
    try {
      final data = <String, dynamic>{};
      if (privacy != null) data['privacy'] = privacy;
      if (allowReplies != null) data['allowReplies'] = allowReplies;
      await _api.updateStorySettings(storyId, data);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    }
  }

  Future<void> deleteStory(String storyId) async {
    try {
      await _api.deleteStory(storyId);
      _myStories.removeWhere((s) => s.id == storyId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<List<StoryViewer>> getViewers(String storyId) async {
    try {
      final response = await _api.getStoryViewers(storyId);
      final data = response.data;
      final viewersList = data['data']?['viewers'] ?? data['viewers'] ?? [];
      return (viewersList as List).map((v) => StoryViewer.fromJson(v)).toList();
    } catch (e) {
      return [];
    }
  }

  void openStory(int ringIndex) {
    _currentRingIndex = ringIndex;
    _currentStoryIndex = 0;
    final ring = currentStoryRing;
    if (ring != null) {
      for (int i = 0; i < ring.stories.length; i++) {
        if (!_viewedStoryIds.contains(ring.stories[i].id)) {
          _currentStoryIndex = i;
          break;
        }
      }
    }
    _showStoryViewer = true;
    notifyListeners();
  }

  bool nextStory() {
    final ring = currentStoryRing;
    if (ring == null) return false;
    if (_currentStoryIndex < ring.stories.length - 1) {
      _currentStoryIndex++;
      notifyListeners();
      return true;
    }
    return nextRing();
  }

  bool previousStory() {
    if (_currentStoryIndex > 0) {
      _currentStoryIndex--;
      notifyListeners();
      return true;
    }
    return previousRing();
  }

  bool nextRing() {
    if (_currentRingIndex < _storyRings.length - 1) {
      _currentRingIndex++;
      _currentStoryIndex = 0;
      notifyListeners();
      return true;
    }
    return false;
  }

  bool previousRing() {
    if (_currentRingIndex > 0) {
      _currentRingIndex--;
      final ring = currentStoryRing;
      if (ring != null) _currentStoryIndex = ring.stories.length - 1;
      notifyListeners();
      return true;
    }
    return false;
  }

  void closeViewer() {
    _showStoryViewer = false;
    _currentRingIndex = 0;
    _currentStoryIndex = 0;
    notifyListeners();
  }
}
