import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';

/// Widget Header dùng chung cho toàn ứng dụng (Tự động co giãn theo màn hình)
class AppHeaderWidget extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  final VoidCallback? onUserPressed;
  final String? userPhotoUrl;
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;
  final String hintText;
  final TabController? tabController;
  final List<String> tabs;

  const AppHeaderWidget({
    super.key,
    this.onMenuPressed,
    this.onUserPressed,
    this.userPhotoUrl,
    this.onSearchChanged,
    this.searchController,
    this.hintText = 'Tìm kiếm trong nhật ký',
    this.tabController,
    this.tabs = const ['Ghi chú', 'Sổ dự giờ'],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Gọi hàm tự động co giãn cỡ chữ theo kích thước màn hình (từ AppTheme)
    final double searchFontSize = AppTheme.getResponsiveFontSize(context, 15);
    final double tabFontSize = AppTheme.getResponsiveFontSize(context, 15);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tự động tính toán khoảng cách co giãn theo chiều rộng màn hình
        final double horizontalPadding = (constraints.maxWidth * 0.04).clamp(12.0, 32.0);
        final double topPadding = (constraints.maxWidth * 0.02).clamp(10.0, 20.0);

        return Container(
          width: double.infinity,
          color: theme.colorScheme.primary, // Màu xanh chủ đạo (#263BAA)
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Phần ô tìm kiếm
                Padding(
                  padding: EdgeInsets.only(
                    left: horizontalPadding,
                    right: horizontalPadding,
                    top: topPadding,
                    bottom: topPadding * 0.5,
                  ),
                  child: Row(
                    children: [
                      // Ô tìm kiếm màu trắng tự động co giãn lấp đầy chiều ngang
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: 48,
                            maxHeight: 58,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.basicWhite, // Màu trắng cơ bản (#FFFFFF)
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Row(
                            children: [
                              // Góc bên trái: Menu 3 gạch màu xanh chủ đạo (#263BAA)
                              IconButton(
                                onPressed: onMenuPressed ?? () {},
                                icon: Icon(
                                  Icons.menu,
                                  color: theme.colorScheme.primary, // Màu xanh theme
                                ),
                                tooltip: 'Menu',
                              ),

                              // Ô nhập dòng chữ gợi ý: "Tìm kiếm trong nhật ký" dùng màu đen tiêu chuẩn
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  onChanged: onSearchChanged,
                                  style: TextStyle(
                                    color: AppColors.basicBlack, // Màu đen tiêu chuẩn
                                    fontSize: searchFontSize, // Cỡ chữ tự động co giãn
                                  ),
                                  decoration: InputDecoration(
                                    hintText: hintText,
                                    hintStyle: TextStyle(
                                      color: AppColors.basicBlack, // Màu đen tiêu chuẩn
                                      fontSize: searchFontSize, // Cỡ chữ tự động co giãn
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

                              // Góc bên phải trong ô tìm kiếm: Nút Icon User đẹp mắt
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: onUserPressed,
                                  customBorder: const CircleBorder(),
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryBlue, // Nền tròn màu xanh (#263BAA)
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.creamBackground, // Viền màu kem (#FFF4D6)
                                        width: 2,
                                      ),
                                      image: (userPhotoUrl != null &&
                                              userPhotoUrl!.isNotEmpty)
                                          ? DecorationImage(
                                              image: NetworkImage(userPhotoUrl!),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: (userPhotoUrl == null ||
                                            userPhotoUrl!.isEmpty)
                                        ? const Icon(
                                            Icons.person_rounded,
                                            color: AppColors.creamBackground, // Icon người dùng màu kem
                                            size: 22,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Hai tab bấm qua lại bên dưới ô tìm kiếm ("Ghi chú" & "Sổ dự giờ")
                if (tabs.isNotEmpty)
                  TabBar(
                    controller: tabController,
                    labelColor: AppColors.basicWhite, // Màu chữ trắng theo theme
                    unselectedLabelColor: AppColors.basicWhite.withValues(alpha: 0.7),
                    indicatorSize: TabBarIndicatorSize.label, // Co theo độ rộng của chữ
                    indicator: UnderlineTabIndicator(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(
                        width: 5.0, // Thanh gạch chân dày và đậm hơn
                        color: AppColors.creamBackground, // Màu kem nổi bật
                      ),
                    ),
                    dividerColor: Colors.transparent,
                    labelStyle: TextStyle(
                      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                      fontSize: tabFontSize, // Cỡ chữ tự động co giãn
                      fontWeight: FontWeight.w700,
                    ),
                    unselectedLabelStyle: TextStyle(
                      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                      fontSize: tabFontSize, // Cỡ chữ tự động co giãn
                      fontWeight: FontWeight.normal,
                    ),
                    tabs: tabs
                        .map(
                          (tabName) => Tab(
                            child: Padding(
                              // Mở rộng nhẹ 2 bên chữ để thanh gạch dưới dài hơn chữ một chút
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(tabName),
                            ),
                          ),
                        )
                        .toList(),
                  ),
              ],
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
  VoidCallback? onUserPressed,
  String? userPhotoUrl,
  ValueChanged<String>? onSearchChanged,
  TextEditingController? searchController,
  String hintText = 'Tìm kiếm trong nhật ký',
  TabController? tabController,
  List<String> tabs = const ['Ghi chú', 'Sổ dự giờ'],
}) {
  return AppHeaderWidget(
    onMenuPressed: onMenuPressed,
    onUserPressed: onUserPressed,
    userPhotoUrl: userPhotoUrl,
    onSearchChanged: onSearchChanged,
    searchController: searchController,
    hintText: hintText,
    tabController: tabController,
    tabs: tabs,
  );
}
