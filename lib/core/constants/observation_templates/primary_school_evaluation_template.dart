import 'package:flutter/material.dart';
import '../../../data/models/stroke_point_model.dart';
import '../../theme/app_theme.dart';
import '../app_colors.dart';

// ===========================================================================
// MODEL THÔNG TIN BỐ CỤC ĐO ĐẠC THỰC TẾ CỦA 3 TRANG BIỂU MẪU & Ô CHỮ KÝ
// Công dụng:
// - Lưu tọa độ chuẩn hóa thực tế (startRy..endRy, sigStartNx..sigEndNx, sigStartRy..sigEndRy)
//   của Trang 1, Trang 2, Trang 3 và vùng ký tên Người dự giờ trên màn hình ứng dụng.
// - Giúp khi xuất PDF và Word, chữ ký và các nét vẽ bút tự do luôn khớp đúng 100%
//   vị trí giống như trên giao diện ứng dụng, không bị bay lệch sang vùng khác.
// ===========================================================================
class EvaluationExportLayoutBounds {
  final double page1StartRy;
  final double page1EndRy;
  final double page2StartRy;
  final double page2EndRy;
  final double page3StartRy;
  final double page3EndRy;
  final double sigStartNx;
  final double sigEndNx;
  final double sigStartRy;
  final double sigEndRy;

  const EvaluationExportLayoutBounds({
    this.page1StartRy = 1.4,
    this.page1EndRy = 33.4,
    this.page2StartRy = 36.2,
    this.page2EndRy = 65.5,
    this.page3StartRy = 68.2,
    this.page3EndRy = 81.2,
    this.sigStartNx = 0.43,
    this.sigEndNx = 0.97,
    this.sigStartRy = 76.8,
    this.sigEndRy = 79.8,
  });

  /// Kiểm tra xem một nét vẽ tự do có nằm trong khu vực chữ ký Người dự giờ ở Trang 3 không
  bool isSignatureStroke(FreehandPageStrokeModel stroke) {
    if (stroke.points.isEmpty) return false;
    double sumNx = 0.0;
    double sumRy = 0.0;
    for (final StrokePointModel pt in stroke.points) {
      sumNx += pt.nx;
      sumRy += pt.ry;
    }
    final double avgNx = sumNx / stroke.points.length;
    final double avgRy = sumRy / stroke.points.length;
    return avgNx >= (sigStartNx - 0.14) &&
        avgRy >= (sigStartRy - 2.2) &&
        avgRy <= (page3EndRy + 2.5);
  }
}

// ===========================================================================
// MODEL THÔNG TIN MỘT BIỂU MẪU SỔ DỰ GIỜ ĐỂ HIỂN THỊ TRONG DANH SÁCH CHỌN
// ===========================================================================
class ObservationTemplateItem {
  final String id;
  final String name;
  final String description;

  const ObservationTemplateItem({
    required this.id,
    required this.name,
    required this.description,
  });
}

// ===========================================================================
// MODEL THÔNG TIN MỘT TIÊU CHÍ CHẤM ĐIỂM TRONG PHIẾU ĐÁNH GIÁ TIẾT DẠY TIỂU HỌC
// Công dụng:
// - Lưu trữ mã tiêu chí (1.1 -> 3.4), tên nhóm tiêu chuẩn, nội dung chi tiết,
//   điểm tối đa và chỉ số dòng (scoreRowIndex) để lưu vào JSON.
// ===========================================================================
class ObservationCriterionSpec {
  final String code;
  final int groupIndex;
  final String groupTitle;
  final String description;
  final double maxScore;
  final int scoreRowIndex;

  const ObservationCriterionSpec({
    required this.code,
    required this.groupIndex,
    required this.groupTitle,
    required this.description,
    required this.maxScore,
    required this.scoreRowIndex,
  });

  /// Hiển thị điểm tối đa theo định dạng số thập phân tiếng Việt (dấu phẩy)
  String get maxScoreLabel =>
      PrimarySchoolEvaluationTemplate.formatScoreVi(maxScore);
}

// ===========================================================================
// KIỂU HÀM DỰNG Ô NHẬP LIỆU TƯƠNG TÁC (BÀN PHÍM & VIẾT BÚT) TRÊN BIỂU MẪU
// ===========================================================================
typedef ObservationInteractiveFieldBuilder = Widget Function({
  required int rowIndex,
  required double width,
  required double height,
  required TextStyle textStyle,
  double horizontalPadding,
  TextAlign textAlign,
  String? hintText,
  TextInputType? keyboardType,
  double bottomContentPadding,
});

// ===========================================================================
// BIỂU MẪU "PHIẾU ĐÁNH GIÁ TIẾT DẠY GIÁO VIÊN CẤP TIỂU HỌC" (3 TRANG)
// Công dụng:
// - Tái tạo 100% nội dung và bố cục 3 trang của biểu mẫu dự giờ cấp Tiểu học:
//   + Trang 1: Quốc hiệu, tiêu đề trường, thông tin người dạy/bài dạy và
//              Bảng ghi chép 3 cột (Nội dung hoạt động | Biểu hiện của học sinh |
//              Nguyên nhân - Biện pháp) gồm 28 dòng kẻ nét đứt.
//   + Trang 2: Mục Nhận xét, đánh giá chung (5 dòng chấm) và Bảng gợi ý thang điểm
//              12 tiêu chí (1.1 -> 3.4, tổng 20,0 điểm) tự động cộng tổng điểm.
//   + Trang 3: Quy định 4 mức xếp loại (Giỏi, Khá, Trung bình, Chưa đạt),
//              mục Đánh giá tiết dạy đạt loại (tự động xét loại) và chữ ký Người dự giờ.
// - Tương thích hoàn toàn với cơ chế lưu tạm RAM (_ramCache) và đồng bộ Google Drive.
// ===========================================================================
class PrimarySchoolEvaluationTemplate {
  PrimarySchoolEvaluationTemplate._();

  /// Mã định danh biểu mẫu lưu trong file JSON trên Google Drive
  static const String templateId = 'primary_school_eval_v1';

  /// Tên hiển thị của biểu mẫu trong danh sách chọn khi tạo Sổ dự giờ mới
  static const String displayName =
      'Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học';

  /// Mô tả ngắn hiển thị dưới tên biểu mẫu trong danh sách chọn
  static const String description =
      'Biểu mẫu 3 trang: Bảng dự giờ 3 cột, thang điểm 12 tiêu chí (20 điểm) và xếp loại tiết dạy';

  /// Chiều ngang tối thiểu chuẩn của trang biểu mẫu (để bảng 3 cột và 5 cột luôn rộng rãi)
  static const double minPaperWidth = 680.0;

  /// Số đơn vị chia dòng mặc định của biểu mẫu
  static const int unitsPerRow = 4;

  /// Danh sách tất cả các biểu mẫu Sổ dự giờ hiện có (dùng để hiển thị dạng danh sách khi tạo file)
  static const List<ObservationTemplateItem> availableTemplates =
      <ObservationTemplateItem>[
    ObservationTemplateItem(
      id: templateId,
      name: displayName,
      description: description,
    ),
  ];

  /// Kiểm tra xem mã biểu mẫu có thuộc nhóm biểu mẫu Sổ dự giờ hay không
  static bool isObservationTemplate(String? id) {
    if (id == null) return false;
    return id == templateId || id == 'observation_blank_v1';
  }

  /// Màu nền trang biểu mẫu theo Theme (#FFFFFF - Màu trắng giống bản gốc biểu mẫu)
  static Color getPaperBackgroundColor() {
    return AppColors.basicWhite;
  }

  /// Màu chữ viết trên biểu mẫu theo Theme (#000000)
  static Color getTextColor() {
    return AppColors.basicBlack;
  }

