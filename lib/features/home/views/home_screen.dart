import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../widgets/app_header_widget.dart';
import '../../notes/views/notes_screen.dart';
import '../../observation_book/views/observation_book_screen.dart';
import '../service/home_service.dart';
import 'widgets/home_sidebar_drawer.dart';

/// Màn hình Home chính của ứng dụng (Tự co giãn theo mọi kích thước màn hình)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();
  final HomeService _homeService = HomeService();

  // Khởi tạo trực tiếp tại dòng khai báo (lazy initialization) để khi Hot Reload không bị lỗi LateInitializationError
  late final TabController _tabController = TabController(
    length: HomeService.tabs.length,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    // Tự động kiểm tra/khởi tạo cây thư mục MeetingBook/ trên Google Drive và tải danh sách thư mục
    _homeService.initDriveFolders();
    _homeService.searchKeywordNotifier.addListener(_syncSearchControllerFromState);
  }

  void _syncSearchControllerFromState() {
    final String latestKeyword = _homeService.searchKeywordNotifier.value;
    if (_searchController.text != latestKeyword) {
      _searchController.value = TextEditingValue(
        text: latestKeyword,
        selection: TextSelection.collapsed(offset: latestKeyword.length),
      );
    }
  }

  @override
  void dispose() {
    _homeService.searchKeywordNotifier
        .removeListener(_syncSearchControllerFromState);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.basicWhite, // Nền trắng cơ bản (#FFFFFF)
      drawer: HomeSidebarDrawer(
        onOpenUserGuide: () {
          _homeService.openUserGuideScreen(context);
        },
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Tự động co giãn khoảng cách và kích thước nút theo màn hình
          final double fabPadding = (constraints.maxWidth * 0.04).clamp(16.0, 32.0);
          final double fabSize = (constraints.maxWidth * 0.08).clamp(56.0, 68.0);
          final double footerHeight = (constraints.maxHeight * 0.07).clamp(48.0, 64.0);

          return Column(
            children: [
              // 1. Header dùng chung (Tự động đổi chữ gợi ý tìm kiếm theo tab + Nút User góc phải)
              AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  final String currentHintText =
                      _homeService.getSearchHintText(_tabController.index);

                  return buildAppHeader(
                    searchController: _searchController,
                    tabController: _tabController,
                    tabs: HomeService.tabs,
                    hintText: currentHintText,
                    userPhotoUrl: _homeService.userPhotoUrl,
                    onMenuPressed: () {
                      _scaffoldKey.currentState?.openDrawer();
                    },
                    onUserPressed: () {
                      // Khi bấm vào icon User góc phải ô tìm kiếm -> Hiện Email & nút Đăng xuất
                      _homeService.openUserProfileDialog(context);
                    },
                    onSearchChanged: (value) {
                      _homeService.handleSearchChanged(value, _tabController.index);
                    },
                  );
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
                      Positioned.fill(
                        child: TabBarView(
                          controller: _tabController,
                          children: const [
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
                              // Gọi HomeService để mở Bottom Sheet theo tab hiện tại
                              _homeService.openCreateBottomSheet(
                                context: context,
                                currentTabIndex: _tabController.index,
                              );
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
    );
  }
}
