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
// - Hỗ trợ nút "Hoàn tác" (onUndo) cho các thao tác Xóa và Di chuyển:
//   + Nếu người dùng bấm "Hoàn tác" -> Khôi phục lại dữ liệu ngay lập tức.
//   + Nếu người dùng không bấm -> Tự động đóng hộp thoại như bình thường.
// ===========================================================================
Future<void> showCenterNotification({
  required BuildContext context,
  String? message,
  String? title,
  bool isError = false,
  Duration? autoCloseDuration,
  Future<void> Function()? onUndo,
  String undoLabel = 'Hoàn tác',
  String? customStatusText,
}) async {
  if (!context.mounted) return;

  final bool hasUndoAction = onUndo != null && !isError;
  final Duration effectiveDuration = autoCloseDuration ??
      (hasUndoAction
          ? const Duration(milliseconds: 3600)
          : const Duration(milliseconds: 1200));

  Timer? autoCloseTimer;
  bool didTriggerUndo = false;
  bool undoSucceeded = false;

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      bool isUndoing = false;

      autoCloseTimer ??= Timer(effectiveDuration, () {
        if (!isUndoing &&
            dialogContext.mounted &&
            Navigator.of(dialogContext).canPop()) {
          Navigator.of(dialogContext).pop();
        }
      });

      final Size screenSize = MediaQuery.sizeOf(dialogContext);
      final double dialogWidth = (screenSize.width * 0.44).clamp(220.0, 340.0);
      final double iconSize =
          (screenSize.shortestSide * 0.11).clamp(48.0, 68.0);
      final double textFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 18);
      final double subFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 13.5);
      final double buttonFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 14);

      const Color successGreen = Color(0xFF2E7D32);
      final Color statusColor =
          isError ? AppColors.paperMarginRed : successGreen;
      final String statusText =
          customStatusText ?? (isError ? 'Thất bại' : 'Thành công');

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> handleUndoTap() async {
            if (isUndoing) return;
            autoCloseTimer?.cancel();
            setDialogState(() {
              isUndoing = true;
            });
            didTriggerUndo = true;
            try {
              await onUndo!();
              undoSucceeded = true;
            } catch (_) {
              undoSucceeded = false;
            }
            if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          }

          return Dialog(
            backgroundColor: AppColors.basicWhite,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: SizedBox(
              width: dialogWidth,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
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

                    // Hiển thị chữ "Thành công" hoặc "Thất bại"
                    Text(
                      statusText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: textFontSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    if (message != null &&
                        message.trim().isNotEmpty &&
                        (hasUndoAction || isError)) ...[
                      const SizedBox(height: 6),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.basicBlack.withValues(alpha: 0.72),
                          fontSize: subFontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],

                    // Nút Hoàn tác (chỉ hiển thị khi thao tác Xóa / Di chuyển thành công)
                    if (hasUndoAction) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isUndoing ? null : handleUndoTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: AppColors.basicWhite,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: isUndoing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.creamBackground,
                                  ),
                                )
                              : const Icon(
                                  Icons.undo_rounded,
                                  color: AppColors.creamBackground,
                                  size: 19,
                                ),
                          label: Text(
                            isUndoing ? 'Đang khôi phục...' : undoLabel,
                            style: TextStyle(
                              color: AppColors.basicWhite,
                              fontSize: buttonFontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  ).whenComplete(() {
    autoCloseTimer?.cancel();
  });

  // Nếu người dùng đã bấm nút Hoàn tác -> Hiển thị thông báo kết quả hoàn tác ngắn gọn
  if (didTriggerUndo && context.mounted) {
    await showCenterNotification(
      context: context,
      isError: !undoSucceeded,
      customStatusText: undoSucceeded ? 'Đã hoàn tác' : 'Hoàn tác thất bại',
      autoCloseDuration: const Duration(milliseconds: 1100),
    );
  }
}
