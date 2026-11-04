import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';

// ===========================================================================
// HỘP THOẠI HIỂN THỊ THÔNG TIN TÀI KHOẢN GOOGLE DRIVE & NÚT ĐĂNG XUẤT
// Công dụng:
// - Bật lên khi người dùng bấm vào icon User ở góc bên phải ô tìm kiếm.
// - Tự động co giãn chiều rộng và chiều cao rộng rãi theo kích thước màn hình.
// - Hiển thị ảnh đại diện / icon, tên người dùng, địa chỉ Email đang đăng nhập
//   và nút "Đăng xuất" để thoát tài khoản.
// ===========================================================================
void showUserProfileDialog({
  required BuildContext context,
  required String userEmail,
  required String userName,
  String? userPhotoUrl,
  required VoidCallback onLogoutPressed,
}) {
  showDialog(
    context: context,
    builder: (dialogContext) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);

      // Tự động co giãn kích thước khung hộp thoại rộng và cao hơn theo màn hình
      final double dialogWidth = (screenSize.width * 0.72).clamp(340.0, 620.0);
      final double horizontalPadding =
          (screenSize.width * 0.045).clamp(24.0, 40.0);
      final double verticalPadding =
          (screenSize.height * 0.035).clamp(24.0, 40.0);
      final double avatarRadius =
          (screenSize.shortestSide * 0.05).clamp(28.0, 40.0);

      // Gọi hàm tự động co giãn cỡ chữ theo kích thước màn hình
      final double titleFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 19);
      final double emailFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 15);
      final double buttonFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 16);

      return Dialog(
        backgroundColor: AppColors.basicWhite,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: SizedBox(
          width: dialogWidth,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hàng trên cùng: Tiêu đề + Nút đóng (X)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tài khoản Google Drive',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.basicBlack,
                      ),
                      tooltip: 'Đóng',
                    ),
                  ],
                ),
                SizedBox(height: verticalPadding * 0.6),

                // Khung thông tin người dùng nền màu kem (#FFF4D6) rộng rãi hơn
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding * 0.8,
                    vertical: verticalPadding * 0.85,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.creamBackground, // Màu kem theo theme
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar hoặc Icon người dùng tự co giãn
                      CircleAvatar(
                        radius: avatarRadius,
                        backgroundColor: AppColors.primaryBlue,
                        backgroundImage:
                            (userPhotoUrl != null && userPhotoUrl.isNotEmpty)
                                ? NetworkImage(userPhotoUrl)
                                : null,
                        child: (userPhotoUrl == null || userPhotoUrl.isEmpty)
                            ? Icon(
                                Icons.person_rounded,
                                color: AppColors.creamBackground,
                                size: avatarRadius * 1.15,
                              )
                            : null,
                      ),
                      SizedBox(width: horizontalPadding * 0.6),

                      // Tên hiển thị & Email đăng nhập
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (userName.isNotEmpty)
                              Text(
                                userName,
                                style: TextStyle(
                                  color: AppColors.basicBlack,
                                  fontSize: emailFontSize * 1.1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              userEmail.isNotEmpty
                                  ? userEmail
                                  : 'Chưa có thông tin email',
                              style: TextStyle(
                                color: AppColors.basicBlack,
                                fontSize: emailFontSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.primaryBlue,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Đã liên kết Google Drive',
                                    style: TextStyle(
                                      color: AppColors.primaryBlue,
                                      fontSize: emailFontSize * 0.92,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: verticalPadding * 0.9),

                // Nút Đăng xuất cao và thoáng hơn
                SizedBox(
                  width: double.infinity,
                  height: (screenSize.height * 0.065).clamp(50.0, 60.0),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      onLogoutPressed();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors.primaryBlue, // Nền xanh (#263BAA)
                      foregroundColor: AppColors.basicWhite,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.creamBackground,
                    ),
                    label: Text(
                      'Đăng xuất',
                      style: TextStyle(
                        color: AppColors.basicWhite,
                        fontSize: buttonFontSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
