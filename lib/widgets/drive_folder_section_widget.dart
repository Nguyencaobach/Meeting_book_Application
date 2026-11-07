import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../data/datasources/google_drive_datasource.dart';
import 'center_notification_dialog.dart';
import 'item_actions_bottom_sheet.dart';

// ===========================================================================
// WIDGET HIỂN THỊ DANH SÁCH / LƯỚI THƯ MỤC & FILE KIỂU GOOGLE DRIVE DÙNG CHUNG
// Công dụng:
// - Góc trên:
//   + Bên trái (khi đang mở bên trong 1 thư mục con): Hiện nút "Quay lại" kèm
//     tên thư mục đang chọn để người dùng biết đang thao tác trong thư mục nào.
//   + Bên phải: Nút "Làm mới" nằm cùng dòng với nút chuyển chế độ xem Danh sách <-> Lưới.
// - Bên dưới: Khu vực cuộn lên xuống (có Scrollbar) chứa cả Thư mục và Tệp ghi chú (.json).
// - Bên trái tên của mỗi Tệp/Thư mục có nút icon thông tin chữ "i":
//   + Khi bấm vào nút "i" -> Sổ lên Bottom Sheet (Đổi tên, Xóa, Di chuyển).
//   + Khi bấm vào vùng tên/ô -> Mở Thư mục hoặc mở Tệp ghi chú để render JSON.
// ===========================================================================
class DriveFolderSectionWidget extends StatefulWidget {
  final int tabIndex;
  final ValueListenable<List<DriveFolderItem>> foldersListenable;
  final ValueListenable<List<DriveFolderItem>>? allTabItemsListenable;
  final ValueListenable<DriveFolderItem?>? activeFolderListenable;
  final ValueListenable<String>? searchKeywordListenable;
  final Future<void> Function() onRefresh;
  final VoidCallback? onExitFolder;
  final String emptyMessage;
  final ValueChanged<DriveFolderItem>? onFolderTap;

