import 'package:flutter/material.dart';
import '../app_colors.dart';

// ===========================================================================
// MẪU ĐỊNH DẠNG VỞ 4 Ô LY (NOTE4X) - TRONG THƯ MỤC NOTE_TEMPLATES
// Công dụng:
// - Định nghĩa thông số khoảng cách dòng dựa trên tỷ lệ chuẩn vở 4 ô ly (4 khoảng đơn vị).
// - Tự động co giãn chiều cao dòng (lineSpacing) đầy đủ theo mọi kích thước màn hình
//   từ điện thoại đến máy tính bảng lớn (Xiaomi Pad 8 11.2 inch).
// - Chỉ vẽ ĐƯỜNG KẺ NGANG (không vẽ đường kẻ dọc) để tạo dòng viết thông thoáng.
// - Toàn bộ hàm màu sắc đều lấy trực tiếp từ bảng màu Theme (AppColors).
// ===========================================================================
class Note4x {
  Note4x._();

  /// Mã định danh lưu trong file JSON trên Google Drive
  static const String templateId = 'note4x';

  /// Tên hiển thị cho người dùng khi chọn loại vở
  static const String displayName = 'Vở 4 ô ly';

  /// Số đơn vị ô ly cấu thành 1 dòng viết của vở 4 ô ly
  static const int oliUnitsPerRow = 4;

  /// Số dòng mặc định tối thiểu trên 1 trang giấy
  static const int defaultLineCount = 28;

  /// Chiều ngang tối thiểu chuẩn của trang giấy vở (đơn vị logic dp).
  /// - Mọi máy tính bảng (dọc >= 540dp & ngang) và điện thoại xoay ngang đều hiển thị trọn chiều ngang màn hình.
  /// - Màn hình điện thoại nhỏ xoay dọc (< 540dp) sẽ bật thêm thanh cuộn trái/phải.
  static const double minPaperWidth = 540.0;

  // ===========================================================================
  // CÁC HÀM MÀU SẮC THEO THEME (APPCOLORS)
  // ===========================================================================

  /// Hàm lấy màu nền trang giấy theo Theme (Màu kem dịu mắt #FFF4D6)
  static Color getPaperBackgroundColor() {
    return AppColors.creamBackground;
  }

  /// Hàm lấy màu đường kẻ ngang chính tạo ra mỗi ô ly lớn (Đậm màu rõ nét theo Theme #263BAA)
  static Color getHorizontalLineColor() {
    return AppColors.primaryBlue.withValues(alpha: 0.72);
  }

  /// Hàm lấy màu đường kẻ ngang phụ bên trong ô (Mờ màu đồng đều theo Theme #263BAA)
  static Color getSubHorizontalLineColor() {
    return AppColors.primaryBlue.withValues(alpha: 0.20);
  }

  /// Hàm lấy màu đường kẻ tiêu đề đầu trang theo màu xanh chủ đạo Theme
  static Color getHeaderDividerColor() {
    return AppColors.primaryBlue.withValues(alpha: 0.65);
  }

  /// Hàm lấy màu chữ viết trên dòng theo màu đen tiêu chuẩn Theme (#000000)
  static Color getTextColor() {
    return AppColors.basicBlack;
  }

  // ===========================================================================
  // CÁC HÀM TỰ ĐỘNG CO GIÃN KHOẢNG CÁCH DÒNG DỰA TRÊN CHUẨN 4 Ô LY
  // ===========================================================================

  /// Tính chiều cao của 1 đơn vị ô ly nhỏ tự động co giãn theo kích thước màn hình
  static double getResponsiveUnitHeight(
    BuildContext context, {
    double? maxWidth,
  }) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double referenceWidth = maxWidth ?? screenSize.width;
    final double shortestSide = screenSize.shortestSide;

