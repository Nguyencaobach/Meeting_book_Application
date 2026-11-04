import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';

// ===========================================================================
// HÀM HIỂN THỊ BOTTOM SHEET TẠO MỚI TỪ DƯỚI LÊN (HỖ TRỢ VUỐT TẮT & NÚT X)
// Công dụng:
// - Khi ở tab Ghi chú (currentTabIndex == 0):
//     1. "Tạo ghi chú mới"
//     2. "Thêm thư mục mới"
// - Khi ở tab Sổ dự giờ (currentTabIndex == 1):
//     1. "Tạo sổ dự giờ mới"
//     2. "Thêm thư mục mới"
// ===========================================================================
void showCreateItemBottomSheet({
  required BuildContext context,
  required int currentTabIndex,
  VoidCallback? onCreateNote,
  VoidCallback? onCreateObservationBook,
  VoidCallback? onCreateFolder,
}) {
  final bool isNoteTab = currentTabIndex == 0;
  final String primaryActionTitle = isNoteTab ? 'Tạo ghi chú mới' : 'Tạo sổ dự giờ mới';
  final IconData primaryActionIcon =
      isNoteTab ? Icons.note_add_outlined : Icons.menu_book_outlined;

  showModalBottomSheet(
    context: context,
    enableDrag: true, // Cho phép vuốt xuống để tắt
    isDismissible: true, // Chạm ra ngoài để tắt
    isScrollControlled: true,
    // Mở rộng chiều ngang Bottom Sheet tràn full 100% màn hình (kể cả trên Tablet màn hình lớn)
    constraints: const BoxConstraints(
      minWidth: double.infinity,
      maxWidth: double.infinity,
    ),
    backgroundColor: AppColors.basicWhite, // Nền trắng theo theme
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      // Gọi hàm tự động co giãn cỡ chữ theo kích thước màn hình
      final double titleFontSize = AppTheme.getResponsiveFontSize(sheetContext, 16);
      final double actionFontSize = AppTheme.getResponsiveFontSize(sheetContext, 16);

      return LayoutBuilder(
        builder: (context, constraints) {
          // Tự động co giãn khoảng cách lề theo độ rộng của màn hình
          final double horizontalPadding = (constraints.maxWidth * 0.05).clamp(16.0, 36.0);
          final double verticalPadding = (constraints.maxWidth * 0.03).clamp(12.0, 24.0);

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: 12,
                bottom: verticalPadding + 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thanh nắm kéo (Drag Handle) ở giữa hỗ trợ nhận biết thao tác vuốt xuống
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Hàng tiêu đề trên cùng kèm nút dấu X đóng ở góc bên phải
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Thêm mới',
                          style: TextStyle(
                            color: AppColors.basicBlack,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // Nút dấu X bên phải để đóng Bottom Sheet
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.basicBlack,
                        ),
                        tooltip: 'Đóng',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 1. Nút chức năng theo Tab ("Tạo ghi chú mới" hoặc "Tạo sổ dự giờ mới")
                  _buildBottomSheetOption(
                    title: primaryActionTitle,
                    icon: primaryActionIcon,
                    fontSize: actionFontSize,
                    horizontalPadding: horizontalPadding,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (isNoteTab) {
                        onCreateNote?.call();
                      } else {
                        onCreateObservationBook?.call();
                      }
                    },
                  ),

                  const SizedBox(height: 12),

                  // 2. Nút chức năng "Thêm thư mục mới" (Áp dụng cho cả 2 Tab)
                  _buildBottomSheetOption(
                    title: 'Thêm thư mục mới',
                    icon: Icons.create_new_folder_outlined,
                    fontSize: actionFontSize,
                    horizontalPadding: horizontalPadding,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onCreateFolder?.call();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Hàm dựng từng dòng nút chức năng trong Bottom Sheet (Tự co giãn & dùng màu Theme)
Widget _buildBottomSheetOption({
  required String title,
  required IconData icon,
  required double fontSize,
  required double horizontalPadding,
  required VoidCallback onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding * 0.8,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.creamBackground, // Nền màu kem theo theme
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.primaryBlue, // Nền icon màu xanh chủ đạo
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: AppColors.creamBackground, // Icon màu kem
              size: fontSize * 1.3,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.basicBlack, // Chữ màu đen tiêu chuẩn
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            color: AppColors.primaryBlue,
            size: 18,
          ),
        ],
      ),
    ),
  );
}
