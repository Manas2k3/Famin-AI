// lib/services/chat_services.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ChatService {
  final String geminiApiKey;
  final String translateApiKey;
  final String whisperBaseUrl;

  ChatService({
    required this.geminiApiKey,
    required this.translateApiKey,
    required this.whisperBaseUrl,
  });

  // --- Google Translate: detect language ---
  Future<String> detectLanguage(String text) async {
    if (text.trim().isEmpty) return 'en';
    final uri = Uri.parse(
      'https://translation.googleapis.com/language/translate/v2/detect?key=$translateApiKey',
    );
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'q': text}),
    );
    if (resp.statusCode != 200) {
      debugPrint('Detect error: ${resp.statusCode} ${resp.body}');
      return 'en';
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final det = data['data']?['detections'];
    if (det is List && det.isNotEmpty && det.first is List && det.first.isNotEmpty) {
      final lang = det.first.first['language']?.toString();
      return (lang == null || lang.isEmpty) ? 'en' : lang;
    }
    return 'en';
  }

  // --- Google Translate: translate ---
  Future<String> translateText(String text, {required String source, required String target}) async {
    if (text.isEmpty) return text;
    if (source == target) return text;
    final uri = Uri.parse(
      'https://translation.googleapis.com/language/translate/v2?key=$translateApiKey',
    );
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'q': text, 'source': source, 'target': target, 'format': 'text'}),
    );
    if (resp.statusCode != 200) {
      debugPrint('Translate error: ${resp.statusCode} ${resp.body}');
      return text;
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final translations = data['data']?['translations'];
    if (translations is List && translations.isNotEmpty) {
      return (translations.first['translatedText'] ?? text).toString();
    }
    return text;
  }

  // --- Gemini: text generation ---
  Future<String> askGemini(String prompt) async {
    if (prompt.trim().isEmpty) return "Say the word and I’ll purr back. 🐾";
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$geminiApiKey',
    );
    final payload = {
      "contents": [
        {
          "parts": [
            {"text": prompt}
          ]
        }
      ],
      "generationConfig": {
        "temperature": 0.8,
        "topP": 0.9,
        "maxOutputTokens": 512
      }
    };
    final resp = await http.post(uri,
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    if (resp.statusCode != 200) {
      debugPrint('Gemini error: ${resp.statusCode} ${resp.body}');
      return "I tripped over a thought. Try again?";
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final parts = candidates.first['content']?['parts'];
      if (parts is List && parts.isNotEmpty) {
        return parts.first['text']?.toString() ?? "Hmm… say that again?";
      }
    }
    return "Hmm… didn’t catch that. Ask me again?";
  }

  // --- OpenWhisper (local) : speech-to-text ---
  // Expects POST /transcribe with multipart field: "file"
  Future<Map<String, String>> transcribeAudio(File audioFile, {String? langHint}) async {
    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$whisperBaseUrl/transcribe'),
      );
      req.files.add(await http.MultipartFile.fromPath('file', audioFile.path));
      if (langHint != null && langHint.isNotEmpty) {
        req.fields['language'] = langHint; // optional, depends on your server
      }
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode != 200) {
        debugPrint('Whisper error: ${resp.statusCode} ${resp.body}');
        return {'text': '', 'lang': 'en'};
      }
      final data = jsonDecode(resp.body);
      final text = (data['text'] ?? '').toString();
      final lang = (data['lang'] ?? '').toString();
      return {
        'text': text,
        'lang': lang.isEmpty ? 'auto' : lang,
      };
    } catch (e) {
      debugPrint('Whisper exception: $e');
      return {'text': '', 'lang': 'en'};
    }
  }

  // --- Orchestrate: text (detect → translate → gemini → translate back) ---
  Future<(String reply, String detectedLang)> chatOnce(String userText, {String? userLangOverride}) async {
    final detected = userLangOverride ?? await detectLanguage(userText);
    final toEnglish = (detected == 'en')
        ? userText
        : await translateText(userText, source: detected, target: 'en');

    final replyEn = await askGemini(toEnglish);

    final back = (detected == 'en')
        ? replyEn
        : await translateText(replyEn, source: 'en', target: detected);

    return (back, detected);
  }

  // Simple factory
  static ChatService fromEnv() {
    return ChatService(
      geminiApiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      translateApiKey: dotenv.env['GOOGLE_TRANSLATE_API_KEY'] ?? '',
      whisperBaseUrl: dotenv.env['WHISPER_BASE_URL'] ?? 'http://127.0.0.1:8080',
    );
  }
}