    // Làm tròn số nguyên pixel để mọi khoảng chia 4 ô ly đều nhau tuyệt đối, không bị lệch sub-pixel
    final double baseUnit =
        (referenceWidth * 0.0085 + shortestSide * 0.0065).clamp(9.0, 13.0);
    return baseUnit.roundToDouble();
  }

  /// Tính khoảng cách dòng viết (chiều cao 1 dòng ngang = 4 đơn vị ô ly * unitHeight)
  /// Tự động giãn đầy đủ theo màn hình dựa trên chuẩn 4 ô ly
  static double getResponsiveRowHeight(
    BuildContext context, {
    double? maxWidth,
  }) {
    final double unitHeight = getResponsiveUnitHeight(
      context,
      maxWidth: maxWidth,
    );
    return unitHeight * oliUnitsPerRow;
  }

  /// Tính khoảng lề ngang hai bên trang giấy cân đối theo chuẩn trang Word (vừa vặn cả dọc lẫn ngang)
  static double getResponsiveHorizontalPadding(double maxWidth) {
    return (maxWidth * 0.022).clamp(14.0, 22.0);
  }

  /// Tính chiều ngang chuẩn của trang giấy phụ thuộc vào màn hình máy:
  /// - Nếu màn hình đủ to (>= minPaperWidth): hiển thị toàn bộ chiều ngang giấy theo màn hình.
  /// - Nếu màn hình nhỏ (< minPaperWidth): giữ chiều ngang giấy = minPaperWidth để dùng con lăn kéo qua lại.
  static double getResponsivePaperWidth(double viewportWidth) {
    return viewportWidth >= minPaperWidth ? viewportWidth : minPaperWidth;
  }
}

// ===========================================================================
// BỘ VẼ ĐƯỜNG KẺ NGANG CHO MẪU VỞ 4 Ô LY (CHỈ VẼ ĐƯỜNG NGANG, KHÔNG VẼ ĐƯỜNG DỌC)
// Công dụng:
// - Vẽ các dòng kẻ ngang cách đều nhau theo đúng khoảng cách 4 ô ly (rowHeight).
// - Không vẽ bất kỳ đường kẻ dọc nào theo đúng yêu cầu của người dùng.
// ===========================================================================
class Note4xHorizontalPaperPainter extends CustomPainter {
  final double rowHeight;
  final int totalRows;
  final bool showSubLines;

  const Note4xHorizontalPaperPainter({
    required this.rowHeight,
    required this.totalRows,
    this.showSubLines = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Tô nền giấy theo hàm màu Theme
    final Paint bgPaint = Paint()
      ..color = Note4x.getPaperBackgroundColor()
      ..style = PaintingStyle.fill;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 2. Bút vẽ đường kẻ ngang chính tạo mỗi ô ly lớn (Đậm màu, đều nét)
    final Paint mainLinePaint = Paint()
      ..color = Note4x.getHorizontalLineColor()
      ..strokeWidth = 1.5
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke;

    // 3. Bút vẽ đường kẻ ngang phụ bên trong ô (Mờ màu đồng đều 100% giữa các dòng)
    final Paint subLinePaint = Paint()
      ..color = Note4x.getSubHorizontalLineColor()
      ..strokeWidth = 1.0
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke;

    final double subStep = rowHeight / Note4x.oliUnitsPerRow;

    for (int row = 0; row < totalRows; row++) {
      final double rowTop = row * rowHeight;
      final double rowBottom = ((row + 1) * rowHeight).roundToDouble();

      // Vẽ 3 đường ngang phụ mờ đều bên trong mỗi ô 4 ô ly
      if (showSubLines) {
        for (int sub = 1; sub < Note4x.oliUnitsPerRow; sub++) {
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

      // Vẽ đường kẻ ngang chính đậm màu ở đáy mỗi dòng lớn
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
  bool shouldRepaint(covariant Note4xHorizontalPaperPainter oldDelegate) {
    return oldDelegate.rowHeight != rowHeight ||
        oldDelegate.totalRows != totalRows ||
        oldDelegate.showSubLines != showSubLines;
  }
}
