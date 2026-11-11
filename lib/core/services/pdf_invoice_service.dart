import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class PdfInvoiceService {
  /// Generates the raw PDF bytes for the official MOH Statutory Invoice
  static Future<Uint8List> generateInvoicePdfBytes({
    required String invoiceNumber,
    required String paymentReference,
    required String? chargeId,
    required String restaurantName,
    required String ownerName,
    required String? premiseAddress,
    required String statutoryCitation,
    required double amountPaid,
    required String settledAt,
    String? receiptUrl,
  }) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;

    try {
      regularFont = await PdfGoogleFonts.robotoRegular();
      boldFont = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      // Fallback to default Helvetica if offline
    }

    final theme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
    );

    final formattedAmt = 'RM ${amountPaid.toStringAsFixed(2)}';

    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // -------------------------------------------------------------
              // Header & Government Banner
              // -------------------------------------------------------------
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFF0F766E),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'MINISTRY OF HEALTH MALAYSIA',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'KEMENTERIAN KESIHATAN MALAYSIA',
                          style: const pw.TextStyle(
                            color: PdfColor.fromInt(0xFFCCFBF1),
                            fontSize: 10,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Food Safety and Quality Division | Statutory Enforcement',
                          style: const pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'OFFICIAL RECEIPT',
                            style: pw.TextStyle(
                              color: const PdfColor.fromInt(0xFF0F766E),
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'STATUTORY SETTLEMENT',
                            style: const pw.TextStyle(
                              color: PdfColors.grey700,
                              fontSize: 7.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // -------------------------------------------------------------
              // Invoice Meta Info Bar
              // -------------------------------------------------------------
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildMetaRow('Invoice Number:', invoiceNumber, isBoldValue: true, valueColor: const PdfColor.fromInt(0xFF0F766E)),
                      _buildMetaRow('Payment Channel:', 'Official Payment Gateway (Card / FPX)'),
                      _buildMetaRow('Payment Reference:', paymentReference),
                      if (chargeId != null && chargeId.isNotEmpty)
                        _buildMetaRow('Transaction Ref ID:', chargeId),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _buildMetaRow('Settlement Date:', settledAt, alignRight: true),
                      _buildMetaRow('Payment Status:', 'OFFICIALLY CLEARED & RECORDED', alignRight: true, valueColor: const PdfColor.fromInt(0xFF059669), isBoldValue: true),
                      _buildMetaRow('Currency:', 'MYR (Malaysian Ringgit)', alignRight: true),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 12),

              // -------------------------------------------------------------
              // Billed To / Premise Information
              // -------------------------------------------------------------
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFF8FAFC),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'PREMISE & LICENSEE DETAILS',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF0F766E),
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Food Premise Name: $restaurantName', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                            if (premiseAddress != null && premiseAddress.isNotEmpty)
                              pw.Text('Address: $premiseAddress', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Licensee / Owner: $ownerName', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
                            pw.Text('Citation: $statutoryCitation', style: pw.TextStyle(fontSize: 8.5, color: const PdfColor.fromInt(0xFFDC2626), fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 18),

              // -------------------------------------------------------------
              // Itemized Breakdown Table
              // -------------------------------------------------------------
              pw.Text(
                'ITEMIZED SETTLEMENT SUMMARY',
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF1E293B)),
              ),
              pw.SizedBox(height: 8),

              pw.Table(
                border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFCBD5E1), width: 0.8),
                children: [
                  // Table Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('No.', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Statutory Item & Citation', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Statutory Basis', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text('Amount (MYR)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  // Row 1: Fine
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('1', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Statutory Compound Fine Penalty\n($statutoryCitation)', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Food Act 1983', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(formattedAmt, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  // Row 2: Fee
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('2', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('MOH Digital Enforcement Processing Fee', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Government Subsidy', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('RM 0.00 (Waived)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, color: const PdfColor.fromInt(0xFF059669), fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  // Row 3: SST
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('3', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Sales & Service Tax (SST 0%)', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Exempted', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('RM 0.00', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 12),

              // Total Summary Box
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 200,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor.fromInt(0xFFCCFBF1),
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: const PdfColor.fromInt(0xFF0F766E)),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Total Paid:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F766E))),
                        pw.Text(formattedAmt, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF0F766E))),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // -------------------------------------------------------------
              // Official Legal Certificate Stamp & Footer
              // -------------------------------------------------------------
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFF059669), width: 1.2),
                  color: const PdfColor.fromInt(0xFFECFDF5),
                ),
                child: pw.Row(
                  children: [
                    pw.Container(
                      width: 32,
                      height: 32,
                      decoration: const pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        color: PdfColor.fromInt(0xFF059669),
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          'MOH',
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'LEGAL CLEARANCE & PREMISES RESTORATION CERTIFICATE',
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF065F46)),
                          ),
                          pw.Text(
                            'This statutory settlement has been officially authenticated. Enforcement notices are marked settled in full compliance with Ministry of Health regulations.',
                            style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF047857)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 10),

              pw.Center(
                child: pw.Text(
                  'This is an official computer-generated statutory clearance document issued under the authority of the Ministry of Health Malaysia.\nNo physical signature or official seal is required.',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildMetaRow(String label, String value, {bool alignRight = false, bool isBoldValue = false, PdfColor? valueColor}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
          ),
          pw.SizedBox(width: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.5,
              fontWeight: isBoldValue ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valueColor ?? PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  /// Writes PDF to local temporary/documents file storage and returns File
  static Future<File> saveInvoiceLocally({
    required String invoiceNumber,
    required Uint8List pdfBytes,
  }) async {
    Directory dir;
    try {
      dir = (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = await getTemporaryDirectory();
    }
    final file = File('${dir.path}/$invoiceNumber.pdf');
    await file.writeAsBytes(pdfBytes, flush: true);
    return file;
  }

  /// Launches native print/save dialog or falls back directly to device share/export
  static Future<void> downloadOrPrintInvoice({
    required String invoiceNumber,
    required String paymentReference,
    required String? chargeId,
    required String restaurantName,
    required String ownerName,
    required String? premiseAddress,
    required String statutoryCitation,
    required double amountPaid,
    required String settledAt,
    String? receiptUrl,
  }) async {
    final pdfBytes = await generateInvoicePdfBytes(
      invoiceNumber: invoiceNumber,
      paymentReference: paymentReference,
      chargeId: chargeId,
      restaurantName: restaurantName,
      ownerName: ownerName,
      premiseAddress: premiseAddress,
      statutoryCitation: statutoryCitation,
      amountPaid: amountPaid,
      settledAt: settledAt,
      receiptUrl: receiptUrl,
    );

    try {
      await Printing.layoutPdf(
        name: '$invoiceNumber.pdf',
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } on MissingPluginException catch (_) {
      // If app was not cold-restarted after adding printing package, fallback to SharePlus file export
      debugPrint('[PdfInvoiceService] Native print plugin not attached to running process. Falling back to local file export...');
      final file = await saveInvoiceLocally(invoiceNumber: invoiceNumber, pdfBytes: pdfBytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: '$invoiceNumber.pdf')],
        text: 'Official MOH Statutory Settlement Invoice ($invoiceNumber)',
      );
    } catch (e) {
      debugPrint('[PdfInvoiceService] layoutPdf notice: $e. Using file share fallback...');
      final file = await saveInvoiceLocally(invoiceNumber: invoiceNumber, pdfBytes: pdfBytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: '$invoiceNumber.pdf')],
        text: 'Official MOH Statutory Settlement Invoice ($invoiceNumber)',
      );
    }
  }

  /// Shares the PDF invoice to any app (WhatsApp, Email, Files, Cloud Storage)
  static Future<void> shareInvoicePdf({
    required String invoiceNumber,
    required String paymentReference,
    required String? chargeId,
    required String restaurantName,
    required String ownerName,
    required String? premiseAddress,
    required String statutoryCitation,
    required double amountPaid,
    required String settledAt,
    String? receiptUrl,
  }) async {
    final pdfBytes = await generateInvoicePdfBytes(
      invoiceNumber: invoiceNumber,
      paymentReference: paymentReference,
      chargeId: chargeId,
      restaurantName: restaurantName,
      ownerName: ownerName,
      premiseAddress: premiseAddress,
      statutoryCitation: statutoryCitation,
      amountPaid: amountPaid,
      settledAt: settledAt,
      receiptUrl: receiptUrl,
    );

    try {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '$invoiceNumber.pdf',
      );
    } catch (_) {
      final file = await saveInvoiceLocally(invoiceNumber: invoiceNumber, pdfBytes: pdfBytes);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: '$invoiceNumber.pdf')],
        text: 'Official MOH Statutory Settlement Invoice ($invoiceNumber)',
      );
    }
  }
}
