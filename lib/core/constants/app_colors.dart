import 'package:flutter/material.dart';

/// Bảng màu dùng chung cho toàn bộ ứng dụng
class AppColors {
  AppColors._(); // Ngăn khởi tạo trực tiếp

  /// 1. Màu xanh chủ đạo (#263BAA)
  static const Color primaryBlue = Color(0xFF263BAA);

  /// 2. Màu kem chủ đạo (#FFF4D6)
  static const Color creamBackground = Color(0xFFFFF4D6);

  /// 3. Màu trắng cơ bản (#FFFFFF)
  static const Color basicWhite = Color(0xFFFFFFFF);
  static const Color white = basicWhite;

  /// 4. Màu đen tiêu chuẩn (#000000)
  static const Color basicBlack = Color(0xFF000000);
  static const Color black = basicBlack;

  // Các sắc độ bổ trợ tự động đồng bộ
  static const Color primaryBlueLight = Color(0xFF4A5FD9);
  static const Color primaryBlueDark = Color(0xFF182675);
  static const Color creamSurface = Color(0xFFFFF9E8);

  // Màu chữ & viền cơ bản
  static const Color textPrimary = basicBlack;
  static const Color textSecondary = Color(0xFF5A6282);

  // Màu phục vụ trang giấy ô ly sau này
  static const Color paperMarginRed = Color(0xFFE53935);
}
