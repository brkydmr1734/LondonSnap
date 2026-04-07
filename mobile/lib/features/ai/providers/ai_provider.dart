import 'package:flutter/foundation.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/features/ai/models/ai_models.dart';

class AIProvider extends ChangeNotifier {
  static final AIProvider _instance = AIProvider._internal();
  factory AIProvider() => _instance;
  AIProvider._internal() {
    // Add welcome message on initialization
    _messages.add(AIMessage.ai(
      "Hey! I'm your LondonSnap AI — I know London inside out! 🏙️\n\nAsk me about:\n🍕 Food & restaurants\n🍺 Pubs & nightlife\n📚 Study spots & cafes\n🎭 Events & things to do\n🚇 Transport tips\n\nWhat are you looking for?",
      ["Best restaurants", "What's on tonight", "Study cafes", "Pub recommendations"],
    ));
  }

  final ApiService _api = ApiService();
  final List<AIMessage> _messages = [];
  bool _isLoading = false;

  List<AIMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    // Add user message
    _messages.add(AIMessage.user(message.trim()));
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _api.chatWithAI(message.trim());
      
      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        final aiResponse = data['response'] as String;
        final suggestions = (data['suggestions'] as List<dynamic>)
            .map((e) => e.toString())
            .toList();
        
        _messages.add(AIMessage.ai(aiResponse, suggestions));
      } else {
        _messages.add(AIMessage.ai(
          "Sorry, I couldn't process that. Try asking about food, pubs, study spots, or things to do in London!",
          ["Best restaurants", "Pub recommendations", "Study cafes"],
        ));
      }
    } catch (e) {
      debugPrint('AI chat error: $e');
      _messages.add(AIMessage.ai(
        "Oops! Something went wrong. Please try again.",
        ["Best restaurants", "What's on tonight", "Study cafes"],
      ));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearHistory() {
    _messages.clear();
    // Add welcome message back
    _messages.add(AIMessage.ai(
      "Hey! I'm your LondonSnap AI — I know London inside out! 🏙️\n\nAsk me about:\n🍕 Food & restaurants\n🍺 Pubs & nightlife\n📚 Study spots & cafes\n🎭 Events & things to do\n🚇 Transport tips\n\nWhat are you looking for?",
      ["Best restaurants", "What's on tonight", "Study cafes", "Pub recommendations"],
    ));
    notifyListeners();
  }
}
