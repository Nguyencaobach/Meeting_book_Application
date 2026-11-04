import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../data/datasources/google_drive_datasource.dart';
import 'center_notification_dialog.dart';

// ===========================================================================
// WIDGET HIỂN THỊ DANH SÁCH / LƯỚI THƯ MỤC KIỂU GOOGLE DRIVE DÙNG CHUNG CHO 2 TAB
// Công dụng:
// - Góc trên bên phải (dưới Header): Nút "Làm mới" (Reload từ Google Drive) nằm
//   cùng dòng với nút chuyển chế độ xem Danh sách <-> Lưới (Ô).
// - Bên dưới: Khu vực cuộn lên xuống (có Scrollbar) chứa các thư mục.
// - Khi ở chế độ Lưới (Ô):
//   + Tên thư mục nằm căn trái.
//   + Số lượng ô trên 1 hàng tự động co giãn theo kích thước màn hình:
//     * Màn hình lớn (>= 900px): 6 ô / hàng
//     * Màn hình vừa (550px - 899px): 4 ô / hàng
//     * Màn hình nhỏ (< 550px): 2 ô / hàng
// ===========================================================================
class DriveFolderSectionWidget extends StatefulWidget {
  final ValueListenable<List<DriveFolderItem>> foldersListenable;
  final Future<void> Function() onRefresh;
  final String emptyMessage;
  final ValueChanged<DriveFolderItem>? onFolderTap;

  const DriveFolderSectionWidget({
    super.key,
    required this.foldersListenable,
    required this.onRefresh,
    required this.emptyMessage,
    this.onFolderTap,
  });

  @override
  State<DriveFolderSectionWidget> createState() =>
      _DriveFolderSectionWidgetState();
}

class _DriveFolderSectionWidgetState extends State<DriveFolderSectionWidget> {
  final ScrollController _scrollController = ScrollController();
  final GoogleDriveDatasource _driveDatasource = GoogleDriveDatasource.instance;

  // true = hiển thị theo từng ô (Lưới), false = hiển thị theo Danh sách
  bool _isGridView = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Hàm xử lý khi bấm nút "Làm mới" và hiển thị thông báo giữa màn hình khi hoàn tất
  Future<void> _handleRefreshWithNotification() async {
    try {
      await widget.onRefresh();
      if (mounted) {
        await showCenterNotification(
          context: context,
          title: 'Làm mới thành công',
          message: 'Đã cập nhật danh sách mới nhất từ Google Drive!',
        );
      }
    } catch (_) {
      if (mounted) {
        await showCenterNotification(
          context: context,
          title: 'Thông báo lỗi',
          message:
              'Không thể làm mới dữ liệu. Vui lòng kiểm tra kết nối mạng!',
          isError: true,
        );
      }
    }
  }

