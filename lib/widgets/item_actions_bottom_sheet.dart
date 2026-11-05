import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../data/datasources/google_drive_datasource.dart';
import 'center_notification_dialog.dart';

// ===========================================================================
// BOTTOM SHEET TÙY CHỌN THÔNG TIN TỆP / THƯ MỤC (KHI BẤM ICON CHỮ "i")
// Công dụng:
// - Sổ từ dưới lên với giao diện đồng bộ y hệt Bottom Sheet "Thêm mới".
// - Cung cấp 3 chức năng theo đúng yêu cầu:
//   1. Đổi tên
//   2. Xóa
//   3. Di chuyển
// ===========================================================================
void showItemActionsBottomSheet({
  required BuildContext context,
  required int tabIndex,
  required DriveFolderItem item,
}) {
  final String itemTypeLabel = item.isFolder ? 'Thư mục' : 'Tệp';

  showModalBottomSheet(
    context: context,
    enableDrag: true,
    isDismissible: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(
      minWidth: double.infinity,
      maxWidth: double.infinity,
    ),
    backgroundColor: AppColors.basicWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final double titleFontSize =
          AppTheme.getResponsiveFontSize(sheetContext, 16);
      final double actionFontSize =
          AppTheme.getResponsiveFontSize(sheetContext, 16);

      return LayoutBuilder(
        builder: (context, constraints) {
          final double horizontalPadding =
              (constraints.maxWidth * 0.05).clamp(16.0, 36.0);
          final double verticalPadding =
              (constraints.maxWidth * 0.03).clamp(12.0, 24.0);

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
                  // Thanh nắm kéo (Drag Handle) ở giữa giống Bottom Sheet tạo mới
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Hàng tiêu đề hiển thị tên Tệp/Thư mục kèm nút X bên phải
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$itemTypeLabel: ${item.displayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.basicBlack,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
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

                  // 1. Chức năng: Đổi tên
                  _buildActionSheetOption(
                    title: 'Đổi tên',
                    icon: Icons.drive_file_rename_outline_rounded,
                    fontSize: actionFontSize,
                    horizontalPadding: horizontalPadding,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showRenameItemDialog(
                        context: context,
                        tabIndex: tabIndex,
                        item: item,
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // 2. Chức năng: Xóa
                  _buildActionSheetOption(
                    title: 'Xóa',
                    icon: Icons.delete_outline_rounded,
                    fontSize: actionFontSize,
                    horizontalPadding: horizontalPadding,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showDeleteItemDialog(
                        context: context,
                        tabIndex: tabIndex,
                        item: item,
                      );
                    },
                  ),

                  const SizedBox(height: 12),

                  // 3. Chức năng: Di chuyển
                  _buildActionSheetOption(
                    title: 'Di chuyển',
                    icon: Icons.drive_file_move_outline,
                    fontSize: actionFontSize,
                    horizontalPadding: horizontalPadding,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _showMoveItemDialog(
                        context: context,
                        tabIndex: tabIndex,
                        item: item,
                      );
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

/// Dựng từng dòng chức năng trong Bottom Sheet giống hệt giao diện Tạo mới
Widget _buildActionSheetOption({
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
        color: AppColors.creamBackground,
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
              color: AppColors.primaryBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: AppColors.creamBackground,
              size: fontSize * 1.3,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: AppColors.basicBlack,
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

// ===========================================================================
// 1. HỘP THOẠI ĐỔI TÊN TỆP HOẶC THƯ MỤC (TỐI ĐA 150 KÝ TỰ, CHỐNG TRÙNG TÊN)
// ===========================================================================
Future<void> _showRenameItemDialog({
  required BuildContext context,
  required int tabIndex,
  required DriveFolderItem item,
}) async {
  final TextEditingController nameController =
      TextEditingController(text: item.displayName);
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final String itemLabel = item.isFolder ? 'thư mục' : 'tệp';

  bool isSubmitting = false;
  String? errorText;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);
      final double dialogWidth = (screenSize.width * 0.72).clamp(340.0, 620.0);
      final double horizontalPadding =
          (screenSize.width * 0.045).clamp(24.0, 40.0);
      final double verticalPadding =
          (screenSize.height * 0.035).clamp(24.0, 40.0);

      final double titleFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 19);
      final double inputFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 15);
      final double subFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 13);

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            setDialogState(() => errorText = null);
            if (!(formKey.currentState?.validate() ?? false)) {
              return;
            }

            setDialogState(() => isSubmitting = true);
            try {
              await GoogleDriveDatasource.instance.renameItemInTab(
                tabIndex: tabIndex,
                item: item,
                newName: nameController.text.trim(),
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Thành công',
                  message: 'Đã đổi tên thành công',
                );
              }
            } on DuplicateDriveItemException catch (e) {
              setDialogState(() {
                isSubmitting = false;
                errorText = e.message;
              });
              formKey.currentState?.validate();
            } catch (_) {
              setDialogState(() {
                isSubmitting = false;
                errorText =
                    'Không thể đổi tên $itemLabel. Vui lòng kiểm tra kết nối mạng.';
              });
              formKey.currentState?.validate();
            }
          }

          return Dialog(
            backgroundColor: AppColors.basicWhite,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Đổi tên $itemLabel',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            child: Text(
                              'X',
                              style: TextStyle(
                                color: AppColors.basicBlack,
                                fontSize: inputFontSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: verticalPadding * 0.5),
                      TextFormField(
                        controller: nameController,
                        autofocus: true,
                        enabled: !isSubmitting,
                        maxLength: 150,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        onChanged: (_) {
                          if (errorText != null) {
                            setDialogState(() => errorText = null);
                            formKey.currentState?.validate();
                          }
                        },
                        style: TextStyle(
                          color: AppColors.basicBlack,
                          fontSize: inputFontSize,
                        ),
                        validator: (value) {
                          if (errorText != null) {
                            return errorText;
                          }
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập tên $itemLabel';
                          }
                          if (value.trim().length > 150) {
                            return 'Tên $itemLabel tối đa 150 ký tự';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Tên $itemLabel mới',
                          labelStyle: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: inputFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                          errorStyle: TextStyle(
                            color: AppColors.paperMarginRed,
                            fontSize: subFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                          errorMaxLines: 2,
                          filled: true,
                          fillColor:
                              AppColors.creamBackground.withValues(alpha: 0.4),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 18,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColors.primaryBlue,
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColors.paperMarginRed,
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: AppColors.paperMarginRed,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: verticalPadding * 0.8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSubmitting
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                            child: Text(
                              'Hủy',
                              style: TextStyle(
                                color: AppColors.basicBlack,
                                fontSize: inputFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: isSubmitting ? null : submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: AppColors.basicWhite,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: AppColors.creamBackground,
                                    ),
                                  )
                                : Text(
                                    'Lưu tên mới',
                                    style: TextStyle(
                                      color: AppColors.basicWhite,
                                      fontSize: inputFontSize,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

// ===========================================================================
// 2. HỘP THOẠI XÁC NHẬN XÓA TỆP HOẶC THƯ MỤC (CÓ NÚT HOÀN TÁC TRONG THÔNG BÁO)
// ===========================================================================
Future<void> _showDeleteItemDialog({
  required BuildContext context,
  required int tabIndex,
  required DriveFolderItem item,
}) async {
  final String itemLabel = item.isFolder ? 'thư mục' : 'tệp';
  bool isDeleting = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);
      final double dialogWidth = (screenSize.width * 0.68).clamp(320.0, 540.0);
      final double horizontalPadding =
          (screenSize.width * 0.045).clamp(24.0, 36.0);
      final double verticalPadding =
          (screenSize.height * 0.032).clamp(22.0, 34.0);

      final double titleFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 19);
      final double bodyFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 15);

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> confirmDelete() async {
            setDialogState(() => isDeleting = true);
            try {
              await GoogleDriveDatasource.instance.deleteItemInTab(
                tabIndex: tabIndex,
                item: item,
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Thành công',
                  message: 'Đã xóa $itemLabel "${item.displayName}"',
                  onUndo: () =>
                      GoogleDriveDatasource.instance.restoreDeletedItemInTab(
                    tabIndex: tabIndex,
                    item: item,
                  ),
                );
              }
            } catch (_) {
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Thất bại',
                  message: 'Không thể xóa $itemLabel "${item.displayName}"',
                  isError: true,
                );
              }
            }
          }

          return Dialog(
            backgroundColor: AppColors.basicWhite,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xác nhận xóa $itemLabel',
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Bạn có chắc chắn muốn xóa $itemLabel "${item.displayName}" không?',
                      style: TextStyle(
                        color: AppColors.basicBlack,
                        fontSize: bodyFontSize,
                        height: 1.45,
                      ),
                    ),
                    SizedBox(height: verticalPadding * 0.85),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isDeleting
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          child: Text(
                            'Hủy',
                            style: TextStyle(
                              color: AppColors.basicBlack,
                              fontSize: bodyFontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: isDeleting ? null : confirmDelete,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.paperMarginRed,
                            foregroundColor: AppColors.basicWhite,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isDeleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.basicWhite,
                                  ),
                                )
                              : Text(
                                  'Xóa',
                                  style: TextStyle(
                                    color: AppColors.basicWhite,
                                    fontSize: bodyFontSize,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

// ===========================================================================
// 3. HỘP THOẠI DI CHUYỂN TỆP / THƯ MỤC DẠNG CÂY THƯ MỤC KIỂU GOOGLE DRIVE
// Công dụng:
// - Sổ ra một cây thư mục (Folder Tree) có mũi tên đóng/mở từng nhánh thư mục con.
// - Cho phép chuyển một Thư mục vào một Thư mục khác (nhiều cấp) hoặc chuyển Tệp
//   vào bất kỳ Thư mục nào trên cây.
// - Khi di chuyển thành công -> Hiển thị thông báo kèm nút "Hoàn tác" để khôi phục.
// ===========================================================================
Future<void> _showMoveItemDialog({
  required BuildContext context,
  required int tabIndex,
  required DriveFolderItem item,
}) async {
  final String itemLabel = item.isFolder ? 'thư mục' : 'tệp';
  bool isLoadingTree = true;
  bool isMoving = false;
  DriveFolderTreeNode? rootTreeNode;
  final Set<String> expandedFolderIds = <String>{};
  String? selectedTargetFolderId;
  String? selectedTargetFolderName;
  String? moveError;
  bool didLoadOnce = false;

  /// Thu thập toàn bộ ID thư mục có nhánh con trong cây (để Mở rộng tất cả / Thu gọn)
  void collectExpandableIds(DriveFolderTreeNode node, Set<String> targetSet) {
    if (node.children.isNotEmpty) {
      targetSet.add(node.folder.id);
      for (final child in node.children) {
        collectExpandableIds(child, targetSet);
      }
    }
  }

  /// Tìm thư mục hợp lệ đầu tiên trên cây (không phải là vị trí hiện tại) để gợi ý chọn sẵn
  DriveFolderItem? findFirstValidTarget(DriveFolderTreeNode node) {
    if (!node.isCurrentParent) {
      return node.folder;
    }
    for (final child in node.children) {
      final found = findFirstValidTarget(child);
      if (found != null) return found;
    }
    return null;
  }

  /// Đếm tổng số nút thư mục hợp lệ có thể chuyển đến trong toàn bộ cây
  int countAvailableTargetNodes(DriveFolderTreeNode node) {
    int count = node.isCurrentParent ? 0 : 1;
    for (final child in node.children) {
      count += countAvailableTargetNodes(child);
    }
    return count;
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);
      final double dialogWidth = (screenSize.width * 0.78).clamp(350.0, 660.0);
      final double horizontalPadding =
          (screenSize.width * 0.045).clamp(20.0, 36.0);
      final double verticalPadding =
          (screenSize.height * 0.032).clamp(20.0, 32.0);

      final double titleFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 19);
      final double itemFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 15);
      final double subFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 13);

      return StatefulBuilder(
        builder: (context, setDialogState) {
          if (!didLoadOnce) {
            didLoadOnce = true;
            GoogleDriveDatasource.instance
                .fetchFolderTreeForMove(
              tabIndex: tabIndex,
              itemToMove: item,
            )
                .then((treeRoot) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  rootTreeNode = treeRoot;
                  // Mặc định sổ (mở rộng) toàn bộ nhánh cây thư mục để người dùng nhìn thấy ngay
                  collectExpandableIds(treeRoot, expandedFolderIds);
                  final firstTarget = findFirstValidTarget(treeRoot);
                  selectedTargetFolderId = firstTarget?.id;
                  selectedTargetFolderName = firstTarget?.displayName;
                  isLoadingTree = false;
                });
              }
            }).catchError((_) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  isLoadingTree = false;
                  moveError = 'Không thể tải cây thư mục từ Google Drive.';
                });
              }
            });
          }

          Future<void> confirmMove() async {
            if (selectedTargetFolderId == null) return;
            final String targetId = selectedTargetFolderId!;
            final String targetName =
                selectedTargetFolderName ?? 'thư mục đã chọn';

            setDialogState(() {
              isMoving = true;
              moveError = null;
            });

            try {
              final String oldParentId =
                  await GoogleDriveDatasource.instance.moveItemInTab(
                tabIndex: tabIndex,
                item: item,
                targetFolderId: targetId,
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Thành công',
                  message:
                      'Đã chuyển "${item.displayName}" vào "$targetName"',
                  onUndo: () =>
                      GoogleDriveDatasource.instance.undoMoveItemInTab(
                    tabIndex: tabIndex,
                    item: item,
                    currentTargetFolderId: targetId,
                    previousParentId: oldParentId,
                  ),
                );
              }
            } on DuplicateDriveItemException catch (e) {
              setDialogState(() {
                isMoving = false;
                moveError = e.message;
              });
            } catch (_) {
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Thất bại',
                  message: 'Không thể di chuyển $itemLabel',
                  isError: true,
                );
              }
            }
          }

          /// Hàm đệ quy dựng giao diện từng nhánh trên Cây thư mục (Folder Tree) kiểu Google Drive
          List<Widget> buildFolderTreeWidgets(
            DriveFolderTreeNode node, {
            required int depth,
          }) {
            final bool hasChildren = node.children.isNotEmpty;
            final bool isExpanded = expandedFolderIds.contains(node.folder.id);
            final bool isSelected = selectedTargetFolderId == node.folder.id;
            final bool isRoot = depth == 0;
            final double leftIndent = (depth * 22.0).clamp(0.0, 132.0);

            final List<Widget> widgets = <Widget>[
              Padding(
                padding: EdgeInsets.only(left: leftIndent, bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: isMoving
                      ? null
                      : () {
                          setDialogState(() {
                            if (!node.isCurrentParent) {
                              selectedTargetFolderId = node.folder.id;
                              selectedTargetFolderName =
                                  node.folder.displayName;
                              moveError = null;
                            }
                            // Nếu nhánh này có thư mục con và đang đóng -> Tự sổ ra khi bấm vào
                            if (hasChildren && !isExpanded) {
                              expandedFolderIds.add(node.folder.id);
                            }
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryBlue
                          : (node.isCurrentParent
                              ? AppColors.creamBackground.withValues(alpha: 0.45)
                              : AppColors.creamBackground),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryBlue
                            : AppColors.primaryBlue.withValues(
                                alpha: node.isCurrentParent ? 0.22 : 0.45,
                              ),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Nút mũi tên Sổ xuống / Thu gọn nhánh thư mục con (giống Google Drive)
                        if (hasChildren)
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: isMoving
                                ? null
                                : () {
                                    setDialogState(() {
                                      if (isExpanded) {
                                        expandedFolderIds
                                            .remove(node.folder.id);
                                      } else {
                                        expandedFolderIds.add(node.folder.id);
                                      }
                                    });
                                  },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.basicWhite.withValues(alpha: 0.18)
                                    : AppColors.primaryBlue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_down_rounded
                                    : Icons.keyboard_arrow_right_rounded,
                                size: 20,
                                color: isSelected
                                    ? AppColors.creamBackground
                                    : AppColors.primaryBlue,
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: 28,
                            child: Icon(
                              Icons.subdirectory_arrow_right_rounded,
                              size: 16,
                              color: isSelected
                                  ? AppColors.creamBackground
                                      .withValues(alpha: 0.7)
                                  : AppColors.primaryBlue
                                      .withValues(alpha: 0.45),
                            ),
                          ),
                        const SizedBox(width: 8),

                        // Icon thư mục (Thư mục gốc hoặc Thư mục con)
                        Icon(
                          isRoot
                              ? Icons.cloud_done_rounded
                              : (isExpanded && hasChildren
                                  ? Icons.folder_open_rounded
                                  : Icons.folder_rounded),
                          color: isSelected
                              ? AppColors.creamBackground
                              : AppColors.primaryBlue,
                          size: 23,
                        ),
                        const SizedBox(width: 10),

                        // Tên thư mục trên cây
                        Expanded(
                          child: Text(
                            node.folder.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.basicWhite
                                  : (node.isCurrentParent
                                      ? AppColors.basicBlack
                                          .withValues(alpha: 0.55)
                                      : AppColors.basicBlack),
                              fontSize: itemFontSize,
                              fontWeight: isSelected || isRoot
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),

                        // Nhãn báo vị trí hiện tại hoặc số thư mục con hoặc dấu tích chọn
                        if (node.isCurrentParent)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Hiện tại',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: subFontSize * 0.88,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else if (isSelected)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.creamBackground,
                              size: 20,
                            ),
                          )
                        else if (hasChildren)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${node.children.length}',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: subFontSize * 0.85,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ];

            // Nếu nhánh đang mở rộng -> Đệ quy hiển thị danh sách thư mục con bên dưới
            if (hasChildren && isExpanded) {
              for (final child in node.children) {
                widgets.addAll(
                  buildFolderTreeWidgets(child, depth: depth + 1),
                );
              }
            }

            return widgets;
          }

          final int validTargetCount = rootTreeNode == null
              ? 0
              : countAvailableTargetNodes(rootTreeNode!);

          return Dialog(
            backgroundColor: AppColors.basicWhite,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hàng tiêu đề hộp thoại Di chuyển
                    Row(
                      children: [
                        const Icon(
                          Icons.account_tree_rounded,
                          color: AppColors.primaryBlue,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Di chuyển $itemLabel "${item.displayName}"',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: isMoving
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          child: Text(
                            'X',
                            style: TextStyle(
                              color: AppColors.basicBlack,
                              fontSize: itemFontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Thanh hướng dẫn + nút Sổ hết / Thu gọn cây thư mục
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Chọn thư mục đích trên cây thư mục Google Drive:',
                            style: TextStyle(
                              color:
                                  AppColors.basicBlack.withValues(alpha: 0.75),
                              fontSize: subFontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!isLoadingTree &&
                            rootTreeNode != null &&
                            rootTreeNode!.children.isNotEmpty)
                          TextButton.icon(
                            onPressed: isMoving
                                ? null
                                : () {
                                    setDialogState(() {
                                      final Set<String> allIds = <String>{};
                                      collectExpandableIds(
                                        rootTreeNode!,
                                        allIds,
                                      );
                                      if (expandedFolderIds.length >=
                                          allIds.length) {
                                        expandedFolderIds
                                          ..clear()
                                          ..add(rootTreeNode!.folder.id);
                                      } else {
                                        expandedFolderIds.addAll(allIds);
                                      }
                                    });
                                  },
                            icon: const Icon(
                              Icons.unfold_more_rounded,
                              size: 16,
                              color: AppColors.primaryBlue,
                            ),
                            label: Text(
                              'Đóng/Mở cây',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: subFontSize * 0.92,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Khu vực hiển thị Cây thư mục (Folder Tree)
                    if (isLoadingTree)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      )
                    else if (rootTreeNode == null || validTargetCount == 0)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.creamBackground,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Chưa có thư mục nào khác để chuyển đến.\nHãy tạo thêm thư mục mới trước.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.basicBlack,
                            fontSize: itemFontSize,
                            height: 1.4,
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              (screenSize.height * 0.46).clamp(200.0, 360.0),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.basicWhite,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Scrollbar(
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(right: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: buildFolderTreeWidgets(
                                  rootTreeNode!,
                                  depth: 0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Hiển thị vị trí đích đang chọn
                    if (!isLoadingTree &&
                        selectedTargetFolderName != null &&
                        validTargetCount > 0) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.drive_file_move_rounded,
                            color: AppColors.primaryBlue,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Chuyển đến: $selectedTargetFolderName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: subFontSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (moveError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        moveError!,
                        style: TextStyle(
                          color: AppColors.paperMarginRed,
                          fontSize: subFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    SizedBox(height: verticalPadding * 0.75),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isMoving
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          child: Text(
                            'Hủy',
                            style: TextStyle(
                              color: AppColors.basicBlack,
                              fontSize: itemFontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: (isMoving ||
                                  isLoadingTree ||
                                  selectedTargetFolderId == null ||
                                  validTargetCount == 0)
                              ? null
                              : confirmMove,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: AppColors.basicWhite,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: isMoving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.creamBackground,
                                  ),
                                )
                              : const Icon(
                                  Icons.drive_file_move_rounded,
                                  color: AppColors.creamBackground,
                                  size: 20,
                                ),
                          label: Text(
                            'Di chuyển đến đây',
                            style: TextStyle(
                              color: AppColors.basicWhite,
                              fontSize: itemFontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
