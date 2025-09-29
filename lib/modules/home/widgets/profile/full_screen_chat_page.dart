import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../../services/chat_services.dart';

/// ======================= FULL-SCREEN CHAT =======================
class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _tc = TextEditingController();
  final _listCtrl = ScrollController();
  final _messages = <_Msg>[];
  bool _isSending = false;
  bool _botTyping = false;
  bool _isRecording = false;

  late final ChatService _svc;
  late final FlutterTts _tts;
  final _recorder = AudioRecorder();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _svc = ChatService(
      geminiApiKey: dotenv.env['GEMINI_API_KEY'] ?? '',
      translateApiKey: dotenv.env['GOOGLE_TRANSLATE_API_KEY'] ?? '',
      openAiKey: dotenv.env['OPENAI_API_KEY'] ?? '', // 👈 for Whisper
    );
    _tts = FlutterTts();

    _messages.add(_Msg(text: 'Hello, how can I help you.', isUser: false));
    // ensure we see the greeting
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tc.dispose();
    _listCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  // Auto-scroll whenever keyboard changes size or we add messages
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    Future.delayed(const Duration(milliseconds: 120), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (!_listCtrl.hasClients) return;
    _listCtrl.animateTo(
      _listCtrl.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _sendText() async {
    final raw = _tc.text.trim();
    if (raw.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
      _messages.add(_Msg(text: raw, isUser: true));
      _tc.clear();
      _botTyping = true;
    });
    _scrollToBottom();

    // FLOW: detect language → if en, direct; else translate → gemini → translate back.
    final detected = await _svc.detectLanguage(raw) ?? 'en';
    final forModel = detected == 'en'
        ? raw
        : await _svc.translateText(raw, source: detected, target: 'en');

    final replyEn = await _svc.askGemini(forModel);
    final replyNative = detected == 'en'
        ? replyEn
        : await _svc.translateText(replyEn, source: 'en', target: detected);

    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(text: replyNative, isUser: false));
      _botTyping = false;
      _isSending = false;
    });
    _scrollToBottom();
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path == null) return;

      setState(() {
        _messages.add(_Msg(text: '🎙️ Processing voice…', isUser: true, isSystemNote: true));
        _botTyping = true;
      });
      _scrollToBottom();

      // Whisper → text
      final transcript = await _svc.transcribeWhisper(path);
      if (transcript.trim().isEmpty) {
        _finishBot("Couldn't hear that clearly. Try again?");
        return;
      }

      // show what user said
      setState(() {
        _messages.removeLast(); // remove system note
        _messages.add(_Msg(text: transcript, isUser: true));
      });
      _scrollToBottom();

      // same multilingual FLOW as text
      final detected = await _svc.detectLanguage(transcript) ?? 'en';
      final forModel = detected == 'en'
          ? transcript
          : await _svc.translateText(transcript, source: detected, target: 'en');

      final replyEn = await _svc.askGemini(forModel);
      final replyNative = detected == 'en'
          ? replyEn
          : await _svc.translateText(replyEn, source: 'en', target: detected);

      _finishBot(replyNative);

      // Speak back (native)
      await _tts.setLanguage(detected); // best-effort; device voices vary
      await _tts.setSpeechRate(0.95);
      await _tts.speak(replyNative);
      return;
    }

    // start recording
    final ok = await _recorder.hasPermission();
    if (!ok) {
      _snack("Mic permission needed for voice chat.");
      return;
    }
    await _recorder.start(const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
    ),);
    setState(() => _isRecording = true);
  }

  void _finishBot(String text) {
    if (!mounted) return;
    setState(() {
      _messages.add(_Msg(text: text, isUser: false));
      _botTyping = false;
      _isSending = false;
    });
    _scrollToBottom();
  }

  void _snack(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) {
    final pink = const Color(0xFFFF8FB1);
    final pale = const Color(0xFFFFF1F6);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: true,
        title: const Text('Chat with Gibud', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _listCtrl,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: _messages.length + (_botTyping ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (_botTyping && i == _messages.length) {
                  return const _TypingBubble();
                }
                final m = _messages[i];
                final isUser = m.isUser;
                final bg = isUser ? pink : Colors.white;
                final fg = isUser ? Colors.white : Colors.black87;

                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 6),
                          bottomRight: Radius.circular(isUser ? 6 : 16),
                        ),
                        border: Border.all(color: isUser ? Colors.transparent : const Color(0xFFFFE1EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        m.text,
                        style: TextStyle(color: fg, fontWeight: FontWeight.w600, height: 1.25),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  // Mic: start/stop whisper record
                  IconButton(
                    onPressed: _toggleRecord,
                    style: IconButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red.shade400 : pale,
                    ),
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: pale,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFE1EB)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _tc,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Type your message…',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendText(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSending ? null : _sendText,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8FB1),
                      disabledBackgroundColor: Colors.pink.shade200,
                    ),
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
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
