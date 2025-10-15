// lib/views/chat/chat_fullscreen_page.dart
import 'dart:async';
import 'dart:convert'; // for base64 decode (server TTS fallback)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:record/record.dart'; // v5+ uses AudioRecorder + RecordConfig
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/gestures.dart'; // for clickable links
import 'package:flutter_dotenv/flutter_dotenv.dart'; // for .env file
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // open external links/maps
import '../../../../services/chat_services.dart';
import '../../../../services/location_service.dart'; // Google Places API

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
  late final LocationService _locSvc;

  bool _sending = false;
  bool _botTyping = false;

  // Voice (record v5+ API)
  final AudioRecorder _rec = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;

  // TTS
  final FlutterTts _tts = FlutterTts();
  String? _speakingMsgId;
  late final AudioPlayer _readbackPlayer;

  // Firestore
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Supabase
  final SupabaseClient _supa = Supabase.instance.client;

  DocumentReference<Map<String, dynamic>>? _chatRef;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _msgSub;
  final List<_Msg> _messages = <_Msg>[];

  // session id for backend (use Firebase uid)
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _svc = ChatService.fromEnv();

    // Load Google Maps API key from .env file
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

    if (apiKey.isEmpty) {
      debugPrint('⚠️ ERROR: GOOGLE_MAPS_API_KEY not found in .env file!');
      debugPrint('Make sure your .env file contains: GOOGLE_MAPS_API_KEY=your_api_key');
    } else {
      debugPrint('✅ Google Maps API key loaded from .env successfully');
    }

    _locSvc = LocationService(apiKey: apiKey);
    _readbackPlayer = AudioPlayer();
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
    _readbackPlayer.dispose();
    super.dispose();
  }

  // ---------------------- URL open helper ------------------------------------

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      Get.snackbar('Open link', 'Could not open the link.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  // ---------------------- Location intent detection --------------------------

  bool _isLocationQuery(String text) {
    final lower = text.toLowerCase();
    const locationKeywords = [
      'doctor',
      'doctors',
      'gynecologist',
      'gynaecologist',
      'thyroid',
      'specialist',
      'near me',
      'around me',
      'nearby',
      'find',
      'search',
      'locate',
      'hospital',
      'clinic',
      'md',
      ' in ', // detect "doctors in X location"
      ' at ', // detect "doctors at X location"
      ' around ', // detect "doctors around X location"
    ];
    return locationKeywords.any((kw) => lower.contains(kw));
  }

  String _extractSpecialty(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('gynecologist') || lower.contains('gynaecologist')) {
      return 'gynecologist';
    }
    if (lower.contains('thyroid')) return 'thyroid specialist';
    if (lower.contains('cardiologist')) return 'cardiologist';
    if (lower.contains('dermatologist')) return 'dermatologist';
    if (lower.contains('pediatrician')) return 'pediatrician';
    if (lower.contains('orthopedic')) return 'orthopedic';
    if (lower.contains('neurologist')) return 'neurologist';
    if (lower.contains('psychiatrist')) return 'psychiatrist';
    if (lower.contains('dentist')) return 'dentist';
    if (lower.contains('hospital')) return 'hospital';
    return 'doctor';
  }

  // Updated location search handler
  Future<void> _handleLocationSearch(String userQuery) async {
    // Extract custom location from query
    String? _extractLocation(String text) {
      final lower = text.toLowerCase();

      // Patterns: "in X", "at X", "around X", "near X"
      final patterns = [
        RegExp(r'\bin\s+([a-z\s,]+?)(?:\s+for|\s+find|\s+search|$)', caseSensitive: false),
        RegExp(r'\bat\s+([a-z\s,]+?)(?:\s+for|\s+find|\s+search|$)', caseSensitive: false),
        RegExp(r'\baround\s+([a-z\s,]+?)(?:\s+for|\s+find|\s+search|$)', caseSensitive: false),
        RegExp(r'\bnear\s+([a-z\s,]+?)(?:\s+for|\s+find|\s+search|$)', caseSensitive: false),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(text);
        if (match != null && match.group(1) != null) {
          var location = match.group(1)!.trim();
          // Clean up common noise words
          location = location.replaceAll(RegExp(r'\s+(area|locality|region)$'), '');
          if (location.length > 3 && !location.contains('near me')) {
            return location;
          }
        }
      }

      return null;
    }

    String? extractGender(String text) {
      final lower = text.toLowerCase();

      if (lower.contains('female doctor') ||
          lower.contains('lady doctor') ||
          lower.contains('women doctor') ||
          lower.contains('female gynecologist') ||
          lower.contains('lady gynecologist') ||
          lower.contains('female specialist') ||
          lower.contains('woman doctor') ||
          lower.contains('female cardiologist') ||
          lower.contains('female dermatologist') ||
          lower.contains('female pediatrician')) {
        return 'female';
      }

      if (lower.contains('male doctor') ||
          lower.contains('male gynecologist') ||
          lower.contains('gentleman doctor') ||
          lower.contains('male specialist') ||
          lower.contains('male cardiologist') ||
          lower.contains('male dermatologist') ||
          lower.contains('male pediatrician')) {
        return 'male';
      }

      return null;
    }

    try {
      final customLocation = _extractLocation(userQuery);
      final gender = extractGender(userQuery);
      final specialty = _extractSpecialty(userQuery);

      double? searchLat;
      double? searchLon;
      String locationDescription = 'your location';

      if (customLocation != null && customLocation.isNotEmpty) {
        // Geocode the custom location
        await _addBotMessage(
          text: "🔍 Looking for ${gender != null ? '**$gender** ' : ''}**${specialty}s** in **$customLocation**...",
          lang: 'en',
        );

        final coords = await _locSvc.geocodeLocation(customLocation);
        if (coords == null) {
          await _addBotMessage(
            text: "❌ I couldn't find the location '$customLocation'. Please try with a more specific address like 'Patia, Bhubaneswar' or use your current location.",
            lang: 'en',
          );
          return;
        }

        searchLat = coords.latitude;
        searchLon = coords.longitude;
        locationDescription = coords.formattedAddress;
      } else {
        // Use current location
        final ok = await _locSvc.ensureLocationReady();
        if (!ok) {
          await _addBotMessage(
            text: "❌ I couldn't access your location. Please allow location **and** turn on Location Services (GPS). On Xiaomi/MIUI, set permission to **Allow while in use** and enable **Precise**.",
            lang: 'en',
          );
          return;
        }

        final position = await _locSvc.getCurrentLocation();
        if (position == null) {
          await _addBotMessage(
            text: "❌ Still couldn't read your location. Please try again after enabling Location Services.",
            lang: 'en',
          );
          return;
        }

        searchLat = position.latitude;
        searchLon = position.longitude;
      }

      // Search for doctors
      final doctors = await _locSvc.searchDoctors(
        specialty: specialty,
        latitude: searchLat,
        longitude: searchLon,
        radius: 5000,
        gender: gender,
      );

      if (doctors.isEmpty) {
        final genderText = gender != null ? '**$gender** ' : '';
        await _addBotMessage(
          text: "😔 I couldn't find any $genderText**${specialty}s** near **$locationDescription**. Try widening your search area or removing the gender filter.",
          lang: 'en',
        );
        return;
      }

      // Add disclaimer for gender filtering
      final genderText = gender != null ? ' (**$gender**)' : '';
      final genderNote = gender != null
          ? '\n\n_ℹ️ Note: Gender filtering is based on name patterns (Dr. Mrs, Dr. Mr, common names) and may not be 100% accurate. Results without clear gender indicators are included but placed lower in the list._\n'
          : '';

      final buffer = StringBuffer(
          "✅ Found **${doctors.length} ${specialty}s$genderText** near **$locationDescription**:$genderNote\n"
      );
      final doctorData = <Map<String, dynamic>>[];

      for (int i = 0; i < doctors.length; i++) {
        final d = doctors[i];
        final ratingStr = d.rating != null
            ? '⭐ ${d.rating!.toStringAsFixed(1)} (${d.userRatingsTotal ?? 0} reviews)'
            : '⭐ No reviews yet';

        buffer.writeln("**${i + 1}. ${d.name}**");

        // Add gender indicator if detected
        if (d.detectedGender != null) {
          final genderEmoji = d.detectedGender == 'female' ? '👩‍⚕️' : '👨‍⚕️';
          buffer.writeln("   $genderEmoji ${d.detectedGender == 'female' ? 'Female' : 'Male'} Doctor");
        }

        if (d.address.trim().isNotEmpty) {
          buffer.writeln("   📍 ${d.address}");
        }

        buffer.writeln("   $ratingStr");

        if (!d.isOpen) {
          buffer.writeln("   ⚠️ **Currently closed**");
        }

        final mapsUrl = LocationService.getGoogleMapsUrl(d);
        buffer.writeln("   [📱 Open in Google Maps]($mapsUrl)\n");

        doctorData.add(d.toJson());
      }

      await _addBotMessage(
        text: buffer.toString(),
        lang: 'en',
        metadata: {
          'doctors': doctorData,
          'search_location': locationDescription,
          'gender_filter': gender,
          'specialty': specialty,
        },
      );
    } catch (e) {
      debugPrint('Location search error: $e');
      await _addBotMessage(
        text: "❌ Sorry, I had trouble searching for doctors. Please try again or check your internet connection.",
        lang: 'en',
      );
    }
  }


  // ---------------------- TTS setup & per-message toggle ---------------------

  String _localeFor(String? appLang) {
    switch (appLang) {
      case 'hi':
        return 'hi-IN';
      case 'en':
        return 'en-US';
      case 'es':
        return 'es-ES';
      case 'fr':
        return 'fr-FR';
      default:
        return ''; // unsupported → use server TTS
    }
  }

  Future<void> _initTts() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      if (!mounted) return;
      setState(() {});
    });
    _tts.setCompletionHandler(() {
      if (!mounted) return;
      setState(() => _speakingMsgId = null);
    });
    _tts.setCancelHandler(() {
      if (!mounted) return;
      setState(() => _speakingMsgId = null);
    });
    _tts.setErrorHandler((_) {
      if (!mounted) return;
      setState(() => _speakingMsgId = null);
    });
  }

  Future<void> _toggleSpeakFor(_Msg m) async {
    final text = m.text?.trim() ?? '';
    if (text.isEmpty) return;

    if (_speakingMsgId == m.id) {
      await _tts.stop();
      await _readbackPlayer.stop();
      setState(() => _speakingMsgId = null);
      return;
    }

    await _tts.stop();
    await _readbackPlayer.stop();

    final locale = _localeFor(m.lang);
    setState(() => _speakingMsgId = m.id);

    if (locale.isNotEmpty) {
      try {
        await _tts.setLanguage(locale);
        await _tts.speak(text);
        return;
      } catch (_) {
        // fall through to server TTS
      }
    }

    try {
      final ttsRes = await _svc.tts(text: text, lang: (m.lang ?? 'en'));
      final b64 = (ttsRes['audio_base64'] ?? '') as String;
      if (b64.isEmpty) throw Exception('No audio from server TTS');
      final bytes = base64Decode(b64);
      await _readbackPlayer.setAudioSource(ByteStreamAudioSource(bytes));
      await _readbackPlayer.play();
      _readbackPlayer.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .then((_) {
        if (!mounted) return;
        setState(() => _speakingMsgId = null);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _speakingMsgId = null);
      Get.snackbar('TTS', 'Could not speak message.',
          snackPosition: SnackPosition.BOTTOM);
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
      await _addBotMessage(
          text: "Hi! Ask me anything — text or voice. 💖", lang: null);
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

  Future<void> _addBotMessage({
    required String text,
    String? lang,
    Map<String, dynamic>? metadata, // store doctor list if present
  }) async {
    final ref = _chatRef!;
    await ref.collection('messages').add({
      'sender': 'bot',
      'type': 'text',
      'text': text,
      'lang': lang,
      if (metadata != null) 'metadata': metadata,
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

  // TEXT → (doctor search if intent) else → /message
  Future<void> _sendText() async {
    final raw = _tc.text.trim();
    if (raw.isEmpty || _sending) return;
    if (_sessionId == null) {
      Get.snackbar('Session', 'Please wait, initializing…',
          snackPosition: SnackPosition.BOTTOM);
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
      if (_isLocationQuery(raw)) {
        await _handleLocationSearch(raw);
      } else {
        final res = await _svc.sendMessage(
          sessionId: _sessionId!,
          message: raw,
          speechOut: false, // we use on-device/server TTS in this widget
        );

        final reply = (res['reply'] ?? '').toString();
        final replyLang = (res['reply_lang'] ?? 'en').toString();

        await _addBotMessage(text: reply, lang: replyLang);
      }
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

  // VOICE → /stt → (doctor search if intent) else → /message
  Future<void> _handleRecordedFile(File file) async {
    if (_sending) return;
    if (_sessionId == null) {
      Get.snackbar('Session', 'Please wait, initializing…',
          snackPosition: SnackPosition.BOTTOM);
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
      final result = await _svc.chatFromAudio(
        sessionId: _sessionId!,
        audioFile: file,
        speechOut: false,
      );

      // STT payload
      final stt = (result['stt'] as Map<String, dynamic>?);
      final spokenText = (stt?['text'] ?? '').toString();
      final detected =
      (stt?['text_out_lang'] ?? stt?['detected_lang'] ?? '').toString();

      if (spokenText.isNotEmpty) {
        await _updateUserVoiceTranscript(
            messageId: doc.id, transcript: spokenText);

        if (_isLocationQuery(spokenText)) {
          await _handleLocationSearch(spokenText);
        } else {
          // Chat payload
          final chat = (result['chat'] as Map<String, dynamic>?);
          final reply = (chat?['reply'] ?? '').toString();
          final replyLang = (chat?['reply_lang'] ?? detected).toString();
          await _addBotMessage(text: reply, lang: replyLang);
        }
      } else {
        await _updateUserVoiceTranscript(
            messageId: doc.id, transcript: '[unrecognized]');
        await _addBotMessage(
            text: "Couldn't understand that. Try again closer to the mic?");
      }
    } catch (e) {
      await _addBotMessage(
          text: "Couldn't process that audio. Try again closer to the mic?");
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
                width: 40,
                height: 4,
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

  // Parse **bold**, *italic*, and [text](url)
  List<InlineSpan> _spansWithMarkdown(String input, TextStyle base) {
    final text = _normalizeBullets(input);
    final spans = <InlineSpan>[];

    // First split by links so we can attach recognizers
    final linkRe = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
    int idx = 0;

    void addBoldItalic(String chunk) {
      if (chunk.isEmpty) return;
      // handle newlines
      final lines = chunk.split('\n');
      for (int li = 0; li < lines.length; li++) {
        final line = lines[li];
        final bi = RegExp(r'(\*\*([^\*]+)\*\*|\*([^\*]+)\*)');
        int j = 0;
        for (final m in bi.allMatches(line)) {
          if (m.start > j) {
            spans.add(TextSpan(text: line.substring(j, m.start), style: base));
          }
          final bold = m.group(2);
          final italic = m.group(3);
          if (bold != null) {
            spans.add(TextSpan(
                text: bold,
                style: base.merge(const TextStyle(fontWeight: FontWeight.w800))));
          } else if (italic != null) {
            spans.add(TextSpan(
                text: italic,
                style: base.merge(const TextStyle(fontStyle: FontStyle.italic))));
          }
          j = m.end;
        }
        if (j < line.length) {
          spans.add(TextSpan(text: line.substring(j), style: base));
        }
        if (li != lines.length - 1) spans.add(const TextSpan(text: '\n'));
      }
    }

    for (final m in linkRe.allMatches(text)) {
      // pre-link text
      if (m.start > idx) {
        addBoldItalic(text.substring(idx, m.start));
      }

      final label = m.group(1) ?? '';
      final url = m.group(2) ?? '';
      spans.add(TextSpan(
        text: label,
        style: base.merge(const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        )),
        recognizer: (TapGestureRecognizer()
          ..onTap = () {
            _openUrl(url);
          }),
      ));

      idx = m.end;
    }

    // tail
    if (idx < text.length) {
      addBoldItalic(text.substring(idx));
    }

    return spans;
  }

  Widget _richMessage(String text, {required bool isUser, String? lang}) {
    final style = TextStyle(
      color: isUser ? Colors.white : Colors.black87,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    return SelectableText.rich(
      TextSpan(children: _spansWithMarkdown(text, style)),
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
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
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
                  alignment:
                  isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    onLongPress: () => _showMessageMenu(m),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      margin:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
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
  final String? id; // Firestore doc ID (for delete)
  final bool isUser;
  final DateTime? createdAt;

  // text
  final String? text;
  final String? lang;

  // voice
  final String? audioUrl; // signed URL (may expire)
  final String? audioPath; // stable storage path in Supabase
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
            .createSignedUrl(
            widget.message.audioPath!, const Duration(days: 7).inSeconds);
        await _player.setUrl(fresh);
      }
      _duration = _player.duration ?? widget.message.audioDuration;
    } catch (_) {
      if ((widget.message.audioPath ?? '').isNotEmpty) {
        try {
          final fresh = await Supabase.instance.client.storage
              .from('voices')
              .createSignedUrl(
              widget.message.audioPath!, const Duration(days: 7).inSeconds);
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
    _ac =
    AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
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