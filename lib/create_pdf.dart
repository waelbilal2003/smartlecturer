import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'permission_helper.dart';

/// 🔹 هذه الدالة تقوم بإنشاء ملف PDF يحتوي على النصوص المحولة من الصوت.
///
/// [transcriptionHistory] قائمة بالنصوص (مع الطوابع الزمنية)
/// [context] لعرض Snackbars (اختياري)
Future<void> createTranscriptionPdf(
  BuildContext context,
  List<String> transcriptionHistory,
) async {
  if (transcriptionHistory.isEmpty) {
    _showSnackbar(context, 'لا يوجد نصوص لتحويلها إلى PDF', isError: true);
    return;
  }

  try {
    // ✅ طلب الأذونات المناسبة لإصدار Android
    if (!await PermissionHelper.requestStoragePermissions(context)) {
      _showSnackbar(context, 'يجب منح إذن الوصول إلى التخزين لحفظ ملف PDF',
          isError: true);
      return;
    }

    _showSnackbar(context, '📄 جاري إنشاء ملف PDF...');

    final pdf = pw.Document();
    final now = DateTime.now();
    final formattedDate =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

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
              ),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'تاريخ الإنشاء: $formattedDate',
            style: pw.TextStyle(fontSize: 12),
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
                      style:
                          pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  pw.Text(
                    text,
                    style: pw.TextStyle(fontSize: 14, height: 1.5),
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

    // 🔹 تحديد مجلد الحفظ (Downloads)
    final List<Directory>? dirs =
        await getExternalStorageDirectories(type: StorageDirectory.downloads);
    Directory downloadDir = dirs != null && dirs.isNotEmpty
        ? dirs.first
        : await getApplicationDocumentsDirectory();

// 🔹 إنشاء اسم الملف
    final filePath =
        "${downloadDir.path}/Transcription_${now.millisecondsSinceEpoch}.pdf";

// 🔹 حفظ الملف
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    // ✅ إعلام نظام أندرويد بأن هناك ملفًا جديدًا ليظهر في تطبيق الملفات
    try {
      const platform = MethodChannel('media_scanner');
      await platform.invokeMethod('scanFile', {'path': filePath});
      debugPrint('📂 تمت فهرسة الملف ليظهر في تطبيق الملفات');
    } catch (e) {
      debugPrint('⚠️ فشل إرسال إشعار MediaScanner: $e');
    }
    _showSnackbar(context, '✅ تم حفظ ملف PDF في مجلد التنزيلات بنجاح');

    // (اختياري) عرض نافذة المشاركة
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: "Transcription.pdf",
    );
  } catch (e) {
    debugPrint('❌ خطأ أثناء إنشاء PDF: $e');
    _showSnackbar(context, 'حدث خطأ أثناء إنشاء ملف PDF', isError: true);
  }
}

/// 🔸 دالة مساعدة لعرض Snackbar
void _showSnackbar(BuildContext context, String message,
    {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, textDirection: TextDirection.rtl),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
    ),
  );
}
