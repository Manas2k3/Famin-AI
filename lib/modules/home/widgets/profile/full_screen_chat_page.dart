// lib/views/chat/chat_fullscreen_page.dart
import 'dart:async';
import 'dart:convert'; // ✅ for base64 decode (server TTS fallback)
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:record/record.dart'; // v5+ uses AudioRecorder + RecordConfig
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/chat_services.dart';

class ChatFullScreenPage extends StatefulWidget {
  const ChatFullScreenPage({Key? key}) : super(key: key);

  @override
  State<ChatFullScreenPage> createState() => _ChatFullScreenPageState();
}

class _ChatFullScreenPageState extends State<ChatFullScreenPage>
    with TickerProviderStateMixin {
  final TextEditingController _tc = TextEditingController();
  final ScrollController _sc = ScrollController();

  late final ChatService _svc;
  bool _sending = false;
  bool _botTyping = false;

  // Voice (record v5+ API)
  final AudioRecorder _rec = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;

  // TTS
  final FlutterTts _tts = FlutterTts();
  String? _speakingMsgId; // which message is currently being spoken
  late final AudioPlayer _readbackPlayer; // ✅ server TTS fallback player

  // Firestore
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Supabase
  final SupabaseClient _supa = Supabase.instance.client;

  DocumentReference<Map<String, dynamic>>? _chatRef;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _msgSub;
  final List<_Msg> _messages = <_Msg>[];

  // NEW: session id for backend (use Firebase uid)
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _svc = ChatService.fromEnv();
    _readbackPlayer = AudioPlayer(); // ✅
    _initTts();
    _ensureSupaAuth().then((_) {
      _ensureChatAndListen();
    });
  }

  @override
  void dispose() {
    _tc.dispose();
    _sc.dispose();
    _tts.stop();
    _rec.dispose();
    _msgSub?.cancel();
    _readbackPlayer.dispose(); // ✅
    super.dispose();
  }

  // ---------------------- TTS setup & per-message toggle ---------------------

  String _localeFor(String? appLang) {
    // Map app language codes to device locales FlutterTts understands
    switch (appLang) {
      case 'hi': return 'hi-IN';
      case 'en': return 'en-US';
      case 'es': return 'es-ES';
      case 'fr': return 'fr-FR';
    // Odia + most Indic not well-supported on-device → fallback to server TTS
      default:   return ''; // empty means "likely unsupported locally"
    }
  }

  Future<void> _initTts() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    // don't force a specific voice—let platform choose for the locale
    // final voices = await _tts.getVoices;
    // debugPrint('TTS voices: $voices');

    _tts.setStartHandler(() {
      if (!mounted) return;
      setState(() {}); // trigger icon update
    });
    _tts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => _speakingMsgId = null);
    });
    _tts.setCancelHandler(() {
      if (!mounted) return;
      setState(() => _speakingMsgId = null);
    });
    _tts.setErrorHandler((msg) {
      if (!mounted) return;
      setState(() => _speakingMsgId = null);
    });
  }

  Future<void> _toggleSpeakFor(_Msg m) async {
    final text = m.text?.trim() ?? '';
    if (text.isEmpty) return;

    // If tapping the one that's already speaking → stop.
    if (_speakingMsgId == m.id) {
      await _tts.stop();
      await _readbackPlayer.stop();
      setState(() => _speakingMsgId = null);
      return;
    }

    // Always stop anything in progress
    await _tts.stop();
    await _readbackPlayer.stop();

    final locale = _localeFor(m.lang);
    setState(() => _speakingMsgId = m.id);

    if (locale.isNotEmpty) {
      // Try on-device TTS first
      try {
        await _tts.setLanguage(locale);
        await _tts.speak(text);
        return; // success → handlers will clear state
      } catch (_) {
        // fall through to server TTS
      }
    }

    // 🔁 Server-side TTS fallback (great for Odia and less-supported locales)
    try {
      final ttsRes = await _svc.tts(text: text, lang: (m.lang ?? 'en'));
      final b64 = (ttsRes['audio_base64'] ?? '') as String;
      if (b64.isEmpty) throw Exception('No audio from server TTS');
      final bytes = base64Decode(b64);
      // play MP3 bytes
      await _readbackPlayer.setAudioSource(
        ByteStreamAudioSource(bytes),
      );
      await _readbackPlayer.play();
      // cleanup when finished
      _readbackPlayer.playerStateStream.firstWhere((s) => s.processingState == ProcessingState.completed).then((_) {
        if (!mounted) return;
        setState(() => _speakingMsgId = null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _speakingMsgId = null);
      Get.snackbar('TTS', 'Could not speak message.', snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ---------------------- Supabase auth (anonymous) --------------------------

  Future<void> _ensureSupaAuth() async {
    final session = _supa.auth.currentSession;
    if (session == null) {
      await _supa.auth.signInAnonymously();
    }
  }

  // -------------------------- Firestore wiring -------------------------------

  Future<void> _ensureChatAndListen() async {
    final user = _auth.currentUser;
    if (user == null) {
      Get.snackbar('Auth', 'Please login first.');
      return;
    }

    final uid = user.uid;
    _sessionId = uid; // use Firebase UID as backend session

    // read pretty name from Users/{uid}.name, fallback to displayName
    final userDoc = await _db.collection('Users').doc(uid).get();
    final usersName = (userDoc.data()?['name'] as String?)?.trim();
    final displayName =
    (usersName != null && usersName.isNotEmpty) ? usersName : (user.displayName ?? 'User');

    final chatRef = _db.collection('Chats').doc(uid);
    final snap = await chatRef.get();

    if (!snap.exists) {
      await chatRef.set({
        'userId': uid,
        'userName': displayName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final existingName = (snap.data()?['userName'] as String?)?.trim();
      if (existingName != displayName) {
        await chatRef.update({'userName': displayName});
      }
      await chatRef.update({'updatedAt': FieldValue.serverTimestamp()});
    }

    _chatRef = chatRef;

    _msgSub?.cancel();
    _msgSub = chatRef
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen((qs) {
      final list = <_Msg>[];
      for (final d in qs.docs) {
        list.add(_msgFromDoc(d));
      }
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
      });
      _scrollToEnd();
    }, onError: (e) {
      Get.snackbar('Load error', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    });

    final firstMsgs =
    await chatRef.collection('messages').limit(1).get(const GetOptions());
    if (firstMsgs.docs.isEmpty) {
      await _addBotMessage(text: "Hi! Ask me anything — text or voice. 💖", lang: null);
    }
  }

  _Msg _msgFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final id = d.id;
    final sender = data['sender'] as String? ?? 'bot';
    final type = data['type'] as String? ?? 'text';
    final text = data['text'] as String?;
    final audioUrl = data['audioUrl'] as String?;
    final audioPath = data['audioPath'] as String?;
    final durMs = (data['durationMs'] as num?)?.toInt();
    final transcript = data['transcript'] as String?;
    final lang = data['lang'] as String?;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    if (type == 'voice') {
      return _Msg.voice(
        id: id,
        isUser: sender == 'user',
        audioUrl: audioUrl,
        audioPath: audioPath,
        duration: durMs != null ? Duration(milliseconds: durMs) : null,
        transcript: transcript,
        createdAt: createdAt,
      );
    }
    return _Msg.text(
      id: id,
      isUser: sender == 'user',
      text: text ?? '',
      lang: lang,
      createdAt: createdAt,
    );
  }

  Future<void> _scrollToEnd() async {
    await Future.delayed(const Duration(milliseconds: 40));
    if (_sc.hasClients) {
      await _sc.animateTo(
        _sc.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _addUserText(String text) async {
    final ref = _chatRef;
    if (ref == null) return;
    await ref.collection('messages').add({
      'sender': 'user',
      'type': 'text',
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.update({'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<DocumentReference<Map<String, dynamic>>> _addUserVoice({
    required String audioUrl,
    required String audioPath,
    required Duration? duration,
  }) async {
    final ref = _chatRef!;
    final doc = await ref.collection('messages').add({
      'sender': 'user',
      'type': 'voice',
      'audioUrl': audioUrl,
      'audioPath': audioPath,
      'durationMs': duration?.inMilliseconds,
      'transcript': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.update({'updatedAt': FieldValue.serverTimestamp()});
    return doc;
  }

  Future<void> _updateUserVoiceTranscript({
    required String messageId,
    required String transcript,
  }) async {
    final ref = _chatRef!;
    await ref.collection('messages').doc(messageId).update({
      'transcript': transcript,
    });
  }

  Future<void> _addBotMessage({required String text, String? lang}) async {
    final ref = _chatRef!;
    await ref.collection('messages').add({
      'sender': 'bot',
      'type': 'text',
      'text': text,
      'lang': lang,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await ref.update({'updatedAt': FieldValue.serverTimestamp()});
  }

  // --------------------- Supabase upload helper ------------------------------

  Future<({String path, String signedUrl})> _uploadVoiceToSupabase({
    required File file,
    Duration signedUrlTTL = const Duration(days: 7),
  }) async {
    final supaUser = _supa.auth.currentUser;
    if (supaUser == null) {
      throw Exception('No Supabase session; call _ensureSupaAuth() first.');
    }

    final filename = '${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = '${supaUser.id}/$filename';

    await _supa.storage.from('voices').upload(path, file);

    final signedUrl = await _supa.storage
        .from('voices')
        .createSignedUrl(path, signedUrlTTL.inSeconds);

    return (path: path, signedUrl: signedUrl);
  }

  // ------------------------------ UI Actions ---------------------------------

  // TEXT → /message
  Future<void> _sendText() async {
    final raw = _tc.text.trim();
    if (raw.isEmpty || _sending) return;
    if (_sessionId == null) {
      Get.snackbar('Session', 'Please wait, initializing…', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() {
      _sending = true;
      _botTyping = true;
    });

    await _addUserText(raw);
    _tc.clear();
    await _scrollToEnd();

    try {
      final res = await _svc.sendMessage(
        sessionId: _sessionId!,
        message: raw,
        speechOut: false,           // we use on-device/server TTS in this widget
        // replyLang: 'hi',         // optional force
        // replyStyle: 'hinglish',  // optional
      );

      final reply = (res['reply'] ?? '').toString();
      final replyLang = (res['reply_lang'] ?? 'en').toString();

      await _addBotMessage(text: reply, lang: replyLang);
    } catch (e) {
      await _addBotMessage(text: "Oops—couldn't reach the server. Try again?");
    }

    if (!mounted) return;
    setState(() {
      _botTyping = false;
      _sending = false;
    });
    await _scrollToEnd();
  }

  // MIC toggle / Record
  Future<void> _toggleRecord() async {
    if (_isRecording) {
      final path = await _rec.stop();
      _recordPath = path;
      setState(() => _isRecording = false);
      if (path != null) {
        await _handleRecordedFile(File(path));
      }
      return;
    }

    final hasPerm = await _rec.hasPermission();
    if (!hasPerm) {
      Get.snackbar(
        'Permission needed',
        'Please grant microphone permission.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final dir = Directory.systemTemp;
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordPath = path;
    });
  }

  // VOICE → /stt → /message
  Future<void> _handleRecordedFile(File file) async {
    if (_sending) return;
    if (_sessionId == null) {
      Get.snackbar('Session', 'Please wait, initializing…', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() {
      _sending = true;
      _botTyping = true;
    });

    // optional: probe duration for UI
    Duration? dur;
    try {
      final probe = AudioPlayer();
      await probe.setFilePath(file.path);
      dur = probe.duration;
      await probe.dispose();
    } catch (_) {}

    // keep your storage flow as-is
    final upload = await _uploadVoiceToSupabase(file: file);
    final audioUrl = upload.signedUrl;
    final audioPath = upload.path;

    final doc = await _addUserVoice(
      audioUrl: audioUrl,
      audioPath: audioPath,
      duration: dur,
    );

    try {
      // If you want Odia transcripts by default, set sttOutLang: 'or'
      final result = await _svc.chatFromAudio(
        sessionId: _sessionId!,
        audioFile: file,
        speechOut: false,                 // we speak locally (or server fallback) later
        // sttLang: 'or',                 // optional hint
        // sttCandidates: ['hi','bn','en'], // optional
        // sttOutLang: 'or',              // ✅ uncomment to always get Odia transcript
        // replyLang: 'or',               // optional force bot reply language
        // replyStyle: 'hinglish',        // optional
      );

      // STT payload
      final stt = (result['stt'] as Map<String, dynamic>?);
      final spokenText = (stt?['text'] ?? '').toString();
      final detected = (stt?['text_out_lang'] ?? stt?['detected_lang'] ?? '').toString();

      if (spokenText.isNotEmpty) {
        await _updateUserVoiceTranscript(messageId: doc.id, transcript: spokenText);
      } else {
        await _updateUserVoiceTranscript(messageId: doc.id, transcript: '[unrecognized]');
      }

      // Chat payload
      final chat = (result['chat'] as Map<String, dynamic>?);
      final reply = (chat?['reply'] ?? '').toString();
      final replyLang = (chat?['reply_lang'] ?? detected).toString();

      await _addBotMessage(text: reply, lang: replyLang);
    } catch (e) {
      await _addBotMessage(text: "Couldn’t process that audio. Try again closer to the mic?");
    }

    if (!mounted) return;
    setState(() {
      _botTyping = false;
      _sending = false;
    });
    await _scrollToEnd();
  }

  // -------- Delete (Firestore + Supabase object if voice) --------------------

  Future<void> _deleteMessage(_Msg m) async {
    final ref = _chatRef;
    if (ref == null || m.id == null) return;

    try {
      await ref.collection('messages').doc(m.id!).delete();
      await ref.update({'updatedAt': FieldValue.serverTimestamp()});

      if (m.isVoice && (m.audioPath ?? '').isNotEmpty) {
        try {
          await _supa.storage.from('voices').remove([m.audioPath!]);
        } catch (_) {}
      }
    } catch (e) {
      Get.snackbar('Delete failed', e.toString(),
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _showMessageMenu(_Msg m) async {
    final isDeletable = true;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(height: 12),
              if (isDeletable)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Delete'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _deleteMessage(m);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // -------------------- Markdown-lite → RichText helpers --------------------

  String _normalizeBullets(String input) {
    final bulletRe = RegExp(r'^[\t ]*[\*\-]\s+', multiLine: true);
    return input.replaceAllMapped(bulletRe, (m) => '• ');
  }

  List<InlineSpan> _spansWithBold(String input, TextStyle base) {
    final text = _normalizeBullets(input);

    final spans = <InlineSpan>[];
    String remaining = text;

    void addPlain(String s) {
      if (s.isEmpty) return;
      spans.add(TextSpan(text: s, style: base));
    }

    final strongRe = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    int idx = 0;
    for (final m in strongRe.allMatches(text)) {
      if (m.start > idx) addPlain(text.substring(idx, m.start));
      final boldContent = m.group(1) ?? '';
      spans.add(TextSpan(
        text: boldContent,
        style: base.merge(const TextStyle(fontWeight: FontWeight.w800)),
      ));
      idx = m.end;
    }
    if (idx < text.length) {
      remaining = text.substring(idx);
    } else {
      remaining = '';
    }

    final emRe = RegExp(r'\*(?!\s)(.+?)(?<!\s)\*', dotAll: true);
    int idx2 = 0;
    for (final m in emRe.allMatches(remaining)) {
      if (m.start > idx2) addPlain(remaining.substring(idx2, m.start));
      final boldContent = m.group(1) ?? '';
      spans.add(TextSpan(
        text: boldContent,
        style: base.merge(const TextStyle(fontWeight: FontWeight.w800)),
      ));
      idx2 = m.end;
    }
    if (idx2 < remaining.length) {
      addPlain(remaining.substring(idx2));
    }

    return spans;
  }

  Widget _richMessage(String text, {required bool isUser, String? lang}) {
    final style = TextStyle(
      color: isUser ? Colors.white : Colors.black87,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    return RichText(
      text: TextSpan(children: _spansWithBold(text, style)),
    );
  }

  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    const pinkLight = Color(0xFFFFF1F6);
    const pinkDeep = Color(0xFFFF8FB1);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.pink.shade400,
        centerTitle: true,
        title: const Text('Chat', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _sc,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _messages.length + (_botTyping ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (_botTyping && i == _messages.length) {
                  return const _TypingBubble();
                }
                final m = _messages[i];
                final isUser = m.isUser;

                final bubble = m.isVoice
                    ? _VoiceBubble(
                  message: m,
                  isUser: isUser,
                )
                    : Column(
                  crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    _richMessage(m.text ?? '', isUser: isUser, lang: m.lang),
                    if (!isUser) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: (m.id == _speakingMsgId)
                                ? 'Stop voice'
                                : 'Play voice',
                            onPressed: () => _toggleSpeakFor(m),
                            icon: Icon(
                              (m.id == _speakingMsgId)
                                  ? Icons.stop_circle_rounded
                                  : Icons.volume_up_rounded,
                              size: 20,
                            ),
                            color: isUser
                                ? Colors.white
                                : Colors.pink.shade400,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ],
                );

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    onLongPress: () => _showMessageMenu(m),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                      padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isUser ? pinkDeep : pinkLight,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(isUser ? 14 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: bubble,
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  // Mic
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      onPressed: _toggleRecord,
                      icon: Icon(
                        _isRecording ? Icons.stop : Icons.mic_none_rounded,
                        color: Colors.pink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Text field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFE1EB)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          textSelectionTheme: const TextSelectionThemeData(
                            cursorColor: Colors.pink,
                            selectionColor: Color(0xFFFFC1D9),
                            selectionHandleColor: Colors.pink,
                          ),
                        ),
                        child: TextFormField(
                          controller: _tc,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.newline,
                          cursorColor: Colors.pink,
                          cursorWidth: 2,
                          cursorRadius: const Radius.circular(6),
                          decoration: const InputDecoration(
                            hintText: 'Type your message…',
                            border: InputBorder.none,
                          ),
                          onFieldSubmitted: (_) => _sendText(),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),
                  // Send
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      onPressed: _sending ? null : _sendText,
                      icon: const Icon(Icons.send_rounded, color: Colors.pink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------- MODELS ---------------------------------------

class _Msg {
  final String? id;           // Firestore doc ID (for delete)
  final bool isUser;
  final DateTime? createdAt;

  // text
  final String? text;
  final String? lang;

  // voice
  final String? audioUrl;       // signed URL (may expire)
  final String? audioPath;      // stable storage path in Supabase
  final Duration? audioDuration;
  final String? transcript;

  final bool isVoice;

  _Msg._({
    required this.id,
    required this.isUser,
    required this.isVoice,
    this.createdAt,
    this.text,
    this.lang,
    this.audioUrl,
    this.audioPath,
    this.audioDuration,
    this.transcript,
  });

  factory _Msg.text({
    required String id,
    required bool isUser,
    required String text,
    String? lang,
    DateTime? createdAt,
  }) =>
      _Msg._(
        id: id,
        isUser: isUser,
        isVoice: false,
        text: text,
        lang: lang,
        createdAt: createdAt,
      );

  factory _Msg.voice({
    required String id,
    required bool isUser,
    required String? audioUrl,
    String? audioPath,
    Duration? duration,
    String? transcript,
    DateTime? createdAt,
  }) =>
      _Msg._(
        id: id,
        isUser: isUser,
        isVoice: true,
        audioUrl: audioUrl,
        audioPath: audioPath,
        audioDuration: duration,
        transcript: transcript,
        createdAt: createdAt,
      );
}

// --------------------------- VOICE BUBBLE -----------------------------------

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({Key? key, required this.message, required this.isUser})
      : super(key: key);
  final _Msg message;
  final bool isUser;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  late final AudioPlayer _player;
  Duration? _duration; // total
  Duration _position = Duration.zero; // current
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool get _playing => _player.playing;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    try {
      if ((widget.message.audioUrl ?? '').isNotEmpty) {
        await _player.setUrl(widget.message.audioUrl!);
      } else if ((widget.message.audioPath ?? '').isNotEmpty) {
        final fresh = await Supabase.instance.client.storage
            .from('voices')
            .createSignedUrl(widget.message.audioPath!, const Duration(days: 7).inSeconds);
        await _player.setUrl(fresh);
      }
      _duration = _player.duration ?? widget.message.audioDuration;
    } catch (_) {
      if ((widget.message.audioPath ?? '').isNotEmpty) {
        try {
          final fresh = await Supabase.instance.client.storage
              .from('voices')
              .createSignedUrl(widget.message.audioPath!, const Duration(days: 7).inSeconds);
          await _player.setUrl(fresh);
          _duration = _player.duration ?? widget.message.audioDuration;
        } catch (_) {}
      }
    }

    _posSub = _player.positionStream.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });

    _stateSub = _player.playerStateStream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration? d) {
    if (d == null) return '0:00';
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) {
      return '$h:${m.padLeft(2, '0')}:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.isUser;
    final textColor = isUser ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment:
      isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () async {
                if (_playing) {
                  await _player.pause();
                } else {
                  await _player.play();
                }
              },
              icon: Icon(_playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded),
              color: isUser ? Colors.white : Colors.pink.shade400,
            ),
            SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      min: 0,
                      max: (_duration ?? const Duration(milliseconds: 1))
                          .inMilliseconds
                          .toDouble(),
                      value: _position.inMilliseconds
                          .clamp(0, (_duration ?? Duration.zero).inMilliseconds)
                          .toDouble(),
                      onChanged: (v) async {
                        final newPos = Duration(milliseconds: v.toInt());
                        await _player.seek(newPos);
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(_position),
                          style: TextStyle(
                              fontSize: 12, color: textColor.withOpacity(0.8))),
                      Text(_fmt(_duration),
                          style: TextStyle(
                              fontSize: 12, color: textColor.withOpacity(0.8))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.graphic_eq_rounded,
                color: textColor.withOpacity(_playing ? 1 : 0.5)),
          ],
        ),
        if ((widget.message.transcript ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.message.transcript!,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ],
    );
  }
}

// --------------------------- TYPING BUBBLE ----------------------------------

class _TypingBubble extends StatefulWidget {
  const _TypingBubble({Key? key}) : super(key: key);
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE6EE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _ac,
            builder: (_, __) {
              final t = (_ac.value + i * 0.2) % 1.0;
              final opacity = (t < 0.5) ? (0.5 + t) : (1.5 - t);
              return Opacity(
                opacity: opacity.clamp(0.4, 1.0),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: CircleAvatar(radius: 4),
                ),
              );
            },
          );
        }),
      ),
    );
    return Align(alignment: Alignment.centerLeft, child: base);
  }
}

/// --- just_audio ByteSource to play raw MP3 bytes from server TTS ---
class ByteStreamAudioSource extends StreamAudioSource {
  final List<int> _bytes;
  ByteStreamAudioSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final e = end ?? _bytes.length;
    final sub = _bytes.sublist(s, e);
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: sub.length,
      offset: s,
      contentType: 'audio/mpeg',
      stream: Stream.value(List<int>.from(sub)),
    );
  }
}
