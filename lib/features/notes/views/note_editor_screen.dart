import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/note4x.dart';
import '../../../core/constants/note5x.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../../data/models/line_model.dart';
import '../../../data/models/notebook_model.dart';
import '../../../data/models/page_model.dart';
import '../../../data/repositories/data_sync_repository.dart';
import '../../../widgets/center_notification_dialog.dart';

// ===========================================================================
// MÀN HÌNH GIAO DIỆN TRANG VỞ RENDER DỮ LIỆU JSON (NOTE EDITOR SCREEN)
// Công dụng:
// - Nhận thông tin file ghi chú (DriveFolderItem) hoặc dữ liệu JSON (NotebookModel).
// - Tự động kiểm tra loại mẫu vở trong JSON ('note5x' cho vở 5 ô ly hoặc 'note4x' cho vở 4 ô ly)
//   để vẽ các ĐƯỜNG KẺ NGANG (không vẽ đường dọc) với khoảng cách dòng tự động giãn đầy đủ.
// - Render từng dòng dữ liệu JSON (rowIndex, text) lên đúng vị trí dòng kẻ ngang tương ứng.
// - Khi người dùng viết/chỉnh sửa trên từng dòng:
//   + Lưu tức thì vào RAM (0ms) và tự động kích hoạt bộ đếm 30 giây đẩy JSON lên Google Drive.
//   + Khi bấm Quay lại (thoát màn hình): Tự động đồng bộ JSON mới nhất lên Google Drive.
// ===========================================================================
class NoteEditorScreen extends StatefulWidget {
  final DriveFolderItem fileItem;
  final NotebookModel? initialNotebook;

  const NoteEditorScreen({
    super.key,
    required this.fileItem,
    this.initialNotebook,
  });

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final GoogleDriveDatasource _driveDatasource = GoogleDriveDatasource.instance;
  final DataSyncRepository _syncRepository = DataSyncRepository.instance;
  final ScrollController _scrollController = ScrollController();

  NotebookModel? _notebook;
  bool _isLoadingJson = true;
  String? _loadError;

  // Quản lý các TextEditingController và FocusNode theo từng dòng (rowIndex)
  final Map<int, TextEditingController> _rowControllers =
      <int, TextEditingController>{};
  final Map<int, FocusNode> _rowFocusNodes = <int, FocusNode>{};

  // Chỉ số trang hiện tại (mặc định trang 0 -> pageNumber = 1)
  final int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadAndPrepareNotebookJson();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _rowControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _rowFocusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  // ===========================================================================
  // 1. HÀM TẢI DỮ LIỆU JSON TỪ GOOGLE DRIVE / RAM VÀ ĐỔ VÀO CÁC DÒNG TRÊN VỞ
  // ===========================================================================
  Future<void> _loadAndPrepareNotebookJson() async {
    setState(() {
      _isLoadingJson = true;
      _loadError = null;
    });

    try {
      final NotebookModel loadedNotebook = widget.initialNotebook ??
          await _driveDatasource.loadNoteJsonFile(widget.fileItem);

      _applyNotebookToRowControllers(loadedNotebook, pageIndex: 0);

      if (mounted) {
        setState(() {
          _notebook = loadedNotebook;
          _isLoadingJson = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingJson = false;
          _loadError =
              'Không thể tải dữ liệu JSON của tệp ghi chú. Vui lòng kiểm tra kết nối mạng.';
        });
      }
    }
  }

  /// Đồng bộ dữ liệu mảng `lines` từ JSON vào các ô dòng viết theo đúng `rowIndex`
  void _applyNotebookToRowControllers(
    NotebookModel notebook, {
    required int pageIndex,
  }) {
    for (final controller in _rowControllers.values) {
      controller.clear();
    }

    if (notebook.pages.isEmpty) return;
    final int safeIndex = pageIndex.clamp(0, notebook.pages.length - 1);
    final PageModel page = notebook.pages[safeIndex];

    for (final LineModel line in page.lines) {
      final controller = _getOrCreateRowController(line.rowIndex);
      controller.text = line.text;
    }
  }

  /// Lấy hoặc khởi tạo TextEditingController cho dòng thứ `rowIndex`
  TextEditingController _getOrCreateRowController(int rowIndex) {
    return _rowControllers.putIfAbsent(
      rowIndex,
      () => TextEditingController(),
    );
  }

  /// Lấy hoặc khởi tạo FocusNode cho dòng thứ `rowIndex`
  FocusNode _getOrCreateRowFocusNode(int rowIndex) {
    return _rowFocusNodes.putIfAbsent(
      rowIndex,
      () => FocusNode(),
    );
  }

