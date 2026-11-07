import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';

/// Thanh menu bên trái (Sidebar) trượt ra từ cạnh trái tầm nửa màn hình
/// khi bấm vào nút menu 3 gạch trên thanh tìm kiếm của màn hình Home.
/// Thiết kế tối giản, nhã nhặn theo màu Theme, không dùng icon rườm rà.
class HomeSidebarDrawer extends StatelessWidget {
  final VoidCallback onOpenUserGuide;

  const HomeSidebarDrawer({
    super.key,
    required this.onOpenUserGuide,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double screenWidth = MediaQuery.sizeOf(context).width;
    // Độ rộng Sidebar chiếm đúng nửa màn hình (50% chiều ngang)
    final double drawerWidth = (screenWidth * 0.5).clamp(240.0, 640.0);

    final double headerTitleFontSize =
        AppTheme.getResponsiveFontSize(context, 17);
    final double headerSubFontSize =
        AppTheme.getResponsiveFontSize(context, 13);
    final double menuTitleFontSize =
        AppTheme.getResponsiveFontSize(context, 15.5);
    final double menuSubFontSize =
        AppTheme.getResponsiveFontSize(context, 13);

    return Drawer(
      width: drawerWidth,
      backgroundColor: AppColors.basicWhite,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Phần đầu Sidebar đồng bộ màu xanh chủ đạo (#263BAA)
          Container(
            color: theme.colorScheme.primary,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Danh mục',
                            style: TextStyle(
                              color: AppColors.basicWhite,
                              fontSize: headerTitleFontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Sổ ghi chép & Sổ dự giờ',
                            style: TextStyle(
                              color: AppColors.creamBackground,
                              fontSize: headerSubFontSize,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.basicWhite.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.creamBackground
                                .withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          'Đóng',
                          style: TextStyle(
                            color: AppColors.basicWhite,
                            fontSize: headerSubFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Danh sách chức năng bên trong Sidebar
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    onOpenUserGuide();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.creamSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hướng dẫn sử dụng',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: menuTitleFontSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Xem tài liệu hướng dẫn chi tiết các chức năng trong ứng dụng',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: menuSubFontSize,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
