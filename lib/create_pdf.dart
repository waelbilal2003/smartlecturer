import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'permission_helper.dart';
import 'services/local_storage_manager.dart';

/// 🔹 هذه الدالة تقوم بإنشاء ملف PDF يحتوي على النصوص المحولة من الصوت.
///
/// [transcriptionHistory] قائمة بالنصوص (مع الطوابع الزمنية)
/// [context] لعرض Snackbars (اختياري)
/// [saveLocation] مكان حفظ الملف (افتراضياً مجلد التطبيق)
/// [showShareDialog] إذا كان true سيظهر خيارات المشاركة بعد الحفظ
Future<SavedFileResult?> createTranscriptionPdf(
  BuildContext context,
  List<String> transcriptionHistory, {
  SaveLocation saveLocation = SaveLocation.appDocuments,
  bool showShareDialog = false,
}) async {
  if (transcriptionHistory.isEmpty) {
    _showSnackbar(context, 'لا يوجد نصوص لتحويلها إلى PDF', isError: true);
    return null;
  }

  try {
    // ✅ طلب الأذونات المناسبة لإصدار Android (فقط للحفظ الخارجي)
    if (saveLocation != SaveLocation.appDocuments) {
      if (!await PermissionHelper.requestStoragePermissions(context)) {
        _showSnackbar(context, 'يجب منح إذن الوصول إلى التخزين للحفظ في هذا الموقع',
            isError: true);
        return null;
      }
    }

    _showSnackbar(context, '📄 جاري إنشاء وحفظ ملف PDF...');

    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

    // ✅ تحميل خط عربي للـ PDF
    final arabicFont = await PdfGoogleFonts.notoSansArabicRegular();

    // إنشاء محتوى المستند
    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl, // ✅ اتجاه عربي
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'تقرير الجلسة الصوتية',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                font: arabicFont,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'تاريخ الإنشاء: $formattedDate',
            style: pw.TextStyle(fontSize: 12, font: arabicFont),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Divider(),

          // ✅ كل فقرة مع الطابع الزمني
          ...transcriptionHistory.map((line) {
            final isTimestamped =
                RegExp(r'^\[\d{2}:\d{2}:\d{2}\]').hasMatch(line);
            final parts = line.split(']');
            final timestamp =
                isTimestamped ? parts[0].replaceAll('[', '').trim() : '';
            final text = isTimestamped && parts.length > 1
                ? parts.sublist(1).join(']').trim()
                : line;

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (timestamp.isNotEmpty)
                    pw.Text(
                      "⏱️ $timestamp",
                      style: pw.TextStyle(
                          fontSize: 10, 
                          color: PdfColors.grey600, 
                          font: arabicFont
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  pw.Text(
                    text,
                    style: pw.TextStyle(
                        fontSize: 14, 
                        height: 1.5, 
                        font: arabicFont
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.Divider(thickness: 0.3),
                ],
              ),
            );
          }),
        ],
      ),
    );

    // 🔹 حفظ الملف باستخدام مدير التخزين المحلي المحسن
    final pdfBytes = await pdf.save();
    final result = await LocalStorageManager.savePdfFile(
      pdfBytes: pdfBytes,
      fileName: 'تقرير_الجلسة_الصوتية',
      description: 'تقرير يحتوي على ${transcriptionHistory.length} نص محول من الصوت - $formattedDate',
      saveLocation: saveLocation,
    );

    if (result.success) {
      _showSnackbar(context, result.message);
      
      // ✅ إعلام نظام أندرويد بأن هناك ملفًا جديدًا (للحفظ الخارجي فقط)
      if (saveLocation != SaveLocation.appDocuments && result.filePath != null) {
        try {
          const platform = MethodChannel('media_scanner');
          await platform.invokeMethod('scanFile', {'path': result.filePath});
          debugPrint('📂 تمت فهرسة الملف ليظهر في تطبيق الملفات');
        } catch (e) {
          debugPrint('⚠️ فشل إرسال إشعار MediaScanner: $e');
        }
      }

      // ✅ عرض خيارات إضافية للمستخدم
      if (showShareDialog) {
        await _showFileActionsDialog(context, result, pdfBytes);
      }
      
      return result;
    } else {
      _showSnackbar(context, result.message, isError: true);
      return null;
    }
  } catch (e) {
    debugPrint('❌ خطأ أثناء إنشاء PDF: $e');
    _showSnackbar(context, 'حدث خطأ أثناء إنشاء ملف PDF: ${e.toString()}', isError: true);
    return null;
  }
}