  // ===========================================================================
  // 2. HÀM CẬP NHẬT DỮ LIỆU TỪNG DÒNG VÀO GÓI JSON & ĐỒNG BỘ LÊN SERVER (DRIVE)
  // ===========================================================================
  void _onRowTextChanged(int rowIndex, String newText) {
    final NotebookModel? currentNotebook = _notebook;
    if (currentNotebook == null) return;

    // Gom tất cả các dòng có nội dung chữ trên trang hiện tại thành mảng JSON `lines`
    final List<LineModel> updatedLines = <LineModel>[];
    final List<int> sortedRowIndices = _rowControllers.keys.toList()..sort();

    for (final int idx in sortedRowIndices) {
      final String textValue =
          idx == rowIndex ? newText : (_rowControllers[idx]?.text ?? '');
      if (textValue.trim().isNotEmpty) {
        updatedLines.add(
          LineModel(
            rowIndex: idx,
            text: textValue,
          ),
        );
      }
    }

    final List<PageModel> updatedPages =
        List<PageModel>.from(currentNotebook.pages);
    if (updatedPages.isEmpty) {
      updatedPages.add(PageModel(pageNumber: 1, lines: updatedLines));
    } else {
      updatedPages[_currentPageIndex] =
          updatedPages[_currentPageIndex].copyWith(lines: updatedLines);
    }

    final NotebookModel updatedNotebook = currentNotebook.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
      pages: updatedPages,
    );

    _notebook = updatedNotebook;

