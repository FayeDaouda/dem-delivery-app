import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/utils/price_format.dart';

const _monthNames = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _fmtDate(DateTime dt) => '${dt.day} ${_monthNames[dt.month - 1]} ${dt.year}';

pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.all(6),
  child: pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 10,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);

/// Génère la facture PDF d'une commande DEM Pro — document professionnel au
/// nom du commerçant (pas le reçu DEM de la livraison), avec le détail des
/// articles vendus. `merchant` est l'utilisateur DEM Pro connecté (voir
/// ProfileRepository().getMe()), `order` la commande complète.
Future<Uint8List> buildInvoicePdf({
  required Map<String, dynamic> order,
  required Map<String, dynamic> merchant,
}) async {
  final pdf = pw.Document();

  final businessName = (merchant['proBusinessName'] as String?)?.trim();
  final ninea = (merchant['proNinea'] as String?)?.trim();
  final merchantPhone = merchant['phone'] as String?;

  final orderId = (order['id'] as String? ?? '').substring(0, 8).toUpperCase();
  final createdAt = DateTime.tryParse(
    order['createdAt'] as String? ?? '',
  )?.toLocal();
  final receiverName = order['receiverName'] as String?;
  final receiverPhone = order['receiverPhone'] as String?;
  final deliveryAddress = order['deliveryAddress'] as String?;
  final items = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final deliveryPrice = (order['price'] as num?)?.toInt() ?? 0;

  int productTotal = 0;
  for (final it in items) {
    productTotal +=
        ((it['price'] as num?)?.toInt() ?? 0) *
        ((it['quantity'] as num?)?.toInt() ?? 1);
  }
  final total = productTotal + deliveryPrice;

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    businessName?.isNotEmpty == true
                        ? businessName!
                        : 'Mon entreprise',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (merchantPhone != null && merchantPhone.isNotEmpty)
                    pw.Text(merchantPhone, style: const pw.TextStyle(fontSize: 10)),
                  if (ninea != null && ninea.isNotEmpty)
                    pw.Text('NINEA : $ninea', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'FACTURE',
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('N° FACT-$orderId', style: const pw.TextStyle(fontSize: 10)),
                  if (createdAt != null)
                    pw.Text(_fmtDate(createdAt), style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 28),
          pw.Text('Facturé à', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 4),
          pw.Text(receiverName?.isNotEmpty == true ? receiverName! : '—'),
          if (receiverPhone != null && receiverPhone.isNotEmpty) pw.Text(receiverPhone),
          if (deliveryAddress != null && deliveryAddress.isNotEmpty)
            pw.Text(deliveryAddress),
          pw.SizedBox(height: 24),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1.5),
              3: pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('Article', bold: true),
                  _cell('Qté', bold: true),
                  _cell('Prix unitaire', bold: true),
                  _cell('Total', bold: true),
                ],
              ),
              if (items.isEmpty)
                pw.TableRow(
                  children: [
                    _cell('Livraison'),
                    _cell('1'),
                    _cell(formatFcfa(deliveryPrice, withSuffix: false)),
                    _cell(formatFcfa(deliveryPrice, withSuffix: false)),
                  ],
                ),
              for (final it in items)
                pw.TableRow(
                  children: [
                    _cell(it['name'] as String? ?? ''),
                    _cell('${it['quantity'] ?? 1}'),
                    _cell(formatFcfa((it['price'] as num?) ?? 0, withSuffix: false)),
                    _cell(
                      formatFcfa(
                        ((it['price'] as num?) ?? 0) * ((it['quantity'] as num?) ?? 1),
                        withSuffix: false,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (items.isNotEmpty) ...[
                  pw.Text('Sous-total produits : ${formatFcfa(productTotal)}'),
                  pw.Text('Frais de livraison : ${formatFcfa(deliveryPrice)}'),
                  pw.SizedBox(height: 6),
                ],
                pw.Text(
                  'TOTAL : ${formatFcfa(total)}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 40),
          pw.Divider(color: PdfColors.grey300),
          pw.Text(
            'Facture générée via DEM Pro',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
          ),
        ],
      ),
    ),
  );

  return pdf.save();
}

/// Ouvre l'aperçu natif (impression / partage / enregistrement) pour la
/// facture de cette commande.
Future<void> shareInvoicePdf({
  required Map<String, dynamic> order,
  required Map<String, dynamic> merchant,
}) async {
  final bytes = await buildInvoicePdf(order: order, merchant: merchant);
  final orderId = (order['id'] as String? ?? '').substring(0, 8).toUpperCase();
  await Printing.layoutPdf(
    onLayout: (format) async => bytes,
    name: 'facture_$orderId.pdf',
  );
}
