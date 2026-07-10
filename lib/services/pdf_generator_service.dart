import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

/// PDF Generator Service for Document Downloads
/// Creates professional PDFs from document data with proper formatting
class PDFGeneratorService {
  static final PDFGeneratorService _instance = PDFGeneratorService._internal();
  factory PDFGeneratorService() => _instance;
  PDFGeneratorService._internal();

  /// Generate and download PDF for a document
  // Future<void> generateAndDownloadPDF(Map<String, dynamic> document) async {
  //   try {
  //     debugPrint('[PDFGenerator] Starting PDF generation for ${document['type']}');
  //
  //     // Request storage permission
  //     if (!await _requestStoragePermission()) {
  //       throw Exception('Storage permission is required to download documents');
  //     }
  //
  //     // Generate PDF
  //     final pdf = await _createPDF(document);
  //
  //     // Save to device
  //     final filePath = await _savePDFToDevice(pdf, document);
  //
  //     debugPrint('[PDFGenerator] PDF saved successfully to: $filePath');
  //   } catch (e) {
  //     debugPrint('[PDFGenerator] Error generating PDF: $e');
  //     rethrow;
  //   }
  // }
  //



  Future<void> generateAndDownloadPDF(
      Map<String, dynamic> document) async {

    final pdf = await _createPDF(document);

    final file = await _savePDFToDevice(pdf, document);

    debugPrint(file);
  }



  /// Request storage permission for downloading files
  // Future<bool> _requestStoragePermission() async {
  //   if (Platform.isAndroid) {
  //     // For Android 13+ (API 33+), use media permissions
  //     final storageStatus = await Permission.storage.request();
  //     if (storageStatus.isGranted) {
  //       return true;
  //     }
  //
  //     // For Android 11+ (API 30+), try manage external storage
  //     final manageStatus = await Permission.manageExternalStorage.request();
  //     if (manageStatus.isGranted) {
  //       return true;
  //     }
  //
  //     // Fallback to storage permission
  //     return storageStatus.isGranted;
  //   } else if (Platform.isIOS) {
  //     final status = await Permission.photos.request();
  //     return status.isGranted;
  //   }
  //   return true; // Web doesn't need permission
  // }

