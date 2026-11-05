import 'package:flutter/material.dart';
import 'app_colors.dart';

// ===========================================================================
// MẪU ĐỊNH DẠNG VỞ 4 Ô LY (NOTE4X)
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
  static const String displayName = 'Vở 4 ô ly (note4x)';

  /// Số đơn vị ô ly cấu thành 1 dòng viết của vở 4 ô ly
  static const int oliUnitsPerRow = 4;

  /// Số dòng mặc định tối thiểu trên 1 trang giấy
  static const int defaultLineCount = 28;

  // ===========================================================================
  // CÁC HÀM MÀU SẮC THEO THEME (APPCOLORS)
  // ===========================================================================

  /// Hàm lấy màu nền trang giấy theo Theme (Màu kem dịu mắt #FFF4D6)
  static Color getPaperBackgroundColor() {
    return AppColors.creamBackground;
  }

  /// Hàm lấy màu đường kẻ ngang chính (dòng viết) theo màu xanh chủ đạo Theme (#263BAA)
  static Color getHorizontalLineColor() {
    return AppColors.primaryBlue.withValues(alpha: 0.42);
  }

  /// Hàm lấy màu đường kẻ ngang phụ (chia 4 nhịp ô ly mảnh) theo màu xanh Theme
  static Color getSubHorizontalLineColor() {
    return AppColors.primaryBlue.withValues(alpha: 0.12);
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

    // Tự động co giãn mượt theo cả chiều ngang khung giấy và cạnh ngắn thiết bị
    final double baseUnit =
        (referenceWidth * 0.0085 + shortestSide * 0.0065).clamp(9.2, 13.2);
    return baseUnit;
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

  /// Tính khoảng lề ngang hai bên trang giấy tự động co giãn theo màn hình
  static double getResponsiveHorizontalPadding(double maxWidth) {
    return (maxWidth * 0.045).clamp(16.0, 44.0);
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

    // 2. Bút vẽ đường kẻ ngang chính (dòng để viết) theo màu Theme
    final Paint mainLinePaint = Paint()
      ..color = Note4x.getHorizontalLineColor()
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke;

    // 3. Bút vẽ đường kẻ ngang phụ chia 4 khoảng ô ly mảnh theo màu Theme
    final Paint subLinePaint = Paint()
      ..color = Note4x.getSubHorizontalLineColor()
      ..strokeWidth = 0.65
      ..style = PaintingStyle.stroke;

    final double subStep = rowHeight / Note4x.oliUnitsPerRow;

    for (int row = 0; row < totalRows; row++) {
      final double rowTop = row * rowHeight;
      final double rowBottom = (row + 1) * rowHeight;

      // Vẽ các đường ngang phụ mảnh bên trong 1 dòng 4 ô ly (chỉ vẽ đường ngang)
      if (showSubLines) {
        for (int sub = 1; sub < Note4x.oliUnitsPerRow; sub++) {
          final double subY = rowTop + (sub * subStep);
          if (subY <= size.height) {
            canvas.drawLine(
              Offset(0, subY),
              Offset(size.width, subY),
              subLinePaint,
            );
          }
        }
      }

      // Vẽ đường kẻ ngang chính ở đáy mỗi dòng để viết chữ lên trên
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
