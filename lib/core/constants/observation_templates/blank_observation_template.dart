import 'package:flutter/material.dart';
import '../app_colors.dart';
import 'primary_school_evaluation_template.dart';

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
// BIỂU MẪU SỔ DỰ GIỜ TRỐNG MẶC ĐỊNH ĐƯỢC CODE SẴN (BLANK OBSERVATION TEMPLATE)
// Công dụng:
// - Biểu mẫu trống cơ sở cho Sổ dự giờ nằm trong thư mục `observation_templates`.
// - Cung cấp cấu hình kích thước trang, khoảng cách dòng tự co giãn và bộ vẽ
//   nền giấy để render trực tiếp dữ liệu JSON của Sổ dự giờ.
// - Quản lý danh sách toàn bộ các biểu mẫu Sổ dự giờ (`availableTemplates`)
//   để hiển thị dạng danh sách khi người dùng bấm "Tạo sổ dự giờ mới".
// ===========================================================================
class BlankObservationTemplate {
  BlankObservationTemplate._();

  /// Mã định danh lưu trong file JSON của Sổ dự giờ trên Google Drive
  static const String templateId = 'observation_blank_v1';

  /// Tên hiển thị của biểu mẫu trong danh sách chọn biểu mẫu
  static const String displayName = 'Biểu mẫu sổ dự giờ trống (Mặc định)';

  /// Mô tả ngắn gọn của biểu mẫu
  static const String description =
      'Biểu mẫu trống tiêu chuẩn dùng để ghi chép và đánh giá tiết dự giờ';

  /// Số đơn vị chia dòng mặc định của biểu mẫu trống
  static const int unitsPerRow = 4;

  /// Số dòng mặc định tối thiểu trên 1 trang biểu mẫu
  static const int defaultLineCount = 26;

  /// Chiều ngang tối thiểu chuẩn của trang biểu mẫu (đơn vị logic dp)
  static const double minPaperWidth = 540.0;

  /// Danh sách tất cả các biểu mẫu Sổ dự giờ hiện có (dùng để hiển thị dạng danh sách khi tạo file)
  static const List<ObservationTemplateItem> availableTemplates =
      <ObservationTemplateItem>[
    ObservationTemplateItem(
      id: PrimarySchoolEvaluationTemplate.templateId,
      name: PrimarySchoolEvaluationTemplate.displayName,
      description: PrimarySchoolEvaluationTemplate.description,
    ),
    ObservationTemplateItem(
      id: templateId,
      name: displayName,
      description: description,
    ),
  ];

  // ===========================================================================
  // CÁC HÀM MÀU SẮC THEO THEME (APPCOLORS)
  // ===========================================================================

  /// Màu nền trang biểu mẫu theo Theme (#FFFFFF - Màu trắng giống bản gốc biểu mẫu)
  static Color getPaperBackgroundColor() {
    return AppColors.basicWhite;
  }

  /// Màu đường kẻ ngang chính của biểu mẫu theo Theme (#263BAA)
  static Color getHorizontalLineColor() {
    return AppColors.primaryBlue.withValues(alpha: 0.72);
  }

  /// Màu đường kẻ ngang phụ bên trong dòng của biểu mẫu theo Theme (#263BAA)
  static Color getSubHorizontalLineColor() {
    return AppColors.primaryBlue.withValues(alpha: 0.18);
  }

  /// Màu chữ viết trên biểu mẫu theo Theme (#000000)
  static Color getTextColor() {
    return AppColors.basicBlack;
  }

  // ===========================================================================
  // CÁC HÀM TỰ ĐỘNG CO GIÃN KÍCH THƯỚC DÒNG & TRANG BIỂU MẪU
  // ===========================================================================

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

  /// Tính chiều ngang chuẩn của trang biểu mẫu phụ thuộc vào màn hình máy
  static double getResponsivePaperWidth(double viewportWidth) {
    return viewportWidth >= minPaperWidth ? viewportWidth : minPaperWidth;
  }
}

// ===========================================================================
// BỘ VẼ NỀN TRANG BIỂU MẪU SỔ DỰ GIỜ TRỐNG (BLANK OBSERVATION PAPER PAINTER)
// ===========================================================================
class BlankObservationPaperPainter extends CustomPainter {
  final double rowHeight;
  final int totalRows;
  final bool showSubLines;

  const BlankObservationPaperPainter({
    required this.rowHeight,
    required this.totalRows,
    this.showSubLines = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint bgPaint = Paint()
      ..color = BlankObservationTemplate.getPaperBackgroundColor()
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final Paint mainLinePaint = Paint()
      ..color = BlankObservationTemplate.getHorizontalLineColor()
      ..strokeWidth = 1.5
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke;

    final Paint subLinePaint = Paint()
      ..color = BlankObservationTemplate.getSubHorizontalLineColor()
      ..strokeWidth = 1.0
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke;

    final double subStep = rowHeight / BlankObservationTemplate.unitsPerRow;

    for (int row = 0; row < totalRows; row++) {
      final double rowTop = row * rowHeight;
      final double rowBottom = ((row + 1) * rowHeight).roundToDouble();

      if (showSubLines) {
        for (int sub = 1; sub < BlankObservationTemplate.unitsPerRow; sub++) {
          final double subY = (rowTop + (sub * subStep)).roundToDouble();
          if (subY <= size.height) {
            canvas.drawLine(
              Offset(0, subY),
              Offset(size.width, subY),
              subLinePaint,
            );
          }
        }
      }

      if (rowBottom <= size.height) {
        canvas.drawLine(
          Offset(0, rowBottom),
          Offset(size.width, rowBottom),
          mainLinePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BlankObservationPaperPainter oldDelegate) {
    return oldDelegate.rowHeight != rowHeight ||
        oldDelegate.totalRows != totalRows ||
        oldDelegate.showSubLines != showSubLines;
  }
}