  /// Tính số lượng ô thư mục trên 1 hàng tùy theo chiều rộng màn hình:
  /// - Màn hình to: max 6 ô
  /// - Màn hình vừa: 4 ô
  /// - Màn hình nhỏ: 2 ô
  int _calculateGridColumns(double maxWidth) {
    if (maxWidth >= 900) {
      return 6;
    } else if (maxWidth >= 550) {
      return 4;
    }
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final double folderNameSize = AppTheme.getResponsiveFontSize(context, 14);
    final double headerLabelSize = AppTheme.getResponsiveFontSize(context, 14);
    final double emptyTextSize = AppTheme.getResponsiveFontSize(context, 15);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.basicWhite,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double horizontalPadding =
              (constraints.maxWidth * 0.04).clamp(16.0, 32.0);
          final int crossAxisCount =
              _calculateGridColumns(constraints.maxWidth);

          return Column(
            children: [
              // 1. Thanh điều khiển nằm ngay dưới Header: Nút "Làm mới" nằm cùng dòng với nút chuyển chế độ xem Lưới/Danh sách
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  10,
                  horizontalPadding,
                  6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Nút "Làm mới" để tự động tải lại danh sách từ Google Drive (nếu mạng lag hoặc xóa thư mục trên Drive)
                    ValueListenableBuilder<bool>(
                      valueListenable:
                          _driveDatasource.isSyncingFoldersNotifier,
                      builder: (context, isSyncing, _) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: isSyncing
                              ? null
                              : () => _handleRefreshWithNotification(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.creamBackground,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSyncing)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primaryBlue,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.refresh_rounded,
                                    color: AppColors.primaryBlue,
                                    size: 20,
                                  ),
                                const SizedBox(width: 6),
                                Text(
                                  isSyncing ? 'Đang tải...' : 'Làm mới',
                                  style: TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontSize: headerLabelSize * 0.92,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 10),

                    // Nút chuyển chế độ xem Danh sách <-> Lưới (Ô) giống Google Drive
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        setState(() {
                          _isGridView = !_isGridView;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.creamBackground,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isGridView
                                  ? Icons.view_list_rounded
                                  : Icons.grid_view_rounded,
                              color: AppColors.primaryBlue,
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isGridView ? 'Danh sách' : 'Lưới ô',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: headerLabelSize * 0.92,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Vùng chứa các thư mục bên dưới (Có thanh cuộn Scrollbar lướt lên xuống)
              Expanded(
                child: ValueListenableBuilder<List<DriveFolderItem>>(
                  valueListenable: widget.foldersListenable,
                  builder: (context, folders, _) {
                    if (folders.isEmpty) {
                      return RefreshIndicator(
                        color: AppColors.primaryBlue,
                        onRefresh: widget.onRefresh,
                        child: ListView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          children: [
                            SizedBox(height: constraints.maxHeight * 0.25),
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                widget.emptyMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.basicBlack
                                      .withValues(alpha: 0.6),
                                  fontSize: emptyTextSize,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      color: AppColors.primaryBlue,
                      onRefresh: widget.onRefresh,
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        radius: const Radius.circular(8),
                        child: _isGridView
                            // Chế độ xem theo từng ô (Lưới): 2, 4 hoặc 6 ô tùy kích thước màn hình, tên thư mục nằm bên trái
                            ? GridView.builder(
                                controller: _scrollController,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: EdgeInsets.fromLTRB(
                                  horizontalPadding,
                                  8,
                                  horizontalPadding,
                                  96, // Chừa khoảng trống cho nút (+) góc dưới
                                ),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  childAspectRatio: 2.3,
                                ),
                                itemCount: folders.length,
                                itemBuilder: (context, index) {
                                  final folder = folders[index];
                                  return _buildGridFolderTile(
                                    folder: folder,
                                    fontSize: folderNameSize,
                                  );
                                },
                              )
                            // Chế độ xem theo Danh sách (List): Lướt lên xuống, tên thư mục nằm bên trái
                            : ListView.separated(
                                controller: _scrollController,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: EdgeInsets.fromLTRB(
                                  horizontalPadding,
                                  8,
                                  horizontalPadding,
                                  96,
                                ),
                                itemCount: folders.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final folder = folders[index];
                                  return _buildListFolderTile(
                                    folder: folder,
                                    fontSize: folderNameSize,
                                  );
                                },
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Ô thư mục ở chế độ Lưới (Tên thư mục căn bên trái)
  Widget _buildGridFolderTile({
    required DriveFolderItem folder,
    required double fontSize,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onFolderTap?.call(folder),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        alignment: Alignment.centerLeft, // Căn tên thư mục nằm bên trái
        decoration: BoxDecoration(
          color: AppColors.creamBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.folder_rounded,
              color: AppColors.primaryBlue,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                folder.name,
                textAlign: TextAlign.left, // Chữ nằm bên trái
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.basicBlack,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dòng thư mục ở chế độ Danh sách (Tên thư mục căn bên trái)
  Widget _buildListFolderTile({
    required DriveFolderItem folder,
    required double fontSize,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onFolderTap?.call(folder),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: AppColors.creamBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.folder_rounded,
              color: AppColors.primaryBlue,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                folder.name,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.basicBlack,
                  fontSize: fontSize * 1.05,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
