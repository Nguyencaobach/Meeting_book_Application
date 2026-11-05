import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/note4x.dart';
import '../core/constants/note5x.dart';
import '../core/theme/app_theme.dart';
import '../data/datasources/google_drive_datasource.dart';
import '../data/models/notebook_model.dart';
import '../features/notes/views/note_editor_screen.dart';
import 'center_notification_dialog.dart';

// ===========================================================================
// HỘP THOẠI TẠO FILE GHI CHÚ MỚI & CHỌN MẪU VỞ (NOTE5X / NOTE4X)
// Công dụng:
// - Hiển thị form nhập tên tệp ghi chú rộng rãi, tự co giãn theo kích thước màn hình.
// - Không sử dụng icon trang trí trong hộp thoại theo đúng yêu cầu trước đó.
// - Giới hạn tối đa 150 ký tự khi nhập tên tệp và kiểm tra chống trùng tên tệp.
// - Cho phép người dùng chọn mẫu định dạng vở:
//   + Vở 5 ô ly (note5x)
//   + Vở 4 ô ly (note4x)
// - Sau khi tạo thành công -> Hiện thông báo giữa màn hình và mở ngay giao diện
//   trang vở để render dữ liệu JSON.
// ===========================================================================
Future<void> showCreateNoteDialog({
  required BuildContext context,
  required Future<({DriveFolderItem fileItem, NotebookModel notebook})> Function(
    String fileName,
    String paperTemplate,
  ) onConfirmCreateNote,
}) async {
  final TextEditingController noteNameController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final String saveLocationLabel =
      GoogleDriveDatasource.instance.currentNotesPathLabel;

  // Mặc định chọn mẫu Vở 5 ô ly (note5x)
  String selectedTemplate = Note5x.templateId;
  bool isCreating = false;
  String? duplicateOrServerError;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final Size screenSize = MediaQuery.sizeOf(dialogContext);

      // Tự động co giãn kích thước hộp thoại theo màn hình
      final double dialogWidth = (screenSize.width * 0.74).clamp(340.0, 640.0);
      final double horizontalPadding =
          (screenSize.width * 0.045).clamp(24.0, 40.0);
      final double verticalPadding =
          (screenSize.height * 0.032).clamp(22.0, 36.0);

      // Cỡ chữ tự động co giãn theo màn hình
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
              final result = await onConfirmCreateNote(
                noteNameController.text.trim(),
                selectedTemplate,
              );

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Thành công',
                  message: 'Đã tạo tệp ghi chú thành công!',
                );
              }
              if (context.mounted) {
                // Mở ngay giao diện trang giấy để render dữ liệu JSON vừa tạo
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(
                      fileItem: result.fileItem,
                      initialNotebook: result.notebook,
                    ),
                  ),
                );
              }
            } on DuplicateDriveItemException catch (e) {
              setDialogState(() {
                isCreating = false;
                duplicateOrServerError = e.message;
              });
              formKey.currentState?.validate();
            } catch (_) {
              setDialogState(() {
                isCreating = false;
                duplicateOrServerError =
                    'Không thể tạo tệp trên Google Drive. Vui lòng kiểm tra kết nối mạng.';
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
              child: SingleChildScrollView(
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
                      // Hàng tiêu đề (Không sử dụng icon trang trí)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tạo tệp ghi chú mới',
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
                      SizedBox(height: verticalPadding * 0.35),

                      // Hiển thị vị trí lưu (Ngoài màn hình chính hoặc trong thư mục đã chọn)
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
                          'Vị trí lưu: $saveLocationLabel',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: subFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(height: verticalPadding * 0.6),

                      // Ô nhập tên tệp ghi chú (Giới hạn tối đa 150 ký tự)
                      TextFormField(
                        controller: noteNameController,
                        autofocus: true,
                        enabled: !isCreating,
                        maxLength: 150,
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
                            return 'Vui lòng nhập tên tệp ghi chú';
                          }
                          if (value.trim().length > 150) {
                            return 'Tên tệp ghi chú tối đa 150 ký tự';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Tên tệp ghi chú',
                          hintText: 'Ví dụ: Biên bản họp giao ban',
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
                      SizedBox(height: verticalPadding * 0.5),

                      // Phần chọn loại mẫu vở: note5x (Vở 5 ô ly) hoặc note4x (Vở 4 ô ly)
                      Text(
                        'Chọn loại mẫu vở:',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: inputFontSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTemplateChoiceButton(
                              title: Note5x.displayName,
                              subtitle: 'Khoảng cách dòng chuẩn 5 ô ly',
                              isSelected: selectedTemplate == Note5x.templateId,
                              titleSize: inputFontSize * 0.95,
                              subSize: subFontSize * 0.92,
                              onTap: isCreating
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        selectedTemplate = Note5x.templateId;
                                      });
                                    },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildTemplateChoiceButton(
                              title: Note4x.displayName,
                              subtitle: 'Khoảng cách dòng chuẩn 4 ô ly',
                              isSelected: selectedTemplate == Note4x.templateId,
                              titleSize: inputFontSize * 0.95,
                              subSize: subFontSize * 0.92,
                              onTap: isCreating
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        selectedTemplate = Note4x.templateId;
                                      });
                                    },
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: verticalPadding * 0.85),

                      // Hàng nút Hủy & Tạo ghi chú
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
                                    'Tạo tệp',
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

/// Nút chọn mẫu định dạng vở (note5x hoặc note4x) dùng màu theo Theme
Widget _buildTemplateChoiceButton({
  required String title,
  required String subtitle,
  required bool isSelected,
  required double titleSize,
  required double subSize,
  VoidCallback? onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryBlue : AppColors.creamBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryBlue,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: isSelected ? AppColors.basicWhite : AppColors.primaryBlue,
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: isSelected
                  ? AppColors.creamBackground
                  : AppColors.basicBlack.withValues(alpha: 0.7),
              fontSize: subSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
