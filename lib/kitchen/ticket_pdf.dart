import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/format.dart';
import '../core/models.dart';

/// Prints a kitchen ticket on an 80 mm receipt printer (or any printer) through the
/// system print dialog: Android print service, AirPrint, or the browser.
Future<void> printTicket(Order order) =>
    Printing.layoutPdf(name: 'Al’s Pizza #${order.number}', format: PdfPageFormat.roll80, onLayout: (format) async => (await ticketPdf(order, format)).save());

/// The PDF's built-in font covers basic Latin only, so fancy punctuation is swapped for plain ASCII.
String _plain(String s) => s
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll(RegExp('[–—]'), '-')
    .replaceAll('×', 'x')
    .replaceAll(RegExp('[•·]'), '-')
    .replaceAll('…', '...')
    .replaceAll(RegExp(r'[^\x20-\x7E\n]'), '');

Future<pw.Document> ticketPdf(Order o, PdfPageFormat format) async {
  final doc = pw.Document(title: 'Order ${o.number}');
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  pw.Widget rule() => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Divider(thickness: 0.8, borderStyle: pw.BorderStyle.dashed));
  final address = o.address;
  final paid = switch (o.paymentStatus) {
    'pay_at_pickup' => 'COLLECT ${money(o.totalCents)} AT PICKUP',
    'pay_on_delivery' => 'DRIVER COLLECTS ${money(o.totalCents)} CASH',
    _ => 'PAID',
  };
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.fromLTRB(8, 10, 8, 14),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(child: pw.Text(_plain(o.storeName), style: bold.copyWith(fontSize: 11))),
          pw.SizedBox(height: 6),
          pw.Center(child: pw.Text('#${o.number}', style: bold.copyWith(fontSize: 30))),
          pw.Center(child: pw.Text(o.isDelivery ? 'DELIVERY' : 'PICKUP', style: bold.copyWith(fontSize: 16))),
          pw.SizedBox(height: 4),
          pw.Text(_plain('Placed ${clock(o.paidAt ?? o.createdAt)}${o.estimatedReadyAt != null ? '   Due ${clock(o.estimatedReadyAt!)}' : ''}'), style: const pw.TextStyle(fontSize: 10)),
          pw.Text(_plain(o.customerName), style: bold.copyWith(fontSize: 12)),
          rule(),
          for (final line in o.items) ...[
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(width: 22, child: pw.Text('${line.quantity}x', style: bold.copyWith(fontSize: 13))),
                pw.Expanded(child: pw.Text(_plain(line.name), style: bold.copyWith(fontSize: 13))),
              ],
            ),
            if (line.summary.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 22, bottom: 4),
                child: pw.Text(_plain(line.summary), style: const pw.TextStyle(fontSize: 10)),
              ),
          ],
          if (o.notes?.isNotEmpty ?? false) ...[
            rule(),
            pw.Text('NOTE: ${_plain(o.notes!)}', style: bold.copyWith(fontSize: 11)),
          ],
          if (address != null) ...[
            rule(),
            pw.Text(_plain(address.full), style: const pw.TextStyle(fontSize: 10)),
            if (address.instructions?.isNotEmpty ?? false) pw.Text(_plain('Drop-off: ${address.instructions}'), style: const pw.TextStyle(fontSize: 10)),
          ],
          rule(),
          pw.Text('${o.itemsCount} item${o.itemsCount == 1 ? '' : 's'}   ${_plain(paid)}', style: bold.copyWith(fontSize: 11)),
        ],
      ),
    ),
  );
  return doc;
}
