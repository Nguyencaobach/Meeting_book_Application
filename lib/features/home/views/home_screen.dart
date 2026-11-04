import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../widgets/app_header_widget.dart';
import '../../notes/views/notes_screen.dart';
import '../../observation_book/views/observation_book_screen.dart';

/// Màn hình Home chính của ứng dụng (Tự co giãn theo mọi kích thước màn hình)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.basicWhite, // Nền trắng cơ bản (#FFFFFF)
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Tự động co giãn khoảng cách và kích thước nút theo màn hình
            final double fabPadding = (constraints.maxWidth * 0.04).clamp(16.0, 32.0);
            final double fabSize = (constraints.maxWidth * 0.08).clamp(56.0, 68.0);
            final double footerHeight = (constraints.maxHeight * 0.07).clamp(48.0, 64.0);

            return Column(
              children: [
                // 1. Header dùng chung (Nền xanh, ô tìm kiếm trắng, kèm 2 tab Ghi chú & Sổ dự giờ)
                buildAppHeader(
                  searchController: _searchController,
                  onMenuPressed: () {
                    // Xử lý mở menu sau này
                  },
                  onSearchChanged: (value) {
                    // Xử lý tìm kiếm nhật ký sau này
                  },
                ),

                // 2. Vùng chứa nội dung nền màu trắng chuyển đổi giữa 2 tab (Tự động co giãn phần thân)
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: AppColors.basicWhite,
                    child: Stack(
                      children: [
                        // Nội dung 2 màn hình tab: Ghi chú & Sổ dự giờ
                        const Positioned.fill(
                          child: TabBarView(
                            children: [
                              NotesScreen(),
                              ObservationBookScreen(),
                            ],
                          ),
                        ),

                        // Nút hình tròn nền màu xanh, dấu cộng màu kem nằm góc cuối bên phải trên footer
                        Positioned(
                          right: fabPadding,
                          bottom: fabPadding,
                          child: SizedBox(
                            width: fabSize,
                            height: fabSize,
                            child: FloatingActionButton(
                              onPressed: () {
                                // Xử lý tạo nhật ký / vở mới
                              },
                              backgroundColor: theme.colorScheme.primary, // Nền màu xanh (#263BAA)
                              foregroundColor: AppColors.creamBackground, // Dấu cộng màu kem (#FFF4D6)
                              shape: const CircleBorder(),
                              elevation: 4,
                              child: Icon(
                                Icons.add,
                                color: AppColors.creamBackground,
                                size: fabSize * 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 3. Footer ở đáy màn hình
                Container(
                  width: double.infinity,
                  height: footerHeight,
                  color: theme.colorScheme.primary, // Đồng bộ màu xanh theme (#263BAA)
                  child: const SafeArea(
                    top: false,
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
