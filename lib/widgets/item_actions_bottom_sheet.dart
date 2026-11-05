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
// 2. HỘP THOẠI XÁC NHẬN XÓA TỆP HOẶC THƯ MỤC
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
                  message: 'Đã xóa thành công',
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
                  message: 'Không thể xóa',
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
// 3. HỘP THOẠI CHỌN THƯ MỤC ĐÍCH ĐỂ DI CHUYỂN TỆP HOẶC THƯ MỤC
// ===========================================================================
Future<void> _showMoveItemDialog({
  required BuildContext context,
  required int tabIndex,
  required DriveFolderItem item,
}) async {
  final String itemLabel = item.isFolder ? 'thư mục' : 'tệp';
  bool isLoadingTargets = true;
  bool isMoving = false;
  List<DriveFolderItem> targetFolders = <DriveFolderItem>[];
  String? selectedTargetFolderId;
  String? moveError;
  bool didLoadOnce = false;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);
      final double dialogWidth = (screenSize.width * 0.74).clamp(340.0, 620.0);
      final double horizontalPadding =
          (screenSize.width * 0.045).clamp(24.0, 40.0);
      final double verticalPadding =
          (screenSize.height * 0.032).clamp(22.0, 36.0);

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
                .fetchAvailableMoveFolders(
              tabIndex: tabIndex,
              itemToMove: item,
            )
                .then((folders) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  targetFolders = folders;
                  selectedTargetFolderId =
                      folders.isNotEmpty ? folders.first.id : null;
                  isLoadingTargets = false;
                });
              }
            }).catchError((_) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  isLoadingTargets = false;
                  moveError = 'Không thể tải danh sách thư mục đích.';
                });
              }
            });
          }

          Future<void> confirmMove() async {
            if (selectedTargetFolderId == null) return;
            setDialogState(() {
              isMoving = true;
              moveError = null;
            });

            try {
              await GoogleDriveDatasource.instance.moveItemInTab(
                tabIndex: tabIndex,
                item: item,
                targetFolderId: selectedTargetFolderId!,
              );
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Thành công',
                  message: 'Đã di chuyển thành công',
                );
              }
            } on DuplicateDriveItemException catch (e) {
              setDialogState(() {
                isMoving = false;
                moveError = e.message;
              });
            } catch (_) {
              setDialogState(() {
                isMoving = false;
                moveError =
                    'Không thể di chuyển $itemLabel. Vui lòng kiểm tra kết nối mạng.';
              });
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Di chuyển "${item.displayName}"',
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
                    const SizedBox(height: 12),
                    Text(
                      'Chọn vị trí thư mục muốn chuyển đến:',
                      style: TextStyle(
                        color: AppColors.basicBlack.withValues(alpha: 0.75),
                        fontSize: subFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isLoadingTargets)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      )
                    else if (targetFolders.isEmpty)
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
                              (screenSize.height * 0.42).clamp(180.0, 320.0),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: targetFolders.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final folder = targetFolders[index];
                            final bool isSelected =
                                folder.id == selectedTargetFolderId;

                            return InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: isMoving
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        selectedTargetFolderId = folder.id;
                                        moveError = null;
                                      });
                                    },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primaryBlue
                                      : AppColors.creamBackground,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.primaryBlue,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.folder_rounded,
                                      color: isSelected
                                          ? AppColors.creamBackground
                                          : AppColors.primaryBlue,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        folder.displayName,
                                        style: TextStyle(
                                          color: isSelected
                                              ? AppColors.basicWhite
                                              : AppColors.basicBlack,
                                          fontSize: itemFontSize,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (moveError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        moveError!,
                        style: TextStyle(
                          color: AppColors.paperMarginRed,
                          fontSize: subFontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    SizedBox(height: verticalPadding * 0.8),
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
                        ElevatedButton(
                          onPressed: (isMoving ||
                                  isLoadingTargets ||
                                  selectedTargetFolderId == null)
                              ? null
                              : confirmMove,
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
                          child: isMoving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.creamBackground,
                                  ),
                                )
                              : Text(
                                  'Di chuyển',
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
