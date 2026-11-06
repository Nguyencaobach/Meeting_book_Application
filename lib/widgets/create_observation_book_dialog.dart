import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/observation_templates/primary_school_evaluation_template.dart';
import '../core/theme/app_theme.dart';
import '../data/datasources/google_drive_datasource.dart';
import '../data/models/notebook_model.dart';
import '../features/notes/views/note_editor_screen.dart';
import 'center_notification_dialog.dart';

// ===========================================================================
// HỘP THOẠI TẠO SỔ DỰ GIỜ MỚI & CHỌN BIỂU MẪU THEO DẠNG DANH SÁCH
// Công dụng:
// - Hiển thị form nhập tên tệp sổ dự giờ rộng rãi, tự co giãn theo kích thước màn hình.
// - Giới hạn tối đa 150 ký tự khi nhập tên tệp và kiểm tra chống trùng tên tệp.
// - Hiển thị danh sách các biểu mẫu Sổ dự giờ (từ thư mục `observation_templates`)
//   theo dạng Danh sách (List) kèm tên biểu mẫu để người dùng bấm chọn.
// - Sau khi tạo thành công -> Hiện thông báo giữa màn hình và mở ngay giao diện
//   trang biểu mẫu để render dữ liệu JSON.
// ===========================================================================
Future<void> showCreateObservationBookDialog({
  required BuildContext context,
  required Future<({DriveFolderItem fileItem, NotebookModel notebook})> Function(
    String fileName,
    String paperTemplate,
  ) onConfirmCreateObservationBook,
}) async {
  final TextEditingController bookNameController = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final String saveLocationLabel =
      GoogleDriveDatasource.instance.currentObservationPathLabel;

  final List<ObservationTemplateItem> templates =
      PrimarySchoolEvaluationTemplate.availableTemplates;

  // Mặc định chọn biểu mẫu đầu tiên trong danh sách
  String selectedTemplateId = templates.isNotEmpty
      ? templates.first.id
      : PrimarySchoolEvaluationTemplate.templateId;
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
              final result = await onConfirmCreateObservationBook(
                bookNameController.text.trim(),
                selectedTemplateId,
              );

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              if (context.mounted) {
                await showCenterNotification(
                  context: context,
                  title: 'Thành công',
                  message: 'Đã tạo sổ dự giờ thành công!',
                );
              }
              if (context.mounted) {
                // Mở ngay giao diện trang biểu mẫu để render dữ liệu JSON vừa tạo
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(
                      fileItem: result.fileItem,
                      initialNotebook: result.notebook,
                      tabIndex: 1,
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
                      // Hàng tiêu đề
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tạo sổ dự giờ mới',
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

                      // Ô nhập tên tệp sổ dự giờ (Giới hạn tối đa 150 ký tự)
                      TextFormField(
                        controller: bookNameController,
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
                            return 'Vui lòng nhập tên sổ dự giờ';
                          }
                          if (value.trim().length > 150) {
                            return 'Tên sổ dự giờ tối đa 150 ký tự';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Tên tệp sổ dự giờ',
                          hintText: 'Ví dụ: Dự giờ môn Toán - Lớp 5A',
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

                      // Phần chọn biểu mẫu Sổ dự giờ hiển thị theo dạng Danh sách (List) với tên biểu mẫu
                      Text(
                        'Chọn biểu mẫu sổ dự giờ:',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: inputFontSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              (screenSize.height * 0.34).clamp(130.0, 260.0),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: templates.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final ObservationTemplateItem template =
                                templates[index];
                            final bool isSelected =
                                template.id == selectedTemplateId;

                            return _buildObservationTemplateListItem(
                              template: template,
                              isSelected: isSelected,
                              titleSize: inputFontSize,
                              subSize: subFontSize,
                              onTap: isCreating
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        selectedTemplateId = template.id;
                                      });
                                    },
                            );
                          },
                        ),
                      ),

                      SizedBox(height: verticalPadding * 0.85),

                      // Hàng nút Hủy & Tạo tệp
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

/// Từng dòng biểu mẫu trong Danh sách chọn biểu mẫu Sổ dự giờ (hiển thị tên biểu mẫu rõ ràng)
Widget _buildObservationTemplateListItem({
  required ObservationTemplateItem template,
  required bool isSelected,
  required double titleSize,
  required double subSize,
  VoidCallback? onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryBlue : AppColors.creamBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryBlue,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSelected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color:
                isSelected ? AppColors.creamBackground : AppColors.primaryBlue,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  template.name,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.basicWhite
                        : AppColors.basicBlack,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (template.description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    template.description,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.creamBackground.withValues(alpha: 0.9)
                          : AppColors.basicBlack.withValues(alpha: 0.68),
                      fontSize: subSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