  /// Create PDF document with professional formatting
  Future<pw.Document> _createPDF(Map<String, dynamic> document) async {
    final pdf = pw.Document();
    // Use default PDF fonts for better compatibility
    final font = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();
    final italicFont = pw.Font.helveticaOblique();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Header Section
            _buildHeader(document, font, boldFont),
            pw.SizedBox(height: 30),
            
            // Document Content
            _buildDocumentContent(document, font, boldFont, italicFont),
            
            pw.SizedBox(height: 40),
            
            // Footer Section
            _buildFooter(document, font),
          ];
        },
      ),
    );

    return pdf;
  }

  /// Build PDF header with company info and document details
  pw.Widget _buildHeader(Map<String, dynamic> document, pw.Font font, pw.Font boldFont) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Company Header
        pw.Container(
          padding: const pw.EdgeInsets.all(20),
          decoration: pw.BoxDecoration(
            color: PdfColors.indigo,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'OFFICIAL DOCUMENT',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 24,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                _getDocumentTypeLabel(document['type'] ?? ''),
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: 18,
                  color: PdfColors.white,
                ),
              ),
            ],
          ),
        ),
        
        pw.SizedBox(height: 20),
        
        // Document Info
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (document['subject'] != null) ...[
                pw.Row(
                  children: [
                    pw.Text(
                      'Subject: ',
                      style: pw.TextStyle(font: boldFont, fontSize: 14),
                    ),
                    pw.Text(
                      document['subject'],
                      style: pw.TextStyle(font: font, fontSize: 14),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
              ],
              pw.Row(
                children: [
                  pw.Text(
                    'Issue Date: ',
                    style: pw.TextStyle(font: boldFont, fontSize: 14),
                  ),
                  pw.Text(
                    _formatDate(document['createdAt']),
                    style: pw.TextStyle(font: font, fontSize: 14),
                  ),
                ],
              ),
              if (document['referenceNumber'] != null) ...[
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Text(
                      'Reference: ',
                      style: pw.TextStyle(font: boldFont, fontSize: 14),
                    ),
                    pw.Text(
                      document['referenceNumber'],
                      style: pw.TextStyle(font: font, fontSize: 14),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build main document content with proper formatting
  pw.Widget _buildDocumentContent(
    Map<String, dynamic> document, 
    pw.Font font, 
    pw.Font boldFont, 
    pw.Font italicFont
  ) {
    final content = document['content'] ?? 'No content available';
    
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Document Content',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: 16,
              color: PdfColors.indigo,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.RichText(
            text: pw.TextSpan(
              children: _parseContentToSpans(content, font, italicFont),
            ),
          ),
        ],
      ),
    );
  }

  /// Parse content string into text spans for better formatting
  List<pw.TextSpan> _parseContentToSpans(String content, pw.Font font, pw.Font italicFont) {
    try {
      if (content.isEmpty) {
        return [
          pw.TextSpan(
            text: 'No content available',
            style: pw.TextStyle(
              font: italicFont,
              fontSize: 12,
              color: PdfColors.grey600,
            ),
          ),
        ];
      }

      final lines = content.split('\n');
      final spans = <pw.TextSpan>[];
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isNotEmpty) {
          spans.add(
            pw.TextSpan(
              text: line,
              style: pw.TextStyle(
                font: font,
                fontSize: 12,
              ),
            ),
          );
          
          if (i < lines.length - 1) {
            spans.add(const pw.TextSpan(text: '\n'));
          }
        } else {
          // Add empty line for formatting
          if (i < lines.length - 1) {
            spans.add(const pw.TextSpan(text: '\n'));
          }
        }
      }
      
      return spans;
    } catch (e) {
      debugPrint('[PDFGenerator] Error parsing content: $e');
      return [
        pw.TextSpan(
          text: 'Error parsing document content',
          style: pw.TextStyle(
            font: font,
            fontSize: 12,
            color: PdfColors.red,
          ),
        ),
      ];
    }
  }

  /// Build PDF footer with authenticity information
  pw.Widget _buildFooter(Map<String, dynamic> document, pw.Font font) {
    return pw.Column(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
          ),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated by OS Attendance System',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                  pw.Text(
                    'Page 1',
                    style: pw.TextStyle(
                      font: font,
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'This is an electronically generated document. Valid without signature.',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 9,
                  color: PdfColors.grey500,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Save PDF to device storage
  Future<String> _savePDFToDevice(pw.Document pdf, Map<String, dynamic> document) async {
    final bytes = await pdf.save();
    
    // Get appropriate directory for saving
    Directory? directory;
    
    if (Platform.isAndroid) {
      // Try multiple Android directories in order of preference
      final directories = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Documents'),
        await getExternalStorageDirectory(),
        await getApplicationDocumentsDirectory(),
      ];
      
      for (final dir in directories) {
        if (dir != null) {
          directory = dir;
          if (await directory.exists()) {
            break;
          }
        }
      }
      
      // If none exist, try to create the Downloads directory
      if (directory == null || !await directory.exists()) {
        directory = Directory('/storage/emulated/0/Download');
        try {
          await directory.create(recursive: true);
        } catch (e) {
          // Fallback to app documents directory
          directory = await getApplicationDocumentsDirectory();
        }
      }
    } else if (Platform.isIOS) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      // For web or other platforms
      directory = await getTemporaryDirectory();
    }

    // Ensure directory exists
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    // Create filename with timestamp to avoid conflicts
    final documentType = _getDocumentTypeLabel(document['type'] ?? '');
    final date = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final fileName = '${documentType.replaceAll(' ', '_')}_$date.pdf';
    
    final file = File('${directory.path}/$fileName');
    
    try {
      await file.writeAsBytes(bytes);
      debugPrint('[PDFGenerator] PDF saved to: ${file.path}');
      return file.path;
    } catch (e) {
      debugPrint('[PDFGenerator] Error saving file: $e');
      // Try fallback directory
      final fallbackDir = await getApplicationDocumentsDirectory();
      final fallbackFile = File('${fallbackDir.path}/$fileName');
      await fallbackFile.writeAsBytes(bytes);
      debugPrint('[PDFGenerator] PDF saved to fallback: ${fallbackFile.path}');
      return fallbackFile.path;
    }
  }

  /// Get formatted document type label
  String _getDocumentTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'offer_letter':
        return 'Offer Letter';
      case 'contract':
        return 'Employment Contract';
      case 'certificate':
        return 'Certificate';
      case 'letter':
        return 'Official Letter';
      case 'policy':
        return 'Policy Document';
      default:
        return 'Document';
    }
  }

  /// Format date for PDF
  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    try {
      if (timestamp is Timestamp) {
        return DateFormat('MMMM dd, yyyy').format(timestamp.toDate());
      } else if (timestamp is String) {
        return DateFormat('MMMM dd, yyyy').format(DateTime.parse(timestamp));
      }
    } catch (e) {
      return 'N/A';
    }
    return 'N/A';
  }

  /// Generate and save a professional PDF of an employee's attendance history
  Future<String> generateAttendanceHistoryPDF({
    required String employeeName,
    required String employeeEmail,
    required String department,
    required String designation,
    required List<Map<String, dynamic>> attendanceRecords,
    required String reportMonthYear,
  }) async {
    final pdf = pw.Document();
    final font = pw.Font.helvetica();
    final boldFont = pw.Font.helveticaBold();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Title Header
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: const pw.BoxDecoration(
                color: PdfColors.indigo,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ATTENDANCE REPORT',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 20,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Attendify Attendance Management System',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 12,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        DateFormat('MMMM dd, yyyy').format(DateTime.now()),
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 12,
                          color: PdfColors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Employee Info Block
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Employee Details', style: pw.TextStyle(font: boldFont, fontSize: 14)),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Name: $employeeName', style: pw.TextStyle(font: font, fontSize: 11)),
                      pw.Text('Email: $employeeEmail', style: pw.TextStyle(font: font, fontSize: 11)),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Department: ${department.isNotEmpty ? department : "N/A"}', style: pw.TextStyle(font: font, fontSize: 11)),
                      pw.Text('Designation: ${designation.isNotEmpty ? designation : "N/A"}', style: pw.TextStyle(font: font, fontSize: 11)),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(height: 1, color: PdfColors.grey300),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Report Period:', style: pw.TextStyle(font: boldFont, fontSize: 11)),
                      pw.Text(reportMonthYear, style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.indigo)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Table of records
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Check In', 'Check Out', 'Status', 'Office Bound'],
              data: attendanceRecords.map((rec) {
                return [
                  rec['date'] ?? 'N/A',
                  rec['checkIn'] ?? 'N/A',
                  rec['checkOut'] ?? 'N/A',
                  rec['status'] ?? 'N/A',
                  rec['insideRadius'] == true ? 'Yes' : 'No',
                ];
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
              cellStyle: pw.TextStyle(font: font, fontSize: 10),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
              },
            ),
            pw.SizedBox(height: 30),

            // Footer
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Generated dynamically by Attendify System', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
                  pw.Text('Valid Official History Report', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
                ],
              ),
            ),
          ];
        },
      ),
    );

    // Save to device
    final bytes = await pdf.save();
    Directory? directory;
    if (Platform.isAndroid) {
      final directories = [
        Directory('/storage/emulated/0/Download'),
        Directory('/storage/emulated/0/Documents'),
        await getExternalStorageDirectory(),
        await getApplicationDocumentsDirectory(),
      ];
      for (final dir in directories) {
        if (dir != null && await dir.exists()) {
          directory = dir;
          break;
        }
      }
      if (directory == null) {
        directory = await getApplicationDocumentsDirectory();
      }
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    final sanitizedName = employeeName.replaceAll(' ', '_');
    final sanitizedMonthYear = reportMonthYear.replaceAll(' ', '_');
    final fileName = 'Attendance_History_${sanitizedName}_$sanitizedMonthYear.pdf';
    final file = File('${directory.path}/$fileName');

    await file.writeAsBytes(bytes);
    debugPrint('[PDFGenerator] Attendance History PDF saved to: ${file.path}');
    return file.path;
  }
}
