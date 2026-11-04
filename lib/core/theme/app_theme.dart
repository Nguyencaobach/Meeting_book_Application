import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Cấu hình Theme dùng chung toàn ứng dụng (Xanh #263BAA - Kem #FFF4D6 - Trắng #FFFFFF)
class AppTheme {
  AppTheme._();

  /// Theme mặc định kết hợp 3 màu chủ đạo: Xanh (#263BAA), Kem (#FFF4D6) và Trắng cơ bản (#FFFFFF)
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryBlue,
      primary: AppColors.primaryBlue,
      onPrimary: AppColors.basicWhite,
      secondary: AppColors.creamBackground,
      onSecondary: AppColors.primaryBlue,
      surface: AppColors.basicWhite,
      surfaceContainerHighest: AppColors.creamBackground,
      onSurface: AppColors.textPrimary,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.creamBackground,

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

      // Cấu hình Thẻ (Card - Nền trắng cơ bản nổi bật trên nền kem)
      cardTheme: CardThemeData(
        color: AppColors.basicWhite,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  /// Theme nền Trắng cơ bản (#FFFFFF) khi cần giao diện sáng trắng thuần túy
  static ThemeData get whiteTheme {
    return lightTheme.copyWith(
      scaffoldBackgroundColor: AppColors.basicWhite,
    );
  }
}
