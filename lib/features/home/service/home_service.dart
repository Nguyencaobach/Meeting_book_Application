import 'package:flutter/material.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../../widgets/create_folder_dialog.dart';
import '../../../widgets/user_profile_dialog.dart';
import '../../auth/service/auth_service.dart';
import '../views/widgets/create_item_bottom_sheet.dart';

// ===========================================================================
// LỚP XỬ LÝ LOGIC CHO MÀN HÌNH HOME (HOME SERVICE)
// Công dụng:
// - Tách toàn bộ phần xử lý nghiệp vụ/logic ra khỏi giao diện HomeScreen.
// - Quản lý danh sách tên Tab, câu chữ gợi ý tìm kiếm theo từng Tab,
//   hiển thị thông tin tài khoản Google Drive & Đăng xuất,
//   và xử lý sự kiện tạo Thư mục mới trực tiếp vào MeetingBook/Ghi_Chu hoặc MeetingBook/So_Du_Gio.
// ===========================================================================
class HomeService {
  final AuthService _authService = AuthService();
  final GoogleDriveDatasource _driveDatasource = GoogleDriveDatasource.instance;

  /// Danh sách các Tab hiển thị trên Header của màn hình Home
  static const List<String> tabs = ['Ghi chú', 'Sổ dự giờ'];

  /// Lấy ảnh đại diện của tài khoản đang đăng nhập
  String? get userPhotoUrl => _authService.currentUserPhotoUrl;

  /// Tải danh sách thư mục của cả 2 Tab từ Google Drive khi mở màn hình Home
  Future<void> initDriveFolders() async {
    await _driveDatasource.refreshAllTabFolders();
  }

  /// Hàm lấy dòng chữ gợi ý trong ô tìm kiếm tương ứng với Tab đang mở
  String getSearchHintText(int currentTabIndex) {
    if (currentTabIndex == 0) {
      return 'Tìm kiếm trong nhật ký';
    }
    return 'Tìm kiếm trong sổ dự giờ';
  }

  /// Hàm mở bảng thông tin tài khoản (Email đang đăng nhập & nút Đăng xuất)
  void openUserProfileDialog(BuildContext context) {
    showUserProfileDialog(
      context: context,
      userEmail: _authService.currentUserEmail,
      userName: _authService.currentUserName,
      userPhotoUrl: _authService.currentUserPhotoUrl,
      onLogoutPressed: () {
        _authService.handleLogout(context);
      },
    );
  }

  /// Hàm mở Bottom Sheet khi người dùng bấm nút dấu cộng (+) ở góc phải dưới
  void openCreateBottomSheet({
    required BuildContext context,
    required int currentTabIndex,
  }) {
    showCreateItemBottomSheet(
      context: context,
      currentTabIndex: currentTabIndex,
      onCreateNote: () => handleCreateNote(context),
      onCreateObservationBook: () => handleCreateObservationBook(context),
      onCreateFolder: () => handleCreateFolder(context, currentTabIndex),
    );
  }

  /// Xử lý logic khi bấm "Tạo ghi chú mới" (ở Tab Ghi chú)
  void handleCreateNote(BuildContext context) {
    // Logic tạo ghi chú mới sẽ được triển khai tại đây
  }

  /// Xử lý logic khi bấm "Tạo sổ dự giờ mới" (ở Tab Sổ dự giờ)
  void handleCreateObservationBook(BuildContext context) {
    // Logic tạo sổ dự giờ mới sẽ được triển khai tại đây
  }

  // ===========================================================================
  // HÀM XỬ LÝ TẠO THƯ MỤC MỚI TRÊN GOOGLE DRIVE THEO TAB HIỆN TẠI
  // - Tab 0 (Ghi chú): Tạo trong MeetingBook/Ghi_Chu/
  // - Tab 1 (Sổ dự giờ): Tạo trong MeetingBook/So_Du_Gio/
  // ===========================================================================
  void handleCreateFolder(BuildContext context, int currentTabIndex) {
    showCreateFolderDialog(
      context: context,
      currentTabIndex: currentTabIndex,
      onConfirmCreate: (folderName) async {
        await _driveDatasource.createFolderInTab(
          tabIndex: currentTabIndex,
          folderName: folderName,
        );
      },
    );
  }

  /// Xử lý logic khi người dùng nhập từ khóa tìm kiếm
  void handleSearchChanged(String keyword, int currentTabIndex) {
    // Logic lọc danh sách theo từ khóa tìm kiếm và tab hiện tại
  }
}
