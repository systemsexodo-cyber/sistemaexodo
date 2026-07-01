import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() async {
  try {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Text("Hello World Thermal Receipt!"),
          );
        },
      ),
    );
    final bytes = await pdf.save();
    print("SUCCESS: Generated PDF with bytes length: ${bytes.length}");
  } catch (e) {
    print("ERROR: $e");
  }
}