  const DriveFolderSectionWidget({
    super.key,
    this.tabIndex = 0,
    required this.foldersListenable,
    this.allTabItemsListenable,
    required this.onRefresh,
    required this.emptyMessage,
    this.activeFolderListenable,
    this.searchKeywordListenable,
    this.onExitFolder,
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

  /// Tính số lượng ô trên 1 hàng tùy theo chiều rộng màn hình:
  /// - Màn hình to (>= 900px): 6 ô
  /// - Màn hình vừa (550px - 899px): 4 ô
  /// - Màn hình nhỏ (< 550px): 2 ô
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
              // 1. Thanh điều khiển nằm ngay dưới Header:
              // Bên trái: Nút Quay lại + tên thư mục đang mở (nếu đang ở trong thư mục)
              // Bên phải: Nút "Làm mới" + Nút chuyển "Danh sách / Lưới ô"
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  10,
                  horizontalPadding,
                  6,
                ),
                child: Row(
                  children: [
                    // Hiển thị thanh điều hướng thư mục đang chọn (Giới hạn tối đa tới 1 nửa màn hình)
                    if (widget.activeFolderListenable != null)
                      ValueListenableBuilder<DriveFolderItem?>(
                        valueListenable: widget.activeFolderListenable!,
                        builder: (context, activeFolder, _) {
                          if (activeFolder == null) {
                            return const SizedBox.shrink();
                          }
                          return ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.5,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: widget.onExitFolder,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryBlue,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.arrow_back_rounded,
                                          color: AppColors.basicWhite,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Quay lại',
                                          style: TextStyle(
                                            color: AppColors.basicWhite,
                                            fontSize: headerLabelSize * 0.92,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    'Thư mục: ${activeFolder.displayName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.primaryBlue,
                                      fontSize: headerLabelSize,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    const Spacer(),

                    // Nút "Làm mới" để tự động tải lại danh sách từ Google Drive
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

              // 2. Vùng chứa các Thư mục và Tệp ghi chú bên dưới (Có thanh cuộn Scrollbar)
              Expanded(
                child: ValueListenableBuilder<List<DriveFolderItem>>(
                  valueListenable: widget.foldersListenable,
                  builder: (context, rawItems, _) {
                    return ValueListenableBuilder<List<DriveFolderItem>>(
                      valueListenable: widget.allTabItemsListenable ??
                          ValueNotifier<List<DriveFolderItem>>(
                            const <DriveFolderItem>[],
                          ),
                      builder: (context, allTabItems, _) {
                        return ValueListenableBuilder<String>(
                          valueListenable: widget.searchKeywordListenable ??
                              ValueNotifier<String>(''),
                          builder: (context, keyword, _) {
                            final String trimmedKeyword = keyword.trim();
                            final bool isSearching = trimmedKeyword.isNotEmpty;
                            final DriveFolderItem? currentActiveFolder =
                                widget.activeFolderListenable?.value;

                            // Khi đang tìm kiếm ở màn hình gốc của Tab -> Tìm trên toàn bộ Thư mục & Tệp (kể cả tệp nằm trong thư mục con)
                            List<DriveFolderItem> candidatePool = rawItems;
                            if (isSearching &&
                                currentActiveFolder == null &&
                                allTabItems.isNotEmpty) {
                              final Map<String, DriveFolderItem> mergedById =
                                  <String, DriveFolderItem>{};
                              for (final DriveFolderItem item in rawItems) {
                                mergedById[item.id] = item;
                              }
                              for (final DriveFolderItem item in allTabItems) {
                                mergedById.putIfAbsent(item.id, () => item);
                              }
                              final List<DriveFolderItem> folders =
                                  <DriveFolderItem>[];
                              final List<DriveFolderItem> files =
                                  <DriveFolderItem>[];
                              for (final DriveFolderItem item
                                  in mergedById.values) {
                                if (item.isFolder) {
                                  folders.add(item);
                                } else {
                                  files.add(item);
                                }
                              }
                              candidatePool = <DriveFolderItem>[
                                ...folders,
                                ...files,
                              ];
                            }

                            final List<DriveFolderItem> items = !isSearching
                                ? rawItems
                                : candidatePool
                                    .where(
                                      (DriveFolderItem item) =>
                                          GoogleDriveDatasource
                                              .matchesSearchKeyword(
                                        item.displayName,
                                        trimmedKeyword,
                                      ),
                                    )
                                    .toList();

                            if (items.isEmpty) {
                              return RefreshIndicator(
                                color: AppColors.primaryBlue,
                                onRefresh: widget.onRefresh,
                                child: ListView(
                                  controller: _scrollController,
                                  physics: const AlwaysScrollableScrollPhysics(
                                    parent: BouncingScrollPhysics(),
                                  ),
                                  children: [
                                    SizedBox(
                                      height: constraints.maxHeight * 0.25,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        isSearching
                                            ? 'Không tìm thấy tệp hoặc thư mục nào phù hợp với "$trimmedKeyword".'
                                            : widget.emptyMessage,
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
                                    // Chế độ xem theo từng ô (Lưới): 2, 4 hoặc 6 ô tùy kích thước màn hình
                                    ? GridView.builder(
                                        controller: _scrollController,
                                        physics:
                                            const AlwaysScrollableScrollPhysics(
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
                                          childAspectRatio: 2.0,
                                        ),
                                        itemCount: items.length,
                                        itemBuilder: (context, index) {
                                          final item = items[index];
                                          return _buildGridItemTile(
                                            item: item,
                                            fontSize: folderNameSize,
                                            isSearchingAtRoot: isSearching &&
                                                currentActiveFolder == null,
                                          );
                                        },
                                      )
                                    // Chế độ xem theo Danh sách (List)
                                    : ListView.separated(
                                        controller: _scrollController,
                                        physics:
                                            const AlwaysScrollableScrollPhysics(
                                          parent: BouncingScrollPhysics(),
                                        ),
                                        padding: EdgeInsets.fromLTRB(
                                          horizontalPadding,
                                          8,
                                          horizontalPadding,
                                          96,
                                        ),
                                        itemCount: items.length,
                                        separatorBuilder: (_, _) =>
                                            const SizedBox(height: 10),
                                        itemBuilder: (context, index) {
                                          final item = items[index];
                                          return _buildListItemTile(
                                            item: item,
                                            fontSize: folderNameSize,
                                            isSearchingAtRoot: isSearching &&
                                                currentActiveFolder == null,
                                          );
                                        },
                                      ),
                              ),
                            );
                          },
                        );
                      },
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

  /// Ô hiển thị Thư mục hoặc Tệp ghi chú ở chế độ Lưới (Nút "i" nằm sát góc phải đối diện tên)
  Widget _buildGridItemTile({
    required DriveFolderItem item,
    required double fontSize,
    bool isSearchingAtRoot = false,
  }) {
    final bool isFolder = item.isFolder;
    final String? parentFolderName = isSearchingAtRoot
        ? _driveDatasource.getParentFolderDisplayName(item)
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onFolderTap?.call(item),
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 6, top: 8, bottom: 8),
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
            Icon(
              isFolder ? Icons.folder_rounded : Icons.description_rounded,
              color: AppColors.primaryBlue,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    textAlign: TextAlign.left,
                    maxLines: parentFolderName != null ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.basicBlack,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (parentFolderName != null)
                    Text(
                      'Trong: $parentFolderName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.primaryBlue.withValues(alpha: 0.8),
                        fontSize: fontSize * 0.82,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Nút icon thông tin chữ "i" nằm đối diện tên tệp/thư mục
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                showItemActionsBottomSheet(
                  context: context,
                  tabIndex: widget.tabIndex,
                  item: item,
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primaryBlue,
                  size: 21,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dòng hiển thị Thư mục hoặc Tệp ghi chú ở chế độ Danh sách (Nút "i" nằm sát góc phải đối diện tên)
  Widget _buildListItemTile({
    required DriveFolderItem item,
    required double fontSize,
    bool isSearchingAtRoot = false,
  }) {
    final bool isFolder = item.isFolder;
    final String? parentFolderName = isSearchingAtRoot
        ? _driveDatasource.getParentFolderDisplayName(item)
        : null;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onFolderTap?.call(item),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.only(left: 16, right: 10, top: 12, bottom: 12),
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
            Icon(
              isFolder ? Icons.folder_rounded : Icons.description_rounded,
              color: AppColors.primaryBlue,
              size: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    textAlign: TextAlign.left,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.basicBlack,
                      fontSize: fontSize * 1.05,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (parentFolderName != null)
                    Text(
                      'Trong thư mục: $parentFolderName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.primaryBlue.withValues(alpha: 0.8),
                        fontSize: fontSize * 0.85,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Nút icon thông tin chữ "i" nằm đối diện tên tệp/thư mục
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                showItemActionsBottomSheet(
                  context: context,
                  tabIndex: widget.tabIndex,
                  item: item,
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.primaryBlue,
                  size: 23,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
