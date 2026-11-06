import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/constants/note_templates/note4x.dart';
import '../core/constants/observation_templates/primary_school_evaluation_template.dart';
import '../data/models/line_model.dart';
import '../data/models/notebook_model.dart';

// ===========================================================================
// DỊCH VỤ KẾT XUẤT FILE PDF (.PDF) TRỰC TIẾP TRÊN RAM (PDF EXPORT SERVICE)
// Công dụng:
// - Chuyển đổi dữ liệu của tệp đang mở (NotebookModel) thành mảng byte PDF (Uint8List)
//   trực tiếp trên bộ nhớ RAM (không lưu file tạm xuống ổ cứng máy).
// - Hỗ trợ giữ nguyên 100% định dạng gốc cho:
//   1. Biểu mẫu 3 trang "Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học"
//      (Quốc hiệu, Bảng 3 cột 28 dòng nét đứt, Nhận xét chung, Bảng 12 tiêu chí
//       gộp ô dọc, Tổng điểm, Xếp loại và Chữ ký).
//   2. Vở ghi chú 5 ô ly (note5x) và 4 ô ly (note4x) với dòng kẻ ngang chính/phụ.
// ===========================================================================
class PdfExportService {
  PdfExportService._();

  // Bộ nhớ đệm Font chữ Unicode Tiếng Việt trên RAM để các lần xuất PDF tiếp theo đạt tốc độ tức thì (0ms tải font)
  static pw.Font? _cachedRegularFont;
  static pw.Font? _cachedMediumFont;
  static pw.Font? _cachedBoldFont;
  static pw.Font? _cachedItalicFont;

  /// Tải song song và lưu bộ đệm 4 kiểu chữ Be Vietnam Pro trên RAM
  static Future<
      ({
        pw.Font regular,
        pw.Font medium,
        pw.Font bold,
        pw.Font italic,
      })> _getOrLoadFontsInRam() async {
    if (_cachedRegularFont != null &&
        _cachedMediumFont != null &&
        _cachedBoldFont != null &&
        _cachedItalicFont != null) {
      return (
        regular: _cachedRegularFont!,
        medium: _cachedMediumFont!,
        bold: _cachedBoldFont!,
        italic: _cachedItalicFont!,
      );
    }

    final List<pw.Font> loaded = await Future.wait<pw.Font>(<Future<pw.Font>>[
      PdfGoogleFonts.beVietnamProRegular(),
      PdfGoogleFonts.beVietnamProMedium(),
      PdfGoogleFonts.beVietnamProBold(),
      PdfGoogleFonts.beVietnamProItalic(),
    ]);

    _cachedRegularFont = loaded[0];
    _cachedMediumFont = loaded[1];
    _cachedBoldFont = loaded[2];
    _cachedItalicFont = loaded[3];

    return (
      regular: _cachedRegularFont!,
      medium: _cachedMediumFont!,
      bold: _cachedBoldFont!,
      italic: _cachedItalicFont!,
    );
  }

  /// Hàm chính: Tạo dữ liệu byte PDF (Uint8List) trên RAM từ `NotebookModel`
  static Future<Uint8List> generatePdfBytes({
    required NotebookModel notebook,
    required int tabIndex,
  }) async {
    final fonts = await _getOrLoadFontsInRam();
    final pw.Font regularFont = fonts.regular;
    final pw.Font mediumFont = fonts.medium;
    final pw.Font boldFont = fonts.bold;
    final pw.Font italicFont = fonts.italic;

    final pw.ThemeData pdfTheme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
      italic: italicFont,
    );

    final pw.Document pdf = pw.Document(
      title: notebook.title,
      author: 'Meeting Book',
      theme: pdfTheme,
    );

    final Map<int, String> rowMap = _extractRowTextMap(notebook);
    final bool isObservationForm = tabIndex == 1 ||
        PrimarySchoolEvaluationTemplate.isObservationTemplate(
          notebook.paperTemplate,
        );

