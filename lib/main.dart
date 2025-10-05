import 'dart:async';
import 'package:flutter/material.dart';
import 'deaf_page.dart';
import 'dart:io';
import 'http_override.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SplashPage(),
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    // ✅ طلب الأذونات المطلوبة ثم الانتقال للصفحة الرئيسية
    _initializeApp();
  }

  /// ✅ تهيئة التطبيق وطلب الأذونات المطلوبة
  Future<void> _initializeApp() async {
    // انتظار لعرض شاشة البداية
    await Future.delayed(const Duration(seconds: 2));

    // طلب الأذونات المطلوبة
    await _requestInitialPermissions();

    // الانتقال للصفحة الرئيسية
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => const DeafPage(),
      ));
    }
  }

  /// ✅ طلب الأذونات الأساسية عند بدء التطبيق
  Future<void> _requestInitialPermissions() async {
    if (Platform.isAndroid) {
      // قائمة الأذونات المطلوبة
      List<Permission> permissions = [
        Permission.microphone, // لتسجيل الصوت
        Permission.camera, // للكاميرا
        Permission.storage, // للإصدارات الأقدم
        Permission.manageExternalStorage, // Android 11+
        Permission.photos, // Android 13+ للصور
        Permission.videos, // Android 13+ للفيديو
        Permission.audio, // Android 13+ للصوت
      ];

      try {
        // طلب الأذونات
        Map<Permission, PermissionStatus> statuses =
            await permissions.request();

        // طباعة نتائج الأذونات للتتبع
        for (var entry in statuses.entries) {
          debugPrint('إذن ${entry.key}: ${entry.value}');
        }

        // التحقق من الأذونات الحرجة
        if (!await Permission.microphone.isGranted) {
          debugPrint('⚠️ لم يتم منح إذن الميكروفون');
        }

        // للأذونات الخاصة مثل MANAGE_EXTERNAL_STORAGE
        if (!await Permission.manageExternalStorage.isGranted) {
          debugPrint('ℹ️ لم يتم منح إذن إدارة الملفات - سيتم طلبه عند الحاجة');
        }
      } catch (e) {
        debugPrint('❌ خطأ في طلب الأذونات: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset('assets/images/logo.png',
            width: 200, height: 200, fit: BoxFit.contain),
      ),
    );
  }
}
