import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import '../permission_helper.dart';

/// 🔹 مدير التخزين المحلي المحسن للملفات
/// يدير حفظ وعرض وفتح الملفات المحفوظة محلياً
class LocalStorageManager {
  static const String _tag = 'LocalStorageManager';
  static Database? _database;

  /// ✅ قاعدة البيانات المحلية لتتبع الملفات المحفوظة
  static Future<Database> get database async {
    if (_database != null) return _database!;
    
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = '${documentsDirectory.path}/saved_files.db';
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE saved_files(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            fileName TEXT NOT NULL,
            filePath TEXT NOT NULL,
            fileType TEXT NOT NULL,
            fileSize INTEGER NOT NULL,
            createdAt TEXT NOT NULL,
            description TEXT
          )
        ''');
      },
    );
  }

  /// ✅ حفظ ملف PDF مع خيارات متعددة
  static Future<SavedFileResult> savePdfFile({
    required List<int> pdfBytes,
    required String fileName,
    String? description,
    SaveLocation saveLocation = SaveLocation.appDocuments,
  }) async {
    try {
      debugPrint('$_tag: بدء حفظ الملف: $fileName');
      
      // الحصول على مجلد الحفظ المناسب
      Directory saveDir = await _getSaveDirectory(saveLocation);
      
      // إنشاء اسم ملف فريد مع طابع زمني
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final uniqueFileName = '${fileName.replaceAll('.pdf', '')}_$timestamp.pdf';
      final filePath = '${saveDir.path}/$uniqueFileName';

      // حفظ الملف
      final file = File(filePath);
      await file.writeAsBytes(pdfBytes);

      // تسجيل الملف في قاعدة البيانات
      final savedFile = SavedFileInfo(
        fileName: uniqueFileName,
        filePath: filePath,
        fileType: 'PDF',
        fileSize: pdfBytes.length,
        createdAt: DateTime.now(),
        description: description ?? 'ملف PDF محول من الصوت',
      );

      await _saveFileToDatabase(savedFile);

      debugPrint('$_tag: تم حفظ الملف بنجاح: $filePath');
      
      return SavedFileResult(
        success: true,
        filePath: filePath,
        fileName: uniqueFileName,
        message: 'تم حفظ الملف بنجاح في ${saveLocation.displayName}',
        fileInfo: savedFile,
      );

    } catch (e) {
      debugPrint('$_tag: خطأ في حفظ الملف: $e');
      return SavedFileResult(
        success: false,
        message: 'فشل في حفظ الملف: $e',
      );
    }
  }

  /// ✅ الحصول على مجلد الحفظ المناسب
  static Future<Directory> _getSaveDirectory(SaveLocation location) async {
    switch (location) {
      case SaveLocation.downloads:
        // محاولة الحصول على مجلد التنزيلات
        try {
          final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
          if (dirs != null && dirs.isNotEmpty) {
            return dirs.first;
          }
        } catch (e) {
          debugPrint('$_tag: فشل الوصول لمجلد Downloads: $e');
        }
        // استخدام مجلد التطبيق كبديل
        return await getApplicationDocumentsDirectory();

      case SaveLocation.externalDocuments:
        // محاولة الحصول على مجلد المستندات الخارجي
        try {
          final dirs = await getExternalStorageDirectories(type: StorageDirectory.documents);
          if (dirs != null && dirs.isNotEmpty) {
            return dirs.first;
          }
        } catch (e) {
          debugPrint('$_tag: فشل الوصول لمجلد Documents الخارجي: $e');
        }
        return await getApplicationDocumentsDirectory();

      case SaveLocation.appDocuments:
      default:
        return await getApplicationDocumentsDirectory();
    }
  }

  /// ✅ حفظ معلومات الملف في قاعدة البيانات
  static Future<void> _saveFileToDatabase(SavedFileInfo fileInfo) async {
    final db = await database;
    await db.insert('saved_files', fileInfo.toMap());
  }

  /// ✅ الحصول على جميع الملفات المحفوظة
  static Future<List<SavedFileInfo>> getSavedFiles() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'saved_files',
        orderBy: 'createdAt DESC',
      );

      return maps.map((map) => SavedFileInfo.fromMap(map)).toList();
    } catch (e) {
      debugPrint('$_tag: خطأ في جلب الملفات المحفوظة: $e');
      return [];
    }
  }

  /// ✅ فتح ملف محفوظ
  static Future<bool> openSavedFile(SavedFileInfo fileInfo) async {
    try {
      // التحقق من وجود الملف
      final file = File(fileInfo.filePath);
      if (!await file.exists()) {
        debugPrint('$_tag: الملف غير موجود: ${fileInfo.filePath}');
        return false;
      }

      // فتح الملف
      final result = await OpenFilex.open(fileInfo.filePath);
      debugPrint('$_tag: نتيجة فتح الملف: ${result.message}');
      
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('$_tag: خطأ في فتح الملف: $e');
      return false;
    }
  }

  /// ✅ حذف ملف محفوظ
  static Future<bool> deleteSavedFile(SavedFileInfo fileInfo) async {
    try {
      // حذف الملف من النظام
      final file = File(fileInfo.filePath);
      if (await file.exists()) {
        await file.delete();
      }

      // حذف سجل الملف من قاعدة البيانات
      final db = await database;
      await db.delete(
        'saved_files',
        where: 'id = ?',
        whereArgs: [fileInfo.id],
      );

      debugPrint('$_tag: تم حذف الملف بنجاح: ${fileInfo.fileName}');
      return true;
    } catch (e) {
      debugPrint('$_tag: خطأ في حذف الملف: $e');
      return false;
    }
  }

  /// ✅ الحصول على حجم جميع الملفات المحفوظة
  static Future<int> getTotalStorageUsed() async {
    try {
      final files = await getSavedFiles();
      int totalSize = 0;
      
      for (final fileInfo in files) {
        final file = File(fileInfo.filePath);
        if (await file.exists()) {
          final stat = await file.stat();
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (e) {
      debugPrint('$_tag: خطأ في حساب حجم التخزين: $e');
      return 0;
    }
  }

  /// ✅ تنظيف الملفات القديمة (اختياري)
  static Future<void> cleanupOldFiles({int maxAgeInDays = 30}) async {
    try {
      final db = await database;
      final cutoffDate = DateTime.now().subtract(Duration(days: maxAgeInDays));
      
      // جلب الملفات القديمة
      final List<Map<String, dynamic>> oldFiles = await db.query(
        'saved_files',
        where: 'createdAt < ?',
        whereArgs: [cutoffDate.toIso8601String()],
      );

      // حذف الملفات القديمة
      for (final fileMap in oldFiles) {
        final fileInfo = SavedFileInfo.fromMap(fileMap);
        await deleteSavedFile(fileInfo);
      }

      debugPrint('$_tag: تم تنظيف ${oldFiles.length} ملف قديم');
    } catch (e) {
      debugPrint('$_tag: خطأ في تنظيف الملفات القديمة: $e');
    }
  }
}

/// 🔸 أماكن الحفظ المتاحة
enum SaveLocation {
  appDocuments('مجلد التطبيق'),
  downloads('مجلد التنزيلات'),
  externalDocuments('المستندات الخارجية');

  const SaveLocation(this.displayName);
  final String displayName;
}

/// 🔸 نتيجة حفظ الملف
class SavedFileResult {
  final bool success;
  final String? filePath;
  final String? fileName;
  final String message;
  final SavedFileInfo? fileInfo;

  SavedFileResult({
    required this.success,
    this.filePath,
    this.fileName,
    required this.message,
    this.fileInfo,
  });
}

/// 🔸 معلومات الملف المحفوظ
class SavedFileInfo {
  final int? id;
  final String fileName;
  final String filePath;
  final String fileType;
  final int fileSize;
  final DateTime createdAt;
  final String? description;

  SavedFileInfo({
    this.id,
    required this.fileName,
    required this.filePath,
    required this.fileType,
    required this.fileSize,
    required this.createdAt,
    this.description,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'filePath': filePath,
      'fileType': fileType,
      'fileSize': fileSize,
      'createdAt': createdAt.toIso8601String(),
      'description': description,
    };
  }

  factory SavedFileInfo.fromMap(Map<String, dynamic> map) {
    return SavedFileInfo(
      id: map['id'],
      fileName: map['fileName'],
      filePath: map['filePath'],
      fileType: map['fileType'],
      fileSize: map['fileSize'],
      createdAt: DateTime.parse(map['createdAt']),
      description: map['description'],
    );
  }

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize بايت';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} كيلوبايت';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} ميجابايت';
  }

  String get formattedDate {
    return DateFormat('yyyy/MM/dd - HH:mm').format(createdAt);
  }
}