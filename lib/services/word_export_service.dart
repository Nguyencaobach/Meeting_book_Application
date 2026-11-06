import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import '../core/constants/note_templates/note4x.dart';
import '../core/constants/observation_templates/primary_school_evaluation_template.dart';
import '../data/models/line_model.dart';
import '../data/models/notebook_model.dart';
import '../data/models/stroke_point_model.dart';

// ===========================================================================
// DỊCH VỤ KẾT XUẤT FILE WORD (.DOC) TRỰC TIẾP TRÊN RAM (WORD EXPORT SERVICE)
// Công dụng:
// - Chuyển đổi dữ liệu của tệp đang mở (NotebookModel) thành mảng byte Word (.doc)
//   trực tiếp trên bộ nhớ RAM (không lưu file tạm xuống ổ cứng máy).
// - Sử dụng chuẩn WordML/HTML A4 (Print View) tương thích 100% với cả
//   Microsoft Word lẫn Google Docs trên Google Drive.
// - Giữ nguyên 100% định dạng gốc cho:
//   1. Biểu mẫu 3 trang "Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học"
//      (Quốc hiệu, Bảng 3 cột 28 dòng nét đứt, Nhận xét chung, Bảng 12 tiêu chí
//       có gộp ô dọc rowspan="4", Tiêu chí colspan="2", Tổng điểm colspan="3",
//       Xếp loại và Chữ ký).
//   2. Vở ghi chú 5 ô ly (note5x) và 4 ô ly (note4x) với các dòng kẻ ngang.
// ===========================================================================
class WordExportService {
  WordExportService._();

