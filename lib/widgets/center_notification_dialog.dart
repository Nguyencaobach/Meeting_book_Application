import 'dart:async';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';

// ===========================================================================
// HỘP THOẠI THÔNG BÁO NGẮN GỌN GIỮA MÀN HÌNH DÙNG CHUNG TOÀN APP
// Công dụng:
// - Hiển thị tối giản ngay chính giữa màn hình:
//   + Thành công: Icon tích xanh lá + chữ "Thành công"
//   + Thất bại: Icon X đỏ + chữ "Thất bại"
// - Tự động co giãn theo kích thước màn hình và tự đóng sau 1.2 giây.
// ===========================================================================
Future<void> showCenterNotification({
  required BuildContext context,
  String? message,
  String? title,
  bool isError = false,
  Duration autoCloseDuration = const Duration(milliseconds: 1200),
}) async {
  if (!context.mounted) return;

  Timer? autoCloseTimer;

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      autoCloseTimer ??= Timer(autoCloseDuration, () {
        if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
          Navigator.of(dialogContext).pop();
        }
      });

      final Size screenSize = MediaQuery.sizeOf(dialogContext);
      final double dialogWidth = (screenSize.width * 0.42).clamp(200.0, 320.0);
      final double iconSize =
          (screenSize.shortestSide * 0.11).clamp(48.0, 68.0);
      final double textFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 18);

      const Color successGreen = Color(0xFF2E7D32);
      final Color statusColor =
          isError ? AppColors.paperMarginRed : successGreen;
      final String statusText = isError ? 'Thất bại' : 'Thành công';

      return Dialog(
        backgroundColor: AppColors.basicWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon tích xanh lá (Thành công) hoặc ô X đỏ (Thất bại)
                if (!isError)
                  Icon(
                    Icons.check_circle_rounded,
                    color: successGreen,
                    size: iconSize,
                  )
                else
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: AppColors.paperMarginRed,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.basicWhite,
                      size: iconSize * 0.7,
                    ),
                  ),
                const SizedBox(height: 14),

                // Chỉ hiển thị chữ "Thành công" hoặc "Thất bại"
                Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: textFontSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  ).whenComplete(() {
    autoCloseTimer?.cancel();
  });
}