  /// Tính chiều cao 1 đơn vị nhỏ tự động co giãn theo kích thước màn hình
  static double getResponsiveUnitHeight(
    BuildContext context, {
    double? maxWidth,
  }) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double referenceWidth = maxWidth ?? screenSize.width;
    final double shortestSide = screenSize.shortestSide;

    final double baseUnit =
        (referenceWidth * 0.0085 + shortestSide * 0.0065).clamp(9.0, 13.0);
    return baseUnit.roundToDouble();
  }

  /// Tính chiều cao 1 dòng viết trên biểu mẫu tự động co giãn theo màn hình
  static double getResponsiveRowHeight(
    BuildContext context, {
    double? maxWidth,
  }) {
    final double unitHeight = getResponsiveUnitHeight(
      context,
      maxWidth: maxWidth,
    );
    return unitHeight * unitsPerRow;
  }

  /// Tính khoảng lề ngang hai bên trang biểu mẫu
  static double getResponsiveHorizontalPadding(double maxWidth) {
    return (maxWidth * 0.022).clamp(14.0, 22.0);
  }

  // ===========================================================================
  // QUY ƯỚC CHỈ SỐ DÒNG (ROW INDEX) LƯU TRONG MẢNG `lines` CỦA FILE JSON
  // ===========================================================================

  // 1. Các trường thông tin hành chính ở đầu Trang 1 (0 -> 4)
  static const int rowTeacherName = 0;
  static const int rowClassName = 1;
  static const int rowSchoolName = 2;
  static const int rowLessonTitle = 3;
  static const int rowSubjectName = 4;

  // 2. Bảng ghi chép dự giờ 3 cột ở Trang 1 (Mỗi cột gồm 28 dòng kẻ nét đứt)
  static const int activityTableRowCount = 28;
  static const int col1StartRow = 100; // 100 -> 127: Nội dung hoạt động
  static const int col2StartRow = 200; // 200 -> 227: Biểu hiện của học sinh
  static const int col3StartRow = 300; // 300 -> 327: Nguyên nhân - Biện pháp

  // 3. Mục "NHẬN XÉT, ĐÁNH GIÁ CHUNG" ở đầu Trang 2 (5 dòng kẻ chấm: 400 -> 404)
  static const int generalCommentLineCount = 5;
  static const int generalCommentStartRow = 400;

  // 4. Cột "Điểm đánh giá" của 12 tiêu chí ở Trang 2 (500 -> 511)
  static const int scoreStartRow = 500;
  static const int scoreRowCount = 12;

  // 5. Mục xếp loại & chữ ký ở Trang 3 (600 -> 604)
  static const int rowEvaluatedRating = 600;
  static const int rowSignDay = 601;
  static const int rowSignMonth = 602;
  static const int rowSignYear = 603;
  static const int rowObserverName = 604;

  // ===========================================================================
  // DANH SÁCH 12 TIÊU CHÍ ĐÁNH GIÁ TIẾT DẠY (NGUYÊN BẢN 100% TỪ FILE BIỂU MẪU)
  // ===========================================================================
  static const List<ObservationCriterionSpec> criteriaList =
      <ObservationCriterionSpec>[
    // Nhóm 1: 1. Yêu cầu cần đạt (4,0 điểm)
    ObservationCriterionSpec(
      code: '1.1',
      groupIndex: 1,
      groupTitle: '1. Yêu cầu cần đạt\n(4,0 điểm)',
      description:
          'Tiết dạy đảm bảo đủ nội dung kiến thức, hoàn thành các yêu cầu cần đạt của chương trình, sách giáo khoa; nội dung Kế hoạch bài dạy phù hợp tiến trình tổ chức các hoạt động dạy học trên lớp.',
      maxScore: 1.0,
      scoreRowIndex: 500,
    ),
    ObservationCriterionSpec(
      code: '1.2',
      groupIndex: 1,
      groupTitle: '1. Yêu cầu cần đạt\n(4,0 điểm)',
      description:
          'Đảm bảo tính chính xác, hệ thống, hình thành và phát triển các năng lực, phẩm chất phù hợp nội dung bài dạy. Tiết dạy đảm bảo thời gian; giáo viên vận dụng, lựa chọn các phương pháp, hình thức, kỹ thuật dạy học đa dạng, phù hợp. Tiết học diễn ra nhẹ nhàng, hiệu quả, không gượng ép, áp đặt.',
      maxScore: 1.0,
      scoreRowIndex: 501,
    ),
    ObservationCriterionSpec(
      code: '1.3',
      groupIndex: 1,
      groupTitle: '1. Yêu cầu cần đạt\n(4,0 điểm)',
      description:
          'Khai thác, sử dụng các thiết bị, phương tiện, kỹ thuật, ứng dụng CNTT các hoạt động học của học sinh đảm bảo phù hợp, hiệu quả, không lạm dụng.',
      maxScore: 1.0,
      scoreRowIndex: 502,
    ),
    ObservationCriterionSpec(
      code: '1.4',
      groupIndex: 1,
      groupTitle: '1. Yêu cầu cần đạt\n(4,0 điểm)',
      description:
          'Phương pháp kiểm tra, đánh giá, nhận xét sản phẩm, bài học, bài tập của học sinh trong quá trình tổ chức hoạt động học phù hợp. Các sản phẩm, bài tập của học sinh được giáo viên ghi nhận, tôn trọng, phát huy quyền học tập của học sinh;',
      maxScore: 1.0,
      scoreRowIndex: 503,
    ),

    // Nhóm 2: 2. Hoạt động dạy học của giáo viên (8,0 điểm)
    ObservationCriterionSpec(
      code: '2.1',
      groupIndex: 2,
      groupTitle: '2. Hoạt động dạy học của giáo viên\n(8,0 điểm)',
      description:
          'Nội dung, phương pháp, hình thức tổ chức các hoạt động dạy học logic, phù hợp đặc trưng của môn học, cấu trúc bài học (bài mới, luyện tập, thực hành, ôn tập) thể hiện rõ yêu cầu cần đạt, giáo viên giao nhiệm vụ học tập rõ ràng, chính xác, phù hợp, sinh động, hấp dẫn.',
      maxScore: 2.0,
      scoreRowIndex: 504,
    ),
    ObservationCriterionSpec(
      code: '2.2',
      groupIndex: 2,
      groupTitle: '2. Hoạt động dạy học của giáo viên\n(8,0 điểm)',
      description:
          'Kĩ năng sư phạm chuẩn mực, lời nói rõ ràng giữa câu lệnh giáo viên giao nhiệm vụ và nội dung cần trao đổi, hướng dẫn, giúp đỡ học sinh; Theo dõi, quan sát, phát hiện kịp thời những khó khăn của học sinh, trong đó có nhóm học sinh Chưa hoàn thành và nhóm học sinh Hoàn thành tự học vươn lên Hoàn thành tốt.',
      maxScore: 2.0,
      scoreRowIndex: 505,
    ),
    ObservationCriterionSpec(
      code: '2.3',
      groupIndex: 2,
      groupTitle: '2. Hoạt động dạy học của giáo viên\n(8,0 điểm)',
      description:
          'Các biện pháp hỗ trợ và khuyến khích học sinh hợp tác, giúp đỡ nhau khi thực hiện nhiệm vụ học tập đảm bảo phù hợp, hiệu quả.',
      maxScore: 2.0,
      scoreRowIndex: 506,
    ),
    ObservationCriterionSpec(
      code: '2.4',
      groupIndex: 2,
      groupTitle: '2. Hoạt động dạy học của giáo viên\n(8,0 điểm)',
      description:
          'Việc tổng hợp, phân tích, đánh giá quá trình và kết quả học tập của học sinh (làm rõ những nội dung/yêu cầu về kiến thức, kĩ năng học sinh cần ghi nhận, thực hiện) đảm bảo chính xác, hiệu quả. Thiết kế, sử dụng các phiếu học tập, các phương tiện, kỹ thuật, đồ dùng dạy học, thiết bị hiệu quả, phát huy tác dụng với thực tế',
      maxScore: 2.0,
      scoreRowIndex: 507,
    ),

    // Nhóm 3: 3. Hoạt động học của học sinh (8,0 điểm)
    ObservationCriterionSpec(
      code: '3.1',
      groupIndex: 3,
      groupTitle: '3. Hoạt động học của học sinh\n(8,0 điểm)',
      description:
          'Học sinh tiếp nhận nhiệm vụ, chủ động, sáng tạo, hợp tác với giáo viên thực hiện nhiệm vụ học tập được giao',
      maxScore: 2.0,
      scoreRowIndex: 508,
    ),
    ObservationCriterionSpec(
      code: '3.2',
      groupIndex: 3,
      groupTitle: '3. Hoạt động học của học sinh\n(8,0 điểm)',
      description:
          'Học sinh tích cực tham gia trình bày, thảo luận về kết quả thực hiện nhiệm vụ học tập.',
      maxScore: 2.0,
      scoreRowIndex: 509,
    ),
    ObservationCriterionSpec(
      code: '3.3',
      groupIndex: 3,
      groupTitle: '3. Hoạt động học của học sinh\n(8,0 điểm)',
      description:
          'Kết quả thực hiện nhiệm vụ học tập của học sinh đảm bảo đúng đắn, chính xác, phù hợp.',
      maxScore: 2.0,
      scoreRowIndex: 510,
    ),
    ObservationCriterionSpec(
      code: '3.4',
      groupIndex: 3,
      groupTitle: '3. Hoạt động học của học sinh\n(8,0 điểm)',
      description:
          'Học sinh phối hợp nhịp nhàng với giáo viên, phát huy khả năng học tập; phát triển phẩm chất, năng lực',
      maxScore: 2.0,
      scoreRowIndex: 511,
    ),
  ];

  // ===========================================================================
  // CÁC HÀM KIỂM TRA VÙNG DÒNG, TÍNH KÍCH THƯỚC & TỰ ĐỘNG CHẤM ĐIỂM / XẾP LOẠI
  // ===========================================================================

  /// Tính chiều ngang chuẩn của trang biểu mẫu phụ thuộc vào kích thước màn hình
  static double getResponsivePaperWidth(double viewportWidth) {
    return viewportWidth >= minPaperWidth ? viewportWidth : minPaperWidth;
  }

  /// Kiểm tra xem `rowIndex` có phải là ô nhập điểm của 1 trong 12 tiêu chí không
  static bool isScoreRow(int rowIndex) {
    return rowIndex >= scoreStartRow &&
        rowIndex < scoreStartRow + scoreRowCount;
  }

  /// Lấy thông tin giới hạn đầu - cuối của vùng chứa `rowIndex`
  /// - Các cột trong bảng 3 cột và mục Nhận xét chung hỗ trợ tự động xuống dòng trong nội bộ vùng.
  /// - Các ô thông tin hành chính, điểm số, ngày tháng là ô đơn lẻ (`isSingleLine: true`).
  static ({int minRow, int maxRow, bool isSingleLine}) getSectionBoundsForRow(
    int rowIndex,
  ) {
    if (rowIndex >= col1StartRow &&
        rowIndex < col1StartRow + activityTableRowCount) {
      return (
        minRow: col1StartRow,
        maxRow: col1StartRow + activityTableRowCount - 1,
        isSingleLine: false,
      );
    }
    if (rowIndex >= col2StartRow &&
        rowIndex < col2StartRow + activityTableRowCount) {
      return (
        minRow: col2StartRow,
        maxRow: col2StartRow + activityTableRowCount - 1,
        isSingleLine: false,
      );
    }
    if (rowIndex >= col3StartRow &&
        rowIndex < col3StartRow + activityTableRowCount) {
      return (
        minRow: col3StartRow,
        maxRow: col3StartRow + activityTableRowCount - 1,
        isSingleLine: false,
      );
    }
    if (rowIndex >= generalCommentStartRow &&
        rowIndex < generalCommentStartRow + generalCommentLineCount) {
      return (
        minRow: generalCommentStartRow,
        maxRow: generalCommentStartRow + generalCommentLineCount - 1,
        isSingleLine: false,
      );
    }
    return (
      minRow: rowIndex,
      maxRow: rowIndex,
      isSingleLine: true,
    );
  }

  /// Tính chiều ngang vùng viết tối đa cho dòng `rowIndex` trên biểu mẫu Sổ dự giờ
  /// (Hỗ trợ tự động xuống dòng chuẩn xác trong từng cột của Bảng 3 cột và mục Nhận xét chung)
  static double getMaxTextWidthForRow(
    int rowIndex, {
    required double paperWidth,
  }) {
    final double hPad = getResponsiveHorizontalPadding(paperWidth);
    final double contentWidth = paperWidth - (hPad * 2);

    // Bảng 3 cột (Cột 1: 35%, Cột 2: 33%, Cột 3: 32%)
    if (rowIndex >= col1StartRow &&
        rowIndex < col1StartRow + activityTableRowCount) {
      return (contentWidth * 0.35 - 14.0).clamp(80.0, contentWidth);
    }
    if (rowIndex >= col2StartRow &&
        rowIndex < col2StartRow + activityTableRowCount) {
      return (contentWidth * 0.33 - 14.0).clamp(80.0, contentWidth);
    }
    if (rowIndex >= col3StartRow &&
        rowIndex < col3StartRow + activityTableRowCount) {
      return (contentWidth * 0.32 - 14.0).clamp(80.0, contentWidth);
    }

    // Mục Nhận xét chung (5 dòng toàn chiều ngang)
    return (contentWidth - 14.0).clamp(120.0, contentWidth);
  }

  /// Lấy tên hiển thị thân thiện của ô/dòng đang chọn để hiện trên thanh trạng thái Bàn phím / Viết bút
  static String getFieldDisplayName(int rowIndex) {
    if (rowIndex == rowTeacherName) return 'Họ, tên người dạy';
    if (rowIndex == rowClassName) return 'Lớp';
    if (rowIndex == rowSchoolName) return 'Trường';
    if (rowIndex == rowLessonTitle) return 'Tên bài dạy';
    if (rowIndex == rowSubjectName) return 'Môn';

    if (rowIndex >= col1StartRow &&
        rowIndex < col1StartRow + activityTableRowCount) {
      return 'Nội dung hoạt động - Dòng ${rowIndex - col1StartRow + 1}';
    }
    if (rowIndex >= col2StartRow &&
        rowIndex < col2StartRow + activityTableRowCount) {
      return 'Biểu hiện của HS - Dòng ${rowIndex - col2StartRow + 1}';
    }
    if (rowIndex >= col3StartRow &&
        rowIndex < col3StartRow + activityTableRowCount) {
      return 'Nguyên nhân & Biện pháp - Dòng ${rowIndex - col3StartRow + 1}';
    }
    if (rowIndex >= generalCommentStartRow &&
        rowIndex < generalCommentStartRow + generalCommentLineCount) {
      return 'Nhận xét chung - Dòng ${rowIndex - generalCommentStartRow + 1}';
    }
    if (isScoreRow(rowIndex)) {
      final int idx = rowIndex - scoreStartRow;
      return 'Điểm tiêu chí ${criteriaList[idx].code}';
    }
    if (rowIndex == rowEvaluatedRating) return 'Xếp loại tiết dạy';
    if (rowIndex == rowSignDay) return 'Ngày dự giờ';
    if (rowIndex == rowSignMonth) return 'Tháng dự giờ';
    if (rowIndex == rowSignYear) return 'Năm dự giờ';
    if (rowIndex == rowObserverName) return 'Họ tên người dự giờ';
    return 'Dòng ${rowIndex + 1}';
  }

  /// Chuyển chuỗi điểm nhập vào (hỗ trợ cả dấu phẩy `1,5` lẫn dấu chấm `1.5`) sang số thực
  static double? parseScoreString(String rawText) {
    final String cleaned = rawText.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Định dạng số điểm sang kiểu tiếng Việt (ví dụ: `18,0`, `1,5`, `0,75`)
  static String formatScoreVi(double score) {
    final double rounded = (score * 100).roundToDouble() / 100.0;
    if ((rounded * 10) % 1 == 0) {
      return rounded.toStringAsFixed(1).replaceAll('.', ',');
    }
    return rounded.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Tính tổng điểm và tự động xét loại tiết dạy dựa trên bảng điểm 12 tiêu chí:
  /// - Loại Giỏi: Tổng điểm từ 18,0 đến 20,0. Tiêu chí 2.1 -> 3.4 >= 1,5. Các tiêu chí còn lại >= 1/2 điểm tối đa (0,5).
  /// - Loại Khá: Tổng điểm từ 13,5 đến dưới 18,0. Tiêu chí 2.1 -> 3.4 >= 1,5. Các tiêu chí còn lại >= 1/2 điểm tối đa (0,5).
  /// - Loại Trung bình: Tổng điểm từ 10,0 đến dưới 13,5 (hoặc >= 13,5 nhưng chưa đủ điều kiện phụ của Khá/Giỏi, không có điểm 0).
  /// - Loại Chưa đạt: Tổng điểm dưới 10,0 hoặc có bất cứ tiêu chí nào 0 điểm.
  static ({
    double totalScore,
    int enteredCount,
    String? suggestedRating,
  }) evaluateScores(String Function(int rowIndex) getRowCleanText) {
    double total = 0.0;
    int enteredCount = 0;
    bool hasZeroScore = false;
    bool group2And3AllAtLeast15 = true;
    bool group1AllAtLeastHalf = true;

    for (final ObservationCriterionSpec spec in criteriaList) {
      final double? parsed =
          parseScoreString(getRowCleanText(spec.scoreRowIndex));
      if (parsed == null) {
        group2And3AllAtLeast15 = false;
        group1AllAtLeastHalf = false;
        continue;
      }

      enteredCount += 1;
      final double clampedScore = parsed.clamp(0.0, spec.maxScore);
      total += clampedScore;

      if (clampedScore <= 0.0001) {
        hasZeroScore = true;
      }
      if (spec.groupIndex == 1) {
        if (clampedScore + 0.0001 < (spec.maxScore * 0.5)) {
          group1AllAtLeastHalf = false;
        }
      } else {
        if (clampedScore + 0.0001 < 1.5) {
          group2And3AllAtLeast15 = false;
        }
      }
    }

    if (enteredCount == 0) {
      return (
        totalScore: 0.0,
        enteredCount: 0,
        suggestedRating: null,
      );
    }

    // Xét loại tự động theo đúng quy định ở Trang 3 của biểu mẫu
    String rating;
    if (hasZeroScore || (enteredCount == scoreRowCount && total < 10.0)) {
      rating = 'Chưa đạt';
    } else if (total >= 18.0 &&
        enteredCount == scoreRowCount &&
        group2And3AllAtLeast15 &&
        group1AllAtLeastHalf) {
      rating = 'Giỏi';
    } else if (total >= 13.5 &&
        enteredCount == scoreRowCount &&
        group2And3AllAtLeast15 &&
        group1AllAtLeastHalf) {
      rating = 'Khá';
    } else if (total >= 10.0) {
      rating = 'Trung bình';
    } else {
      rating = 'Chưa đạt';
    }

    return (
      totalScore: total,
      enteredCount: enteredCount,
      suggestedRating: rating,
    );
  }
}

// ===========================================================================
// BỘ VẼ ĐƯỜNG CHẤM NGANG (`......`) CHO CÁC TRƯỜNG THÔNG TIN & NHẬN XÉT CHUNG
// ===========================================================================
class ObservationDottedUnderlinePainter extends CustomPainter {
  final Color color;
  final double bottomOffset;

  const ObservationDottedUnderlinePainter({
    required this.color,
    this.bottomOffset = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final double y = (size.height - bottomOffset).clamp(0.0, size.height);
    const double dotLength = 2.0;
    const double gapLength = 3.5;
    double startX = 0.0;

    while (startX < size.width) {
      final double endX = (startX + dotLength).clamp(0.0, size.width);
      canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
      startX += dotLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant ObservationDottedUnderlinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.bottomOffset != bottomOffset;
  }
}

// ===========================================================================
// BỘ VẼ ĐƯỜNG KẺ NGANG NÉT ĐỨT (`- - - -`) CHO BẢNG GHI CHÉP 3 CỘT Ở TRANG 1
// ===========================================================================
class ObservationDashedCellBottomPainter extends CustomPainter {
  final Color color;

  const ObservationDashedCellBottomPainter({
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    final double y = size.height - 0.6;
    const double dashWidth = 5.0;
    const double dashSpace = 4.0;
    double startX = 2.0;

    while (startX < size.width - 2.0) {
      final double endX = (startX + dashWidth).clamp(0.0, size.width - 2.0);
      canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant ObservationDashedCellBottomPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

// ===========================================================================
// WIDGET HIỂN THỊ TRỌN VẸN 3 TRANG "PHIẾU ĐÁNH GIÁ TIẾT DẠY GIÁO VIÊN CẤP TIỂU HỌC"
// ===========================================================================
class PrimarySchoolEvaluationFormWidget extends StatelessWidget {
  final double paperWidth;
  final double rowHeight;
  final TextStyle bodyTextStyle;
  final ObservationInteractiveFieldBuilder buildInteractiveField;
  final String Function(int rowIndex) getRowCleanText;
  final VoidCallback onApplySuggestedRating;
  final GlobalKey? page1ContentKey;
  final GlobalKey? page2ContentKey;
  final GlobalKey? page3ContentKey;
  final GlobalKey? signatureBoxKey;

  const PrimarySchoolEvaluationFormWidget({
    super.key,
    required this.paperWidth,
    required this.rowHeight,
    required this.bodyTextStyle,
    required this.buildInteractiveField,
    required this.getRowCleanText,
    required this.onApplySuggestedRating,
    this.page1ContentKey,
    this.page2ContentKey,
    this.page3ContentKey,
    this.signatureBoxKey,
  });

  @override
  Widget build(BuildContext context) {
    final double pageHorizontalPadding =
        (paperWidth * 0.032).clamp(16.0, 32.0);
    final double innerWidth = paperWidth - (pageHorizontalPadding * 2);

    final double baseFontSize = (rowHeight * 0.39).clamp(13.5, 18.0);
    final double titleFontSize = (baseFontSize * 1.18).clamp(15.5, 21.0);
    final double smallFontSize = (baseFontSize * 0.92).clamp(12.5, 16.5);

    final TextStyle labelStyle = bodyTextStyle.copyWith(
      fontSize: baseFontSize,
      fontWeight: FontWeight.w500,
      color: AppColors.basicBlack,
    );
    final TextStyle boldStyle = labelStyle.copyWith(
      fontWeight: FontWeight.w700,
    );
    final TextStyle italicStyle = labelStyle.copyWith(
      fontStyle: FontStyle.italic,
    );
    final TextStyle inputTextStyle = bodyTextStyle.copyWith(
      fontSize: baseFontSize,
      fontWeight: FontWeight.w600,
      color: AppColors.primaryBlue,
    );

    final scoreEval =
        PrimarySchoolEvaluationTemplate.evaluateScores(getRowCleanText);

    return Container(
      width: paperWidth,
      color: AppColors.basicWhite,
      padding: EdgeInsets.symmetric(
        horizontal: pageHorizontalPadding,
        vertical: 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // =================================================================
          // TRANG 1: QUỐC HIỆU, THÔNG TIN CHUNG & BẢNG DỰ GIỜ 3 CỘT
          // =================================================================
          _buildPageBadge(
            context: context,
            pageLabel: 'Trang 1 / 3 — Ghi chép tiến trình tiết dạy',
          ),
          const SizedBox(height: 12),
          Column(
            key: page1ContentKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPage1HeaderAndInfo(
                innerWidth: innerWidth,
                labelStyle: labelStyle,
                boldStyle: boldStyle,
                inputTextStyle: inputTextStyle,
                titleFontSize: titleFontSize,
                smallFontSize: smallFontSize,
              ),
              const SizedBox(height: 14),
              _buildPage1ThreeColumnTable(
                innerWidth: innerWidth,
                boldStyle: boldStyle,
                inputTextStyle: inputTextStyle,
              ),
            ],
          ),

          const SizedBox(height: 32),
          _buildPageSeparator(),
          const SizedBox(height: 20),

          // =================================================================
          // TRANG 2: NHẬN XÉT CHUNG & BẢNG THANG ĐIỂM 12 TIÊU CHÍ (20 ĐIỂM)
          // =================================================================
          _buildPageBadge(
            context: context,
            pageLabel: 'Trang 2 / 3 — Nhận xét chung & Thang điểm tiêu chí',
          ),
          const SizedBox(height: 12),
          Column(
            key: page2ContentKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPage2GeneralComments(
                innerWidth: innerWidth,
                boldStyle: boldStyle,
                inputTextStyle: inputTextStyle,
              ),
              const SizedBox(height: 18),
              _buildPage2EvaluationTable(
                innerWidth: innerWidth,
                labelStyle: labelStyle,
                boldStyle: boldStyle,
                inputTextStyle: inputTextStyle,
                smallFontSize: smallFontSize,
                totalScore: scoreEval.totalScore,
                enteredScoreCount: scoreEval.enteredCount,
              ),
            ],
          ),

          const SizedBox(height: 32),
          _buildPageSeparator(),
          const SizedBox(height: 20),

          // =================================================================
          // TRANG 3: QUY ĐỊNH XẾP LOẠI, ĐÁNH GIÁ TIẾT DẠY & CHỮ KÝ NGƯỜI DỰ GIỜ
          // =================================================================
          _buildPageBadge(
            context: context,
            pageLabel: 'Trang 3 / 3 — Xếp loại tiết dạy & Ký tên',
          ),
          const SizedBox(height: 14),
          Container(
            key: page3ContentKey,
            child: _buildPage3RatingAndSignature(
              innerWidth: innerWidth,
              labelStyle: labelStyle,
              boldStyle: boldStyle,
              italicStyle: italicStyle,
              inputTextStyle: inputTextStyle,
              suggestedRating: scoreEval.suggestedRating,
            ),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  /// Nhãn đánh dấu số trang của biểu mẫu (Trang 1/3, Trang 2/3, Trang 3/3)
  Widget _buildPageBadge({
    required BuildContext context,
    required String pageLabel,
  }) {
    final double badgeFont = AppTheme.getResponsiveFontSize(context, 12);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          pageLabel,
          style: TextStyle(
            color: AppColors.primaryBlue,
            fontSize: badgeFont,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// Đường phân cách giữa các trang của biểu mẫu
  Widget _buildPageSeparator() {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: AppColors.primaryBlue.withValues(alpha: 0.35),
            thickness: 1.5,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(
            Icons.description_outlined,
            size: 18,
            color: AppColors.primaryBlue.withValues(alpha: 0.6),
          ),
        ),
        Expanded(
          child: Divider(
            color: AppColors.primaryBlue.withValues(alpha: 0.35),
            thickness: 1.5,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TRANG 1 - PHẦN 1: QUỐC HIỆU, TIÊU ĐỀ & CÁC TRƯỜNG THÔNG TIN HÀNH CHÍNH
  // ===========================================================================
  Widget _buildPage1HeaderAndInfo({
    required double innerWidth,
    required TextStyle labelStyle,
    required TextStyle boldStyle,
    required TextStyle inputTextStyle,
    required double titleFontSize,
    required double smallFontSize,
  }) {
    final double fieldHeight = rowHeight * 0.92;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hàng Quốc hiệu & Tên trường (2 cột chuẩn văn bản hành chính)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cột trái: TRƯỜNG TH NGUYỄN BÁ NGỌC
            Expanded(
              flex: 44,
              child: Column(
                children: [
                  Text(
                    'TRƯỜNG TH NGUYỄN BÁ NGỌC',
                    textAlign: TextAlign.center,
                    style: boldStyle.copyWith(fontSize: smallFontSize),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: (innerWidth * 0.18).clamp(80.0, 150.0),
                    height: 1.2,
                    color: AppColors.basicBlack,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Cột phải: CỘNG HOÀ XÃ HỘI CHỦ NGHĨA VIỆT NAM / Độc lập – Tự do – Hạnh phúc
            Expanded(
              flex: 56,
              child: Column(
                children: [
                  Text(
                    'CỘNG HOÀ XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                    textAlign: TextAlign.center,
                    style: boldStyle.copyWith(fontSize: smallFontSize),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Độc lập – Tự do – Hạnh phúc',
                    textAlign: TextAlign.center,
                    style: boldStyle.copyWith(fontSize: smallFontSize),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: (innerWidth * 0.24).clamp(110.0, 190.0),
                    height: 1.2,
                    color: AppColors.basicBlack,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Tiêu đề chính: PHIẾU ĐÁNH GIÁ TIẾT DẠY GIÁO VIÊN CẤP TIỂU HỌC
        Text(
          'PHIẾU ĐÁNH GIÁ TIẾT DẠY GIÁO VIÊN CẤP TIỂU HỌC',
          textAlign: TextAlign.center,
          style: boldStyle.copyWith(
            fontSize: titleFontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),

        // Dòng thông tin 1: Họ, tên người dạy: ............ Lớp ...... Trường ............
        LayoutBuilder(
          builder: (context, constraints) {
            final double totalW = constraints.maxWidth;
            final double teacherSectionW = totalW * 0.50;
            final double classSectionW = totalW * 0.18;
            final double schoolSectionW =
                totalW - teacherSectionW - classSectionW;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildLabeledDottedField(
                  sectionWidth: teacherSectionW,
                  height: fieldHeight,
                  label: 'Họ, tên người dạy: ',
                  labelStyle: labelStyle,
                  inputStyle: inputTextStyle,
                  rowIndex: PrimarySchoolEvaluationTemplate.rowTeacherName,
                  hintText: 'Nhập họ tên...',
                ),
                _buildLabeledDottedField(
                  sectionWidth: classSectionW,
                  height: fieldHeight,
                  label: ' Lớp: ',
                  labelStyle: labelStyle,
                  inputStyle: inputTextStyle,
                  rowIndex: PrimarySchoolEvaluationTemplate.rowClassName,
                  hintText: '...',
                ),
                _buildLabeledDottedField(
                  sectionWidth: schoolSectionW,
                  height: fieldHeight,
                  label: ' Trường: ',
                  labelStyle: labelStyle,
                  inputStyle: inputTextStyle,
                  rowIndex: PrimarySchoolEvaluationTemplate.rowSchoolName,
                  hintText: 'Nhập trường...',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),

        // Dòng thông tin 2: Tên bài dạy: ............................ Môn: ...............
        LayoutBuilder(
          builder: (context, constraints) {
            final double totalW = constraints.maxWidth;
            final double lessonSectionW = totalW * 0.66;
            final double subjectSectionW = totalW - lessonSectionW;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildLabeledDottedField(
                  sectionWidth: lessonSectionW,
                  height: fieldHeight,
                  label: 'Tên bài dạy: ',
                  labelStyle: labelStyle,
                  inputStyle: inputTextStyle,
                  rowIndex: PrimarySchoolEvaluationTemplate.rowLessonTitle,
                  hintText: 'Nhập tên bài dạy...',
                ),
                _buildLabeledDottedField(
                  sectionWidth: subjectSectionW,
                  height: fieldHeight,
                  label: ' Môn: ',
                  labelStyle: labelStyle,
                  inputStyle: inputTextStyle,
                  rowIndex: PrimarySchoolEvaluationTemplate.rowSubjectName,
                  hintText: 'Nhập môn...',
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Dựng một cụm [Nhãn văn bản + Ô nhập liệu có đường chấm bên dưới]
  Widget _buildLabeledDottedField({
    required double sectionWidth,
    required double height,
    required String label,
    required TextStyle labelStyle,
    required TextStyle inputStyle,
    required int rowIndex,
    String? hintText,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    final double labelWidth = tp.width + 2.0;
    final double fieldWidth =
        (sectionWidth - labelWidth).clamp(36.0, sectionWidth);

    return SizedBox(
      width: sectionWidth,
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: height * 0.15),
            child: Text(label, style: labelStyle),
          ),
          Expanded(
            child: CustomPaint(
              painter: ObservationDottedUnderlinePainter(
                color: AppColors.basicBlack.withValues(alpha: 0.65),
                bottomOffset: height * 0.14,
              ),
              child: buildInteractiveField(
                rowIndex: rowIndex,
                width: fieldWidth,
                height: height,
                textStyle: inputStyle,
                horizontalPadding: 4.0,
                hintText: hintText,
                bottomContentPadding: height * 0.14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TRANG 1 - PHẦN 2: BẢNG GHI CHÉP DỰ GIỜ 3 CỘT (28 DÒNG KẺ NÉT ĐỨT)
  // ===========================================================================
  Widget _buildPage1ThreeColumnTable({
    required double innerWidth,
    required TextStyle boldStyle,
    required TextStyle inputTextStyle,
  }) {
    final double colWidth = (innerWidth - 4.0) / 3.0;
    final double tableRowH = rowHeight * 0.94;
    final Color dashLineColor = AppColors.primaryBlue.withValues(alpha: 0.6);

    return Container(
      width: innerWidth,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.basicBlack, width: 1.2),
      ),
      child: Column(
        children: [
          // Hàng tiêu đề của bảng 3 cột
          Container(
            decoration: const BoxDecoration(
              color: AppColors.basicWhite,
              border: Border(
                bottom: BorderSide(color: AppColors.basicBlack, width: 1.2),
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: AppColors.basicBlack,
                            width: 1.2,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Nội dung hoạt động',
                        textAlign: TextAlign.center,
                        style: boldStyle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: AppColors.basicBlack,
                            width: 1.2,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Biểu hiện của học sinh',
                        textAlign: TextAlign.center,
                        style: boldStyle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Nguyên nhân - Biện pháp',
                        textAlign: TextAlign.center,
                        style: boldStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 28 dòng kẻ ngang nét đứt bên trong bảng 3 cột
          ...List<Widget>.generate(
            PrimarySchoolEvaluationTemplate.activityTableRowCount,
            (int r) {
              final bool isLastRow = r ==
                  PrimarySchoolEvaluationTemplate.activityTableRowCount - 1;
              final int col1RowIdx =
                  PrimarySchoolEvaluationTemplate.col1StartRow + r;
              final int col2RowIdx =
                  PrimarySchoolEvaluationTemplate.col2StartRow + r;
              final int col3RowIdx =
                  PrimarySchoolEvaluationTemplate.col3StartRow + r;

              return SizedBox(
                height: tableRowH,
                child: Row(
                  children: [
                    // Ô Cột 1: Nội dung hoạt động
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: AppColors.basicBlack,
                              width: 1.2,
                            ),
                          ),
                        ),
                        child: CustomPaint(
                          painter: isLastRow
                              ? null
                              : ObservationDashedCellBottomPainter(
                                  color: dashLineColor,
                                ),
                          child: buildInteractiveField(
                            rowIndex: col1RowIdx,
                            width: colWidth,
                            height: tableRowH,
                            textStyle: inputTextStyle,
                            horizontalPadding: 6.0,
                            hintText:
                                r == 0 ? 'Chạm để ghi hoạt động...' : null,
                            bottomContentPadding: tableRowH * 0.14,
                          ),
                        ),
                      ),
                    ),

                    // Ô Cột 2: Biểu hiện của học sinh
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: AppColors.basicBlack,
                              width: 1.2,
                            ),
                          ),
                        ),
                        child: CustomPaint(
                          painter: isLastRow
                              ? null
                              : ObservationDashedCellBottomPainter(
                                  color: dashLineColor,
                                ),
                          child: buildInteractiveField(
                            rowIndex: col2RowIdx,
                            width: colWidth,
                            height: tableRowH,
                            textStyle: inputTextStyle,
                            horizontalPadding: 6.0,
                            hintText:
                                r == 0 ? 'Chạm để ghi biểu hiện...' : null,
                            bottomContentPadding: tableRowH * 0.14,
                          ),
                        ),
                      ),
                    ),

                    // Ô Cột 3: Nguyên nhân - Biện pháp
                    Expanded(
                      child: CustomPaint(
                        painter: isLastRow
                            ? null
                            : ObservationDashedCellBottomPainter(
                                color: dashLineColor,
                              ),
                        child: buildInteractiveField(
                          rowIndex: col3RowIdx,
                          width: colWidth,
                          height: tableRowH,
                          textStyle: inputTextStyle,
                          horizontalPadding: 6.0,
                          hintText: r == 0
                              ? 'Chạm để ghi nguyên nhân/biện pháp...'
                              : null,
                          bottomContentPadding: tableRowH * 0.14,
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
    );
  }

  // ===========================================================================
  // TRANG 2 - PHẦN 1: NHẬN XÉT, ĐÁNH GIÁ CHUNG (5 DÒNG CHẤM)
  // ===========================================================================
  Widget _buildPage2GeneralComments({
    required double innerWidth,
    required TextStyle boldStyle,
    required TextStyle inputTextStyle,
  }) {
    final double commentRowH = rowHeight * 0.94;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NHẬN XÉT, ĐÁNH GIÁ CHUNG:',
          style: boldStyle,
        ),
        const SizedBox(height: 4),
        ...List<Widget>.generate(
          PrimarySchoolEvaluationTemplate.generalCommentLineCount,
          (int idx) {
            final int rowIdx =
                PrimarySchoolEvaluationTemplate.generalCommentStartRow + idx;
            return SizedBox(
              width: innerWidth,
              height: commentRowH,
              child: CustomPaint(
                painter: ObservationDottedUnderlinePainter(
                  color: AppColors.basicBlack.withValues(alpha: 0.65),
                  bottomOffset: commentRowH * 0.14,
                ),
                child: buildInteractiveField(
                  rowIndex: rowIdx,
                  width: innerWidth,
                  height: commentRowH,
                  textStyle: inputTextStyle,
                  horizontalPadding: 4.0,
                  hintText: idx == 0
                      ? 'Chạm vào dòng chấm để nhập nhận xét, đánh giá chung...'
                      : null,
                  bottomContentPadding: commentRowH * 0.14,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ===========================================================================
  // TRANG 2 - PHẦN 2: BẢNG THANG ĐIỂM, TIÊU CHUẨN, TIÊU CHÍ ĐÁNH GIÁ (12 TIÊU CHÍ)
  // ===========================================================================
  Widget _buildPage2EvaluationTable({
    required double innerWidth,
    required TextStyle labelStyle,
    required TextStyle boldStyle,
    required TextStyle inputTextStyle,
    required double smallFontSize,
    required double totalScore,
    required int enteredScoreCount,
  }) {
    final TextStyle tableTextStyle =
        labelStyle.copyWith(fontSize: smallFontSize, height: 1.32);
    final TextStyle tableBoldStyle =
        boldStyle.copyWith(fontSize: smallFontSize, height: 1.32);

    // Nhóm các tiêu chí theo groupIndex (1, 2, 3)
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GỢI Ý THANG ĐIỂM, TIÊU CHUẨN, TIÊU CHÍ ĐÁNH GIÁ TIẾT DẠY:',
          style: boldStyle,
        ),
        const SizedBox(height: 8),
        Container(
          width: innerWidth,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.basicBlack, width: 1.2),
          ),
          child: Column(
            children: [
              // Hàng tiêu đề của bảng thang điểm
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.basicWhite,
                  border: Border(
                    bottom: BorderSide(color: AppColors.basicBlack, width: 1.2),
                  ),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Cột Nội dung (Tiêu chuẩn) - rộng bằng đúng Cột Nhóm (flex: 18) như biểu mẫu gốc
                      Expanded(
                        flex: 18,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: AppColors.basicBlack,
                                width: 1.2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Nội dung\n(Tiêu chuẩn)',
                            textAlign: TextAlign.center,
                            style: tableBoldStyle,
                          ),
                        ),
                      ),
                      // Cột Tiêu chí - gộp Cột Mã (7) + Cột Nội dung Tiêu chí (51) = 58 như biểu mẫu gốc
                      Expanded(
                        flex: 58,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: AppColors.basicBlack,
                                width: 1.2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Tiêu chí',
                            textAlign: TextAlign.center,
                            style: tableBoldStyle,
                          ),
                        ),
                      ),
                      // Cột Điểm tối đa (flex: 12)
                      Expanded(
                        flex: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: AppColors.basicBlack,
                                width: 1.2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Điểm\ntối đa',
                            textAlign: TextAlign.center,
                            style: tableBoldStyle,
                          ),
                        ),
                      ),
                      // Cột Điểm đánh giá (flex: 12)
                      Expanded(
                        flex: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Điểm\nđánh giá',
                            textAlign: TextAlign.center,
                            style: tableBoldStyle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Nhóm 1: 1. Yêu cầu cần đạt (4,0 điểm)
              _buildCriterionGroupBlock(
                groupSpecs: group1,
                innerWidth: innerWidth,
                tableTextStyle: tableTextStyle,
                tableBoldStyle: tableBoldStyle,
                inputTextStyle: inputTextStyle,
              ),

              // Nhóm 2: 2. Hoạt động dạy học của giáo viên (8,0 điểm)
              _buildCriterionGroupBlock(
                groupSpecs: group2,
                innerWidth: innerWidth,
                tableTextStyle: tableTextStyle,
                tableBoldStyle: tableBoldStyle,
                inputTextStyle: inputTextStyle,
              ),

              // Nhóm 3: 3. Hoạt động học của học sinh (8,0 điểm)
              _buildCriterionGroupBlock(
                groupSpecs: group3,
                innerWidth: innerWidth,
                tableTextStyle: tableTextStyle,
                tableBoldStyle: tableBoldStyle,
                inputTextStyle: inputTextStyle,
              ),

              // Hàng cuối: Tổng điểm (20,0)
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.basicWhite,
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 76,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: AppColors.basicBlack,
                                width: 1.2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Tổng điểm',
                            textAlign: TextAlign.center,
                            style: tableBoldStyle,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: AppColors.basicBlack,
                                width: 1.2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '20,0',
                            textAlign: TextAlign.center,
                            style: tableBoldStyle,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          color: AppColors.primaryBlue.withValues(alpha: 0.08),
                          alignment: Alignment.center,
                          child: Text(
                            enteredScoreCount > 0
                                ? PrimarySchoolEvaluationTemplate.formatScoreVi(
                                    totalScore,
                                  )
                                : '...',
                            textAlign: TextAlign.center,
                            style: tableBoldStyle.copyWith(
                              color: AppColors.primaryBlue,
                              fontSize: smallFontSize * 1.06,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Dựng 1 khối nhóm tiêu chuẩn (Cột trái gộp dọc 4 tiêu chí, cột phải chứa 4 hàng tiêu chí)
  Widget _buildCriterionGroupBlock({
    required List<ObservationCriterionSpec> groupSpecs,
    required double innerWidth,
    required TextStyle tableTextStyle,
    required TextStyle tableBoldStyle,
    required TextStyle inputTextStyle,
  }) {
    final String groupTitle = groupSpecs.first.groupTitle;
    final double scoreColWidth = (innerWidth - 2.4) * 0.12;
    final double scoreFieldHeight = rowHeight * 1.05;

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.basicBlack, width: 1.2),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cột trái gộp dọc: Tên tiêu chuẩn (flex: 18)
            Expanded(
              flex: 18,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: AppColors.basicBlack, width: 1.2),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  groupTitle,
                  textAlign: TextAlign.center,
                  style: tableBoldStyle,
                ),
              ),
            ),

            // Cột phải (flex: 82): Danh sách 4 tiêu chí của nhóm
            Expanded(
              flex: 82,
              child: Column(
                children: List<Widget>.generate(groupSpecs.length, (int idx) {
                  final ObservationCriterionSpec spec = groupSpecs[idx];
                  final bool isLastInGroup = idx == groupSpecs.length - 1;

                  return Container(
                    decoration: BoxDecoration(
                      border: isLastInGroup
                          ? null
                          : const Border(
                              bottom: BorderSide(
                                color: AppColors.basicBlack,
                                width: 1.0,
                              ),
                            ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Cột Mã tiêu chí (1.1, 1.2...) - flex: 7
                          Expanded(
                            flex: 7,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: AppColors.basicBlack,
                                    width: 1.2,
                                  ),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                spec.code,
                                textAlign: TextAlign.center,
                                style: tableTextStyle,
                              ),
                            ),
                          ),

                          // Cột Nội dung Tiêu chí - flex: 51
                          Expanded(
                            flex: 51,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: AppColors.basicBlack,
                                    width: 1.2,
                                  ),
                                ),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                spec.description,
                                style: tableTextStyle,
                              ),
                            ),
                          ),

                          // Cột Điểm tối đa - flex: 12
                          Expanded(
                            flex: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                              decoration: const BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: AppColors.basicBlack,
                                    width: 1.2,
                                  ),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                spec.maxScoreLabel,
                                textAlign: TextAlign.center,
                                style: tableBoldStyle,
                              ),
                            ),
                          ),

                          // Cột Điểm đánh giá (Ô nhập điểm tương tác) - flex: 12
                          // Lưu ý: Không dùng LayoutBuilder bên trong IntrinsicHeight vì Flutter cấm tính Intrinsic Dimensions trên LayoutBuilder
                          Expanded(
                            flex: 12,
                            child: Container(
                              color:
                                  AppColors.basicWhite.withValues(alpha: 0.65),
                              alignment: Alignment.center,
                              child: buildInteractiveField(
                                rowIndex: spec.scoreRowIndex,
                                width: scoreColWidth,
                                height: scoreFieldHeight,
                                textStyle: inputTextStyle.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                                horizontalPadding: 4.0,
                                textAlign: TextAlign.center,
                                hintText: '...',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                bottomContentPadding: scoreFieldHeight * 0.22,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  // ===========================================================================
  // TRANG 3: QUY ĐỊNH ĐIỂM ĐÁNH GIÁ, XẾP LOẠI TIẾT DẠY & CHỮ KÝ NGƯỜI DỰ GIỜ
  // ===========================================================================
  Widget _buildPage3RatingAndSignature({
    required double innerWidth,
    required TextStyle labelStyle,
    required TextStyle boldStyle,
    required TextStyle italicStyle,
    required TextStyle inputTextStyle,
    required String? suggestedRating,
  }) {
    final double fieldHeight = rowHeight * 0.92;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ĐIỂM ĐÁNH GIÁ TIẾT DẠY',
          style: boldStyle,
        ),
        const SizedBox(height: 8),

        // 4 mức xếp loại tiết dạy nguyên bản từ biểu mẫu
        _buildRatingRuleParagraph(
          boldTitle: '1. Loại Giỏi: ',
          bodyText:
              'Tổng điểm từ 18,0 đến 20,0 điểm. Trong đó Tiêu chí 2.1 đến 3.4 đạt từ 1,5 điểm trở lên. Các tiêu chí còn lại không có tiêu chí nào dưới 1/2 điểm tối đa.',
          labelStyle: labelStyle,
          boldStyle: boldStyle,
        ),
        const SizedBox(height: 6),
        _buildRatingRuleParagraph(
          boldTitle: '2. Loại Khá: ',
          bodyText:
              'Tổng điểm từ 13,5 đến dưới 18,0 điểm. Trong đó Tiêu chí 2.1 đến 3.4 đạt từ 1,5 điểm trở lên. Các tiêu chí còn lại không có tiêu chí nào dưới 1/2 điểm tối đa.',
          labelStyle: labelStyle,
          boldStyle: boldStyle,
        ),
        const SizedBox(height: 6),
        _buildRatingRuleParagraph(
          boldTitle: '3. Loại Trung bình: ',
          bodyText: 'Tổng điểm từ 10,0 đến dưới 13,5 điểm.',
          labelStyle: labelStyle,
          boldStyle: boldStyle,
        ),
        const SizedBox(height: 6),
        _buildRatingRuleParagraph(
          boldTitle: '4. Loại Chưa đạt: ',
          bodyText:
              'Tổng điểm dưới 10,0 điểm hoặc có bất cứ tiêu chí nào 0 điểm.',
          labelStyle: labelStyle,
          boldStyle: boldStyle,
        ),

        const SizedBox(height: 16),
        Text(
          'V. ĐÁNH GIÁ TIẾT DẠY:',
          style: boldStyle,
        ),
        const SizedBox(height: 6),

        // Dòng: Tiết dạy đạt loại: ........................................
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _buildLabeledDottedField(
                sectionWidth: innerWidth * 0.72,
                height: fieldHeight,
                label: 'Tiết dạy đạt loại: ',
                labelStyle: labelStyle,
                inputStyle: inputTextStyle.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                rowIndex: PrimarySchoolEvaluationTemplate.rowEvaluatedRating,
                hintText: suggestedRating != null
                    ? 'Gợi ý: $suggestedRating'
                    : 'Nhập xếp loại (Giỏi / Khá / Trung bình / Chưa đạt)...',
              ),
            ),
            if (suggestedRating != null) ...[
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onApplySuggestedRating,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Điền: $suggestedRating',
                    style: TextStyle(
                      color: AppColors.basicWhite,
                      fontSize: labelStyle.fontSize! * 0.86,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 24),

        // Khối ngày tháng năm & Chữ ký Người dự giờ (Căn phải chuẩn biểu mẫu)
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: (innerWidth * 0.56).clamp(260.0, 420.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Dòng: Đức Lập, ngày ... tháng ... năm ...
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: fieldHeight * 0.15),
                        child: Text('Đức Lập, ngày ', style: italicStyle),
                      ),
                      SizedBox(
                        width: 52,
                        height: fieldHeight,
                        child: CustomPaint(
                          painter: ObservationDottedUnderlinePainter(
                            color: AppColors.basicBlack.withValues(alpha: 0.65),
                            bottomOffset: fieldHeight * 0.14,
                          ),
                          child: buildInteractiveField(
                            rowIndex:
                                PrimarySchoolEvaluationTemplate.rowSignDay,
                            width: 52,
                            height: fieldHeight,
                            textStyle: inputTextStyle,
                            horizontalPadding: 2.0,
                            textAlign: TextAlign.center,
                            hintText: '...',
                            keyboardType: TextInputType.number,
                            bottomContentPadding: fieldHeight * 0.14,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: fieldHeight * 0.15),
                        child: Text(' tháng ', style: italicStyle),
                      ),
                      SizedBox(
                        width: 52,
                        height: fieldHeight,
                        child: CustomPaint(
                          painter: ObservationDottedUnderlinePainter(
                            color: AppColors.basicBlack.withValues(alpha: 0.65),
                            bottomOffset: fieldHeight * 0.14,
                          ),
                          child: buildInteractiveField(
                            rowIndex:
                                PrimarySchoolEvaluationTemplate.rowSignMonth,
                            width: 52,
                            height: fieldHeight,
                            textStyle: inputTextStyle,
                            horizontalPadding: 2.0,
                            textAlign: TextAlign.center,
                            hintText: '...',
                            keyboardType: TextInputType.number,
                            bottomContentPadding: fieldHeight * 0.14,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: fieldHeight * 0.15),
                        child: Text(' năm ', style: italicStyle),
                      ),
                      SizedBox(
                        width: 78,
                        height: fieldHeight,
                        child: CustomPaint(
                          painter: ObservationDottedUnderlinePainter(
                            color: AppColors.basicBlack.withValues(alpha: 0.65),
                            bottomOffset: fieldHeight * 0.14,
                          ),
                          child: buildInteractiveField(
                            rowIndex:
                                PrimarySchoolEvaluationTemplate.rowSignYear,
                            width: 78,
                            height: fieldHeight,
                            textStyle: inputTextStyle,
                            horizontalPadding: 2.0,
                            textAlign: TextAlign.center,
                            hintText: '202...',
                            keyboardType: TextInputType.number,
                            bottomContentPadding: fieldHeight * 0.14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Người dự giờ',
                  textAlign: TextAlign.center,
                  style: boldStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  '(Ký, ghi rõ họ tên)',
                  textAlign: TextAlign.center,
                  style: italicStyle,
                ),
                // Giãn khoảng trống rộng rãi để chừa chỗ ký tên trước dòng Họ tên người dự giờ
                SizedBox(
                  key: signatureBoxKey,
                  width: double.infinity,
                  height: (rowHeight * 2.5).clamp(80.0, 110.0),
                ),
                // Dòng nhập họ tên người dự giờ
                SizedBox(
                  width: 256,
                  height: fieldHeight,
                  child: CustomPaint(
                    painter: ObservationDottedUnderlinePainter(
                      color: AppColors.basicBlack.withValues(alpha: 0.65),
                      bottomOffset: fieldHeight * 0.14,
                    ),
                    child: buildInteractiveField(
                      rowIndex: PrimarySchoolEvaluationTemplate.rowObserverName,
                      width: 256,
                      height: fieldHeight,
                      textStyle: inputTextStyle,
                      horizontalPadding: 6.0,
                      textAlign: TextAlign.center,
                      hintText: 'Nhập họ tên người dự giờ...',
                      bottomContentPadding: fieldHeight * 0.14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Dựng một đoạn văn quy định xếp loại (In đậm tiêu đề loại, chữ thường phần mô tả)
  Widget _buildRatingRuleParagraph({
    required String boldTitle,
    required String bodyText,
    required TextStyle labelStyle,
    required TextStyle boldStyle,
  }) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: boldTitle, style: boldStyle),
          TextSpan(text: bodyText, style: labelStyle),
        ],
      ),
    );
  }
}