    // Lưu tức thì vào RAM (0ms) và đặt bộ đếm 30 giây tự động ghi đè JSON lên Google Drive
    _syncRepository.onUserWritingChanged(
      documentId: widget.fileItem.id,
      fileName: widget.fileItem.displayName,
      tabIndex: 0,
      parentFolderId: widget.fileItem.parentFolderId,
      existingDriveFileId: widget.fileItem.id,
      updatedJsonData: updatedNotebook.toJson(),
    );
  }

  /// Hàm xử lý khi người dùng bấm nút Quay lại (Thoát trang -> đẩy ngay JSON lên Drive)
  Future<void> _handleExitEditor() async {
    await _syncRepository.syncOnPageExit();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Hàm lưu ngay lập tức gói JSON lên Google Drive khi người dùng bấm nút Lưu
  Future<void> _handleManualSaveNow() async {
    try {
      await _syncRepository.syncOnPageExit();
      if (mounted) {
        await showCenterNotification(
          context: context,
          title: 'Lưu thành công',
          message: 'Đã lưu dữ liệu JSON lên Google Drive',
        );
      }
    } catch (_) {
      if (mounted) {
        await showCenterNotification(
          context: context,
          title: 'Lưu thất bại',
          message: 'Không thể lưu tệp',
          isError: true,
        );
      }
    }
  }

  // ===========================================================================
  // 3. HỘP THOẠI XEM CẤU TRÚC DỮ LIỆU JSON ĐANG RENDER TRỰC TIẾP
  // ===========================================================================
  void _showJsonPreviewDialog() {
    if (_notebook == null) return;
    final String prettyJson =
        const JsonEncoder.withIndent('  ').convert(_notebook!.toJson());

    showDialog(
      context: context,
      builder: (dialogContext) {
        final Size screenSize = MediaQuery.sizeOf(dialogContext);
        final double titleSize =
            AppTheme.getResponsiveFontSize(dialogContext, 17);
        final double codeSize =
            AppTheme.getResponsiveFontSize(dialogContext, 13);

        return Dialog(
          backgroundColor: AppColors.basicWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (screenSize.width * 0.78).clamp(320.0, 680.0),
              maxHeight: (screenSize.height * 0.75).clamp(300.0, 640.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Dữ liệu JSON của tệp (${_notebook!.paperTemplate})',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(
                          'Đóng',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: codeSize * 1.05,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.creamBackground,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.25),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          prettyJson,
                          style: TextStyle(
                            color: AppColors.basicBlack,
                            fontSize: codeSize,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String activeTemplate =
        _notebook?.paperTemplate ?? widget.fileItem.paperTemplate;
    final bool isNote4x = activeTemplate == Note4x.templateId;
    final String templateLabel =
        isNote4x ? Note4x.displayName : Note5x.displayName;

    final double titleFontSize = AppTheme.getResponsiveFontSize(context, 16);
    final double badgeFontSize = AppTheme.getResponsiveFontSize(context, 12);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleExitEditor();
      },
      child: Scaffold(
        backgroundColor: isNote4x
            ? Note4x.getPaperBackgroundColor()
            : Note5x.getPaperBackgroundColor(),
        body: Column(
          children: [
            // 1. Thanh tiêu đề trên cùng đồng bộ màu xanh chủ đạo Theme (#263BAA)
            Container(
              width: double.infinity,
              color: AppColors.primaryBlue,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      // Nút Quay lại (Tự động lưu JSON trước khi thoát)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _handleExitEditor,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.basicWhite.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.arrow_back_rounded,
                                color: AppColors.basicWhite,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Quay lại',
                                style: TextStyle(
                                  color: AppColors.basicWhite,
                                  fontSize: badgeFontSize * 1.05,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Tên tệp ghi chú và nhãn loại vở (note5x / note4x)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _notebook?.title ?? widget.fileItem.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.basicWhite,
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              templateLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.creamBackground,
                                fontSize: badgeFontSize,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Nút xem dữ liệu JSON trực tiếp
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: _showJsonPreviewDialog,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.creamBackground,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            'JSON',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontSize: badgeFontSize,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Nút Lưu JSON ngay lập tức & trạng thái đồng bộ
                      ValueListenableBuilder<bool>(
                        valueListenable: _syncRepository.isSyncingDriveNotifier,
                        builder: (context, isSyncing, _) {
                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: isSyncing ? null : _handleManualSaveNow,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.basicWhite,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSyncing)
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primaryBlue,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.cloud_done_outlined,
                                      color: AppColors.primaryBlue,
                                      size: 17,
                                    ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isSyncing ? 'Đang lưu...' : 'Lưu',
                                    style: TextStyle(
                                      color: AppColors.primaryBlue,
                                      fontSize: badgeFontSize,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 2. Vùng thân: Mặt giấy kẻ ngang (note5x hoặc note4x) tự động giãn đầy đủ & render JSON
            Expanded(
              child: _buildPaperBody(isNote4x: isNote4x),
            ),
          ],
        ),
      ),
    );
  }

  /// Xây dựng mặt giấy kẻ ngang tự động co giãn theo loại vở (`note5x` hoặc `note4x`)
  Widget _buildPaperBody({required bool isNote4x}) {
    if (_isLoadingJson) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primaryBlue,
        ),
      );
    }

    if (_loadError != null) {
      final double errSize = AppTheme.getResponsiveFontSize(context, 15);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.basicBlack,
                  fontSize: errSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAndPrepareNotebookJson,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.basicWhite,
                ),
                child: const Text('Thử tải lại'),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Tính chiều cao mỗi dòng kẻ ngang dựa trên mẫu vở 5 ô ly (note5x) hoặc 4 ô ly (note4x)
        final double rowHeight = isNote4x
            ? Note4x.getResponsiveRowHeight(
                context,
                maxWidth: constraints.maxWidth,
              )
            : Note5x.getResponsiveRowHeight(
                context,
                maxWidth: constraints.maxWidth,
              );

        final double horizontalPadding = isNote4x
            ? Note4x.getResponsiveHorizontalPadding(constraints.maxWidth)
            : Note5x.getResponsiveHorizontalPadding(constraints.maxWidth);

        // Tính tổng số dòng sao cho luôn phủ kín 100% chiều dọc màn hình và tự giãn thêm khi viết dài
        final int minRowsToFillScreen =
            (constraints.maxHeight / rowHeight).ceil() + 2;
        final int defaultMinRows =
            isNote4x ? Note4x.defaultLineCount : Note5x.defaultLineCount;
        final int highestUsedRow = _rowControllers.keys.isEmpty
            ? 0
            : (_rowControllers.keys.reduce(math.max) + 6);
        final int totalRows = math.max(
          math.max(minRowsToFillScreen, defaultMinRows),
          highestUsedRow,
        );

        // Cỡ chữ tự động co giãn vừa khít với khoảng cách dòng 5 ô ly hoặc 4 ô ly
        final double lineFontSize = (rowHeight * 0.42).clamp(15.0, 22.0);
        final double totalPaperHeight = totalRows * rowHeight;

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            child: SizedBox(
              width: constraints.maxWidth,
              height: totalPaperHeight,
              child: CustomPaint(
                // Chỉ vẽ các đường kẻ ngang theo đúng mẫu note5x hoặc note4x
                painter: isNote4x
                    ? Note4xHorizontalPaperPainter(
                        rowHeight: rowHeight,
                        totalRows: totalRows,
                      )
                    : Note5xHorizontalPaperPainter(
                        rowHeight: rowHeight,
                        totalRows: totalRows,
                      ),
                child: Column(
                  children: List<Widget>.generate(totalRows, (int rowIndex) {
                    final TextEditingController controller =
                        _getOrCreateRowController(rowIndex);
                    final FocusNode focusNode =
                        _getOrCreateRowFocusNode(rowIndex);

                    return SizedBox(
                      width: constraints.maxWidth,
                      height: rowHeight,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            maxLines: 1,
                            textInputAction: TextInputAction.next,
                            onChanged: (value) =>
                                _onRowTextChanged(rowIndex, value),
                            onSubmitted: (_) {
                              // Khi bấm Enter -> Tự động xuống dòng kẻ ngang tiếp theo (rowIndex + 1)
                              final FocusNode nextFocus =
                                  _getOrCreateRowFocusNode(rowIndex + 1);
                              setState(() {});
                              nextFocus.requestFocus();
                            },
                            style: TextStyle(
                              color: isNote4x
                                  ? Note4x.getTextColor()
                                  : Note5x.getTextColor(),
                              fontSize: lineFontSize,
                              fontWeight: FontWeight.w500,
                              height: 1.15,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.only(
                                bottom: rowHeight * 0.14,
                              ),
                              hintText: rowIndex == 0
                                  ? 'Chạm vào dòng kẻ ngang để viết nội dung...'
                                  : null,
                              hintStyle: TextStyle(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.35),
                                fontSize: lineFontSize * 0.92,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