/// 🔸 دالة مساعدة لعرض Snackbar
void _showSnackbar(BuildContext context, String message,
    {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, textDirection: TextDirection.rtl),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      duration: Duration(seconds: isError ? 4 : 3),
    ),
  );
}

/// 🔸 عرض حوار خيارات الملف بعد الحفظ
Future<void> _showFileActionsDialog(
  BuildContext context, 
  SavedFileResult result, 
  List<int> pdfBytes
) async {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text(
          'تم حفظ الملف بنجاح ✅',
          textDirection: TextDirection.rtl,
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اسم الملف: ${result.fileName}',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'الحجم: ${result.fileInfo?.formattedSize ?? 'غير معروف'}',
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'ماذا تريد أن تفعل الآن؟',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              if (result.fileInfo != null) {
                final opened = await LocalStorageManager.openSavedFile(result.fileInfo!);
                if (!opened && context.mounted) {
                  _showSnackbar(context, 'لا يمكن فتح الملف. تأكد من وجود تطبيق لقراءة PDF', isError: true);
                }
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('فتح الملف'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await Printing.sharePdf(
                  bytes: pdfBytes,
                  filename: result.fileName ?? "تقرير_صوتي.pdf",
                );
              } catch (e) {
                if (context.mounted) {
                  _showSnackbar(context, 'خطأ في مشاركة الملف: $e', isError: true);
                }
              }
            },
            icon: const Icon(Icons.share),
            label: const Text('مشاركة'),
          ),
        ],
      );
    },
  );
}

/// 🔸 دالة سريعة لحفظ PDF في مجلد التطبيق (بدون أذونات)
Future<SavedFileResult?> createAndSaveTranscriptionPdfQuick(
  BuildContext context,
  List<String> transcriptionHistory,
) async {
  return await createTranscriptionPdf(
    context,
    transcriptionHistory,
    saveLocation: SaveLocation.appDocuments,
    showShareDialog: true,
  );
}

/// 🔸 دالة لحفظ PDF مع خيار المكان
Future<void> showSaveLocationDialog(
  BuildContext context,
  List<String> transcriptionHistory,
) async {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text(
          'اختر مكان حفظ الملف',
          textDirection: TextDirection.rtl,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder, color: Colors.blue),
              title: const Text(
                'مجلد التطبيق (موصى به)',
                textDirection: TextDirection.rtl,
              ),
              subtitle: const Text(
                'سريع ولا يحتاج أذونات خاصة',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 12),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await createTranscriptionPdf(
                  context,
                  transcriptionHistory,
                  saveLocation: SaveLocation.appDocuments,
                  showShareDialog: true,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.green),
              title: const Text(
                'مجلد التنزيلات',
                textDirection: TextDirection.rtl,
              ),
              subtitle: const Text(
                'يحتاج أذونات، ويظهر في تطبيق الملفات',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 12),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await createTranscriptionPdf(
                  context,
                  transcriptionHistory,
                  saveLocation: SaveLocation.downloads,
                  showShareDialog: true,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.orange),
              title: const Text(
                'المستندات الخارجية',
                textDirection: TextDirection.rtl,
              ),
              subtitle: const Text(
                'للتنظيم مع ملفات أخرى',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 12),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await createTranscriptionPdf(
                  context,
                  transcriptionHistory,
                  saveLocation: SaveLocation.externalDocuments,
                  showShareDialog: true,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      );
    },
  );
}
