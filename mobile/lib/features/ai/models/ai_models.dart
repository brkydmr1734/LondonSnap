class AIMessage {
  final String content;
  final bool isUser;
  final List<String> suggestions;
  final DateTime timestamp;

  AIMessage({
    required this.content,
    required this.isUser,
    this.suggestions = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory AIMessage.user(String content) {
    return AIMessage(
      content: content,
      isUser: true,
    );
  }

  factory AIMessage.ai(String content, List<String> suggestions) {
    return AIMessage(
      content: content,
      isUser: false,
      suggestions: suggestions,
    );
  }
}
