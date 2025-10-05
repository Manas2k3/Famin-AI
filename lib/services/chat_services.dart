// lib/services/chat_services.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http_parser/http_parser.dart' as http_parser; // ✅ fixed alias
import 'package:path/path.dart' as p;

class ChatService {
  final String backendBaseUrl; // e.g., http://192.168.29.59:8000

  ChatService({required this.backendBaseUrl});

  /// --- Helpers ---
  Uri _u(String path, [Map<String, String>? q]) =>
      Uri.parse('$backendBaseUrl$path').replace(queryParameters: q);

  String _joinCandidates(List<String>? candidates) =>
      (candidates == null || candidates.isEmpty) ? '' : candidates.join(',');

  /// --- 1) STT: POST /stt ---
  /// Accepts any common audio (m4a/mp4/mp3/ogg/webm/wav/flac/aiff).
  /// Server auto-converts & recognizes. Optional lang/candidates hints.
  /// NEW: outLang → ask server to translate transcript to this app language.
  Future<Map<String, dynamic>> transcribeAudio(
      File audioFile, {
        String? lang,               // e.g., 'hi'
        List<String>? candidates,   // e.g., ['en','hi','bn']
        String? outLang,            // e.g., 'or' (Odia transcript even if ASR used hi/bn)
      }) async {
    final qp = <String, String>{};
    if (lang != null && lang.isNotEmpty) qp['lang'] = lang;
    if (candidates != null && candidates.isNotEmpty) {
      qp['candidates'] = _joinCandidates(candidates);
    }
    if (outLang != null && outLang.isNotEmpty) {
      qp['out_lang'] = outLang;
    }

    final uri = _u('/stt', qp);

    final req = http.MultipartRequest('POST', uri);
    final mimeGuess = _guessMime(audioFile.path);
    req.files.add(await http.MultipartFile.fromPath(
      'audio',
      audioFile.path,
      contentType: mimeGuess == null ? null : MediaTypeParser.parse(mimeGuess),
    ));

    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      debugPrint('STT error: ${resp.statusCode} ${resp.body}');
      throw Exception('STT failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// --- 2) Chat: POST /message ---
  /// Sends user text to server; server handles language, translation, Gemini, and optional TTS.
  Future<Map<String, dynamic>> sendMessage({
    required String sessionId,
    required String message,
    bool speechOut = false,
    String? replyLang,       // e.g., 'en' | 'hi' | 'or'
    String? replyStyle,      // e.g., 'hinglish'
    String? ttsLang,         // override TTS output voice language
  }) async {
    final uri = _u('/message');
    final payload = {
      'session_id': sessionId,
      'message': message,
      'speech_out': speechOut,
      if (replyLang != null) 'reply_lang': replyLang,
      if (replyStyle != null) 'reply_style': replyStyle,
      if (ttsLang != null) 'tts_lang': ttsLang,
    };

    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (resp.statusCode != 200) {
      debugPrint('Message error: ${resp.statusCode} ${resp.body}');
      throw Exception('Message failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// --- 3) TTS only: POST /tts ---
  Future<Map<String, dynamic>> tts({
    required String text,
    String lang = 'en',
  }) async {
    final uri = _u('/tts');
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'lang': lang}),
    );
    if (resp.statusCode != 200) {
      debugPrint('TTS error: ${resp.statusCode} ${resp.body}');
      throw Exception('TTS failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// --- 4) Convenience: audio -> transcript -> reply (+ optional audio out) ---
  /// NEW: sttOutLang threads through to /stt (e.g., 'or' for Odia transcript output).
  Future<Map<String, dynamic>> chatFromAudio({
    required String sessionId,
    required File audioFile,
    bool speechOut = true,          // get voice reply back by default
    String? sttLang,                // e.g., 'hi'
    List<String>? sttCandidates,    // e.g., ['en','hi','bn']
    String? sttOutLang,             // e.g., 'or'
    String? replyLang,              // force reply language
    String? replyStyle,             // 'hinglish'
    String? ttsLang,                // override TTS voice
  }) async {
    final sttRes = await transcribeAudio(
      audioFile,
      lang: sttLang,
      candidates: sttCandidates,
      outLang: sttOutLang, // ✅
    );
    final transcript = (sttRes['text'] ?? '').toString();

    final msgRes = await sendMessage(
      sessionId: sessionId,
      message: transcript,
      speechOut: speechOut,
      replyLang: replyLang,
      replyStyle: replyStyle,
      ttsLang: ttsLang,
    );

    return {
      'stt': sttRes,
      'chat': msgRes,
    };
  }

  /// --- Optional: GET /voices, useful for settings screens ---
  Future<Map<String, dynamic>> getVoices() async {
    final resp = await http.get(_u('/voices'));
    if (resp.statusCode != 200) {
      debugPrint('Voices error: ${resp.statusCode} ${resp.body}');
      throw Exception('Voices failed: ${resp.statusCode}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// --- Utility: decode audio_base64 from server to bytes (MP3) ---
  Uint8List? decodeAudioBase64(Map<String, dynamic> chatResponse) {
    final b64 = chatResponse['audio_base64'];
    if (b64 is String && b64.isNotEmpty) {
      return base64Decode(b64);
    }
    return null;
  }

  /// Simple factory from .env
  static ChatService fromEnv() {
    return ChatService(
      backendBaseUrl: dotenv.env['BACKEND_BASE_URL'] ?? 'https://famin-ai-chatbot-api-506773688937.asia-south1.run.app',
    );
  }
}

/// --- Minimal MIME helper (uses http_parser alias correctly) ---
class MediaTypeParser {
  static http_parser.MediaType? parse(String s) {
    try {
      final parts = s.split('/');
      if (parts.length != 2) return null;
      return http_parser.MediaType(parts[0], parts[1]);
    } catch (_) {
      return null;
    }
  }
}

String? _guessMime(String path) {
  final ext = p.extension(path).toLowerCase();
  switch (ext) {
    case '.wav':
      return 'audio/wav';
    case '.flac':
      return 'audio/flac';
    case '.aiff':
    case '.aif':
      return 'audio/aiff';
    case '.mp3':
      return 'audio/mpeg';
    case '.m4a':
      return 'audio/mp4';
    case '.mp4':
      return 'audio/mp4';
    case '.ogg':
      return 'audio/ogg';
    case '.webm':
      return 'audio/webm';
    default:
      return null;
  }
}
