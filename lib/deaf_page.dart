import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vad/vad.dart';

class DeafPage extends StatefulWidget {
  const DeafPage({super.key});

  @override
  State<DeafPage> createState() => _DeafPageState();
}

class _DeafPageState extends State<DeafPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // UI controllers
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _apiController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // API
  String _apiUrl = '';

  // VAD Handler
  VadHandlerBase? _vadHandler;
  StreamSubscription? _speechStartSub;
  StreamSubscription? _realSpeechStartSub;
  StreamSubscription? _speechEndSub;
  StreamSubscription? _vadErrorSub;
  StreamSubscription? _frameProcessedSub;

  // State flags
  bool _microphonePermissionGranted = false;
  bool _permissionsChecked = false;
  bool _isProcessing = false;
  bool _isListening = false;
  bool _inSpeechSegment = false;

  // إعدادات VAD القابلة للتعديل
  double _vadThreshold = 0.5;
  int _silenceDurationMs = 1500;
  int _minSpeechDurationMs = 800;

  // تتبع حالة السكوت والكلام
  Timer? _silenceTimer;
  DateTime? _speechStartTime;
  DateTime? _lastSpeechTime;

  // إحصائيات
  int _segmentCount = 0;
  int _totalProcessingTime = 0;
  List<String> _transcriptionHistory = [];

  // Visual & animation
  late AnimationController _micAnimationController;
  late Animation<double> _micScaleAnimation;
  late AnimationController _pulseAnimationController;
  late Animation<double> _pulseAnimation;
  late AnimationController _voiceActivityController;
  late Animation<Color?> _voiceActivityColor;
  late AnimationController _volumeAnimationController;
  late Animation<double> _volumeLevelAnimation;

  // مؤشرات الصوت
  double _currentVolume = 0.0;
  double _smoothedVolume = 0.0;
  final List<double> _volumeHistory = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupAnimations();
    _initializeVad();
  }

  void _setupAnimations() {
    _micAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _micScaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _micAnimationController,
        curve: Curves.elasticOut,
      ),
    );
    _pulseAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _voiceActivityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _voiceActivityColor = ColorTween(
      begin: Colors.blue,
      end: Colors.green,
    ).animate(_voiceActivityController);
    _volumeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _volumeLevelAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _volumeAnimationController,
        curve: Curves.easeOut,
      ),
    );
  }

  Future<void> _initializeVad() async {
    await _loadSettings();
    await _checkPermissions();
    if (!_microphonePermissionGranted) {
      debugPrint('⚠️ لا يمكن تهيئة VAD بدون إذن الميكروفون');
      return;
    }
    try {
      _vadHandler = VadHandler.create(isDebug: true);
      _setupVadListeners();
      debugPrint('✅ تم تهيئة VAD بنجاح');
    } catch (e) {
      debugPrint('❌ فشل في تهيئة VAD: $e');
      _showErrorSnackbar('خطأ في تهيئة نظام تحليل الصوت');
    }
  }

  void _setupVadListeners() {
    if (_vadHandler == null) return;
    _speechStartSub = _vadHandler!.onSpeechStart.listen((_) {
      _handleSpeechStart();
    });
    _speechEndSub = _vadHandler!.onSpeechEnd.listen((List<double> samples) {
      _handleSpeechEnd(samples);
    });
    _vadErrorSub = _vadHandler!.onError.listen((String errorMessage) {
      debugPrint('VAD Error: $errorMessage');
      _showErrorSnackbar('خطأ في تحليل الصوت: $errorMessage');
    });
  }

  void _handleSpeechStart() {
    if (!mounted) return;
    setState(() {
      _inSpeechSegment = true;
      _speechStartTime = DateTime.now();
      _lastSpeechTime = DateTime.now();
    });
    _voiceActivityController.forward();
    _updateVolumeLevel(0.8);
    debugPrint('🎤 بداية الكلام المكتشف بواسطة VAD');
    HapticFeedback.lightImpact();
  }

  void _handleSpeechEnd(List<double> samples) {
    if (!mounted || _speechStartTime == null) return;
    final speechDuration = DateTime.now().difference(_speechStartTime!);
    setState(() {
      _inSpeechSegment = false;
    });
    _voiceActivityController.reverse();
    _updateVolumeLevel(0.0);
    debugPrint('⏹️ نهاية الكلام - المدة: ${speechDuration.inMilliseconds}ms');
    debugPrint('📊 عدد العينات: ${samples.length}');
    if (speechDuration.inMilliseconds >= _minSpeechDurationMs) {
      _processAudioSamples(samples);
    } else {
      debugPrint('⏭️ تجاهل كلام قصير: ${speechDuration.inMilliseconds}ms');
    }
  }

  void _updateVolumeLevel(double level) {
    if (!mounted) return;
    _currentVolume = level;
    _smoothedVolume = 0.7 * _smoothedVolume + 0.3 * _currentVolume;
    _volumeAnimationController.animateTo(
      _smoothedVolume,
      duration: const Duration(milliseconds: 100),
    );
    setState(() {
      _volumeHistory.add(_smoothedVolume);
      if (_volumeHistory.length > 50) {
        _volumeHistory.removeAt(0);
      }
    });
  }

  void _simulateVolumeChanges() {
    if (_inSpeechSegment) {
      final random = math.Random();
      final volume = 0.3 + random.nextDouble() * 0.7;
      _updateVolumeLevel(volume);
    }
  }

  // ===== إدارة التسجيل والمعالجة =====
  Future<void> _toggleContinuousListening() async {
    if (!_microphonePermissionGranted) {
      _showPermissionDialog();
      return;
    }

    // ✅ لا نمنع التشغيل إذا كان API فارغًا — نسمح بالمحاكاة
    if (_vadHandler == null) {
      _showErrorSnackbar('VAD غير مهيأ - يرجى إعادة تشغيل التطبيق');
      return;
    }

    if (_isListening) {
      await _stopContinuousListening();
    } else {
      await _startContinuousListening();
    }
  }

  Future<void> _startContinuousListening() async {
    if (_vadHandler == null) return;
    try {
      _vadHandler!.startListening(
        positiveSpeechThreshold: _vadThreshold,
        negativeSpeechThreshold: _vadThreshold - 0.15,
        preSpeechPadFrames: 1,
        redemptionFrames: 8,
        frameSamples: 1536,
        minSpeechFrames: (_minSpeechDurationMs / 96).ceil(),
        submitUserSpeechOnPause: false,
        model: 'legacy',
      );
      if (!mounted) return;
      setState(() {
        _isListening = true;
        _segmentCount = 0;
      });
      _micAnimationController.forward();
      _pulseAnimationController.repeat(reverse: true);
      _startVolumeSimulation();
      debugPrint('🎙️ بدء الاستماع المتواصل - عتبة VAD: $_vadThreshold');
      HapticFeedback.mediumImpact();
      _showSuccessSnackbar('بدء الاستماع المتواصل - جاهز لالتقاط الكلام');
    } catch (e) {
      debugPrint('❌ خطأ في بدء الاستماع: $e');
      _showErrorSnackbar('خطأ في بدء الاستماع المتواصل');
      if (mounted) {
        setState(() => _isListening = false);
      }
    }
  }

  Future<void> _stopContinuousListening() async {
    if (_vadHandler == null) return;
    try {
      _vadHandler!.stopListening();
      if (!mounted) return;
      setState(() => _isListening = false);
      _stopVolumeSimulation();
      _micAnimationController.reverse();
      _pulseAnimationController.stop();
      _voiceActivityController.reset();
      _volumeAnimationController.animateTo(0.0);
      debugPrint('🛑 إيقاف الاستماع المتواصل. القطع المعالجة: $_segmentCount');
      _showSuccessSnackbar(
        'تم إيقاف الاستماع - معالجة $_segmentCount قطعة صوتية',
      );
    } catch (e) {
      debugPrint('❌ خطأ في إيقاف الاستماع: $e');
      _showErrorSnackbar('خطأ في إيقاف الاستماع');
    }
  }

  Timer? _volumeSimulationTimer;
  void _startVolumeSimulation() {
    _volumeSimulationTimer?.cancel();
    _volumeSimulationTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_inSpeechSegment) {
        _simulateVolumeChanges();
      } else if (_isListening) {
        final random = math.Random();
        final noise = random.nextDouble() * 0.1;
        _updateVolumeLevel(noise);
      }
    });
  }

  void _stopVolumeSimulation() {
    _volumeSimulationTimer?.cancel();
    _volumeSimulationTimer = null;
  }

  Future<void> _processAudioSamples(List<double> samples) async {
    if (_isProcessing || !mounted) return;

    // ✅ إذا لم يكن هناك API، قم بمحاكاة النص
    if (_apiUrl.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 800));
      final fakeText = "هذا نص محاكاة للقطعة $_segmentCount";
      _segmentCount++;
      _transcriptionHistory.add(fakeText);
      if (mounted) {
        setState(() {
          if (_textController.text.isNotEmpty) _textController.text += '\n';
          _textController.text += '[$_segmentCount] $fakeText';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
      return;
    }

    setState(() => _isProcessing = true);
    final startTime = DateTime.now().millisecondsSinceEpoch;
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempPath = '${tempDir.path}/vad_segment_$timestamp.wav';
      await _saveSamplesAsWav(samples, tempPath);
      final audioFile = File(tempPath);
      debugPrint('📤 معالجة عينات الصوت: ${samples.length} عينة');

      final uri = Uri.parse('$_apiUrl/stt');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(
        await http.MultipartFile.fromPath('file', audioFile.path),
      );
      final response = await request.send().timeout(
            const Duration(seconds: 45),
          );
      final responseData = await response.stream.bytesToString();
      final processingTime = DateTime.now().millisecondsSinceEpoch - startTime;
      _totalProcessingTime += processingTime;

      if (response.statusCode == 200) {
        final json = jsonDecode(responseData);
        final text = (json['text'] as String?) ?? '';
        if (text.trim().isNotEmpty) {
          _segmentCount++;
          _transcriptionHistory.add(text);
          if (mounted) {
            setState(() {
              if (_textController.text.isNotEmpty) {
                _textController.text += '\n';
              }
              _textController.text += '[$_segmentCount] $text';
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            });
          }
          debugPrint(
            '✅ النص المحول ($_segmentCount): ${text.substring(0, math.min(text.length, 50))}...',
          );
          HapticFeedback.selectionClick();
        } else {
          debugPrint('📝 نص فارغ للقطعة $_segmentCount');
        }
      } else {
        debugPrint('❌ خطأ في الخادم ${response.statusCode}: $responseData');
        _showErrorSnackbar('خطأ في الخادم: ${response.statusCode}');
      }

      try {
        await audioFile.delete();
      } catch (e) {
        debugPrint('تحذير: لم يتم حذف الملف المؤقت: $e');
      }
    } catch (e) {
      debugPrint('❌ خطأ في معالجة العينات: $e');
      if (mounted) {
        _showErrorSnackbar(
          'خطأ في المعالجة: ${e.toString().substring(0, math.min(50, e.toString().length))}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _saveSamplesAsWav(List<double> samples, String path) async {
    try {
      const int sampleRate = 16000;
      const int numChannels = 1;
      const int bitsPerSample = 16;
      final int byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
      final int blockAlign = numChannels * bitsPerSample ~/ 8;
      final int dataSize = samples.length * 2;
      final int fileSize = 36 + dataSize;
      final file = File(path);
      final bytesBuilder = BytesBuilder();

      bytesBuilder.add('RIFF'.codeUnits);
      bytesBuilder.add(_int32ToBytes(fileSize));
      bytesBuilder.add('WAVE'.codeUnits);

      bytesBuilder.add('fmt '.codeUnits);
      bytesBuilder.add(_int32ToBytes(16));
      bytesBuilder.add(_int16ToBytes(1));
      bytesBuilder.add(_int16ToBytes(numChannels));
      bytesBuilder.add(_int32ToBytes(sampleRate));
      bytesBuilder.add(_int32ToBytes(byteRate));
      bytesBuilder.add(_int16ToBytes(blockAlign));
      bytesBuilder.add(_int16ToBytes(bitsPerSample));

      bytesBuilder.add('data'.codeUnits);
      bytesBuilder.add(_int32ToBytes(dataSize));

      for (var sample in samples) {
        int intSample = (sample.clamp(-1.0, 1.0) * 32767).round();
        bytesBuilder.add(_int16ToBytes(intSample));
      }

      await file.writeAsBytes(bytesBuilder.toBytes());
    } catch (e) {
      debugPrint('❌ خطأ في حفظ ملف WAV: $e');
      rethrow;
    }
  }

  List<int> _int32ToBytes(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  List<int> _int16ToBytes(int value) {
    return [value & 0xFF, (value >> 8) & 0xFF];
  }

  // ===== إدارة الإعدادات =====
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _apiUrl = prefs.getString('whisper_api_url') ?? '';
        _apiController.text = _apiUrl;
        _vadThreshold = prefs.getDouble('vad_threshold') ?? 0.5;
        _silenceDurationMs = prefs.getInt('silence_duration_ms') ?? 1500;
        _minSpeechDurationMs = prefs.getInt('min_speech_duration_ms') ?? 800;
      });
    } catch (e) {
      debugPrint('❌ خطأ في تحميل الإعدادات: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('whisper_api_url', _apiUrl);
      await prefs.setDouble('vad_threshold', _vadThreshold);
      await prefs.setInt('silence_duration_ms', _silenceDurationMs);
      await prefs.setInt('min_speech_duration_ms', _minSpeechDurationMs);
    } catch (e) {
      debugPrint('❌ خطأ في حفظ الإعدادات: $e');
    }
  }

  Future<void> _checkPermissions() async {
    try {
      final micStatus = await Permission.microphone.status;
      setState(() {
        _microphonePermissionGranted = micStatus == PermissionStatus.granted;
        _permissionsChecked = true;
      });
      if (!_microphonePermissionGranted) {
        final result = await Permission.microphone.request();
        setState(() {
          _microphonePermissionGranted = result == PermissionStatus.granted;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في الصلاحيات: $e');
      if (mounted) {
        setState(() => _permissionsChecked = true);
      }
    }
  }

  void _showSettingsDialog() {
    final thresholdController = TextEditingController(
      text: _vadThreshold.toStringAsFixed(2),
    );
    final silenceController = TextEditingController(
      text: _silenceDurationMs.toString(),
    );
    final minSpeechController = TextEditingController(
      text: _minSpeechDurationMs.toString(),
    );
    // ✅ نسخة مؤقتة من الـ API لتجنب التعديل المباشر على _apiController
    final apiTempController = TextEditingController(text: _apiUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات VAD المتقدمة'),
        content: Form(
          // <<<--- Form يمنع الانهيار
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'رابط API:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  // <<<--- TextFormField
                  controller: apiTempController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'https://your-api.com',
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'عتبة VAD (0.0 - 1.0):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: thresholdController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '0.5',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'مدة السكوت (مللي ثانية):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: silenceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '1500',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'أقل مدة للكلام (مللي ثانية):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: minSpeechController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '800',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'عتبة VAD: كلما قلت القيمة (أقرب إلى 0) أصبح النظام أكثر حساسية',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              _apiUrl = apiTempController.text.trim();
              if (_apiUrl.endsWith('/')) {
                _apiUrl = _apiUrl.substring(0, _apiUrl.length - 1);
              }

              final newThreshold = double.tryParse(thresholdController.text);
              final newSilence = int.tryParse(silenceController.text);
              final newMinSpeech = int.tryParse(minSpeechController.text);

              if (newThreshold != null &&
                  newThreshold >= 0.0 &&
                  newThreshold <= 1.0) {
                _vadThreshold = newThreshold;
              }
              if (newSilence != null && newSilence > 0) {
                _silenceDurationMs = newSilence;
              }
              if (newMinSpeech != null && newMinSpeech > 0) {
                _minSpeechDurationMs = newMinSpeech;
              }

              await _saveSettings();
              await _reinitializeVad();
              if (context.mounted) Navigator.pop(context);
              _showSuccessSnackbar('تم حفظ الإعدادات وإعادة تهيئة VAD');
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _reinitializeVad() async {
    try {
      await _speechStartSub?.cancel();
      await _speechEndSub?.cancel();
      await _vadErrorSub?.cancel();

      _vadHandler = VadHandler.create(isDebug: true);
      _setupVadListeners();

      if (_isListening && _vadHandler != null) {
        _vadHandler!.startListening(
          positiveSpeechThreshold: _vadThreshold,
          negativeSpeechThreshold: _vadThreshold - 0.15,
          minSpeechFrames: (_minSpeechDurationMs / 96).ceil(),
        );
      }
      debugPrint('✅ تمت إعادة تهيئة VAD بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في إعادة تهيئة VAD: $e');
      _showErrorSnackbar('خطأ في إعادة تهيئة VAD');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إذن الميكروفون مطلوب'),
        content: const Text(
          'يحتاج التطبيق إلى إذن الميكروفون لتحليل الصوت.\nاذهب إلى إعدادات التطبيق ومنح الإذن.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('الإعدادات'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndSendFile() async {
    // التحقق من وجود رابط API قبل البدء
    if (_apiUrl.isEmpty) {
      _showErrorSnackbar('يرجى إدخال رابط API في الإعدادات أولاً');
      return;
    }

    try {
      // 1. اختيار الملف الصوتي
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isProcessing = true); // تفعيل مؤشر التحميل
        _showSuccessSnackbar('جاري معالجة الملف الصوتي...');

        final startTime = DateTime.now().millisecondsSinceEpoch;
        final audioFile = File(result.files.single.path!);
        debugPrint('📤 جاري إرسال الملف: ${audioFile.path}');

        // 2. إعداد وإرسال الطلب (نفس منطق دالة الميكروفون)
        try {
          final uri = Uri.parse('$_apiUrl/stt');
          final request = http.MultipartRequest('POST', uri);
          request.files.add(
            await http.MultipartFile.fromPath('file', audioFile.path),
          );

          final response = await request.send().timeout(
              const Duration(seconds: 90)); // زيادة مهلة الوقت للملفات الكبيرة
          final responseData = await response.stream.bytesToString();
          final processingTime =
              DateTime.now().millisecondsSinceEpoch - startTime;

          // 3. معالجة الرد من الخادم
          if (response.statusCode == 200) {
            final json = jsonDecode(responseData);
            final text = (json['text'] as String?) ?? '';
            if (text.trim().isNotEmpty) {
              _segmentCount++; // زيادة العداد
              _transcriptionHistory.add(text);
              if (mounted) {
                setState(() {
                  if (_textController.text.isNotEmpty) {
                    _textController.text += '\n';
                  }
                  // إضافة علامة مميزة للنص القادم من ملف
                  _textController.text += '[ملف-$_segmentCount] $text';
                });
                // التمرير لأسفل تلقائياً
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
              debugPrint(
                  '✅ النص المحول من الملف: ${text.substring(0, math.min(text.length, 50))}...');
              _showSuccessSnackbar('تمت معالجة الملف بنجاح');
            } else {
              debugPrint('📝 نص فارغ من الملف');
              _showErrorSnackbar('لم يتمكن الخادم من استخراج نص من الملف');
            }
          } else {
            debugPrint('❌ خطأ في الخادم ${response.statusCode}: $responseData');
            _showErrorSnackbar('خطأ في الخادم: ${response.statusCode}');
          }
        } catch (e) {
          debugPrint('❌ خطأ في إرسال الملف: $e');
          _showErrorSnackbar('حدث خطأ أثناء إرسال الملف');
        } finally {
          if (mounted) {
            setState(() => _isProcessing = false); // إيقاف مؤشر التحميل
          }
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في اختيار الملف: $e');
      _showErrorSnackbar('خطأ في اختيار الملف');
    }
  }

  void _showErrorSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clearText() {
    setState(() {
      _textController.clear();
      _transcriptionHistory.clear();
      _segmentCount = 0;
      _volumeHistory.clear();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _silenceTimer?.cancel();
    _volumeSimulationTimer?.cancel();
    _speechStartSub?.cancel();
    _speechEndSub?.cancel();
    _vadErrorSub?.cancel();
    _vadHandler?.dispose();
    _micAnimationController.dispose();
    _pulseAnimationController.dispose();
    _voiceActivityController.dispose();
    _volumeAnimationController.dispose();
    _textController.dispose();
    _apiController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_isListening) {
        _stopContinuousListening();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final micColor = !_microphonePermissionGranted
        ? Colors.grey
        : (_isListening
            ? (_inSpeechSegment ? Colors.green : Colors.orange)
            : Colors.blue);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المحاضر الذكي'),
        backgroundColor: micColor.withOpacity(0.1),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsDialog,
            tooltip: 'الإعدادات',
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _pickAndSendFile,
            tooltip: 'رفع ملف صوتي',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            color: Colors.red,
            onPressed: _clearText,
            tooltip: 'مسح النص',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [micColor.withOpacity(0.1), micColor.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: micColor.withOpacity(0.3), width: 2),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _voiceActivityColor,
                      builder: (context, child) {
                        return Icon(
                          _isListening
                              ? (_inSpeechSegment
                                  ? Icons.record_voice_over
                                  : Icons.hearing)
                              : Icons.mic,
                          color: _voiceActivityColor.value ?? micColor,
                          size: 28,
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getStatusText(),
                            style: TextStyle(
                              color: micColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (_isListening) ...[
                            const SizedBox(height: 4),
                            Text(
                              'القطع المعالجة: $_segmentCount | العتبة: ${_vadThreshold.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: micColor.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_isProcessing)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isListening) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'حالة VAD: ${_inSpeechSegment ? "كلام نشط" : "في انتظار الكلام"}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'عتبة الحساسية: ${_vadThreshold.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'مستوى الصوت: ${(_smoothedVolume * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AdvancedVoiceActivityIndicator(
                    volumeLevel: _volumeLevelAnimation.value,
                    isActive: _inSpeechSegment,
                    volumeHistory: _volumeHistory,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.text_snippet, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        'النص المحول:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_transcriptionHistory.isNotEmpty)
                        Text(
                          'المجموع: ${_transcriptionHistory.length}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      scrollController: _scrollController,
                      maxLines: null,
                      expands: true,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontSize: 16, height: 1.6),
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'جاري الاستماع... سيظهر النص هنا تلقائياً عند اكتشاف الكلام'
                            : 'اضغط على زر الميكروفون لبدء الاستماع المتواصل',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _toggleContinuousListening,
                  child: AnimatedBuilder(
                    animation: _micScaleAnimation,
                    builder: (context, child) {
                      return AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _micScaleAnimation.value *
                                (_isListening ? _pulseAnimation.value : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_isListening)
                                  AnimatedBuilder(
                                    animation: _volumeLevelAnimation,
                                    builder: (context, child) {
                                      return Container(
                                        width: 100 +
                                            (_volumeLevelAnimation.value * 40),
                                        height: 100 +
                                            (_volumeLevelAnimation.value * 40),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: micColor.withOpacity(
                                            0.2 * _volumeLevelAnimation.value,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        micColor.withOpacity(0.9),
                                        micColor.withOpacity(0.7),
                                        micColor.withOpacity(0.5),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: micColor.withOpacity(
                                          _isListening ? 0.4 : 0.2,
                                        ),
                                        blurRadius: _isListening ? 25 : 12,
                                        spreadRadius: _isListening ? 8 : 3,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: _isProcessing
                                        ? const CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 3,
                                          )
                                        : Icon(
                                            _isListening
                                                ? Icons.stop
                                                : Icons.mic,
                                            color: Colors.white,
                                            size: 65,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isListening
                      ? 'اضغط لإيقاف الاستماع المتواصل'
                      : 'اضغط لبدء الاستماع المتواصل',
                  style: TextStyle(
                    color: micColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_isListening) ...[
                  const SizedBox(height: 8),
                  Text(
                    'عتبة VAD: ${_vadThreshold.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText() {
    if (!_microphonePermissionGranted) {
      return 'منح إذن الميكروفون للمتابعة';
    } else if (!_isListening) {
      return 'جاهز للاستماع المتواصل - اضغط للبدء';
    } else if (_isProcessing) {
      return 'جاري معالجة القطعة الصوتية...';
    } else if (_inSpeechSegment) {
      return 'يتم اكتشاف الكلام - جاري التسجيل...';
    } else {
      return 'في انتظار الكلام - VAD نشط';
    }
  }
}

// ===== widget مساعد متقدم للحالة الصوتية =====
class AdvancedVoiceActivityIndicator extends StatelessWidget {
  final double volumeLevel;
  final bool isActive;
  final List<double> volumeHistory;
  const AdvancedVoiceActivityIndicator({
    super.key,
    required this.volumeLevel,
    required this.isActive,
    required this.volumeHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.grey[300],
          ),
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: volumeLevel.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      colors: isActive
                          ? [Colors.green[400]!, Colors.green[600]!]
                          : [Colors.blue[400]!, Colors.blue[600]!],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (volumeHistory.isNotEmpty)
          SizedBox(
            height: 30,
            child: CustomPaint(
              painter: VolumeHistoryPainter(volumeHistory, isActive),
              size: const Size(double.infinity, 30),
            ),
          ),
      ],
    );
  }
}

class VolumeHistoryPainter extends CustomPainter {
  final List<double> volumeHistory;
  final bool isActive;
  VolumeHistoryPainter(this.volumeHistory, this.isActive);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isActive ? Colors.green : Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = isActive
          ? Colors.green.withOpacity(0.3)
          : Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    if (volumeHistory.isEmpty) return;
    final path = Path();
    final fillPath = Path();
    final stepX = size.width / math.max(volumeHistory.length - 1, 1);

    for (int i = 0; i < volumeHistory.length; i++) {
      final x = i * stepX;
      final y = size.height - (volumeHistory[i].clamp(0.0, 1.0) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
