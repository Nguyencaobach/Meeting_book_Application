import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'widgets/pen_handwriting_pad_widget.dart';

// ===========================================================================
// CÁC CHẾ ĐỘ & TÁC VỤ TRONG MENU CỦA TRANG GHI CHÚ:
// - viewOnly : Chỉ xem (Không cho chọn dòng hay chỉnh sửa, không chạy kiểm tra/đồng bộ Drive để tiết kiệm API)
// - keyboard : Bàn phím hệ thống máy
// - pen      : Viết bút (Mở Bottom Sheet trắng cao nửa màn hình)
// - refresh  : Làm mới (Tải lại nội dung mới nhất của tệp từ Google Drive giống ngoài màn hình Home)
// ===========================================================================
enum NoteInputMode {
  viewOnly,
  keyboard,
  pen,
  refresh,
}

// ===========================================================================
// MÀN HÌNH GIAO DIỆN TRANG VỞ RENDER DỮ LIỆU JSON (NOTE EDITOR SCREEN)
// Công dụng:
// - Nhận thông tin file ghi chú (DriveFolderItem) hoặc dữ liệu JSON (NotebookModel).
// - Tự động kiểm tra loại mẫu vở trong JSON ('note5x' cho vở 5 ô ly hoặc 'note4x' cho vở 4 ô ly)
//   để vẽ các ĐƯỜNG KẺ NGANG (thanh chính đậm, thanh phụ trong ô mờ đều) tự động giãn đầy đủ.
// - Tích hợp bộ cuộn (Scrollbar + SingleChildScrollView) lướt mượt mà ngay cả khi đang mở
//   bàn phím hệ thống hoặc đang mở Bottom Sheet Viết bút.
// - Chế độ "Chỉ xem":
//   + Người dùng chỉ xem và cuộn trang vở, khóa chọn dòng và khóa chỉnh sửa.
//   + Không chạy bất kỳ kiểm tra cập nhật dữ liệu mới hay gọi Google Drive API nào để tránh tốn API.
// - Chế độ "Bàn phím":
//   + Khi bấm vào dòng viết -> Mở bàn phím hệ thống máy kèm nút "X" để đóng bàn phím.
//   + Khi bấm nút "X" -> Đóng bàn phím hệ thống và bỏ chọn dòng vừa viết.
// - Chế độ "Viết bút":
//   + Hiển thị Bottom Sheet nền trắng (AppColors.basicWhite), cao bằng nửa màn hình (50%),
//     không có kiểu vuốt (chỉ có nút "X" để đóng), màn hình vở bên trên vẫn lướt bình thường.
// - Ô trạng thái kế bên nút Lưu:
//   + Bình thường: Nền màu xanh, chữ "Đang tự động lưu".
//   + Nếu lỗi không lưu được vào RAM: Đổi sang nền màu đỏ "Có lỗi bộ nhớ" và chặn ngay
//     không cho người dùng bấm chọn dòng để viết thêm.
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
  final ScrollController _horizontalScrollController = ScrollController();
  final ValueNotifier<double> _horizontalScrollOffsetNotifier =
      ValueNotifier<double>(0.0);

  NotebookModel? _notebook;
  bool _isLoadingJson = true;
  String? _loadError;

  // Ký tự khoảng trắng độ rộng 0 (Zero-Width Space) đặt ở đầu các dòng > 0
  // giúp bắt chính xác phím Xóa (Backspace) trên cả bàn phím ảo Android lẫn bàn phím cứng để tự động nhảy ngược lên dòng trên như Word
  static const String _kZeroWidthSpace = '\u200B';

  // Cờ tránh gọi đệ quy khi đang tự động ngắt chữ / dồn dòng
  bool _isWrappingLine = false;

  // Lưu chiều rộng dòng lần cuối đã căn lề để khi xoay ngang / dọc tự động dàn lại chữ vừa khít 2 bên lề
  double? _lastReflowedMaxLineWidth;

  // Lưu nội dung chữ sạch của từng dòng trước thao tác gõ để nhận biết khi người dùng xóa hết ký tự của dòng
  final Map<int, String> _lastCleanRowTexts = <int, String>{};

  // Quản lý các TextEditingController và FocusNode theo từng dòng (rowIndex)
  final Map<int, TextEditingController> _rowControllers =
      <int, TextEditingController>{};
  final Map<int, FocusNode> _rowFocusNodes = <int, FocusNode>{};

  // Chỉ số trang hiện tại (mặc định trang 0 -> pageNumber = 1)
  final int _currentPageIndex = 0;

  // Chế độ nhập liệu hiện tại: Chỉ xem (viewOnly), Bàn phím (keyboard), hoặc Viết bút (pen)
  NoteInputMode _inputMode = NoteInputMode.keyboard;

  bool get _isViewOnlyMode => _inputMode == NoteInputMode.viewOnly;
  bool get _isKeyboardMode => _inputMode == NoteInputMode.keyboard;
  bool get _isPenMode => _inputMode == NoteInputMode.pen;

  // Trạng thái mở Bottom Sheet của chế độ Viết bút (cao nửa màn hình, không vuốt)
  bool _isPenSheetOpen = false;

  // Dòng đang được người dùng bấm chọn để viết (null = chưa chọn dòng nào)
  int? _selectedRowIndex;

  // Tỷ lệ phóng to / thu nhỏ màn hình trang vở (mặc định 1.0 = 100%, hỗ trợ từ 1.0 đến 3.0)
  static const double _minZoomScale = 1.0;
  static const double _maxZoomScale = 3.0;
  static const double _zoomStep = 0.25;
  double _zoomScale = 1.0;

  /// Loại bỏ ký tự ẩn Zero-Width Space để lấy chuỗi văn bản thực tế
  String _cleanText(String rawText) {
    return rawText.replaceAll(_kZeroWidthSpace, '');
  }

  /// Đặt văn bản cho dòng `rowIndex` kèm ký tự neo `_kZeroWidthSpace` (nếu `rowIndex > 0`) để bắt phím Backspace
  void _setRowCleanText(
    int rowIndex,
    String cleanText, {
    int? cursorCleanOffset,
    bool forceSentinel = false,
  }) {
    final TextEditingController controller = _getOrCreateRowController(rowIndex);
    _lastCleanRowTexts[rowIndex] = cleanText;

    if (rowIndex == 0) {
      final int safeOffset =
          (cursorCleanOffset ?? cleanText.length).clamp(0, cleanText.length);
      controller.value = TextEditingValue(
        text: cleanText,
        selection: TextSelection.collapsed(offset: safeOffset),
      );
      return;
    }

    final bool shouldKeepSentinel =
        forceSentinel || cleanText.isNotEmpty || _selectedRowIndex == rowIndex;
    if (!shouldKeepSentinel) {
      controller.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      return;
    }

    final String rawWithSentinel = '$_kZeroWidthSpace$cleanText';
    final int safeRawOffset = ((cursorCleanOffset ?? cleanText.length) + 1)
        .clamp(1, rawWithSentinel.length);
    controller.value = TextEditingValue(
      text: rawWithSentinel,
      selection: TextSelection.collapsed(offset: safeRawOffset),
    );
  }

  /// Phóng to trang vở khi bấm nút dấu Cộng (+)
  void _handleZoomIn() {
    if (_zoomScale >= _maxZoomScale) return;
    setState(() {
      _zoomScale = (_zoomScale + _zoomStep).clamp(_minZoomScale, _maxZoomScale);
    });
  }

  /// Thu nhỏ trang vở khi bấm nút dấu Trừ (-)
  void _handleZoomOut() {
    if (_zoomScale <= _minZoomScale) return;
    setState(() {
      _zoomScale = (_zoomScale - _zoomStep).clamp(_minZoomScale, _maxZoomScale);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_horizontalScrollController.hasClients) {
        final double maxExt =
            _horizontalScrollController.position.maxScrollExtent;
        if (_horizontalScrollController.offset > maxExt) {
          _horizontalScrollController.jumpTo(maxExt);
        }
      }
      if (_scrollController.hasClients) {
        final double maxVert = _scrollController.position.maxScrollExtent;
        if (_scrollController.offset > maxVert) {
          _scrollController.jumpTo(maxVert);
        }
      }
    });
  }

  /// Tính tổng số ký tự thực tế đã nhập trên toàn trang hiện tại (không tính ký tự neo ẩn)
  int _getTotalCharacterCount() {
    int total = 0;
    for (final controller in _rowControllers.values) {
      total += _cleanText(controller.text).length;
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    _syncRepository.hasRamErrorNotifier.value = false;
    _horizontalScrollController.addListener(_onHorizontalScrollChanged);
    _loadAndPrepareNotebookJson();
  }

  void _onHorizontalScrollChanged() {
    if (_horizontalScrollController.hasClients) {
      _horizontalScrollOffsetNotifier.value =
          _horizontalScrollController.offset;
    }
  }

  @override
  void dispose() {
    _horizontalScrollController.removeListener(_onHorizontalScrollChanged);
    _horizontalScrollController.dispose();
    _horizontalScrollOffsetNotifier.dispose();
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

  /// Hàm xử lý khi bấm nút "Làm mới" trong menu (Tải lại dữ liệu JSON mới nhất từ Google Drive giống màn hình Home)
  Future<void> _handleRefreshNoteFromDrive() async {
    if (_isLoadingJson) return;
    setState(() {
      _isLoadingJson = true;
      _loadError = null;
    });

    try {
      final NotebookModel refreshedNotebook =
          await _driveDatasource.loadNoteJsonFile(
        widget.fileItem,
        forceRefreshFromDrive: true,
      );

      _lastReflowedMaxLineWidth = 0;
      _applyNotebookToRowControllers(refreshedNotebook, pageIndex: 0);

      if (mounted) {
        setState(() {
          _notebook = refreshedNotebook;
          _isLoadingJson = false;
        });
        await showCenterNotification(
          context: context,
          title: 'Làm mới thành công',
          message: 'Đã cập nhật nội dung mới nhất từ Google Drive!',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingJson = false;
        });
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

  /// Đồng bộ dữ liệu mảng `lines` từ JSON vào các ô dòng viết theo đúng `rowIndex`
  void _applyNotebookToRowControllers(
    NotebookModel notebook, {
    required int pageIndex,
  }) {
    _lastCleanRowTexts.clear();
    for (final controller in _rowControllers.values) {
      controller.clear();
    }

    if (notebook.pages.isEmpty) return;
    final int safeIndex = pageIndex.clamp(0, notebook.pages.length - 1);
    final PageModel page = notebook.pages[safeIndex];

    for (final LineModel line in page.lines) {
      final String clean = _cleanText(line.text);
      _setRowCleanText(line.rowIndex, clean);
    }
  }

  /// Lấy hoặc khởi tạo TextEditingController cho dòng thứ `rowIndex`
  TextEditingController _getOrCreateRowController(int rowIndex) {
    return _rowControllers.putIfAbsent(
      rowIndex,
      () => TextEditingController(),
    );
  }

  /// Lấy hoặc khởi tạo FocusNode cho dòng thứ `rowIndex` (Hỗ trợ bắt phím Xóa Backspace nhảy lên dòng trên)
  FocusNode _getOrCreateRowFocusNode(int rowIndex) {
    return _rowFocusNodes.putIfAbsent(
      rowIndex,
      () {
        final node = FocusNode(
          onKeyEvent: (FocusNode focusNode, KeyEvent event) {
            if (_isViewOnlyMode || rowIndex <= 0) {
              return KeyEventResult.ignored;
            }
            if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
                event.logicalKey == LogicalKeyboardKey.backspace) {
              final TextEditingController ctrl =
                  _getOrCreateRowController(rowIndex);
              final String raw = ctrl.text;
              final String clean = _cleanText(raw);
              final int minOffset = raw.startsWith(_kZeroWidthSpace) ? 1 : 0;
              final bool isAtLineStart = ctrl.selection.isCollapsed &&
                  ctrl.selection.baseOffset <= minOffset;

              if (clean.isEmpty || isAtLineStart) {
                _jumpOrMergeToPreviousRow(
                  rowIndex: rowIndex,
                  remainingCleanOnCurrentRow: clean,
                );
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
        );
        node.addListener(() {
          if (_isViewOnlyMode) {
            node.unfocus();
            return;
          }
          if (node.hasFocus && (_isKeyboardMode || _isPenMode) && mounted) {
            if (rowIndex > 0) {
              final TextEditingController ctrl =
                  _getOrCreateRowController(rowIndex);
              if (!ctrl.text.startsWith(_kZeroWidthSpace)) {
                final String clean = _cleanText(ctrl.text);
                final int currentCursor = ctrl.selection.baseOffset >= 0
                    ? ctrl.selection.baseOffset.clamp(0, clean.length)
                    : clean.length;
                _setRowCleanText(
                  rowIndex,
                  clean,
                  cursorCleanOffset: currentCursor,
                  forceSentinel: true,
                );
              }
            }
            if (_selectedRowIndex != rowIndex) {
              setState(() {
                _selectedRowIndex = rowIndex;
                if (_isPenMode) {
                  _isPenSheetOpen = true;
                }
              });
            }
          }
        });
        return node;
      },
    );
  }

  /// Lấy vị trí con trỏ thực tế (đã trừ ký tự neo ẩn) trên dòng `rowIndex`
  int _getRowCleanCursorOffset(int rowIndex) {
    final TextEditingController ctrl = _getOrCreateRowController(rowIndex);
    final String raw = ctrl.text;
    final String clean = _cleanText(raw);
    final int rawOffset = ctrl.selection.baseOffset;
    if (rawOffset < 0) {
      return clean.length;
    }
    final int cleanOffset =
        (rowIndex > 0 && raw.startsWith(_kZeroWidthSpace))
            ? rawOffset - 1
            : rawOffset;
    return cleanOffset.clamp(0, clean.length);
  }

  /// Tính chính xác vị trí ký tự (cleanOffset) tại điểm chạm ngang `tapLocalDx` trên câu
  int _calculateCleanOffsetFromTapDx({
    required String cleanText,
    required double tapLocalDx,
    required double horizontalPadding,
    required TextStyle rowTextStyle,
  }) {
    if (cleanText.isEmpty) return 0;
    final double textX =
        (tapLocalDx - horizontalPadding).clamp(0.0, double.infinity);
    final TextPainter painter = TextPainter(
      text: TextSpan(text: cleanText, style: rowTextStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(minWidth: 0, maxWidth: double.infinity);

    return painter
        .getPositionForOffset(Offset(textX, 0))
        .offset
        .clamp(0, cleanText.length);
  }

  // ===========================================================================
  // 2. HÀM ĐÓNG BÀN PHÍM HỆ THỐNG & BỎ CHỌN DÒNG VỪA VIẾT (KHI BẤM NÚT X)
  // ===========================================================================
  void _closeKeyboardAndDeselectRow() {
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    setState(() {
      _selectedRowIndex = null;
    });
  }

  /// Hàm chọn 1 dòng trên trang vở và đặt con trỏ đúng vào vị trí điểm chạm trên câu (hỗ trợ cả Bàn phím & Viết bút)
  void _handleSelectRow(
    int rowIndex,
    double rowHeight, {
    double? tapLocalDx,
    double? horizontalPadding,
    TextStyle? rowTextStyle,
  }) {
    // Nếu đang ở chế độ "Chỉ xem" hoặc đang có lỗi bộ nhớ RAM -> Chặn ngay không cho bấm chọn dòng
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) {
      FocusScope.of(context).unfocus();
      return;
    }

    final TextEditingController ctrl = _getOrCreateRowController(rowIndex);
    final String clean = _cleanText(ctrl.text);

    // Xác định vị trí con trỏ tại điểm bút/tay vừa chạm vào câu (để chèn bù chữ thiếu ngay tại đó)
    final int targetCleanOffset;
    if (tapLocalDx != null &&
        horizontalPadding != null &&
        rowTextStyle != null) {
      targetCleanOffset = _calculateCleanOffsetFromTapDx(
        cleanText: clean,
        tapLocalDx: tapLocalDx,
        horizontalPadding: horizontalPadding,
        rowTextStyle: rowTextStyle,
      );
    } else {
      targetCleanOffset = _getRowCleanCursorOffset(rowIndex);
    }

    _setRowCleanText(
      rowIndex,
      clean,
      cursorCleanOffset: targetCleanOffset,
      forceSentinel: rowIndex > 0,
    );

    setState(() {
      _selectedRowIndex = rowIndex;
      if (_isPenMode) {
        _isPenSheetOpen = true;
      }
    });

    final FocusNode node = _getOrCreateRowFocusNode(rowIndex);
    node.requestFocus();

    if (_isKeyboardMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isKeyboardMode) {
          node.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        }
      });
    } else {
      // Chế độ Viết bút: Giữ Focus để hiển thị con trỏ nhấp nháy tại điểm trỏ trên câu nhưng ẩn bàn phím ảo
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  // ===========================================================================
  // 3. CƠ CHẾ SOẠN THẢO NHƯ WORD: CĂN LỀ 2 BÊN, TỰ XUỐNG DÒNG, XÓA NHẢY LÊN DÒNG TRÊN,
  //    XOAY NGANG / DỌC TỰ ĐỘNG DÀN LẠI CHỮ VỪA KHÍT MÀN HÌNH
  // ===========================================================================

  /// Đo chiều rộng thực tế (pixel) của chuỗi chữ trên 1 dòng theo đúng font và cỡ chữ hiện tại
  double _measureTextWidth(String text, TextStyle style) {
    final String clean = _cleanText(text);
    if (clean.isEmpty) return 0;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: clean, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return painter.width;
  }

  /// Tìm số ký tự tối đa vừa khít trong chiều ngang cho phép (`maxLineTextWidth`) của dòng giấy
  /// Tối ưu chỉ dùng 1 lần `TextPainter.layout()` duy nhất để xuống dòng mượt tức thì (0ms lag)
  int _findFittingCharCount(
    String cleanText,
    TextStyle style,
    double maxLineTextWidth,
  ) {
    if (cleanText.isEmpty) return 0;

    final TextPainter painter = TextPainter(
      text: TextSpan(text: cleanText, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(minWidth: 0, maxWidth: double.infinity);

    if (painter.width <= maxLineTextWidth) {
      return cleanText.length;
    }

    int best = painter
        .getPositionForOffset(Offset(maxLineTextWidth, 0))
        .offset
        .clamp(1, cleanText.length);

    // Nếu vị trí làm tròn vượt nhẹ qua maxLineTextWidth thì lùi lại 1 ký tự ngay trên cùng painter
    while (best > 1 &&
        painter.getOffsetForCaret(TextPosition(offset: best), Rect.zero).dx >
            maxLineTextWidth) {
      best -= 1;
    }

    // Tránh cắt đôi cặp ký tự UTF-16 surrogate
    if (best > 1 &&
        best < cleanText.length &&
        (cleanText.codeUnitAt(best - 1) & 0xFC00) == 0xD800) {
      best -= 1;
    }
    return best;
  }

  /// Tự động cuộn dọc trang vở khi con trỏ nhảy sang dòng mới
  void _ensureRowVisible(int rowIndex, double rowHeight) {
    if (!_scrollController.hasClients) return;
    final double rowTop = rowIndex * rowHeight;
    final double rowBottom = rowTop + rowHeight * 2.0;
    final double currentOffset = _scrollController.offset;
    final double viewportHeight = _scrollController.position.viewportDimension;

    if (rowBottom > currentOffset + viewportHeight) {
      final double targetOffset = (rowBottom - viewportHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    } else if (rowTop < currentOffset) {
      final double targetOffset = rowTop.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    }
  }

  /// Xử lý khi người dùng xóa hết chữ ở dòng `rowIndex` (> 0) hoặc bấm Xóa ở đầu dòng:
  /// Tự động nhảy con trỏ ngược lên cuối dòng phía trên (`rowIndex - 1`) và dồn các dòng dưới lên
  void _jumpOrMergeToPreviousRow({
    required int rowIndex,
    required String remainingCleanOnCurrentRow,
    double? maxLineTextWidth,
    TextStyle? rowTextStyle,
    double? rowHeight,
  }) {
    if (rowIndex <= 0) return;

    _isWrappingLine = true;
    try {
      final int prevRow = rowIndex - 1;
      final String prevClean =
          _cleanText(_getOrCreateRowController(prevRow).text);

      // Dịch chuyển các dòng phía dưới `rowIndex` lên 1 bậc nếu dòng `rowIndex` bị xóa trống
      final int maxRowIdx = _rowControllers.keys.isEmpty
          ? rowIndex
          : _rowControllers.keys.reduce(math.max);

      if (remainingCleanOnCurrentRow.isEmpty) {
        for (int r = rowIndex; r < maxRowIdx; r++) {
          final String nextClean =
              _cleanText(_getOrCreateRowController(r + 1).text);
          _setRowCleanText(r, nextClean);
        }
        _setRowCleanText(maxRowIdx, '');

        final int targetCursorCleanOffset = prevClean.length;
        _setRowCleanText(
          prevRow,
          prevClean,
          cursorCleanOffset: targetCursorCleanOffset,
          forceSentinel: prevRow > 0,
        );

        if (_selectedRowIndex != prevRow) {
          setState(() {
            _selectedRowIndex = prevRow;
          });
        }

        // Chuyển focus ngay lập tức trong cùng frame để không bị trễ nhịp gõ
        final FocusNode prevNode = _getOrCreateRowFocusNode(prevRow);
        prevNode.requestFocus();
        _setRowCleanText(
          prevRow,
          prevClean,
          cursorCleanOffset: targetCursorCleanOffset,
          forceSentinel: prevRow > 0,
        );
        if (rowHeight != null) {
          _ensureRowVisible(prevRow, rowHeight);
        }
      } else {
        // Trường hợp bấm Xóa ở đầu dòng `rowIndex` khi dòng vẫn còn chữ -> nối lên dòng `prevRow`
        final String basePrev = prevClean.isNotEmpty
            ? prevClean.substring(0, prevClean.length - 1)
            : '';
        final int joinCursorCleanOffset = basePrev.length;
        final String mergedText = '$basePrev$remainingCleanOnCurrentRow';

        for (int r = rowIndex; r < maxRowIdx; r++) {
          final String nextClean =
              _cleanText(_getOrCreateRowController(r + 1).text);
          _setRowCleanText(r, nextClean);
        }
        _setRowCleanText(maxRowIdx, '');
        _setRowCleanText(
          prevRow,
          mergedText,
          cursorCleanOffset: joinCursorCleanOffset,
          forceSentinel: prevRow > 0,
        );

        if (maxLineTextWidth != null &&
            rowTextStyle != null &&
            rowHeight != null &&
            _measureTextWidth(mergedText, rowTextStyle) > maxLineTextWidth) {
          _wrapOverflowFromRow(
            startRowIndex: prevRow,
            maxLineTextWidth: maxLineTextWidth,
            rowTextStyle: rowTextStyle,
            rowHeight: rowHeight,
            keepFocusOnRow: prevRow,
            keepCursorCleanOffset: joinCursorCleanOffset,
          );
        } else {
          if (_selectedRowIndex != prevRow) {
            setState(() {
              _selectedRowIndex = prevRow;
            });
          }
          final FocusNode prevNode = _getOrCreateRowFocusNode(prevRow);
          prevNode.requestFocus();
          _setRowCleanText(
            prevRow,
            _cleanText(_getOrCreateRowController(prevRow).text),
            cursorCleanOffset: joinCursorCleanOffset,
            forceSentinel: prevRow > 0,
          );
        }
      }
    } finally {
      _isWrappingLine = false;
    }

    _saveLinesToRamAndScheduleDriveSync();
  }

  /// Tự động ngắt phần chữ vượt quá chiều ngang giấy (`maxLineTextWidth`) xuống dòng tiếp theo (`rowIndex + 1`)
  /// Căn sát lề 2 bên chuẩn như Word
  void _wrapOverflowFromRow({
    required int startRowIndex,
    required double maxLineTextWidth,
    required TextStyle rowTextStyle,
    required double rowHeight,
    int? keepFocusOnRow,
    int? keepCursorCleanOffset,
  }) {
    int currentRow = startRowIndex;
    int? targetFocusRow = keepFocusOnRow;
    int targetCursorCleanOffset = keepCursorCleanOffset ?? 0;

    while (true) {
      final TextEditingController currentController =
          _getOrCreateRowController(currentRow);
      final String currentClean = _cleanText(currentController.text);

      final int fitCount = _findFittingCharCount(
        currentClean,
        rowTextStyle,
        maxLineTextWidth,
      );

      if (fitCount >= currentClean.length) {
        break;
      }

      // Căn sát lề phải; chỉ ngắt ở khoảng trắng nếu từ cuối dòng rất ngắn (<= 6 ký tự)
      int splitIndex = fitCount;
      final int lastSpace = currentClean.lastIndexOf(' ', fitCount);
      if (lastSpace > 0 && (fitCount - lastSpace) <= 6) {
        splitIndex = lastSpace;
      }

      final String keptText =
          currentClean.substring(0, splitIndex).trimRight();
      final String overflowText =
          currentClean.substring(splitIndex).trimLeft();

      if (overflowText.isEmpty) {
        _setRowCleanText(
          currentRow,
          keptText,
          cursorCleanOffset: keptText.length,
        );
        break;
      }

      // Giữ lại phần chữ vừa khít chiều ngang 2 bên lề trên dòng hiện tại
      _setRowCleanText(
        currentRow,
        keptText,
        cursorCleanOffset: keptText.length,
      );

      // Chuyển phần chữ tràn xuống dòng kẻ ngang tiếp theo (currentRow + 1)
      final int nextRow = currentRow + 1;
      final TextEditingController nextController =
          _getOrCreateRowController(nextRow);
      final String existingNextClean = _cleanText(nextController.text);

      final String combinedNextClean = existingNextClean.isEmpty
          ? overflowText
          : '$overflowText$existingNextClean';

      _setRowCleanText(
        nextRow,
        combinedNextClean,
        cursorCleanOffset: overflowText.length,
        forceSentinel: true,
      );

      if (targetFocusRow == null) {
        targetFocusRow = nextRow;
        targetCursorCleanOffset = overflowText.length;
      } else if (targetFocusRow == currentRow &&
          targetCursorCleanOffset > keptText.length) {
        targetFocusRow = nextRow;
        targetCursorCleanOffset =
            (targetCursorCleanOffset - splitIndex).clamp(0, overflowText.length);
      }

      currentRow = nextRow;
    }

    if (targetFocusRow != null) {
      final int focusRow = targetFocusRow;
      final int cursorCleanOffset = targetCursorCleanOffset;
      if (_selectedRowIndex != focusRow) {
        setState(() {
          _selectedRowIndex = focusRow;
        });
      }

      // Chuyển focus ngay lập tức trong cùng chu kỳ để bàn phím không bị khựng 1 frame
      final FocusNode nextFocusNode = _getOrCreateRowFocusNode(focusRow);
      final String focusClean =
          _cleanText(_getOrCreateRowController(focusRow).text);
      nextFocusNode.requestFocus();
      _setRowCleanText(
        focusRow,
        focusClean,
        cursorCleanOffset: cursorCleanOffset.clamp(0, focusClean.length),
        forceSentinel: focusRow > 0,
      );
      _ensureRowVisible(focusRow, rowHeight);
    }
  }

  /// Tự động dàn lại chữ trên toàn trang (Reflow như Word) khi xoay dọc <-> xoay ngang
  /// để các dòng luôn lấp đầy khoảng cách giữa 2 bên lề mà không bị hụt hay tràn lề
  void _reflowEntirePageForWidth({
    required double maxLineTextWidth,
    required TextStyle rowTextStyle,
  }) {
    if (_isWrappingLine || _rowControllers.isEmpty) return;

    final List<int> sortedIndices = _rowControllers.keys.toList()..sort();
    final int maxIdx = sortedIndices.last;

    // Gom các dòng liên tiếp có chữ thành từng đoạn văn (giữ nguyên các dòng trống cố ý)
    final List<String> newWrappedLines = <String>[];
    StringBuffer activeParagraph = StringBuffer();

    void flushParagraph() {
      String remaining = activeParagraph.toString();
      activeParagraph.clear();
      if (remaining.isEmpty) return;

      while (remaining.isNotEmpty) {
        if (_measureTextWidth(remaining, rowTextStyle) <= maxLineTextWidth) {
          newWrappedLines.add(remaining);
          break;
        }
        final int fitCount = _findFittingCharCount(
          remaining,
          rowTextStyle,
          maxLineTextWidth,
        );
        int splitIndex = fitCount;
        final int lastSpace = remaining.lastIndexOf(' ', fitCount);
        if (lastSpace > 0 && (fitCount - lastSpace) <= 6) {
          splitIndex = lastSpace;
        }
        final String linePart =
            remaining.substring(0, splitIndex).trimRight();
        remaining = remaining.substring(splitIndex).trimLeft();
        if (linePart.isNotEmpty) {
          newWrappedLines.add(linePart);
        }
      }
    }

    for (int i = 0; i <= maxIdx; i++) {
      final String clean =
          _cleanText(_rowControllers[i]?.text ?? '');
      if (clean.isEmpty) {
        flushParagraph();
        // Nếu phía sau vẫn còn dòng có chữ thì giữ dòng trống phân cách
        final bool hasTextBelow = sortedIndices
            .any((idx) => idx > i && _cleanText(_rowControllers[idx]?.text ?? '').isNotEmpty);
        if (hasTextBelow && newWrappedLines.isNotEmpty) {
          newWrappedLines.add('');
        }
      } else {
        if (activeParagraph.isNotEmpty &&
            !activeParagraph.toString().endsWith(' ') &&
            !clean.startsWith(' ')) {
          activeParagraph.write(clean);
        } else {
          activeParagraph.write(clean);
        }
      }
    }
    flushParagraph();

    // Kiểm tra xem nội dung các dòng có thay đổi sau khi dàn lại theo chiều ngang mới không
    bool changed = false;
    final int totalToApply = math.max(maxIdx + 1, newWrappedLines.length);
    for (int i = 0; i < totalToApply; i++) {
      final String oldClean = _cleanText(_rowControllers[i]?.text ?? '');
      final String newClean =
          i < newWrappedLines.length ? newWrappedLines[i] : '';
      if (oldClean != newClean) {
        changed = true;
        break;
      }
    }

    if (!changed) return;

    _isWrappingLine = true;
    try {
      for (int i = 0; i < totalToApply; i++) {
        final String newClean =
            i < newWrappedLines.length ? newWrappedLines[i] : '';
        _setRowCleanText(
          i,
          newClean,
          forceSentinel: i > 0 && _selectedRowIndex == i,
        );
      }
      if (mounted) {
        setState(() {});
      }
    } finally {
      _isWrappingLine = false;
    }
  }

  // ===========================================================================
  // 4. HÀM CẬP NHẬT DỮ LIỆU TỪNG DÒNG VÀO GÓI JSON & KIỂM TRA LỖI LƯU RAM
  // ===========================================================================
  Future<void> _onRowTextChanged(
    int rowIndex,
    String rawNewText, {
    required double maxLineTextWidth,
    required TextStyle rowTextStyle,
    required double rowHeight,
  }) async {
    // Chế độ "Chỉ xem" hoặc có lỗi RAM hoặc đang xử lý tự động xuống dòng -> Bỏ qua
    if (_isWrappingLine ||
        _isViewOnlyMode ||
        _syncRepository.hasRamErrorNotifier.value) {
      return;
    }

    final String prevClean = _lastCleanRowTexts[rowIndex] ?? '';
    final String currentClean = _cleanText(rawNewText);

    // 1. Kiểm tra nếu người dùng bấm Xóa (Backspace) ở dòng > 0:
    // - Hoặc đã xóa mất ký tự neo `_kZeroWidthSpace` ở đầu dòng
    // - Hoặc vừa xóa hết ký tự cuối cùng của dòng (`prevClean` có chữ -> `currentClean` rỗng)
    if (rowIndex > 0) {
      final bool deletedLeadingSentinel =
          !rawNewText.startsWith(_kZeroWidthSpace);
      final bool emptiedCurrentRow =
          prevClean.isNotEmpty && currentClean.isEmpty;

      if (deletedLeadingSentinel || emptiedCurrentRow) {
        _jumpOrMergeToPreviousRow(
          rowIndex: rowIndex,
          remainingCleanOnCurrentRow:
              emptiedCurrentRow ? '' : currentClean,
          maxLineTextWidth: maxLineTextWidth,
          rowTextStyle: rowTextStyle,
          rowHeight: rowHeight,
        );
        return;
      }
    }

    _lastCleanRowTexts[rowIndex] = currentClean;

    // 2. Nếu người dùng xóa bớt ký tự trên dòng hiện tại mà dòng kế tiếp (`rowIndex + 1`) đang có chữ:
    // Tự động kéo chữ từ dòng dưới lên để lấp đầy chiều ngang như Word
    if (currentClean.length < prevClean.length) {
      final String nextClean =
          _cleanText(_rowControllers[rowIndex + 1]?.text ?? '');
      if (nextClean.isNotEmpty &&
          _measureTextWidth(currentClean, rowTextStyle) < maxLineTextWidth) {
        _isWrappingLine = true;
        try {
          final TextEditingController currCtrl =
              _getOrCreateRowController(rowIndex);
          final int rawOffset = currCtrl.selection.baseOffset;
          final int cleanCursorOffset =
              (rowIndex > 0 ? rawOffset - 1 : rawOffset)
                  .clamp(0, currentClean.length);

          final String combined = '$currentClean$nextClean';
          _setRowCleanText(rowIndex + 1, '');
          _setRowCleanText(
            rowIndex,
            combined,
            cursorCleanOffset: cleanCursorOffset,
            forceSentinel: rowIndex > 0,
          );
          _wrapOverflowFromRow(
            startRowIndex: rowIndex,
            maxLineTextWidth: maxLineTextWidth,
            rowTextStyle: rowTextStyle,
            rowHeight: rowHeight,
            keepFocusOnRow: rowIndex,
            keepCursorCleanOffset: cleanCursorOffset,
          );
        } finally {
          _isWrappingLine = false;
        }
        await _saveLinesToRamAndScheduleDriveSync();
        return;
      }
    }

    // 3. Nếu người dùng viết hết chiều ngang giấy -> Tự động ngắt chữ chuyển xuống dòng tiếp theo
    if (_measureTextWidth(currentClean, rowTextStyle) > maxLineTextWidth) {
      _isWrappingLine = true;
      try {
        _wrapOverflowFromRow(
          startRowIndex: rowIndex,
          maxLineTextWidth: maxLineTextWidth,
          rowTextStyle: rowTextStyle,
          rowHeight: rowHeight,
        );
      } finally {
        _isWrappingLine = false;
      }
    }

    await _saveLinesToRamAndScheduleDriveSync();
  }

  /// Đóng gói dữ liệu sạch của các dòng vào JSON (RAM 0ms + hẹn 30 giây đẩy lên Google Drive)
  Future<void> _saveLinesToRamAndScheduleDriveSync() async {
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) {
      return;
    }

    final NotebookModel? currentNotebook = _notebook;
    if (currentNotebook == null) return;

    // Gom tất cả các dòng có nội dung chữ thực tế trên trang hiện tại thành mảng JSON `lines`
    final List<LineModel> updatedLines = <LineModel>[];
    final List<int> sortedRowIndices = _rowControllers.keys.toList()..sort();

    for (final int idx in sortedRowIndices) {
      final String textValue = _cleanText(_rowControllers[idx]?.text ?? '');
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
    try {
      await _syncRepository.onUserWritingChanged(
        documentId: widget.fileItem.id,
        fileName: widget.fileItem.displayName,
        tabIndex: 0,
        parentFolderId: widget.fileItem.parentFolderId,
        existingDriveFileId: widget.fileItem.id,
        updatedJsonData: updatedNotebook.toJson(),
      );
    } catch (_) {
      // Nếu không lưu được vào RAM -> Báo "Có lỗi bộ nhớ" và khóa chọn dòng ngay lập tức
      _syncRepository.hasRamErrorNotifier.value = true;
      _closeKeyboardAndDeselectRow();
      if (mounted) {
        setState(() {
          _isPenSheetOpen = false;
        });
      }
    }
  }

  /// Hàm xử lý khi người dùng bấm nút Quay lại (Nếu đang ở chế độ "Chỉ xem" thì thoát luôn không gọi API Drive)
  Future<void> _handleExitEditor() async {
    if (!_isViewOnlyMode) {
      await _syncRepository.syncOnPageExit();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Hàm lưu ngay lập tức gói JSON lên Google Drive khi người dùng bấm nút Lưu
  Future<void> _handleManualSaveNow() async {
    if (_isViewOnlyMode) return;
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

  @override
  Widget build(BuildContext context) {
    final String activeTemplate =
        _notebook?.paperTemplate ?? widget.fileItem.paperTemplate;
    final bool isNote4x = activeTemplate == Note4x.templateId;

    final Size screenSize = MediaQuery.sizeOf(context);
    final double titleFontSize = AppTheme.getResponsiveFontSize(context, 16);
    final double badgeFontSize = AppTheme.getResponsiveFontSize(context, 12);

    // Chiều ngang trang giấy phụ thuộc vào màn hình máy và mức phóng to (_zoomScale):
    // - Nếu máy đủ to và ở 100%: hiển thị toàn bộ chiều ngang giấy.
    // - Nếu màn nhỏ hoặc đang phóng to (> 100%): hiện thêm con lăn trái/phải và cho phép giữ chuột kéo qua đủ chỗ.
    final double paperWidth = isNote4x
        ? Note4x.getResponsivePaperWidth(screenSize.width)
        : Note5x.getResponsivePaperWidth(screenSize.width);
    final double scaledPaperWidth = paperWidth * _zoomScale;
    final bool needsHorizontalScroll =
        scaledPaperWidth > screenSize.width + 1.0;
    final double maxHorizontalScrollExtent =
        math.max(0.0, scaledPaperWidth - screenSize.width);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleExitEditor();
      },
      child: Scaffold(
        // Cho phép màn hình co giãn mượt khi bàn phím hệ thống bật lên để bộ cuộn lướt bình thường
        resizeToAvoidBottomInset: true,
        backgroundColor: isNote4x
            ? Note4x.getPaperBackgroundColor()
            : Note5x.getPaperBackgroundColor(),
        body: ValueListenableBuilder<bool>(
          valueListenable: _syncRepository.hasRamErrorNotifier,
          builder: (context, hasRamError, _) {
            return Column(
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              // Giới hạn cụm nút Quay lại + Tên tệp chỉ hiển thị tối đa tới 1 nửa màn hình (50%)
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: screenSize.width * 0.5,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Nút Quay lại (Tự động lưu JSON trước khi thoát)
                                        InkWell(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          onTap: _handleExitEditor,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.basicWhite
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(20),
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
                                                    fontSize:
                                                        badgeFontSize * 1.05,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),

                                        // Tên tệp ghi chú (Nếu dài quá một nửa màn hình sẽ tự động ẩn đoạn sau bằng "...")
                                        Flexible(
                                          child: Text(
                                            _notebook?.title ??
                                                widget.fileItem.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: AppColors.basicWhite,
                                              fontSize: titleFontSize,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Sắp xếp bên phải Header: Cụm nút Zoom (- / +) -> Nút Lưu -> Trạng thái bộ nhớ -> Nút Menu 3 gạch
                              // Tự động co giãn trên mọi kích cỡ màn hình (từ điện thoại nhỏ đến máy tính bảng lớn)
                              Flexible(
                                flex: 0,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: screenSize.width * 0.62,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 0. Hai nút Dấu Trừ (-) và Dấu Cộng (+) nằm kế bên nút Lưu để Zoom màn hình vở
                                        _buildZoomControls(
                                            fontSize: badgeFontSize),
                                        const SizedBox(width: 8),

                                        // 1. Nút Lưu JSON ngay lập tức
                                        ValueListenableBuilder<bool>(
                                          valueListenable: _syncRepository
                                              .isSyncingDriveNotifier,
                                          builder: (context, isSyncing, _) {
                                            return InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              onTap: (isSyncing || hasRamError)
                                                  ? null
                                                  : _handleManualSaveNow,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 7,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.basicWhite,
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (isSyncing)
                                                      const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: AppColors
                                                              .primaryBlue,
                                                        ),
                                                      )
                                                    else
                                                      const Icon(
                                                        Icons
                                                            .cloud_done_outlined,
                                                        color: AppColors
                                                            .primaryBlue,
                                                        size: 17,
                                                      ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      isSyncing
                                                          ? 'Đang lưu...'
                                                          : 'Lưu',
                                                      style: TextStyle(
                                                        color: AppColors
                                                            .primaryBlue,
                                                        fontSize: badgeFontSize,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 8),

                                        // 2. Ô Trạng thái bộ nhớ:
                                        // - Bình thường: Nền màu xanh ("Đang tự động lưu")
                                        // - Khi lỗi RAM: Nền màu đỏ ("Có lỗi bộ nhớ")
                                        _buildRamStatusBadge(
                                          hasRamError: hasRamError,
                                          fontSize: badgeFontSize,
                                        ),
                                        const SizedBox(width: 8),

                                        // 3. Nút Menu 3 gạch nằm sát bên phải (Bấm vào hiện lựa chọn "Chỉ xem", "Bàn phím" và "Viết bút")
                                        _buildInputModeMenuButton(
                                          hasRamError: hasRamError,
                                          fontSize: badgeFontSize,
                                        ),
                                      ],
                                    ),
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

                // 2. Vùng thân: Mặt giấy kẻ ngang có bộ cuộn lướt bình thường (Chặn thao tác ngay nếu có lỗi RAM)
                Expanded(
                  child: IgnorePointer(
                    ignoring: hasRamError,
                    child: _buildPaperBody(
                      isNote4x: isNote4x,
                      hasRamError: hasRamError,
                    ),
                  ),
                ),

                // 3. Thanh cuộn trái/phải nằm ngay phía trên thanh hiển thị "Đang chọn dòng" và "Số ký tự"
                if (needsHorizontalScroll && !hasRamError)
                  _buildBottomHorizontalRoller(
                    maxScrollExtent: maxHorizontalScrollExtent,
                    viewportWidth: screenSize.width,
                  ),

                // 4. Thanh chứa "Đang chọn dòng", "Số ký tự đã nhập" và nút "X" đóng bàn phím
                if (_isKeyboardMode &&
                    _selectedRowIndex != null &&
                    !hasRamError)
                  _buildKeyboardCloseBar(fontSize: badgeFontSize),

                // 5. Bottom Sheet chế độ "Viết bút" (Cao nửa màn hình, nền trắng, không có kiểu vuốt, chỉ có dấu X để đóng)
                if (_isPenMode && _isPenSheetOpen && !hasRamError)
                  _buildPenWritingBottomSheet(
                    screenHeight: screenSize.height,
                    titleFontSize: titleFontSize,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Thanh cuộn trái/phải nằm ngay phía trên thanh hiển thị "Đang chọn dòng" và "Số ký tự"
  Widget _buildBottomHorizontalRoller({
    required double maxScrollExtent,
    required double viewportWidth,
  }) {
    return ValueListenableBuilder<double>(
      valueListenable: _horizontalScrollOffsetNotifier,
      builder: (context, currentOffset, _) {
        final double clampedOffset =
            currentOffset.clamp(0.0, maxScrollExtent);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            border: Border(
              top: BorderSide(
                color: AppColors.basicWhite.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              // Nút cuộn sang trái
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (!_horizontalScrollController.hasClients) return;
                  final double target =
                      (clampedOffset - viewportWidth * 0.25)
                          .clamp(0.0, maxScrollExtent);
                  _horizontalScrollController.animateTo(
                    target,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    color: AppColors.creamBackground,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Thanh kéo con lăn trái/phải mượt mà
              Expanded(
                child: SizedBox(
                  height: 22,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      activeTrackColor: AppColors.creamBackground,
                      inactiveTrackColor:
                          AppColors.basicWhite.withValues(alpha: 0.3),
                      thumbColor: AppColors.creamBackground,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8,
                      ),
                    ),
                    child: Slider(
                      value: clampedOffset,
                      min: 0.0,
                      max: maxScrollExtent > 0 ? maxScrollExtent : 1.0,
                      onChanged: (double newValue) {
                        _horizontalScrollOffsetNotifier.value = newValue;
                        if (_horizontalScrollController.hasClients) {
                          _horizontalScrollController.jumpTo(newValue);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Nút cuộn sang phải
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (!_horizontalScrollController.hasClients) return;
                  final double target =
                      (clampedOffset + viewportWidth * 0.25)
                          .clamp(0.0, maxScrollExtent);
                  _horizontalScrollController.animateTo(
                    target,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.creamBackground,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Xây dựng mặt giấy kẻ ngang có tích hợp bộ cuộn (`Scrollbar` + `SingleChildScrollView`)
  /// và giới hạn chiều ngang viết tự động xuống dòng khi viết hết chiều ngang giấy
  Widget _buildPaperBody({
    required bool isNote4x,
    required bool hasRamError,
  }) {
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
        // Tính chiều ngang trang giấy phụ thuộc vào màn hình máy:
        // - Màn hình đủ to: hiển thị toàn bộ chiều ngang giấy (paperWidth = constraints.maxWidth)
        // - Màn hình nhỏ: giữ chiều ngang giấy chuẩn (minPaperWidth) và cho phép kéo qua lại bằng con lăn
        final double paperWidth = isNote4x
            ? Note4x.getResponsivePaperWidth(constraints.maxWidth)
            : Note5x.getResponsivePaperWidth(constraints.maxWidth);
        final double scaledPaperWidth = paperWidth * _zoomScale;
        final bool enableHorizontalScroll =
            scaledPaperWidth > constraints.maxWidth + 1.0;
        final bool isZoomedIn = _zoomScale > 1.01;

        // Tính chiều cao mỗi dòng kẻ ngang dựa trên mẫu vở 5 ô ly (note5x) hoặc 4 ô ly (note4x)
        final double rowHeight = isNote4x
            ? Note4x.getResponsiveRowHeight(
                context,
                maxWidth: paperWidth,
              )
            : Note5x.getResponsiveRowHeight(
                context,
                maxWidth: paperWidth,
              );

        final double horizontalPadding = isNote4x
            ? Note4x.getResponsiveHorizontalPadding(paperWidth)
            : Note5x.getResponsiveHorizontalPadding(paperWidth);

        // Chiều ngang vùng viết tối đa giữa 2 bên lề (căn đều 2 bên lề như Word)
        final double maxLineTextWidth = math.max(
          120.0,
          paperWidth - (horizontalPadding * 2) - 2.0,
        );

        final double lineFontSize = (rowHeight * 0.42).clamp(15.0, 22.0);
        final TextStyle effectiveRowTextStyle =
            (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
          color: isNote4x ? Note4x.getTextColor() : Note5x.getTextColor(),
          fontSize: lineFontSize,
          fontWeight: FontWeight.w500,
          height: 1.15,
        );

        // Khi xoay ngang <-> xoay dọc làm thay đổi chiều rộng dòng (`maxLineTextWidth`):
        // Tự động dàn lại chữ (Reflow) để luôn lấp đầy khoảng cách 2 bên lề như Word
        if ((_lastReflowedMaxLineWidth == null ||
                (maxLineTextWidth - _lastReflowedMaxLineWidth!).abs() > 2.0) &&
            _rowControllers.isNotEmpty) {
          _lastReflowedMaxLineWidth = maxLineTextWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _reflowEntirePageForWidth(
              maxLineTextWidth: maxLineTextWidth,
              rowTextStyle: effectiveRowTextStyle,
            );
          });
        } else {
          _lastReflowedMaxLineWidth ??= maxLineTextWidth;
        }

        // Tính tổng số dòng sao cho luôn phủ kín màn hình và tự giãn thêm khi viết dài
        final int minRowsToFillScreen =
            (constraints.maxHeight / rowHeight).ceil() + 4;
        final int defaultMinRows =
            isNote4x ? Note4x.defaultLineCount : Note5x.defaultLineCount;
        final int highestUsedRow = _rowControllers.keys.isEmpty
            ? 0
            : (_rowControllers.keys.reduce(math.max) + 6);
        final int totalRows = math.max(
          math.max(minRowsToFillScreen, defaultMinRows),
          highestUsedRow,
        );

        final double totalPaperHeight = totalRows * rowHeight;
        final double scaledPaperHeight = totalPaperHeight * _zoomScale;

        final Widget paperSheetContent = SizedBox(
          width: paperWidth,
          height: totalPaperHeight,
          child: IgnorePointer(
            // Chế độ "Chỉ xem": cho phép cuộn trang vở mượt mà nhưng chặn hoàn toàn chọn dòng / chỉnh sửa
            ignoring: _isViewOnlyMode,
            child: CustomPaint(
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
                  final bool isRowSelected =
                      !_isViewOnlyMode && _selectedRowIndex == rowIndex;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _isViewOnlyMode
                        ? null
                        : (TapUpDetails details) => _handleSelectRow(
                              rowIndex,
                              rowHeight,
                              tapLocalDx: details.localPosition.dx,
                              horizontalPadding: horizontalPadding,
                              rowTextStyle: effectiveRowTextStyle,
                            ),
                    onHorizontalDragUpdate: (_isViewOnlyMode ||
                            (!isRowSelected && !_isPenMode))
                        ? null
                        : (DragUpdateDetails details) => _handleSelectRow(
                              rowIndex,
                              rowHeight,
                              tapLocalDx: details.localPosition.dx,
                              horizontalPadding: horizontalPadding,
                              rowTextStyle: effectiveRowTextStyle,
                            ),
                    child: Container(
                      width: paperWidth,
                      height: rowHeight,
                      color: isRowSelected
                          ? AppColors.primaryBlue.withValues(alpha: 0.08)
                          : Colors.transparent,
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomLeft,
                        children: [
                          Align(
                            alignment: Alignment.bottomLeft,
                            child: IgnorePointer(
                              // Các dòng chưa chọn hoặc đang ở chế độ Viết bút sẽ để GestureDetector bên ngoài bắt điểm trỏ & kéo con trỏ
                              ignoring: _isViewOnlyMode ||
                                  !isRowSelected ||
                                  _isPenMode,
                              child: TextField(
                                controller: controller,
                                focusNode: focusNode,
                                readOnly: _isViewOnlyMode ||
                                    _isPenMode ||
                                    hasRamError,
                                showCursor: _isKeyboardMode && isRowSelected,
                                cursorColor: AppColors.primaryBlue,
                                cursorWidth: 2.2,
                                maxLines: 1,
                                // Khóa cuộn ngang nội bộ của TextField để chữ không bao giờ chạy dài vô tận trên 1 dòng
                                scrollPhysics:
                                    const NeverScrollableScrollPhysics(),
                                textInputAction: TextInputAction.next,
                                onTap: _isViewOnlyMode
                                    ? null
                                    : () =>
                                        _handleSelectRow(rowIndex, rowHeight),
                                onChanged: (value) => _onRowTextChanged(
                                  rowIndex,
                                  value,
                                  maxLineTextWidth: maxLineTextWidth,
                                  rowTextStyle: effectiveRowTextStyle,
                                  rowHeight: rowHeight,
                                ),
                                onSubmitted: (_) {
                                  // Khi bấm Enter -> Tự động xuống dòng kẻ ngang tiếp theo (rowIndex + 1)
                                  _handleSelectRow(rowIndex + 1, rowHeight);
                                },
                                style: effectiveRowTextStyle,
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.only(
                                    bottom: rowHeight * 0.14,
                                  ),
                                  hintText: (rowIndex == 0 && !_isViewOnlyMode)
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

                          // Con trỏ + nút nắm kéo (Handle) hiển thị trực quan trên dòng đang chọn ở chế độ Viết bút
                          if (isRowSelected && _isPenMode)
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: controller,
                              builder: (context, textValue, _) {
                                final String clean = _cleanText(textValue.text);
                                final int cleanCursor =
                                    _getRowCleanCursorOffset(rowIndex)
                                        .clamp(0, clean.length);
                                final String textBeforeCursor =
                                    clean.substring(0, cleanCursor);
                                final double cursorX = _measureTextWidth(
                                  textBeforeCursor,
                                  effectiveRowTextStyle,
                                ).clamp(0.0, maxLineTextWidth);

                                return Positioned(
                                  left: (cursorX - 5.0)
                                      .clamp(-5.0, maxLineTextWidth - 5.0),
                                  bottom: rowHeight * 0.04,
                                  child: IgnorePointer(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Thanh dọc con trỏ |
                                        Container(
                                          width: 2.4,
                                          height: rowHeight * 0.58,
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryBlue,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                        // Đầu nắm tròn dưới chân con trỏ để người dùng dễ nhìn và kéo ngang
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryBlue,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: AppColors.basicWhite,
                                              width: 1.5,
                                            ),
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
                  );
                }),
              ),
            ),
          ),
        );

        // Áp dụng tỷ lệ phóng to (_zoomScale) cho trang giấy vở
        final Widget zoomedPaperWidget = isZoomedIn
            ? SizedBox(
                width: scaledPaperWidth,
                height: scaledPaperHeight,
                child: FittedBox(
                  fit: BoxFit.fill,
                  alignment: Alignment.topLeft,
                  child: paperSheetContent,
                ),
              )
            : paperSheetContent;

        // Khi đang phóng to hoặc màn hình nhỏ có cuộn ngang: hỗ trợ giữ chuột / giữ tay kéo tự do 360 độ qua mọi góc
        final bool enableFree2DPan = isZoomedIn || enableHorizontalScroll;

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          thickness: 6,
          radius: const Radius.circular(8),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: enableFree2DPan
                ? (DragUpdateDetails details) {
                    if (_scrollController.hasClients) {
                      final double nextVert =
                          (_scrollController.offset - details.delta.dy).clamp(
                        0.0,
                        _scrollController.position.maxScrollExtent,
                      );
                      _scrollController.jumpTo(nextVert);
                    }
                    if (_horizontalScrollController.hasClients) {
                      final double nextHoriz = (_horizontalScrollController
                                  .offset -
                              details.delta.dx)
                          .clamp(
                        0.0,
                        _horizontalScrollController.position.maxScrollExtent,
                      );
                      _horizontalScrollController.jumpTo(nextHoriz);
                    }
                  }
                : null,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: enableFree2DPan
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
              child: enableHorizontalScroll
                  ? SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: zoomedPaperWidget,
                    )
                  : zoomedPaperWidget,
            ),
          ),
        );
      },
    );
  }

  /// Cụm 2 nút Dấu Trừ (-) và Dấu Cộng (+) nằm kế bên nút Lưu để Zoom màn hình vở
  Widget _buildZoomControls({required double fontSize}) {
    final bool canZoomOut = _zoomScale > _minZoomScale + 0.01;
    final bool canZoomIn = _zoomScale < _maxZoomScale - 0.01;
    final int zoomPercent = (_zoomScale * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.basicWhite.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.creamBackground.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nút Dấu Trừ (-) để thu nhỏ
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canZoomOut ? _handleZoomOut : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: canZoomOut
                    ? AppColors.creamBackground
                    : AppColors.basicWhite.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.remove_rounded,
                color: canZoomOut
                    ? AppColors.primaryBlue
                    : AppColors.basicWhite.withValues(alpha: 0.5),
                size: 16,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$zoomPercent%',
              style: TextStyle(
                color: AppColors.basicWhite,
                fontSize: fontSize * 0.95,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Nút Dấu Cộng (+) để phóng to
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canZoomIn ? _handleZoomIn : null,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: canZoomIn
                    ? AppColors.creamBackground
                    : AppColors.basicWhite.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_rounded,
                color: canZoomIn
                    ? AppColors.primaryBlue
                    : AppColors.basicWhite.withValues(alpha: 0.5),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Thanh chứa nút "X" nằm ngay trên bàn phím hệ thống để đóng bàn phím & bỏ chọn dòng vừa viết
  /// Kèm hiển thị trực tiếp tổng số ký tự đã nhập vào ngay bên cạnh "Đang chọn dòng..."
  Widget _buildKeyboardCloseBar({required double fontSize}) {
    final int selectedRow = _selectedRowIndex ?? 0;
    final TextEditingController activeController =
        _getOrCreateRowController(selectedRow);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.basicWhite,
        border: Border(
          top: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: activeController,
          builder: (context, value, _) {
            final int totalCharCount = _getTotalCharacterCount();
            final String charCountLabel = '$totalCharCount ký tự';

            return Row(
              children: [
                // Cạnh bên trái: Đang chọn dòng X   [Y ký tự]
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Đang chọn dòng ${selectedRow + 1}',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: fontSize * 1.05,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // Ô hiển thị tổng số ký tự đã nhập bên cạnh "Đang chọn dòng"
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.creamBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          charCountLabel,
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: fontSize * 0.96,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Cạnh bên phải: Đóng bàn phím ×
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _closeKeyboardAndDeselectRow,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.creamBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Đóng bàn phím',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: fontSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.close_rounded,
                          color: AppColors.basicBlack,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Tính thông số kích thước dòng và kiểu chữ hiện tại của trang vở
  ({double rowHeight, double maxLineTextWidth, TextStyle rowTextStyle})
      _getCurrentRowLayoutMetrics() {
    final String activeTemplate =
        _notebook?.paperTemplate ?? widget.fileItem.paperTemplate;
    final bool isNote4x = activeTemplate == Note4x.templateId;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double paperWidth = isNote4x
        ? Note4x.getResponsivePaperWidth(screenWidth)
        : Note5x.getResponsivePaperWidth(screenWidth);
    final double rowHeight = isNote4x
        ? Note4x.getResponsiveRowHeight(context, maxWidth: paperWidth)
        : Note5x.getResponsiveRowHeight(context, maxWidth: paperWidth);
    final double horizontalPadding = isNote4x
        ? Note4x.getResponsiveHorizontalPadding(paperWidth)
        : Note5x.getResponsiveHorizontalPadding(paperWidth);
    final double maxLineTextWidth = math.max(
      120.0,
      paperWidth - (horizontalPadding * 2) - 2.0,
    );
    final double lineFontSize = (rowHeight * 0.42).clamp(15.0, 22.0);
    final TextStyle rowTextStyle =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: isNote4x ? Note4x.getTextColor() : Note5x.getTextColor(),
      fontSize: lineFontSize,
      fontWeight: FontWeight.w500,
      height: 1.15,
    );
    return (
      rowHeight: rowHeight,
      maxLineTextWidth: maxLineTextWidth,
      rowTextStyle: rowTextStyle,
    );
  }

  /// Xử lý điền văn bản vừa được AI nhận diện từ Bottom Sheet Viết bút vào ĐÚNG VỊ TRÍ CON TRỎ trên câu:
  /// - Cho phép người dùng dùng bút trỏ vào bất kỳ điểm nào trên câu để chèn thêm chữ bù/thiếu.
  /// - Nếu viết liên tục (insertLeadingSpace == false): nối liền ký tự vào ngay vị trí con trỏ.
  /// - Nếu ngừng 1 khoảnh khắc (insertLeadingSpace == true): tự động cách ra 1 khoảng trắng trước từ mới.
  /// - Nếu vượt quá chiều ngang giấy: tự động ngắt xuống dòng kế tiếp như Word.
  void _handleCommitRecognizedPenText(
    String recognizedText, {
    required bool insertLeadingSpace,
  }) {
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) return;
    final String trimmed = recognizedText.trim();
    if (trimmed.isEmpty) return;

    final int rowIndex = _selectedRowIndex ?? 0;
    final String existingClean =
        _cleanText(_getOrCreateRowController(rowIndex).text);
    final int cursorOffset =
        _getRowCleanCursorOffset(rowIndex).clamp(0, existingClean.length);

    final String beforeCursor = existingClean.substring(0, cursorOffset);
    final String afterCursor = existingClean.substring(cursorOffset);

    // Không chèn khoảng trắng trước dấu câu (, . ? ! : ; ) ])
    const String punctuationChars = ',.?!:;)]}';
    final bool isPunctuation =
        trimmed.length == 1 && punctuationChars.contains(trimmed);

    final String insertedPart;
    if (beforeCursor.isEmpty || beforeCursor.endsWith(' ') || isPunctuation) {
      insertedPart = trimmed;
    } else if (insertLeadingSpace) {
      insertedPart = ' $trimmed';
    } else {
      insertedPart = trimmed;
    }

    final String newClean = '$beforeCursor$insertedPart$afterCursor';
    final int newCursorCleanOffset = beforeCursor.length + insertedPart.length;
    final metrics = _getCurrentRowLayoutMetrics();

    _isWrappingLine = true;
    try {
      _setRowCleanText(
        rowIndex,
        newClean,
        cursorCleanOffset: newCursorCleanOffset,
        forceSentinel: rowIndex > 0,
      );

      if (_measureTextWidth(newClean, metrics.rowTextStyle) >
          metrics.maxLineTextWidth) {
        _wrapOverflowFromRow(
          startRowIndex: rowIndex,
          maxLineTextWidth: metrics.maxLineTextWidth,
          rowTextStyle: metrics.rowTextStyle,
          rowHeight: metrics.rowHeight,
          keepFocusOnRow: rowIndex,
          keepCursorCleanOffset: newCursorCleanOffset,
        );
      } else {
        _ensureRowVisible(rowIndex, metrics.rowHeight);
      }
    } finally {
      _isWrappingLine = false;
    }

    // Giữ hiển thị con trỏ tại điểm vừa chèn nhưng ẩn bàn phím ảo
    _getOrCreateRowFocusNode( _selectedRowIndex ?? rowIndex).requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');

    _saveLinesToRamAndScheduleDriveSync();
  }

  /// Chủ động thêm 1 khoảng trắng ngay tại vị trí con trỏ đang trỏ trên câu trong chế độ Viết bút
  void _handlePenInsertSpace() {
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) return;
    final int rowIndex = _selectedRowIndex ?? 0;
    final String existingClean =
        _cleanText(_getOrCreateRowController(rowIndex).text);
    final int cursorOffset =
        _getRowCleanCursorOffset(rowIndex).clamp(0, existingClean.length);

    final String beforeCursor = existingClean.substring(0, cursorOffset);
    final String afterCursor = existingClean.substring(cursorOffset);
    if (beforeCursor.isEmpty || beforeCursor.endsWith(' ')) return;

    final String newClean = '$beforeCursor $afterCursor';
    final int newCursorCleanOffset = cursorOffset + 1;
    final metrics = _getCurrentRowLayoutMetrics();

    _isWrappingLine = true;
    try {
      _setRowCleanText(
        rowIndex,
        newClean,
        cursorCleanOffset: newCursorCleanOffset,
        forceSentinel: rowIndex > 0,
      );
      if (_measureTextWidth(newClean, metrics.rowTextStyle) >
          metrics.maxLineTextWidth) {
        _wrapOverflowFromRow(
          startRowIndex: rowIndex,
          maxLineTextWidth: metrics.maxLineTextWidth,
          rowTextStyle: metrics.rowTextStyle,
          rowHeight: metrics.rowHeight,
          keepFocusOnRow: rowIndex,
          keepCursorCleanOffset: newCursorCleanOffset,
        );
      }
    } finally {
      _isWrappingLine = false;
    }
    _getOrCreateRowFocusNode(_selectedRowIndex ?? rowIndex).requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    _saveLinesToRamAndScheduleDriveSync();
  }

  /// Xóa lùi 1 ký tự ngay tại vị trí con trỏ đang trỏ trên câu trong chế độ Viết bút
  void _handlePenBackspace() {
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) return;
    final int rowIndex = _selectedRowIndex ?? 0;
    final String existingClean =
        _cleanText(_getOrCreateRowController(rowIndex).text);
    final int cursorOffset =
        _getRowCleanCursorOffset(rowIndex).clamp(0, existingClean.length);
    final metrics = _getCurrentRowLayoutMetrics();

    if (existingClean.isEmpty || cursorOffset == 0) {
      if (rowIndex > 0) {
        _jumpOrMergeToPreviousRow(
          rowIndex: rowIndex,
          remainingCleanOnCurrentRow: existingClean,
          maxLineTextWidth: metrics.maxLineTextWidth,
          rowTextStyle: metrics.rowTextStyle,
          rowHeight: metrics.rowHeight,
        );
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
      return;
    }

    final String beforeCursor = existingClean.substring(0, cursorOffset - 1);
    final String afterCursor = existingClean.substring(cursorOffset);
    final String shortened = '$beforeCursor$afterCursor';
    final int newCursorCleanOffset = cursorOffset - 1;

    if (shortened.isEmpty && rowIndex > 0) {
      _jumpOrMergeToPreviousRow(
        rowIndex: rowIndex,
        remainingCleanOnCurrentRow: '',
        maxLineTextWidth: metrics.maxLineTextWidth,
        rowTextStyle: metrics.rowTextStyle,
        rowHeight: metrics.rowHeight,
      );
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      return;
    }

    _isWrappingLine = true;
    try {
      final String nextClean =
          _cleanText(_rowControllers[rowIndex + 1]?.text ?? '');
      if (nextClean.isNotEmpty &&
          _measureTextWidth(shortened, metrics.rowTextStyle) <
              metrics.maxLineTextWidth) {
        final String combined = '$shortened$nextClean';
        _setRowCleanText(rowIndex + 1, '');
        _setRowCleanText(
          rowIndex,
          combined,
          cursorCleanOffset: newCursorCleanOffset,
          forceSentinel: rowIndex > 0,
        );
        _wrapOverflowFromRow(
          startRowIndex: rowIndex,
          maxLineTextWidth: metrics.maxLineTextWidth,
          rowTextStyle: metrics.rowTextStyle,
          rowHeight: metrics.rowHeight,
          keepFocusOnRow: rowIndex,
          keepCursorCleanOffset: newCursorCleanOffset,
        );
      } else {
        _setRowCleanText(
          rowIndex,
          shortened,
          cursorCleanOffset: newCursorCleanOffset,
          forceSentinel: rowIndex > 0,
        );
      }
    } finally {
      _isWrappingLine = false;
    }
    _getOrCreateRowFocusNode(_selectedRowIndex ?? rowIndex).requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    _saveLinesToRamAndScheduleDriveSync();
  }

  /// Bottom Sheet chế độ "Viết bút":
  /// - Cao đúng nửa màn hình (50% chiều cao màn hình)
  /// - Nền màu trắng (AppColors.basicWhite)
  /// - Không có kiểu vuốt (không có thanh nắm kéo, không bị vuốt đóng), chỉ có dấu X để đóng
  /// - Màn hình vở bên trên vẫn lướt cuộn lên xuống bình thường
  Widget _buildPenWritingBottomSheet({
    required double screenHeight,
    required double titleFontSize,
  }) {
    final double sheetHeight = (screenHeight * 0.5).clamp(220.0, 560.0);
    final int selectedRow = _selectedRowIndex ?? 0;
    final TextEditingController activeController =
        _getOrCreateRowController(selectedRow);
    final double badgeFontSize = AppTheme.getResponsiveFontSize(context, 12);

    return Container(
      width: double.infinity,
      height: sheetHeight,
      decoration: BoxDecoration(
        color: AppColors.basicWhite, // Nền màu trắng theo yêu cầu
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.basicBlack.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          // Hàng tiêu đề trên cùng của Bottom Sheet Viết bút (Chỉ có nút dấu X để đóng, không có thanh vuốt)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: activeController,
              builder: (context, value, _) {
                final int totalCharCount = _getTotalCharacterCount();
                final String charCountLabel = '$totalCharCount ký tự';

                return Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          Text(
                            _selectedRowIndex != null
                                ? 'Viết bút - Dòng ${_selectedRowIndex! + 1}'
                                : 'Viết bút',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.creamBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              charCountLabel,
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: badgeFontSize * 0.96,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Nút Cách thủ công nhanh
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _handlePenInsertSpace,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.creamBackground,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.space_bar_rounded,
                              color: AppColors.primaryBlue,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Cách',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: badgeFontSize * 0.95,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Nút Xóa lùi 1 ký tự
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _handlePenBackspace,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.creamBackground,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                AppColors.primaryBlue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.backspace_outlined,
                              color: AppColors.primaryBlue,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Xóa',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: badgeFontSize * 0.95,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Nút dấu X duy nhất để đóng Bottom Sheet Viết bút và bỏ chọn dòng
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _isPenSheetOpen = false;
                          _selectedRowIndex = null;
                        });
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.basicBlack,
                      ),
                      tooltip: 'Đóng',
                    ),
                  ],
                );
              },
            ),
          ),
          Divider(
            height: 1,
            color: AppColors.primaryBlue.withValues(alpha: 0.15),
          ),

          // Vùng bảng viết bút như tờ giấy thật (0ms lag, hiện nét vẽ -> thêm chữ -> tự ẩn nét vẽ)
          Expanded(
            child: PenHandwritingPadWidget(
              getCurrentRowCleanText: () {
                final int rowIdx = _selectedRowIndex ?? 0;
                final String fullClean =
                    _cleanText(_getOrCreateRowController(rowIdx).text);
                final int cursorIdx =
                    _getRowCleanCursorOffset(rowIdx).clamp(0, fullClean.length);
                return fullClean.substring(0, cursorIdx);
              },
              onCommitRecognizedText: _handleCommitRecognizedPenText,
            ),
          ),
        ],
      ),
    );
  }

  /// Ô trạng thái nằm kế bên nút Lưu:
  /// - Khi ở chế độ Chỉ xem: Hiển thị "Chế độ chỉ xem" (tạm ngưng tự động lưu để tiết kiệm API)
  /// - Bình thường (Bàn phím / Viết bút): Nền màu xanh ("Đang tự động lưu")
  /// - Khi lỗi RAM: Đổi sang nền màu đỏ ("Có lỗi bộ nhớ")
  Widget _buildRamStatusBadge({
    required bool hasRamError,
    required double fontSize,
  }) {
    final Color badgeBgColor = hasRamError
        ? AppColors.paperMarginRed
        : (_isViewOnlyMode
            ? AppColors.basicWhite.withValues(alpha: 0.2)
            : const Color(0xFF2E7D32)); // Màu xanh báo đang tự động lưu
    final String statusText = hasRamError
        ? 'Có lỗi bộ nhớ'
        : (_isViewOnlyMode ? 'Chế độ chỉ xem' : 'Đang tự động lưu');
    final IconData statusIcon = hasRamError
        ? Icons.error_outline_rounded
        : (_isViewOnlyMode
            ? Icons.visibility_outlined
            : Icons.check_circle_outline_rounded);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: badgeBgColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            color: AppColors.basicWhite,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              color: AppColors.basicWhite,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Nút Menu 3 gạch nằm sát góc phải Header (Gom 3 chức năng: "Chỉ xem", "Bàn phím" và "Viết bút")
  Widget _buildInputModeMenuButton({
    required bool hasRamError,
    required double fontSize,
  }) {
    final double menuTextSize = AppTheme.getResponsiveFontSize(context, 14);

    return PopupMenuButton<NoteInputMode>(
      enabled: !hasRamError,
      tooltip: 'Chọn chế độ',
      offset: const Offset(0, 44),
      color: AppColors.basicWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      onSelected: (NoteInputMode selectedMode) {
        if (selectedMode == NoteInputMode.refresh) {
          _handleRefreshNoteFromDrive();
          return;
        }
        if (selectedMode == NoteInputMode.viewOnly) {
          // Chế độ "Chỉ xem": Đóng bàn phím / bảng viết bút, bỏ chọn dòng,
          // và hủy mọi bộ đếm kiểm tra cập nhật dữ liệu lên Drive để không tốn API
          FocusScope.of(context).unfocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          _syncRepository.cancelPendingSyncTimer();
          setState(() {
            _inputMode = NoteInputMode.viewOnly;
            _isPenSheetOpen = false;
            _selectedRowIndex = null;
          });
        } else if (selectedMode == NoteInputMode.pen) {
          FocusScope.of(context).unfocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          setState(() {
            _inputMode = NoteInputMode.pen;
            _isPenSheetOpen = true;
            _selectedRowIndex ??= 0;
          });
        } else {
          final int targetRow = _selectedRowIndex ?? 0;
          setState(() {
            _inputMode = NoteInputMode.keyboard;
            _isPenSheetOpen = false;
            _selectedRowIndex = targetRow;
          });
          // Chờ PopupMenu đóng hẳn rồi mới focus dòng để không bị PopupMenu làm mất focus
          Future<void>.delayed(const Duration(milliseconds: 150), () {
            if (mounted && _isKeyboardMode) {
              final node = _getOrCreateRowFocusNode(targetRow);
              node.requestFocus();
              SystemChannels.textInput.invokeMethod('TextInput.show');
            }
          });
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<NoteInputMode>>[
        // Tùy chọn 1: Chỉ xem (Không chọn dòng, không chỉnh sửa, không chạy kiểm tra/đồng bộ tốn API)
        PopupMenuItem<NoteInputMode>(
          value: NoteInputMode.viewOnly,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _isViewOnlyMode
                  ? AppColors.creamBackground
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Chỉ xem',
                    style: TextStyle(
                      color: AppColors.basicBlack,
                      fontSize: menuTextSize,
                      fontWeight:
                          _isViewOnlyMode ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (_isViewOnlyMode)
                  const Icon(
                    Icons.check_rounded,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
        // Tùy chọn 2: Bàn phím
        PopupMenuItem<NoteInputMode>(
          value: NoteInputMode.keyboard,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _isKeyboardMode
                  ? AppColors.creamBackground
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.keyboard_alt_outlined,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bàn phím',
                    style: TextStyle(
                      color: AppColors.basicBlack,
                      fontSize: menuTextSize,
                      fontWeight:
                          _isKeyboardMode ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (_isKeyboardMode)
                  const Icon(
                    Icons.check_rounded,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
        // Tùy chọn 3: Viết bút
        PopupMenuItem<NoteInputMode>(
          value: NoteInputMode.pen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _isPenMode
                  ? AppColors.creamBackground
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.edit_outlined,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Viết bút',
                    style: TextStyle(
                      color: AppColors.basicBlack,
                      fontSize: menuTextSize,
                      fontWeight:
                          _isPenMode ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (_isPenMode)
                  const Icon(
                    Icons.check_rounded,
                    color: AppColors.primaryBlue,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
        const PopupMenuDivider(height: 8),
        // Tùy chọn 4: Làm mới (Tải lại dữ liệu mới nhất từ Google Drive giống ngoài màn hình Home)
        PopupMenuItem<NoteInputMode>(
          value: NoteInputMode.refresh,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.creamBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Làm mới',
                    style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontSize: menuTextSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.creamBackground,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.menu_rounded,
          color: AppColors.primaryBlue,
          size: 20,
        ),
      ),
    );
  }
}
