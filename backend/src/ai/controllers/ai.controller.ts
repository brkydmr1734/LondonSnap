import { Request, Response, NextFunction } from 'express';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { logger } from '../../common/utils/logger';

// Initialize Gemini
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || '');

const SYSTEM_PROMPT = `You are LondonSnap AI — a fun, knowledgeable, and friendly assistant built into the LondonSnap app, a social platform for university students in London.

Your personality:
- Enthusiastic but concise — use emojis sparingly and naturally
- You speak like a helpful local friend, not a formal guide
- Give specific venue names, locations, and practical tips
- Keep responses under 200 words unless the user asks for detail

Your expertise:
- London restaurants, cafes, pubs, bars, clubs, and nightlife
- Student life: study spots, libraries, coworking spaces
- Events, concerts, theatre, exhibitions
- Transport: Tube, buses, bikes, walking routes
- Shopping, markets, vintage stores
- Budget tips, student discounts, free things to do
- University-specific info (halls, societies, campus areas)
- Safety tips for students, especially at night
- Hidden gems and local secrets

Rules:
- Always respond in the same language the user writes in
- If asked about something unrelated to London or student life, politely redirect
- Never make up venue names — only recommend real places
- Include practical details like area/neighbourhood when recommending places
- If unsure about current opening hours or prices, say so

At the end of EVERY response, include a JSON block on a new line like this:
[SUGGESTIONS]: ["suggestion 1", "suggestion 2", "suggestion 3"]
These should be 3 natural follow-up questions the user might want to ask. Always include this block.`;

// Store conversation history per user (in-memory, resets on restart)
const conversationHistory = new Map<string, Array<{ role: string; parts: Array<{ text: string }> }>>();

const MAX_HISTORY = 20; // Keep last 20 messages per user

export const chatWithAI = async (
  req: Request,
  res: Response,
  _next: NextFunction
) => {
  try {
    const { message } = req.body;
    const userId = req.user?.id;

    if (!message || typeof message !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'Message is required',
      });
    }

    if (!process.env.GEMINI_API_KEY) {
      logger.error('GEMINI_API_KEY is not configured');
      return res.status(500).json({
        success: false,
        error: 'AI service is not configured',
      });
    }

    // Get or create conversation history for this user
    const historyKey = userId || 'anonymous';
    if (!conversationHistory.has(historyKey)) {
      conversationHistory.set(historyKey, []);
    }
    const history = conversationHistory.get(historyKey)!;

    // Initialize Gemini model with system instruction
    const model = genAI.getGenerativeModel({
      model: 'gemini-2.0-flash',
      systemInstruction: SYSTEM_PROMPT,
    });

    // Start chat with history
    const chat = model.startChat({
      history: history,
    });

    // Send message and get response
    const result = await chat.sendMessage(message);
    const responseText = result.response.text();

    // Parse suggestions from response
    let aiResponse = responseText;
    let suggestions: string[] = ['Best restaurants', "What's on tonight", 'Study cafes'];

    const suggestionsMatch = responseText.match(/\[SUGGESTIONS\]:\s*\[([^\]]+)\]/);
    if (suggestionsMatch) {
      try {
        suggestions = JSON.parse(`[${suggestionsMatch[1]}]`);
        // Remove the suggestions block from the visible response
        aiResponse = responseText.replace(/\n?\[SUGGESTIONS\]:\s*\[([^\]]+)\]/, '').trim();
      } catch {
        // Keep defaults if parsing fails
      }
    }

    // Update conversation history
    history.push(
      { role: 'user', parts: [{ text: message }] },
      { role: 'model', parts: [{ text: responseText }] }
    );

    // Trim history if too long
    if (history.length > MAX_HISTORY * 2) {
      history.splice(0, history.length - MAX_HISTORY * 2);
    }

    res.json({
      success: true,
      data: {
        response: aiResponse,
        suggestions,
      },
    });
  } catch (error: any) {
    logger.error('Gemini AI error:', error);

    // Return a friendly fallback instead of crashing
    if (error?.status === 429) {
      return res.json({
        success: true,
        data: {
          response: "I'm getting a lot of questions right now! Give me a moment and try again. 😅",
          suggestions: ['Try again', 'Best restaurants', 'Study spots'],
        },
      });
    }

    res.json({
      success: true,
      data: {
        response: "Sorry, I'm having a quick brain freeze! 🧊 Try asking me again.",
        suggestions: ['Best restaurants', "What's on tonight", 'Study cafes'],
      },
    });
  }
};
