import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionHelper {
  static const String _tag = 'PermissionHelper';

  /// ✅ التحقق من إصدار Android
  static Future<int> getAndroidSdkVersion() async {
    if (Platform.isAndroid) {
      try {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.version.sdkInt;
      } catch (e) {
        debugPrint('$_tag: خطأ في الحصول على إصدار Android: $e');
        return 30; // افتراضي
      }
    }
    return 0;
  }

  /// ✅ طلب أذونات التخزين المناسبة حسب إصدار Android
  static Future<bool> requestStoragePermissions(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = await getAndroidSdkVersion();
    debugPrint('$_tag: Android SDK Version: $sdkVersion');

    try {
      if (sdkVersion >= 33) {
        // Android 13+
        return await _requestAndroid13PlusPermissions(context);
      } else if (sdkVersion >= 30) {
        // Android 11-12
        return await _requestAndroid11PlusPermissions(context);
      } else {
        // Android 10 وأقل
        return await _requestLegacyStoragePermissions();
      }
    } catch (e) {
      debugPrint('$_tag: خطأ في طلب أذونات التخزين: $e');
      return false;
    }
  }

  /// ✅ أذونات Android 13+ (API 33+)
  static Future<bool> _requestAndroid13PlusPermissions(
      BuildContext context) async {
    // المحاولة الأولى: MANAGE_EXTERNAL_STORAGE (الأفضل)
    if (await Permission.manageExternalStorage.isGranted) {
      debugPrint('$_tag: MANAGE_EXTERNAL_STORAGE مُمنوح مسبقاً');
      return true;
    }

    // إظهار حوار توضيحي للمستخدم
    bool shouldRequest = await _showPermissionDialog(
      context,
      'إذن الوصول للملفات',
      'يحتاج التطبيق للوصول إلى ملفاتك لحفظ ملفات PDF.\n\n'
          'سيتم توجيهك لصفحة الإعدادات لمنح الإذن.',
    );

    if (!shouldRequest) return false;

    // طلب MANAGE_EXTERNAL_STORAGE
    var manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) {
      debugPrint('$_tag: MANAGE_EXTERNAL_STORAGE تم منحه');
      return true;
    }

    // المحاولة الثانية: الأذونات الخاصة بنوع الملف
    List<Permission> mediaPermissions = [
      Permission.photos, // READ_MEDIA_IMAGES
      Permission.videos, // READ_MEDIA_VIDEO
      Permission.audio, // READ_MEDIA_AUDIO
    ];

    Map<Permission, PermissionStatus> statuses =
        await mediaPermissions.request();

    bool hasAnyPermission = statuses.values.any((status) => status.isGranted);

    if (hasAnyPermission) {
      debugPrint('$_tag: تم منح بعض أذونات الوسائط');
      return true;
    }

    debugPrint('$_tag: فشل في الحصول على أذونات Android 13+');
    return false;
  }

  /// ✅ أذونات Android 11-12 (API 30-32)
  static Future<bool> _requestAndroid11PlusPermissions(
      BuildContext context) async {
    // محاولة MANAGE_EXTERNAL_STORAGE أولاً
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    var manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) {
      return true;
    }

    // إذا فشل، استخدم الأذونات التقليدية مع Scoped Storage
    return await _requestLegacyStoragePermissions();
  }

  /// ✅ أذونات Android 10 وأقل (Legacy Storage)
  static Future<bool> _requestLegacyStoragePermissions() async {
    var storageStatus = await Permission.storage.request();
    debugPrint('$_tag: Storage permission status: $storageStatus');
    return storageStatus.isGranted;
  }

  /// ✅ إظهار حوار توضيحي للمستخدم
  static Future<bool> _showPermissionDialog(
      BuildContext context, String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title, textDirection: TextDirection.rtl),
            content: Text(message, textDirection: TextDirection.rtl),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('موافق'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// ✅ التحقق من حالة أذونات التخزين
  static Future<bool> hasStoragePermissions() async {
    if (!Platform.isAndroid) return true;

    // التحقق من MANAGE_EXTERNAL_STORAGE أولاً
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // التحقق من الأذونات الأخرى
    return await Permission.storage.isGranted ||
        await Permission.photos.isGranted ||
        await Permission.videos.isGranted ||
        await Permission.audio.isGranted;
  }
}
