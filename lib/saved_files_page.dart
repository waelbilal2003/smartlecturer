import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'services/local_storage_manager.dart';

/// 🔹 صفحة عرض الملفات المحفوظة محلياً
class SavedFilesPage extends StatefulWidget {
  const SavedFilesPage({super.key});

  @override
  State<SavedFilesPage> createState() => _SavedFilesPageState();
}

class _SavedFilesPageState extends State<SavedFilesPage> {
  List<SavedFileInfo> _savedFiles = [];
  bool _isLoading = true;
  int _totalStorageUsed = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedFiles();
  }

  /// ✅ تحميل الملفات المحفوظة
  Future<void> _loadSavedFiles() async {
    setState(() => _isLoading = true);

    try {
      final files = await LocalStorageManager.getSavedFiles();
      final storage = await LocalStorageManager.getTotalStorageUsed();

      setState(() {
        _savedFiles = files;
        _totalStorageUsed = storage;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('خطأ في تحميل الملفات: $e');
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في تحميل الملفات: $e',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ✅ حذف ملف
  Future<void> _deleteFile(SavedFileInfo fileInfo) async {
    final confirmed = await _showDeleteConfirmation(fileInfo.fileName);
    if (!confirmed) return;

    try {
      final success = await LocalStorageManager.deleteSavedFile(fileInfo);

      if (success) {
        await _loadSavedFiles(); // إعادة تحميل القائمة
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم حذف الملف بنجاح',
                textDirection: TextDirection.rtl,
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('فشل في حذف الملف');
      }
    } catch (e) {
      debugPrint('خطأ في حذف الملف: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في حذف الملف: $e',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ✅ فتح ملف
  Future<void> _openFile(SavedFileInfo fileInfo) async {
    try {
      final opened = await LocalStorageManager.openSavedFile(fileInfo);

      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لا يمكن فتح الملف. تأكد من وجود تطبيق لقراءة PDF',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في فتح الملف: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في فتح الملف: $e',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ✅ حوار تأكيد الحذف
  Future<bool> _showDeleteConfirmation(String fileName) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد الحذف', textDirection: TextDirection.rtl),
            content: Text(
              'هل أنت متأكد من حذف الملف "$fileName"؟\nلا يمكن التراجع عن هذه العملية.',
              textDirection: TextDirection.rtl,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('حذف', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// ✅ تنسيق حجم التخزين
  String _formatStorageSize(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024)
      return '${(bytes / 1024).toStringAsFixed(1)} كيلوبايت';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} ميجابايت';
  }

  /// ✅ تنظيف الملفات القديمة
  Future<void> _cleanupOldFiles() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(
              'تنظيف الملفات القديمة',
              textDirection: TextDirection.rtl,
            ),
            content: const Text(
              'سيتم حذف جميع الملفات الأقدم من 30 يوماً.\nهل تريد المتابعة؟',
              textDirection: TextDirection.rtl,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('تنظيف'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await LocalStorageManager.cleanupOldFiles();
      await _loadSavedFiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم تنظيف الملفات القديمة بنجاح',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في تنظيف الملفات: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في تنظيف الملفات: $e',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الملفات المحفوظة', textDirection: TextDirection.rtl),
        backgroundColor: Colors.blue.shade50,
        actions: [
          IconButton(
            onPressed: _loadSavedFiles,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'cleanup',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services, color: Colors.orange),
                    SizedBox(width: 8),
                    Text(
                      'تنظيف الملفات القديمة',
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'cleanup') {
                _cleanupOldFiles();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ✅ معلومات التخزين
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.storage, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'معلومات التخزين',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'عدد الملفات: ${_savedFiles.length}',
                  textDirection: TextDirection.rtl,
                ),
                Text(
                  'المساحة المستخدمة: ${_formatStorageSize(_totalStorageUsed)}',
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),

          // ✅ قائمة الملفات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _savedFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد ملفات محفوظة',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'قم بإنشاء تقرير PDF من الصفحة الرئيسية',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadSavedFiles,
                    child: ListView.builder(
                      itemCount: _savedFiles.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final file = _savedFiles[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.red.shade100,
                              child: Icon(
                                Icons.picture_as_pdf,
                                color: Colors.red.shade700,
                              ),
                            ),
                            title: Text(
                              file.fileName,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  file.formattedDate,
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                                Text(
                                  '${file.formattedSize} • ${file.description ?? 'بدون وصف'}',
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'open',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.open_in_new,
                                        color: Colors.blue,
                                      ),
                                      SizedBox(width: 8),
                                      Text('فتح'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('حذف'),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'open') {
                                  _openFile(file);
                                } else if (value == 'delete') {
                                  _deleteFile(file);
                                }
                              },
                            ),
                            onTap: () => _openFile(file),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