  /// Hàm chính: Tạo dữ liệu byte Word (.doc) trên RAM từ `NotebookModel`
  static Uint8List generateWordBytes({
    required NotebookModel notebook,
    required int tabIndex,
  }) {
    final Map<int, String> rowMap = _extractRowTextMap(notebook);
    final Map<int, List<HandwritingClusterModel>> clusterMap =
        _extractRowClusterMap(notebook);
    final List<FreehandPageStrokeModel> freehandStrokes =
        notebook.pages.isEmpty
            ? const <FreehandPageStrokeModel>[]
            : notebook.pages.first.freehandStrokes;
    final bool isObservationForm = tabIndex == 1 ||
        PrimarySchoolEvaluationTemplate.isObservationTemplate(
          notebook.paperTemplate,
        );

    final String htmlContent = isObservationForm
        ? _buildPrimarySchoolEvaluationWordHtml(
            title: notebook.title,
            rowMap: rowMap,
            clusterMap: clusterMap,
            freehandStrokes: freehandStrokes,
          )
        : _buildNoteRuledWordHtml(
            notebook: notebook,
            rowMap: rowMap,
          );

    // Đính kèm UTF-8 BOM (\uFEFF) để Microsoft Word & Google Docs nhận diện chuẩn tiếng Việt
    final List<int> utf8Bytes = utf8.encode('\uFEFF$htmlContent');
    return Uint8List.fromList(utf8Bytes);
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

  /// Trích xuất Map (rowIndex -> danh sách cụm nét chữ viết tay) từ trang đầu tiên
  static Map<int, List<HandwritingClusterModel>> _extractRowClusterMap(
    NotebookModel notebook,
  ) {
    final Map<int, List<HandwritingClusterModel>> map =
        <int, List<HandwritingClusterModel>>{};
    if (notebook.pages.isEmpty) return map;
    for (final LineModel line in notebook.pages.first.lines) {
      if (line.handwritingClusters.isNotEmpty) {
        map[line.rowIndex] = line.handwritingClusters;
      }
    }
    return map;
  }

  /// Mã hóa ký tự đặc biệt HTML để tránh vỡ cấu trúc bảng Word
  static String _escapeHtml(String input) {
    return const HtmlEscape().convert(input);
  }

  static String _toCssHexColor(int colorValue) {
    final int rgb = colorValue & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Tạo chuỗi HTML kết hợp văn bản gõ phím và SVG nét chữ viết tay trên 1 dòng Sổ dự giờ
  static String _buildRowContentHtml({
    required int rowIndex,
    required Map<int, String> rowMap,
    required Map<int, List<HandwritingClusterModel>> clusterMap,
    double svgHeight = 19.0,
  }) {
    final String text = _escapeHtml(rowMap[rowIndex] ?? '');
    final List<HandwritingClusterModel> clusters =
        clusterMap[rowIndex] ?? const <HandwritingClusterModel>[];
    if (clusters.isEmpty) return text;

    final StringBuffer polySb = StringBuffer();
    double cursorX = 1.0;
    final double targetH = svgHeight * 0.80;
    final double topOffset = (svgHeight - targetH) * 0.5;

    for (int i = 0; i < clusters.length; i++) {
      final HandwritingClusterModel cluster = clusters[i];
      if (i > 0 || cluster.leadingSpace) {
        cursorX += cluster.getLeadingGap(svgHeight);
      }
      final double cWidth = cluster.getRenderedWidth(svgHeight);
      final String hexColor = _toCssHexColor(cluster.colorValue);
      final double svgStrokeW = ((cluster.strokeWidth / 2.6) * 1.5)
          .clamp(0.9, 3.6) *
          (cluster.penStyle == PenStrokeStyle.highlighter ? 2.4 : 1.0);
      final String extraSvgAttrs =
          cluster.penStyle == PenStrokeStyle.highlighter
              ? ' stroke-opacity="0.35"'
              : (cluster.penStyle == PenStrokeStyle.dashed
                  ? ' stroke-dasharray="4,3"'
                  : '');

      for (final InkStrokeModel stroke in cluster.strokes) {
        if (stroke.points.isEmpty) continue;
        final String pointsAttr = stroke.points
            .map(
              (StrokePointModel p) =>
                  '${(cursorX + p.x * cWidth).toStringAsFixed(1)},${(topOffset + p.y * targetH).toStringAsFixed(1)}',
            )
            .join(' ');
        polySb.write(
          '<polyline fill="none" stroke="$hexColor" stroke-width="${svgStrokeW.toStringAsFixed(1)}"$extraSvgAttrs stroke-linecap="round" stroke-linejoin="round" points="$pointsAttr" />',
        );
      }
      cursorX += cWidth;
    }

    final int totalW = (cursorX + 2.0).ceil();
    final int totalH = svgHeight.ceil();
    final String svgHtml =
        '<svg xmlns="http://www.w3.org/2000/svg" width="$totalW" height="$totalH" viewBox="0 0 $totalW $totalH" style="vertical-align: middle; display: inline-block;">${polySb.toString()}</svg>';

    return text.isEmpty ? svgHtml : '$text $svgHtml';
  }

  // ===========================================================================
  // 1. KẾT XUẤT WORD 3 TRANG "PHIẾU ĐÁNH GIÁ TIẾT DẠY GIÁO VIÊN CẤP TIỂU HỌC"
  // ===========================================================================
  static String _buildPrimarySchoolEvaluationWordHtml({
    required String title,
    required Map<int, String> rowMap,
    required Map<int, List<HandwritingClusterModel>> clusterMap,
    required List<FreehandPageStrokeModel> freehandStrokes,
  }) {
    String getRowText(int rowIndex) => rowMap[rowIndex] ?? '';
    String getRowHtml(int rowIndex, {double svgHeight = 19.0}) =>
        _buildRowContentHtml(
          rowIndex: rowIndex,
          rowMap: rowMap,
          clusterMap: clusterMap,
          svgHeight: svgHeight,
        );
    final scoreEval =
        PrimarySchoolEvaluationTemplate.evaluateScores(getRowText);

    final String teacherName =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowTeacherName);
    final String className =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowClassName);
    final String schoolName =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowSchoolName);
    final String lessonTitle =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowLessonTitle);
    final String subjectName =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowSubjectName);

    final StringBuffer sb = StringBuffer();

    sb.write('''
<html xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:w="urn:schemas-microsoft-com:office:word"
      xmlns="http://www.w3.org/TR/REC-html40">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>${_escapeHtml(title)}</title>
  <!--[if gte mso 9]>
  <xml>
    <w:WordDocument>
      <w:View>Print</w:View>
      <w:Zoom>100</w:Zoom>
      <w:DoNotOptimizeForBrowser/>
    </w:WordDocument>
  </xml>
  <![endif]-->
  <style>
    @page WordSection1 {
      size: 21.0cm 29.7cm;
      margin: 1.5cm 1.5cm 1.5cm 1.8cm;
      mso-header-margin: 1.0cm;
      mso-footer-margin: 1.0cm;
    }
    div.WordSection1 {
      page: WordSection1;
    }
    body {
      font-family: "Times New Roman", serif;
      font-size: 12pt;
      color: #000000;
      background-color: #FFFFFF;
    }
    table {
      border-collapse: collapse;
      width: 100%;
    }
    .header-table td {
      border: none;
      vertical-align: top;
      text-align: center;
      padding: 2pt 4pt;
    }
    .main-title {
      text-align: center;
      font-size: 13.5pt;
      font-weight: bold;
      margin: 12pt 0 8pt 0;
    }
    .info-line {
      margin: 4pt 0;
      font-size: 12pt;
    }
    .dotted-span {
      border-bottom: 1pt dotted #333333;
      display: inline-block;
      padding: 0 4pt;
      color: #1A237E;
      font-weight: bold;
    }
    .obs-table {
      border: 1pt solid #000000;
      margin-top: 8pt;
    }
    .obs-table th {
      border: 1pt solid #000000;
      padding: 6pt 4pt;
      text-align: center;
      font-weight: normal;
      font-size: 12pt;
      background-color: #FFFFFF;
    }
    .obs-table td {
      border-left: 1pt solid #000000;
      border-right: 1pt solid #000000;
      border-bottom: 1pt dashed #4A65C6;
      height: 19pt;
      padding: 2pt 5pt;
      vertical-align: bottom;
      color: #1A237E;
    }
    .obs-table tr.last-row td {
      border-bottom: 1pt solid #000000;
    }
    .comment-line {
      border-bottom: 1pt dotted #333333;
      height: 19pt;
      padding: 2pt 4pt;
      color: #1A237E;
    }
    .rubric-table {
      border: 1pt solid #000000;
      margin-top: 6pt;
      font-size: 11.5pt;
    }
    .rubric-table th, .rubric-table td {
      border: 1pt solid #000000;
      padding: 4pt 5pt;
      vertical-align: middle;
    }
    .page-break {
      page-break-before: always;
    }
  </style>
</head>
<body>
<div class="WordSection1">
''');

    // -------------------------------------------------------------------------
    // TRANG 1: QUỐC HIỆU, THÔNG TIN CHUNG & BẢNG GHI CHÉP 3 CỘT
    // -------------------------------------------------------------------------
    sb.write('''
  <table class="header-table" style="border: none; width: 100%;">
    <tr>
      <td style="width: 44%; border: none; text-align: center;">
        <div style="font-weight: bold;">TRƯỜNG TH NGUYỄN BÁ NGỌC</div>
        <div style="border-bottom: 1pt solid #000000; width: 110pt; margin: 2pt auto 0 auto;"></div>
      </td>
      <td style="width: 56%; border: none; text-align: center;">
        <div style="font-weight: bold;">CỘNG HOÀ XÃ HỘI CHỦ NGHĨA VIỆT NAM</div>
        <div style="font-weight: bold;">Độc lập – Tự do – Hạnh phúc</div>
        <div style="border-bottom: 1pt solid #000000; width: 145pt; margin: 2pt auto 0 auto;"></div>
      </td>
    </tr>
  </table>

  <div class="main-title">PHIẾU ĐÁNH GIÁ TIẾT DẠY GIÁO VIÊN CẤP TIỂU HỌC</div>

  <table style="border: none; margin-bottom: 4pt; width: 100%;">
    <tr>
      <td style="border: none; width: 50%; padding: 2pt 0;">
        Họ, tên người dạy: <span class="dotted-span" style="min-width: 120pt;">${teacherName.isEmpty ? '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' : teacherName}</span>
      </td>
      <td style="border: none; width: 18%; padding: 2pt 0;">
        Lớp: <span class="dotted-span" style="min-width: 45pt;">${className.isEmpty ? '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' : className}</span>
      </td>
      <td style="border: none; width: 32%; padding: 2pt 0;">
        Trường: <span class="dotted-span" style="min-width: 90pt;">${schoolName.isEmpty ? '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' : schoolName}</span>
      </td>
    </tr>
    <tr>
      <td colspan="2" style="border: none; width: 68%; padding: 2pt 0;">
        Tên bài dạy: <span class="dotted-span" style="min-width: 210pt;">${lessonTitle.isEmpty ? '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' : lessonTitle}</span>
      </td>
      <td style="border: none; width: 32%; padding: 2pt 0;">
        Môn: <span class="dotted-span" style="min-width: 95pt;">${subjectName.isEmpty ? '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' : subjectName}</span>
      </td>
    </tr>
  </table>

  <table class="obs-table" border="1" cellspacing="0" cellpadding="4" style="border-collapse: collapse; border: 1pt solid #000000; width: 100%;">
    <tr>
      <th style="width: 33.33%; border: 1pt solid #000000; text-align: center;">Nội dung hoạt động</th>
      <th style="width: 33.33%; border: 1pt solid #000000; text-align: center;">Biểu hiện của học sinh</th>
      <th style="width: 33.34%; border: 1pt solid #000000; text-align: center;">Nguyên nhân - Biện pháp</th>
    </tr>
''');

    for (int r = 0;
        r < PrimarySchoolEvaluationTemplate.activityTableRowCount;
        r++) {
      final bool isLast =
          r == PrimarySchoolEvaluationTemplate.activityTableRowCount - 1;
      final String c1 = getRowHtml(
        PrimarySchoolEvaluationTemplate.col1StartRow + r,
      );
      final String c2 = getRowHtml(
        PrimarySchoolEvaluationTemplate.col2StartRow + r,
      );
      final String c3 = getRowHtml(
        PrimarySchoolEvaluationTemplate.col3StartRow + r,
      );
      final String bottomBorderCss =
          isLast ? '1pt solid #000000' : '1pt dashed #4A65C6';

      sb.write('''
    <tr${isLast ? ' class="last-row"' : ''}>
      <td style="border-left: 1pt solid #000000; border-right: 1pt solid #000000; border-bottom: $bottomBorderCss;">${c1.isEmpty ? '&nbsp;' : c1}</td>
      <td style="border-left: 1pt solid #000000; border-right: 1pt solid #000000; border-bottom: $bottomBorderCss;">${c2.isEmpty ? '&nbsp;' : c2}</td>
      <td style="border-left: 1pt solid #000000; border-right: 1pt solid #000000; border-bottom: $bottomBorderCss;">${c3.isEmpty ? '&nbsp;' : c3}</td>
    </tr>
''');
    }

    sb.write('''
  </table>

  <br clear="all" style="page-break-before:always" />
''');

    // -------------------------------------------------------------------------
    // TRANG 2: NHẬN XÉT CHUNG & BẢNG THANG ĐIỂM 12 TIÊU CHÍ
    // -------------------------------------------------------------------------
    sb.write('''
  <div style="font-weight: bold; margin-bottom: 4pt;">NHẬN XÉT, ĐÁNH GIÁ CHUNG:</div>
''');

    for (int i = 0;
        i < PrimarySchoolEvaluationTemplate.generalCommentLineCount;
        i++) {
      final String cmt = getRowHtml(
        PrimarySchoolEvaluationTemplate.generalCommentStartRow + i,
      );
      sb.write(
        '  <div class="comment-line">${cmt.isEmpty ? '&nbsp;' : cmt}</div>\n',
      );
    }

    sb.write('''
  <div style="font-weight: bold; margin-top: 14pt; margin-bottom: 6pt;">
    GỢI Ý THANG ĐIỂM, TIÊU CHUẨN, TIÊU CHÍ ĐÁNH GIÁ TIẾT DẠY:
  </div>

  <table class="rubric-table" border="1" cellspacing="0" cellpadding="4" style="border-collapse: collapse; border: 1pt solid #000000; width: 100%;">
    <tr>
      <th style="width: 18%; border: 1pt solid #000000; text-align: center; font-weight: bold;">Nội dung<br/>(Tiêu chuẩn)</th>
      <th colspan="2" style="width: 58%; border: 1pt solid #000000; text-align: center; font-weight: bold;">Tiêu chí</th>
      <th style="width: 12%; border: 1pt solid #000000; text-align: center; font-weight: bold;">Điểm<br/>tối đa</th>
      <th style="width: 12%; border: 1pt solid #000000; text-align: center; font-weight: bold;">Điểm<br/>đánh giá</th>
    </tr>
''');

    for (int groupIdx = 1; groupIdx <= 3; groupIdx++) {
      final List<ObservationCriterionSpec> groupSpecs =
          PrimarySchoolEvaluationTemplate.criteriaList
              .where((c) => c.groupIndex == groupIdx)
              .toList();

      for (int i = 0; i < groupSpecs.length; i++) {
        final ObservationCriterionSpec spec = groupSpecs[i];
        final String scoreVal = getRowHtml(spec.scoreRowIndex);
        final String groupTitleHtml =
            _escapeHtml(spec.groupTitle).replaceAll('\n', '<br/>');

        sb.write('    <tr>\n');
        if (i == 0) {
          sb.write(
            '      <td rowspan="${groupSpecs.length}" style="width: 18%; border: 1pt solid #000000; text-align: center; font-weight: bold; vertical-align: middle;">$groupTitleHtml</td>\n',
          );
        }
        sb.write('''
      <td style="width: 7%; border: 1pt solid #000000; text-align: center; vertical-align: middle;">${_escapeHtml(spec.code)}</td>
      <td style="width: 51%; border: 1pt solid #000000; text-align: left; vertical-align: middle;">${_escapeHtml(spec.description)}</td>
      <td style="width: 12%; border: 1pt solid #000000; text-align: center; vertical-align: middle;">${spec.maxScoreLabel}</td>
      <td style="width: 12%; border: 1pt solid #000000; text-align: center; font-weight: bold; color: #1A237E; vertical-align: middle;">${scoreVal.isEmpty ? '&nbsp;' : scoreVal}</td>
    </tr>
''');
      }
    }

    final String totalScoreText = scoreEval.enteredCount > 0
        ? PrimarySchoolEvaluationTemplate.formatScoreVi(scoreEval.totalScore)
        : '&nbsp;';

    sb.write('''
    <tr>
      <td colspan="3" style="border: 1pt solid #000000; text-align: center; font-weight: bold;">Tổng điểm</td>
      <td style="border: 1pt solid #000000; text-align: center;">20,0</td>
      <td style="border: 1pt solid #000000; text-align: center; font-weight: bold; color: #1A237E;">$totalScoreText</td>
    </tr>
  </table>

  <br clear="all" style="page-break-before:always" />
''');

    // -------------------------------------------------------------------------
    // TRANG 3: QUY ĐỊNH ĐIỂM ĐÁNH GIÁ, XẾP LOẠI & CHỮ KÝ NGƯỜI DỰ GIỜ
    // -------------------------------------------------------------------------
    final String rawRatingHtml =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowEvaluatedRating);
    final String ratingText = rawRatingHtml.isNotEmpty
        ? rawRatingHtml
        : _escapeHtml(scoreEval.suggestedRating ?? '');
    final String signDay =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowSignDay);
    final String signMonth =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowSignMonth);
    final String signYear =
        getRowHtml(PrimarySchoolEvaluationTemplate.rowSignYear);
    final String observerName = getRowHtml(
      PrimarySchoolEvaluationTemplate.rowObserverName,
      svgHeight: 24.0,
    );

    sb.write('''
  <div style="font-weight: bold; margin-bottom: 8pt;">ĐIỂM ĐÁNH GIÁ TIẾT DẠY</div>
  <p style="margin: 5pt 0;">
    1. <b>Loại Giỏi:</b> Tổng điểm từ 18,0 đến 20,0 điểm. Trong đó Tiêu chí 2.1 đến 3.4 đạt từ 1,5 điểm trở lên. Các tiêu chí còn lại không có tiêu chí nào dưới 1/2 điểm tối đa.
  </p>
  <p style="margin: 5pt 0;">
    2. <b>Loại Khá:</b> Tổng điểm từ 13,5 đến dưới 18,0 điểm. Trong đó Tiêu chí 2.1 đến 3.4 đạt từ 1,5 điểm trở lên. Các tiêu chí còn lại không có tiêu chí nào dưới 1/2 điểm tối đa.
  </p>
  <p style="margin: 5pt 0;">
    3. <b>Loại Trung bình:</b> Tổng điểm từ 10,0 đến dưới 13,5 điểm.
  </p>
  <p style="margin: 5pt 0;">
    4. <b>Loại Chưa đạt:</b> Tổng điểm dưới 10,0 điểm hoặc có bất cứ tiêu chí nào 0 điểm.
  </p>

  <div style="font-weight: bold; margin-top: 10pt; margin-bottom: 6pt; padding-left: 14pt;">V. ĐÁNH GIÁ TIẾT DẠY:</div>
  <div style="margin-bottom: 20pt; padding-left: 95pt;">
    Tiết dạy đạt loại: <span class="dotted-span" style="min-width: 180pt;">${ratingText.isEmpty ? '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;' : ratingText}</span>
  </div>

  <table style="border: none; width: 100%;">
    <tr>
      <td style="border: none; width: 45%;"></td>
      <td style="border: none; width: 55%; text-align: center;">
        <div style="font-style: italic;">
          Đức Lập, ngày ${signDay.isEmpty ? '...' : signDay} tháng ${signMonth.isEmpty ? '...' : signMonth} năm ${signYear.isEmpty ? '...' : signYear}
        </div>
        <div style="margin-top: 4pt;">Người dự giờ</div>
        <div style="font-style: italic;">(Ký, ghi rõ họ tên)</div>
        <div style="height: 75pt;"></div>
        <div style="font-weight: bold;">$observerName</div>
      </td>
    </tr>
  </table>
''');

    if (freehandStrokes.isNotEmpty) {
      const double evalPageWidthPx = 660.0;
      const double evalRowHeightPx = 28.0;
      double maxRy = 108.0;
      for (final FreehandPageStrokeModel stroke in freehandStrokes) {
        for (final StrokePointModel p in stroke.points) {
          if (p.ry + 2.0 > maxRy) {
            maxRy = p.ry + 2.0;
          }
        }
      }
      final double totalEvalHeightPx = maxRy * evalRowHeightPx;
      sb.write(
        '  <svg xmlns="http://www.w3.org/2000/svg" width="${evalPageWidthPx.toInt()}" height="${totalEvalHeightPx.toInt()}" viewBox="0 0 ${evalPageWidthPx.toInt()} ${totalEvalHeightPx.toInt()}" style="position: absolute; top: 0; left: 0; pointer-events: none;">\n',
      );
      for (final FreehandPageStrokeModel stroke in freehandStrokes) {
        if (stroke.points.isEmpty) continue;
        final String hexColor = _toCssHexColor(stroke.colorValue);
        final double svgStrokeW =
            ((stroke.strokeWidth / 2.6) * 1.8).clamp(1.0, 4.5) *
                (stroke.penStyle == PenStrokeStyle.highlighter ? 2.4 : 1.0);
        final String extraSvgAttrs =
            stroke.penStyle == PenStrokeStyle.highlighter
                ? ' stroke-opacity="0.35"'
                : (stroke.penStyle == PenStrokeStyle.dashed
                    ? ' stroke-dasharray="5,4"'
                    : '');
        final String pointsAttr = stroke.points
            .map(
              (StrokePointModel p) =>
                  '${(p.x * evalPageWidthPx).toStringAsFixed(1)},${(p.y * evalRowHeightPx).toStringAsFixed(1)}',
            )
            .join(' ');
        sb.write(
          '    <polyline fill="none" stroke="$hexColor" stroke-width="${svgStrokeW.toStringAsFixed(1)}"$extraSvgAttrs stroke-linecap="round" stroke-linejoin="round" points="$pointsAttr" />\n',
        );
      }
      sb.write('  </svg>\n');
    }

    sb.write('''
</div>
</body>
</html>
''');

    return sb.toString();
  }

  // ===========================================================================
  // 2. KẾT XUẤT WORD CHO VỞ GHI CHÚ KẺ NGANG (NOTE5X / NOTE4X)
  // ===========================================================================
  static String _buildNoteRuledWordHtml({
    required NotebookModel notebook,
    required Map<int, String> rowMap,
  }) {
    final bool isNote4x = notebook.paperTemplate == Note4x.templateId;
    final List<FreehandPageStrokeModel> freehandStrokes =
        notebook.pages.isEmpty
            ? const <FreehandPageStrokeModel>[]
            : notebook.pages.first.freehandStrokes;
    final int highestTextRow = rowMap.keys.isEmpty
        ? 0
        : rowMap.keys.reduce(math.max);
    int highestStrokeRow = 0;
    for (final FreehandPageStrokeModel stroke in freehandStrokes) {
      for (final StrokePointModel p in stroke.points) {
        highestStrokeRow = math.max(highestStrokeRow, p.y.ceil());
      }
    }
    final int minRows = isNote4x ? 26 : 24;
    final int totalRows = math.max(
      minRows,
      math.max(highestTextRow + 1, highestStrokeRow + 1),
    );
    const double rowHeightPx = 30.0;
    const double pageWidthPx = 660.0;
    final double totalHeightPx = totalRows * rowHeightPx;

    final StringBuffer sb = StringBuffer();
    sb.write('''
<html xmlns:o="urn:schemas-microsoft-com:office:office"
      xmlns:w="urn:schemas-microsoft-com:office:word"
      xmlns="http://www.w3.org/TR/REC-html40">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <title>${_escapeHtml(notebook.title)}</title>
  <!--[if gte mso 9]>
  <xml>
    <w:WordDocument>
      <w:View>Print</w:View>
      <w:Zoom>100</w:Zoom>
      <w:DoNotOptimizeForBrowser/>
    </w:WordDocument>
  </xml>
  <![endif]-->
  <style>
    @page WordSection1 {
      size: 21.0cm 29.7cm;
      margin: 1.8cm 1.6cm 1.8cm 1.8cm;
    }
    div.WordSection1 {
      page: WordSection1;
    }
    body {
      font-family: "Times New Roman", serif;
      font-size: 13pt;
      color: #000000;
    }
    .note-title {
      font-size: 15pt;
      font-weight: bold;
      color: #263BAA;
      margin-bottom: 10pt;
    }
    .ruled-line {
      border-bottom: 1pt solid #263BAA;
      height: 22pt;
      line-height: 22pt;
      padding: 0 4pt;
    }
  </style>
</head>
<body>
<div class="WordSection1">
  <div class="note-title">${_escapeHtml(notebook.title)}</div>
  <div style="position: relative; width: ${pageWidthPx.toInt()}px;">
''');

    for (int r = 0; r < totalRows; r++) {
      final String text = _escapeHtml(rowMap[r] ?? '');
      sb.write(
        '    <div class="ruled-line">${text.isEmpty ? '&nbsp;' : text}</div>\n',
      );
    }

    if (freehandStrokes.isNotEmpty) {
      sb.write(
        '    <svg xmlns="http://www.w3.org/2000/svg" width="${pageWidthPx.toInt()}" height="${totalHeightPx.toInt()}" viewBox="0 0 ${pageWidthPx.toInt()} ${totalHeightPx.toInt()}" style="position: absolute; top: 0; left: 0; pointer-events: none;">\n',
      );
      for (final FreehandPageStrokeModel stroke in freehandStrokes) {
        if (stroke.points.isEmpty) continue;
        final String hexColor = _toCssHexColor(stroke.colorValue);
        final double svgStrokeW = ((stroke.strokeWidth / 2.6) * 1.8)
            .clamp(1.0, 4.5) *
            (stroke.penStyle == PenStrokeStyle.highlighter ? 2.4 : 1.0);
        final String extraSvgAttrs =
            stroke.penStyle == PenStrokeStyle.highlighter
                ? ' stroke-opacity="0.35"'
                : (stroke.penStyle == PenStrokeStyle.dashed
                    ? ' stroke-dasharray="5,4"'
                    : '');
        final String pointsAttr = stroke.points
            .map(
              (StrokePointModel p) =>
                  '${(p.x * pageWidthPx).toStringAsFixed(1)},${(p.y * rowHeightPx).toStringAsFixed(1)}',
            )
            .join(' ');
        sb.write(
          '      <polyline fill="none" stroke="$hexColor" stroke-width="${svgStrokeW.toStringAsFixed(1)}"$extraSvgAttrs stroke-linecap="round" stroke-linejoin="round" points="$pointsAttr" />\n',
        );
      }
      sb.write('    </svg>\n');
    }

    sb.write('''
  </div>
</div>
</body>
</html>
''');
    return sb.toString();
  }
}
