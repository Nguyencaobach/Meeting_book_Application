import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// Widget Header dùng chung cho toàn ứng dụng (Tự động co giãn theo màn hình)
class AppHeaderWidget extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;
  final String hintText;

  const AppHeaderWidget({
    super.key,
    this.onMenuPressed,
    this.onSearchChanged,
    this.searchController,
    this.hintText = 'Tìm kiếm trong nhật ký',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tự động tính toán khoảng cách co giãn theo chiều rộng màn hình
        final double horizontalPadding = (constraints.maxWidth * 0.04).clamp(12.0, 32.0);
        final double verticalPadding = (constraints.maxWidth * 0.02).clamp(10.0, 20.0);

        return Container(
          width: double.infinity,
          color: theme.colorScheme.primary, // Màu xanh chủ đạo (#263BAA)
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Row(
                children: [
                  // Ô tìm kiếm màu trắng tự động co giãn lấp đầy chiều ngang
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: 48,
                        maxHeight: 56,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.basicWhite, // Màu trắng cơ bản (#FFFFFF)
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        children: [
                          // Góc bên trái: Menu 3 gạch màu kem (#FFF4D6)
                          IconButton(
                            onPressed: onMenuPressed ?? () {},
                            icon: const Icon(
                              Icons.menu,
                              color: AppColors.creamBackground,
                            ),
                            tooltip: 'Menu',
                          ),

                          // Ô nhập dòng chữ gợi ý: "Tìm kiếm trong nhật ký"
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              onChanged: onSearchChanged,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: hintText,
                                hintStyle: TextStyle(
                                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                                  fontSize: 16,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 4,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
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
}

/// Hàm tiện ích gọi nhanh Header dùng chung
Widget buildAppHeader({
  VoidCallback? onMenuPressed,
  ValueChanged<String>? onSearchChanged,
  TextEditingController? searchController,
  String hintText = 'Tìm kiếm trong nhật ký',
}) {
  return AppHeaderWidget(
    onMenuPressed: onMenuPressed,
    onSearchChanged: onSearchChanged,
    searchController: searchController,
    hintText: hintText,
  );
}
