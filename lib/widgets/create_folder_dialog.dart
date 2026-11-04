import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../data/datasources/google_drive_datasource.dart';
import 'center_notification_dialog.dart';

// ===========================================================================
// HỘP THOẠI NHẬP TÊN THƯ MỤC MỚI & TẠO TRÊN GOOGLE DRIVE
// Công dụng:
// - Hiển thị form nhập tên thư mục rộng rãi, tự co giãn theo kích thước màn hình.
// - Không sử dụng icon trang trí theo yêu cầu, chỉ giữ chữ và ô nhập tối giản.
// - Kiểm tra tên thư mục không được để trống và CHỐNG TRÙNG TÊN ngay trong ô nhập.
// ===========================================================================
Future<void> showCreateFolderDialog({
  required BuildContext context,
  required int currentTabIndex,
  required Future<void> Function(String folderName) onConfirmCreate,
}) async {
  final TextEditingController folderNameController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final String tabFolderLabel =
      currentTabIndex == 0 ? 'MeetingBook / Ghi_Chu' : 'MeetingBook / So_Du_Gio';

  bool isCreating = false;
  String? duplicateOrServerError;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);

      // Tự động co giãn chiều rộng và chiều cao rộng rãi theo kích thước màn hình
      final double dialogWidth = (screenSize.width * 0.72).clamp(340.0, 620.0);
      final double horizontalPadding =
          (screenSize.width * 0.045).clamp(24.0, 40.0);
      final double verticalPadding =
          (screenSize.height * 0.035).clamp(24.0, 40.0);

      // Gọi hàm tự động co giãn cỡ chữ theo kích thước màn hình
      final double titleFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 19);
      final double inputFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 15);
      final double subFontSize =
          AppTheme.getResponsiveFontSize(dialogContext, 13);

      return StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            setDialogState(() => duplicateOrServerError = null);
            if (!(formKey.currentState?.validate() ?? false)) {
              return;
            }

            setDialogState(() => isCreating = true);
            try {
              await onConfirmCreate(folderNameController.text.trim());
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Tạo mới thành công',
                  message:
                      'Đã tạo thư mục "${folderNameController.text.trim()}" thành công!',
                );
              }
            } on DuplicateDriveItemException catch (e) {
              // Nếu trùng tên thư mục -> Hiển thị lỗi trực tiếp ngay trong ô nhập
              setDialogState(() {
                isCreating = false;
                duplicateOrServerError = e.message;
              });
              formKey.currentState?.validate();
            } catch (_) {
              setDialogState(() {
                isCreating = false;
                duplicateOrServerError =
                    'Không thể tạo thư mục trên Google Drive. Vui lòng kiểm tra kết nối mạng.';
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
                      // Hàng tiêu đề (Không dùng icon)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Thêm thư mục mới',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: isCreating
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
                      SizedBox(height: verticalPadding * 0.4),

                      // Hiển thị đường dẫn nơi thư mục sẽ được lưu trên Google Drive
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.creamBackground,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          'Vị trí lưu: $tabFolderLabel',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: subFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(height: verticalPadding * 0.7),

                      // Ô nhập tên thư mục (Giới hạn tối đa 150 ký tự, kiểm tra trống & báo lỗi trùng tên trực tiếp dưới ô nhập)
                      TextFormField(
                        controller: folderNameController,
                        autofocus: true,
                        enabled: !isCreating,
                        maxLength: 150, // Giới hạn tối đa 150 ký tự khi nhập tên
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => submit(),
                        onChanged: (_) {
                          if (duplicateOrServerError != null) {
                            setDialogState(() => duplicateOrServerError = null);
                            formKey.currentState?.validate();
                          }
                        },
                        style: TextStyle(
                          color: AppColors.basicBlack,
                          fontSize: inputFontSize,
                        ),
                        validator: (value) {
                          if (duplicateOrServerError != null) {
                            return duplicateOrServerError;
                          }
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập tên thư mục';
                          }
                          if (value.trim().length > 150) {
                            return 'Tên thư mục tối đa 150 ký tự';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Tên thư mục',
                          hintText: currentTabIndex == 0
                              ? 'Ví dụ: Thư mục Họp tuần'
                              : 'Ví dụ: Học kỳ 1',
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

                      SizedBox(height: verticalPadding * 0.9),

                      // Hàng nút Hủy & Tạo thư mục
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isCreating
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
                            onPressed: isCreating ? null : submit,
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
                            child: isCreating
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: AppColors.creamBackground,
                                    ),
                                  )
                                : Text(
                                    'Tạo thư mục',
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