    if (isObservationForm) {
      _buildPrimarySchoolEvaluationPdfPages(
        pdf: pdf,
        rowMap: rowMap,
        regularFont: regularFont,
        mediumFont: mediumFont,
        boldFont: boldFont,
        italicFont: italicFont,
      );
    } else {
      _buildNoteRuledPdfPages(
        pdf: pdf,
        notebook: notebook,
        rowMap: rowMap,
        regularFont: regularFont,
        mediumFont: mediumFont,
        boldFont: boldFont,
      );
    }

    return pdf.save();
  }

  /// Trích xuất Map (rowIndex -> text) từ trang đầu tiên của NotebookModel
  static Map<int, String> _extractRowTextMap(NotebookModel notebook) {
    final Map<int, String> map = <int, String>{};
    if (notebook.pages.isEmpty) return map;
    for (final LineModel line in notebook.pages.first.lines) {
      map[line.rowIndex] = line.text.replaceAll('\u200B', '').trimRight();
    }
    return map;
  }

  /// Vẽ các đường kẻ dọc xuyên suốt chiều cao của một khối bằng `CustomPaint`
  static void _paintVerticalDividers(
    PdfGraphics canvas,
    PdfPoint size,
    List<double> ratios, {
    double lineWidth = 1.0,
    PdfColor color = PdfColors.black,
  }) {
    canvas
      ..saveContext()
      ..setStrokeColor(color)
      ..setLineWidth(lineWidth);
    for (final double r in ratios) {
      final double x = size.x * r;
      canvas
        ..moveTo(x, 0)
        ..lineTo(x, size.y)
        ..strokePath();
    }
    canvas.restoreContext();
  }

  // ===========================================================================
  // 1. KẾT XUẤT PDF 3 TRANG "PHIẾU ĐÁNH GIÁ TIẾT DẠY GIÁO VIÊN CẤP TIỂU HỌC"
  // ===========================================================================
  static void _buildPrimarySchoolEvaluationPdfPages({
    required pw.Document pdf,
    required Map<int, String> rowMap,
    required pw.Font regularFont,
    required pw.Font mediumFont,
    required pw.Font boldFont,
    required pw.Font italicFont,
  }) {
    String getRowText(int rowIndex) => rowMap[rowIndex] ?? '';

    final scoreEval =
        PrimarySchoolEvaluationTemplate.evaluateScores(getRowText);

    final pw.TextStyle baseStyle = pw.TextStyle(
      font: regularFont,
      fontSize: 10.5,
      color: PdfColors.black,
    );
    final pw.TextStyle boldStyle = pw.TextStyle(
      font: boldFont,
      fontSize: 10.5,
      color: PdfColors.black,
    );
    final pw.TextStyle italicStyle = pw.TextStyle(
      font: italicFont,
      fontSize: 10.5,
      color: PdfColors.black,
    );
    final pw.TextStyle inputStyle = pw.TextStyle(
      font: mediumFont,
      fontSize: 10.2,
      color: PdfColor.fromInt(0xFF1A237E),
    );

    const double pageHorizontalMargin = 34.0;
    const double pageVerticalMargin = 26.0;
    final double pageContentWidth =
        PdfPageFormat.a4.width - (pageHorizontalMargin * 2);

    // -------------------------------------------------------------------------
    // TRANG 1: QUỐC HIỆU, THÔNG TIN HÀNH CHÍNH & BẢNG DỰ GIỜ 3 CỘT (28 DÒNG)
    // -------------------------------------------------------------------------
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          pageHorizontalMargin,
          pageVerticalMargin,
          pageHorizontalMargin,
          pageVerticalMargin,
        ),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Quốc hiệu & Tiêu đề trường (2 cột in đậm như biểu mẫu gốc)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 44,
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'TRƯỜNG TH NGUYỄN BÁ NGỌC',
                          textAlign: pw.TextAlign.center,
                          style: boldStyle.copyWith(fontSize: 10),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Container(
                          width: 90,
                          height: 0.8,
                          color: PdfColors.black,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    flex: 56,
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'CỘNG HOÀ XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                          textAlign: pw.TextAlign.center,
                          style: boldStyle.copyWith(fontSize: 10),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Độc lập – Tự do – Hạnh phúc',
                          textAlign: pw.TextAlign.center,
                          style: boldStyle.copyWith(fontSize: 10.5),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Container(
                          width: 130,
                          height: 0.8,
                          color: PdfColors.black,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),

              // Tiêu đề chính
              pw.Text(
                'PHIẾU ĐÁNH GIÁ TIẾT DẠY GIÁO VIÊN CẤP TIỂU HỌC',
                textAlign: pw.TextAlign.center,
                style: boldStyle.copyWith(fontSize: 12.5),
              ),
              pw.SizedBox(height: 9),

              // Dòng thông tin 1: Họ, tên người dạy / Lớp / Trường
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 50,
                    child: _buildPdfDottedInfoField(
                      label: 'Họ, tên người dạy: ',
                      value: getRowText(
                        PrimarySchoolEvaluationTemplate.rowTeacherName,
                      ),
                      baseStyle: baseStyle,
                      inputStyle: inputStyle,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 18,
                    child: _buildPdfDottedInfoField(
                      label: 'Lớp: ',
                      value: getRowText(
                        PrimarySchoolEvaluationTemplate.rowClassName,
                      ),
                      baseStyle: baseStyle,
                      inputStyle: inputStyle,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 32,
                    child: _buildPdfDottedInfoField(
                      label: 'Trường: ',
                      value: getRowText(
                        PrimarySchoolEvaluationTemplate.rowSchoolName,
                      ),
                      baseStyle: baseStyle,
                      inputStyle: inputStyle,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),

              // Dòng thông tin 2: Tên bài dạy / Môn
              pw.Row(
                children: [
                  pw.Expanded(
                    flex: 66,
                    child: _buildPdfDottedInfoField(
                      label: 'Tên bài dạy: ',
                      value: getRowText(
                        PrimarySchoolEvaluationTemplate.rowLessonTitle,
                      ),
                      baseStyle: baseStyle,
                      inputStyle: inputStyle,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Expanded(
                    flex: 34,
                    child: _buildPdfDottedInfoField(
                      label: 'Môn: ',
                      value: getRowText(
                        PrimarySchoolEvaluationTemplate.rowSubjectName,
                      ),
                      baseStyle: baseStyle,
                      inputStyle: inputStyle,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 8),

              // Bảng ghi chép tiến trình 3 cột (28 dòng kẻ nét đứt)
              // Bọc trong Expanded + FittedBox để đảm bảo bảng 28 dòng luôn hiển thị trọn vẹn 100% trên Trang 1
              pw.Expanded(
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.topCenter,
                  child: pw.SizedBox(
                    width: pageContentWidth,
                    child: pw.CustomPaint(
                      foregroundPainter:
                          (PdfGraphics canvas, PdfPoint size) =>
                              _paintVerticalDividers(
                                canvas,
                                size,
                                const <double>[1.0 / 3.0, 2.0 / 3.0],
                              ),
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColors.black,
                            width: 1.0,
                          ),
                        ),
                        child: pw.Column(
                          children: [
                            // Hàng tiêu đề bảng 3 cột
                            pw.Container(
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(
                                  bottom: pw.BorderSide(
                                    color: PdfColors.black,
                                    width: 1.0,
                                  ),
                                ),
                              ),
                              child: pw.Row(
                                children: [
                                  pw.Expanded(
                                    child: pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        'Nội dung hoạt động',
                                        textAlign: pw.TextAlign.center,
                                        style: baseStyle.copyWith(fontSize: 11),
                                      ),
                                    ),
                                  ),
                                  pw.Expanded(
                                    child: pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        'Biểu hiện của học sinh',
                                        textAlign: pw.TextAlign.center,
                                        style: baseStyle.copyWith(fontSize: 11),
                                      ),
                                    ),
                                  ),
                                  pw.Expanded(
                                    child: pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 6,
                                      ),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        'Nguyên nhân - Biện pháp',
                                        textAlign: pw.TextAlign.center,
                                        style: baseStyle.copyWith(fontSize: 11),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 28 dòng nội dung có đường kẻ ngang nét đứt
                            ...List<pw.Widget>.generate(
                              PrimarySchoolEvaluationTemplate
                                  .activityTableRowCount,
                              (int r) {
                                final bool isLast = r ==
                                    PrimarySchoolEvaluationTemplate
                                            .activityTableRowCount -
                                        1;
                                final String c1 = getRowText(
                                  PrimarySchoolEvaluationTemplate.col1StartRow +
                                      r,
                                );
                                final String c2 = getRowText(
                                  PrimarySchoolEvaluationTemplate.col2StartRow +
                                      r,
                                );
                                final String c3 = getRowText(
                                  PrimarySchoolEvaluationTemplate.col3StartRow +
                                      r,
                                );

                                final pw.BorderSide bottomDash = isLast
                                    ? pw.BorderSide.none
                                    : pw.BorderSide(
                                        color: PdfColor.fromInt(0xFF4A65C6),
                                        width: 0.65,
                                        style: pw.BorderStyle.dashed,
                                      );

                                return pw.Container(
                                  height: 21.0,
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border(
                                      bottom: bottomDash,
                                    ),
                                  ),
                                  child: pw.Row(
                                    crossAxisAlignment:
                                        pw.CrossAxisAlignment.stretch,
                                    children: [
                                      pw.Expanded(
                                        child: pw.Container(
                                          padding:
                                              const pw.EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          alignment: pw.Alignment.bottomLeft,
                                          child: pw.Text(
                                            c1,
                                            maxLines: 1,
                                            style: inputStyle.copyWith(
                                              fontSize: 9.6,
                                            ),
                                          ),
                                        ),
                                      ),
                                      pw.Expanded(
                                        child: pw.Container(
                                          padding:
                                              const pw.EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          alignment: pw.Alignment.bottomLeft,
                                          child: pw.Text(
                                            c2,
                                            maxLines: 1,
                                            style: inputStyle.copyWith(
                                              fontSize: 9.6,
                                            ),
                                          ),
                                        ),
                                      ),
                                      pw.Expanded(
                                        child: pw.Container(
                                          padding:
                                              const pw.EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          alignment: pw.Alignment.bottomLeft,
                                          child: pw.Text(
                                            c3,
                                            maxLines: 1,
                                            style: inputStyle.copyWith(
                                              fontSize: 9.6,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // -------------------------------------------------------------------------
    // TRANG 2: NHẬN XÉT CHUNG (5 DÒNG CHẤM) & BẢNG THANG ĐIỂM 12 TIÊU CHÍ
    // -------------------------------------------------------------------------
    final List<ObservationCriterionSpec> group1 = PrimarySchoolEvaluationTemplate
        .criteriaList
        .where((c) => c.groupIndex == 1)
        .toList();
    final List<ObservationCriterionSpec> group2 = PrimarySchoolEvaluationTemplate
        .criteriaList
        .where((c) => c.groupIndex == 2)
        .toList();
    final List<ObservationCriterionSpec> group3 = PrimarySchoolEvaluationTemplate
        .criteriaList
        .where((c) => c.groupIndex == 3)
        .toList();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          pageHorizontalMargin,
          pageVerticalMargin,
          pageHorizontalMargin,
          pageVerticalMargin,
        ),
        build: (pw.Context context) {
          final pw.TextStyle tblText = baseStyle.copyWith(
            fontSize: 8.8,
            lineSpacing: 1.2,
          );
          final pw.TextStyle tblBold = boldStyle.copyWith(
            fontSize: 8.8,
            lineSpacing: 1.2,
          );

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('NHẬN XÉT, ĐÁNH GIÁ CHUNG:', style: boldStyle),
              pw.SizedBox(height: 3),
              ...List<pw.Widget>.generate(
                PrimarySchoolEvaluationTemplate.generalCommentLineCount,
                (int idx) {
                  final String commentLine = getRowText(
                    PrimarySchoolEvaluationTemplate.generalCommentStartRow +
                        idx,
                  );
                  return pw.Container(
                    height: 18.5,
                    alignment: pw.Alignment.bottomLeft,
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColors.grey700,
                          width: 0.7,
                          style: pw.BorderStyle.dotted,
                        ),
                      ),
                    ),
                    child: pw.Text(commentLine, style: inputStyle),
                  );
                },
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'GỢI Ý THANG ĐIỂM, TIÊU CHUẨN, TIÊU CHÍ ĐÁNH GIÁ TIẾT DẠY:',
                style: boldStyle,
              ),
              pw.SizedBox(height: 5),

              // Bảng 12 tiêu chí có gộp ô dọc chuẩn biểu mẫu gốc
              // Bọc trong Expanded + FittedBox để bảng chấm điểm KHÔNG BAO GIỜ bị tràn trang hay biến mất khi xuất PDF
              pw.Expanded(
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  alignment: pw.Alignment.topCenter,
                  child: pw.SizedBox(
                    width: pageContentWidth,
                    child: pw.Container(
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                          color: PdfColors.black,
                          width: 1.0,
                        ),
                      ),
                      child: pw.Column(
                        children: [
                          // Hàng tiêu đề bảng điểm (4 ô: Nội dung 18% | Tiêu chí 58% | Điểm tối đa 12% | Điểm đánh giá 12%)
                          pw.CustomPaint(
                            foregroundPainter:
                                (PdfGraphics canvas, PdfPoint size) =>
                                    _paintVerticalDividers(
                                      canvas,
                                      size,
                                      const <double>[0.18, 0.76, 0.88],
                                    ),
                            child: pw.Container(
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(
                                  bottom: pw.BorderSide(
                                    color: PdfColors.black,
                                    width: 1.0,
                                  ),
                                ),
                              ),
                              child: pw.Row(
                                children: [
                                  pw.Expanded(
                                    flex: 18,
                                    child: pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 5,
                                      ),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        'Nội dung\n(Tiêu chuẩn)',
                                        textAlign: pw.TextAlign.center,
                                        style: tblBold,
                                      ),
                                    ),
                                  ),
                                  pw.Expanded(
                                    flex: 58,
                                    child: pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 5,
                                      ),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        'Tiêu chí',
                                        textAlign: pw.TextAlign.center,
                                        style: tblBold,
                                      ),
                                    ),
                                  ),
                                  pw.Expanded(
                                    flex: 12,
                                    child: pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 3,
                                        vertical: 5,
                                      ),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        'Điểm\ntối đa',
                                        textAlign: pw.TextAlign.center,
                                        style: tblBold,
                                      ),
                                    ),
                                  ),
                                  pw.Expanded(
                                    flex: 12,
                                    child: pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 3,
                                        vertical: 5,
                                      ),
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        'Điểm\nđánh giá',
                                        textAlign: pw.TextAlign.center,
                                        style: tblBold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 3 nhóm tiêu chuẩn (1. Yêu cầu cần đạt, 2. Hoạt động GV, 3. Hoạt động HS)
                          _buildPdfCriterionGroup(
                            specs: group1,
                            getRowText: getRowText,
                            tblText: tblText,
                            tblBold: tblBold,
                            inputStyle: inputStyle,
                          ),
                          _buildPdfCriterionGroup(
                            specs: group2,
                            getRowText: getRowText,
                            tblText: tblText,
                            tblBold: tblBold,
                            inputStyle: inputStyle,
                          ),
                          _buildPdfCriterionGroup(
                            specs: group3,
                            getRowText: getRowText,
                            tblText: tblText,
                            tblBold: tblBold,
                            inputStyle: inputStyle,
                          ),

                          // Hàng cuối: Tổng điểm (76% | 12% | 12%)
                          pw.CustomPaint(
                            foregroundPainter:
                                (PdfGraphics canvas, PdfPoint size) =>
                                    _paintVerticalDividers(
                                      canvas,
                                      size,
                                      const <double>[0.76, 0.88],
                                    ),
                            child: pw.Row(
                              children: [
                                pw.Expanded(
                                  flex: 76,
                                  child: pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 5,
                                    ),
                                    alignment: pw.Alignment.center,
                                    child: pw.Text(
                                      'Tổng điểm',
                                      textAlign: pw.TextAlign.center,
                                      style: tblBold,
                                    ),
                                  ),
                                ),
                                pw.Expanded(
                                  flex: 12,
                                  child: pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 5,
                                    ),
                                    alignment: pw.Alignment.center,
                                    child: pw.Text(
                                      '20,0',
                                      textAlign: pw.TextAlign.center,
                                      style: tblBold,
                                    ),
                                  ),
                                ),
                                pw.Expanded(
                                  flex: 12,
                                  child: pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 5,
                                    ),
                                    alignment: pw.Alignment.center,
                                    child: pw.Text(
                                      scoreEval.enteredCount > 0
                                          ? PrimarySchoolEvaluationTemplate
                                              .formatScoreVi(
                                              scoreEval.totalScore,
                                            )
                                          : ' ',
                                      textAlign: pw.TextAlign.center,
                                      style: tblBold.copyWith(
                                        color: PdfColor.fromInt(0xFF1A237E),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // -------------------------------------------------------------------------
    // TRANG 3: ĐIỂM ĐÁNH GIÁ TIẾT DẠY, XẾP LOẠI & CHỮ KÝ NGƯỜI DỰ GIỜ
    // -------------------------------------------------------------------------
    final String ratingText =
        getRowText(PrimarySchoolEvaluationTemplate.rowEvaluatedRating).isNotEmpty
            ? getRowText(PrimarySchoolEvaluationTemplate.rowEvaluatedRating)
            : (scoreEval.suggestedRating ?? '');
    final String signDay =
        getRowText(PrimarySchoolEvaluationTemplate.rowSignDay);
    final String signMonth =
        getRowText(PrimarySchoolEvaluationTemplate.rowSignMonth);
    final String signYear =
        getRowText(PrimarySchoolEvaluationTemplate.rowSignYear);
    final String observerName =
        getRowText(PrimarySchoolEvaluationTemplate.rowObserverName);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 36, 38, 36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('ĐIỂM ĐÁNH GIÁ TIẾT DẠY', style: boldStyle),
              pw.SizedBox(height: 8),
              _buildPdfRatingRule(
                title: '1. Loại Giỏi: ',
                body:
                    'Tổng điểm từ 18,0 đến 20,0 điểm. Trong đó Tiêu chí 2.1 đến 3.4 đạt từ 1,5 điểm trở lên. Các tiêu chí còn lại không có tiêu chí nào dưới 1/2 điểm tối đa.',
                baseStyle: baseStyle,
                boldStyle: boldStyle,
              ),
              pw.SizedBox(height: 6),
              _buildPdfRatingRule(
                title: '2. Loại Khá: ',
                body:
                    'Tổng điểm từ 13,5 đến dưới 18,0 điểm. Trong đó Tiêu chí 2.1 đến 3.4 đạt từ 1,5 điểm trở lên. Các tiêu chí còn lại không có tiêu chí nào dưới 1/2 điểm tối đa.',
                baseStyle: baseStyle,
                boldStyle: boldStyle,
              ),
              pw.SizedBox(height: 6),
              _buildPdfRatingRule(
                title: '3. Loại Trung bình: ',
                body: 'Tổng điểm từ 10,0 đến dưới 13,5 điểm.',
                baseStyle: baseStyle,
                boldStyle: boldStyle,
              ),
              pw.SizedBox(height: 6),
              _buildPdfRatingRule(
                title: '4. Loại Chưa đạt: ',
                body:
                    'Tổng điểm dưới 10,0 điểm hoặc có bất cứ tiêu chí nào 0 điểm.',
                baseStyle: baseStyle,
                boldStyle: boldStyle,
              ),
              pw.SizedBox(height: 14),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 14),
                child: pw.Text('V. ĐÁNH GIÁ TIẾT DẠY:', style: boldStyle),
              ),
              pw.SizedBox(height: 6),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 90, right: 60),
                child: _buildPdfDottedInfoField(
                  label: 'Tiết dạy đạt loại: ',
                  value: ratingText,
                  baseStyle: baseStyle,
                  inputStyle: boldStyle.copyWith(
                    color: PdfColor.fromInt(0xFF1A237E),
                  ),
                ),
              ),
              pw.SizedBox(height: 22),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.SizedBox(
                  width: 240,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'Đức Lập, ngày ${signDay.isEmpty ? "..." : signDay} tháng ${signMonth.isEmpty ? "..." : signMonth} năm ${signYear.isEmpty ? "......" : signYear}',
                        textAlign: pw.TextAlign.center,
                        style: italicStyle,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Người dự giờ',
                        textAlign: pw.TextAlign.center,
                        style: boldStyle,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        '(Ký, ghi rõ họ tên)',
                        textAlign: pw.TextAlign.center,
                        style: italicStyle,
                      ),
                      pw.SizedBox(height: 72),
                      if (observerName.isNotEmpty)
                        pw.Text(
                          observerName,
                          textAlign: pw.TextAlign.center,
                          style: boldStyle,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dựng một khối nhóm tiêu chuẩn trong bảng PDF:
  /// - Cột trái (18%) gộp dọc 4 hàng tiêu chí
  /// - Cột phải (82%) chia làm 4 cột con: Mã (7%) | Tiêu chí (51%) | Điểm tối đa (12%) | Điểm đánh giá (12%)
  /// - Các đường kẻ dọc (18%, 25%, 76%, 88%) được vẽ xuyên suốt chiều cao bằng `CustomPaint` để không bị đứt nét
  static pw.Widget _buildPdfCriterionGroup({
    required List<ObservationCriterionSpec> specs,
    required String Function(int) getRowText,
    required pw.TextStyle tblText,
    required pw.TextStyle tblBold,
    required pw.TextStyle inputStyle,
  }) {
    return pw.CustomPaint(
      foregroundPainter: (PdfGraphics canvas, PdfPoint size) =>
          _paintVerticalDividers(
        canvas,
        size,
        const <double>[0.18, 0.25, 0.76, 0.88],
      ),
      child: pw.Container(
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.black, width: 1.0),
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Cột trái gộp dọc (flex: 18)
            pw.Expanded(
              flex: 18,
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 5,
                ),
                alignment: pw.Alignment.center,
                child: pw.Text(
                  specs.first.groupTitle,
                  textAlign: pw.TextAlign.center,
                  style: tblBold,
                ),
              ),
            ),

            // Cột phải (flex: 82) chứa 4 tiêu chí
            pw.Expanded(
              flex: 82,
              child: pw.Column(
                children: List<pw.Widget>.generate(specs.length, (int idx) {
                  final ObservationCriterionSpec spec = specs[idx];
                  final bool isLast = idx == specs.length - 1;
                  final String scoreVal = getRowText(spec.scoreRowIndex);

                  return pw.Container(
                    decoration: pw.BoxDecoration(
                      border: isLast
                          ? null
                          : const pw.Border(
                              bottom: pw.BorderSide(
                                color: PdfColors.black,
                                width: 0.8,
                              ),
                            ),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Expanded(
                          flex: 7,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 3.8,
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              spec.code,
                              textAlign: pw.TextAlign.center,
                              style: tblText,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 51,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 3.8,
                            ),
                            alignment: pw.Alignment.centerLeft,
                            child: pw.Text(
                              spec.description,
                              style: tblText,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 12,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 3.8,
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              spec.maxScoreLabel,
                              textAlign: pw.TextAlign.center,
                              style: tblText,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 12,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 3.8,
                            ),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              scoreVal.isEmpty ? ' ' : scoreVal,
                              textAlign: pw.TextAlign.center,
                              style: inputStyle.copyWith(
                                fontSize: 9.2,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dựng một dòng thông tin có đường chấm bên dưới trong PDF
  static pw.Widget _buildPdfDottedInfoField({
    required String label,
    required String value,
    required pw.TextStyle baseStyle,
    required pw.TextStyle inputStyle,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: baseStyle),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 1.5, left: 2),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: PdfColors.grey700,
                  width: 0.7,
                  style: pw.BorderStyle.dotted,
                ),
              ),
            ),
            child: pw.Text(
              value.isEmpty ? ' ' : value,
              maxLines: 1,
              style: inputStyle,
            ),
          ),
        ),
      ],
    );
  }

  /// Dựng một đoạn văn quy định xếp loại trong PDF
  static pw.Widget _buildPdfRatingRule({
    required String title,
    required String body,
    required pw.TextStyle baseStyle,
    required pw.TextStyle boldStyle,
  }) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(text: title, style: boldStyle),
          pw.TextSpan(text: body, style: baseStyle),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. KẾT XUẤT PDF TRANG VỞ GHI CHÚ KẺ NGANG (NOTE5X / NOTE4X)
  // ===========================================================================
  static void _buildNoteRuledPdfPages({
    required pw.Document pdf,
    required NotebookModel notebook,
    required Map<int, String> rowMap,
    required pw.Font regularFont,
    required pw.Font mediumFont,
    required pw.Font boldFont,
  }) {
    final bool isNote4x = notebook.paperTemplate == Note4x.templateId;
    final int highestRow = rowMap.keys.isEmpty
        ? 0
        : rowMap.keys.reduce(math.max);
    final int rowsPerPage = isNote4x ? 26 : 24;
    final int totalRows = math.max(rowsPerPage, highestRow + 1);
    final int pageCount = (totalRows / rowsPerPage).ceil();

    final pw.TextStyle titleStyle = pw.TextStyle(
      font: boldFont,
      fontSize: 13,
      color: PdfColor.fromInt(0xFF263BAA),
    );
    final pw.TextStyle rowTextStyle = pw.TextStyle(
      font: mediumFont,
      fontSize: 11.5,
      color: PdfColors.black,
    );

    for (int pageIdx = 0; pageIdx < pageCount; pageIdx++) {
      final int startRow = pageIdx * rowsPerPage;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (pageIdx == 0) ...[
                  pw.Text(notebook.title, style: titleStyle),
                  pw.SizedBox(height: 8),
                ],
                ...List<pw.Widget>.generate(rowsPerPage, (int r) {
                  final int rowIndex = startRow + r;
                  final String lineText = rowMap[rowIndex] ?? '';

                  return pw.Container(
                    height: isNote4x ? 27.0 : 29.0,
                    alignment: pw.Alignment.bottomLeft,
                    padding: const pw.EdgeInsets.only(bottom: 3, left: 4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          color: PdfColor.fromInt(0xFF263BAA),
                          width: 0.75,
                        ),
                      ),
                    ),
                    child: pw.Text(
                      lineText,
                      maxLines: 1,
                      style: rowTextStyle,
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );
    }
  }
}
