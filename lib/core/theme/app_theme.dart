import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

/// Cấu hình Theme và Font chữ dùng chung toàn ứng dụng
/// (Xanh #263BAA - Kem #FFF4D6 - Trắng #FFFFFF - Đen #000000)
class AppTheme {
  AppTheme._();

  // ===========================================================================
  // HÀM TỰ ĐỘNG CO GIÃN CỠ CHỮ THEO KÍCH THƯỚC MÀN HÌNH (RESPONSIVE FONT SIZE)
  // Công dụng:
  // - Tự động phóng to cỡ chữ khi chạy trên màn hình lớn (Tablet Xiaomi Pad 8)
  //   và thu gọn vừa vặn trên màn hình nhỏ (Điện thoại).
  // - Tính theo cạnh ngắn của màn hình (shortestSide) nên khi xoay ngang hay
  //   xoay dọc máy tính bảng, cỡ chữ vẫn giữ nguyên ổn định, không bị phình to.
  // Cách dùng: AppTheme.getResponsiveFontSize(context, 16)
  // ===========================================================================
  static double getResponsiveFontSize(BuildContext context, double baseFontSize) {
    final double shortestSide = MediaQuery.sizeOf(context).shortestSide;
    // Lấy mốc màn hình chuẩn 400dp, giới hạn tỷ lệ phóng từ 0.95x đến 1.3x
    final double scaleFactor = (shortestSide / 400.0).clamp(0.95, 1.3);
    return baseFontSize * scaleFactor;
  }

  /// Theme mặc định kết hợp 4 màu chủ đạo và bộ Font kiểu Google Drive (Be Vietnam Pro)
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      primary: AppColors.primaryBlue,
      onPrimary: AppColors.basicWhite,
      secondary: AppColors.creamBackground,
      onSecondary: AppColors.primaryBlue,
      surface: AppColors.basicWhite,
      surfaceContainerHighest: AppColors.creamBackground,
      onSurface: AppColors.basicBlack, // Màu chữ đen tiêu chuẩn trên nền sáng
      error: AppColors.dangerRed, // Màu đỏ cảnh báo / xóa / làm sạch trong Theme
      onError: AppColors.basicWhite,
      brightness: Brightness.light,
    );

    // Áp dụng bộ font Be Vietnam Pro (dáng chữ tròn hiện đại giống Google Sans trên Google Drive, hỗ trợ tiếng Việt chuẩn)
    final baseTextTheme = GoogleFonts.beVietnamProTextTheme(
      const TextTheme(
        bodyLarge: TextStyle(color: AppColors.basicBlack),
        bodyMedium: TextStyle(color: AppColors.basicBlack),
        titleMedium: TextStyle(color: AppColors.basicBlack),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.creamBackground,
      textTheme: baseTextTheme,
      fontFamily: GoogleFonts.beVietnamPro().fontFamily,

      // Cấu hình AppBar mặc định (Nền xanh, chữ trắng)
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.basicWhite,
        elevation: 0,
        centerTitle: false,
      ),

      // Cấu hình Nút bấm (ElevatedButton)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: AppColors.basicWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),

      // Cấu hình Nút nổi (FloatingActionButton)
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: AppColors.basicWhite,
      ),

      // Cấu hình Thẻ (Card)
      cardTheme: CardThemeData(
        color: AppColors.basicWhite,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  /// Theme nền Trắng cơ bản (#FFFFFF)
  static ThemeData get whiteTheme {
    return lightTheme.copyWith(
      scaffoldBackgroundColor: AppColors.basicWhite,
    );
  }
}
