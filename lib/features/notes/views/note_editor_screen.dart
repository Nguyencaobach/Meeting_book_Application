import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/note_templates/note4x.dart';
import '../../../core/constants/note_templates/note5x.dart';
import '../../../core/constants/observation_templates/primary_school_evaluation_template.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../../data/models/line_model.dart';
import '../../../data/models/notebook_model.dart';
import '../../../data/models/page_model.dart';
import '../../../data/models/stroke_point_model.dart';
import '../../../data/repositories/data_sync_repository.dart';
import '../../../services/pdf_export_service.dart';
import '../../../services/word_export_service.dart';
import '../../../widgets/center_notification_dialog.dart';
import 'widgets/floating_pen_bubble_widget.dart';
import 'widgets/pen_handwriting_pad_widget.dart';

// ===========================================================================
// CÁC CHẾ ĐỘ & TÁC VỤ TRONG MENU CỦA TRANG GHI CHÚ:
// - viewOnly     : Chỉ xem (Không cho chọn dòng hay chỉnh sửa, không chạy kiểm tra/đồng bộ Drive để tiết kiệm API)
// - keyboard     : Bàn phím hệ thống máy
// - pen          : Viết bút (Vẽ trực tiếp trên mặt giấy + Bong bóng công cụ Bút viết nổi kéo thả tự do)
// - exportFile   : Xuất file (Xuất tệp đang mở ra PDF .pdf hoặc Word .doc vào thư mục Export File trên Google Drive)
// - refresh      : Làm mới (Tải lại nội dung mới nhất của tệp từ Google Drive giống ngoài màn hình Home)
// - clearContent : Làm sạch (Xóa toàn bộ nội dung hiện tại trong tệp, có hộp thoại xác nhận & nút Hoàn tác)
// ===========================================================================
enum NoteInputMode {
  viewOnly,
  keyboard,
  pen,
  exportFile,
  refresh,
  clearContent,
}

// ===========================================================================
// MÀN HÌNH GIAO DIỆN TRANG VỞ RENDER DỮ LIỆU JSON (NOTE EDITOR SCREEN)
// Công dụng:
// - Nhận thông tin file ghi chú (DriveFolderItem) hoặc dữ liệu JSON (NotebookModel).
// - Tự động kiểm tra loại mẫu vở trong JSON ('note5x' cho vở 5 ô ly, 'note4x' cho vở 4 ô ly,
//   hoặc 'primary_school_eval_v1' cho Sổ dự giờ 3 trang) để hiển thị giao diện trang giấy tương ứng.
// - Tích hợp bộ cuộn (Scrollbar + SingleChildScrollView) lướt mượt mà.
// - Chế độ "Chỉ xem":
//   + Người dùng chỉ xem và cuộn trang vở, khóa chọn dòng và khóa chỉnh sửa.
//   + Không chạy bất kỳ kiểm tra cập nhật dữ liệu mới hay gọi Google Drive API nào để tránh tốn API.
// - Chế độ "Bàn phím":
//   + Khi bấm vào dòng viết -> Mở bàn phím hệ thống máy kèm nút "X" để đóng bàn phím.
//   + Khi bấm nút "X" -> Đóng bàn phím hệ thống và bỏ chọn dòng vừa viết.
// - Chế độ "Viết bút" (Dùng chung cho cả Ghi chú & Sổ dự giờ, không dùng Bottom Sheet):
//   + Người dùng đặt bút/1 ngón tay viết/vẽ trực tiếp lên mặt giấy (60-120fps), dùng 2 ngón tay để cuộn trang.
//   + Hiển thị Bong bóng công cụ Bút viết nổi kéo thả tự do (Màu chữ, Nét chữ, Cục tẩy, Hoàn tác nét).
// - Ô trạng thái kế bên nút Lưu:
//   + Bình thường: Nền màu xanh, chữ "Đang tự động lưu".
//   + Nếu lỗi không lưu được vào RAM: Đổi sang nền màu đỏ "Có lỗi bộ nhớ" và chặn ngay
//     không cho người dùng bấm chọn dòng để viết thêm.
// ===========================================================================
class NoteEditorScreen extends StatefulWidget {
  final DriveFolderItem fileItem;
  final NotebookModel? initialNotebook;
  final int tabIndex;

  const NoteEditorScreen({
    super.key,
    required this.fileItem,
    this.initialNotebook,
    this.tabIndex = 0,
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

  // Lưu trữ danh sách các cụm nét chữ viết tay đã chuẩn hóa theo từng dòng (dùng cho Sổ dự giờ)
  final Map<int, List<HandwritingClusterModel>> _rowHandwritingMap =
      <int, List<HandwritingClusterModel>>{};
  final List<Map<int, List<HandwritingClusterModel>>> _observationPenUndoStack =
      <Map<int, List<HandwritingClusterModel>>>[];

  // Lưu trữ màu chữ đánh máy theo từng dòng (khi viết bằng chế độ "Nét đánh máy" trong Bong bóng Bút)
  final Map<int, int> _rowTextColorMap = <int, int>{};

  // Ngăn xếp hoàn tác cho chế độ "Nét đánh máy" (lưu trạng thái chữ và màu của các dòng)
  final List<
      ({
        Map<int, String> rowTexts,
        Map<int, int> rowColors,
        int? selectedRow,
      })> _typedPenUndoStack = <({
    Map<int, String> rowTexts,
    Map<int, int> rowColors,
    int? selectedRow,
  })>[];

  // Chế độ con bên trong Viết bút:
  // - false: "Nét viết tự nhiên" (Vẽ trực tiếp trên mặt giấy như ứng dụng Paint)
  // - true : "Nét đánh máy" (Chọn dòng + Mở Bottom Sheet viết bút nhận diện ra chữ đánh máy)
  bool _isPenTypedHandwritingMode = false;
  bool _isPenSheetOpen = false;

  // Số khoảng trắng chờ chèn trước cụm nét chữ viết tay kế tiếp khi bấm nút "Cách" trên Bottom Sheet
  int _pendingPenSpaceCount = 0;

  // Cấu hình Bút viết đang chọn trong Bong bóng công cụ Bút (Màu chữ, Độ dày nét, Kiểu nét vẽ)
  int _selectedPenColorValue = 0xFF263BAA;
  double _selectedPenStrokeWidth = 2.6;
  String _selectedPenStyle = PenStrokeStyle.ballpoint;

  // Lưu trữ danh sách các nét vẽ tự do trực tiếp trên mặt giấy (dùng cho Ghi chú & Sổ dự giờ chế độ Viết bút như ứng dụng Paint)
  final List<FreehandPageStrokeModel> _pageFreehandStrokes =
      <FreehandPageStrokeModel>[];
  final List<List<FreehandPageStrokeModel>> _freehandUndoStack =
      <List<FreehandPageStrokeModel>>[];
  final List<StrokePointModel> _activeFreehandPoints = <StrokePointModel>[];
  bool _isNotePenEraserMode = false;
  Offset? _currentEraserCursorOffset;
  final Map<int, Offset> _activeCanvasPointers = <int, Offset>{};
  bool _isMultiTouchPanning = false;
  bool _didModifyStrokesInCurrentEraseGesture = false;
  final ValueNotifier<int> _freehandCanvasRepaintVersion =
      ValueNotifier<int>(0);

  // Cấu hình Cây thước kẻ ảo (Virtual Ruler) trong Bong bóng công cụ Bút viết
  static const double _kRulerHeight = 68.0;
  bool _isRulerVisible = false;
  Offset _rulerCenterOnPaper = const Offset(320.0, 220.0);
  double _rulerAngleRad = 0.0;
  double? _activeRulerSnapEdgeSign;

  // Các khóa đo bố cục thực tế của 3 trang Sổ dự giờ & ô Chữ ký để xuất PDF/Word khớp đúng 100% vị trí
  final GlobalKey _evalFormStackKey = GlobalKey();
  final GlobalKey _evalPage1Key = GlobalKey();
  final GlobalKey _evalPage2Key = GlobalKey();
  final GlobalKey _evalPage3Key = GlobalKey();
  final GlobalKey _evalSignatureBoxKey = GlobalKey();
  double _lastMeasuredEvalPaperWidth =
      PrimarySchoolEvaluationTemplate.minPaperWidth;
  double _lastMeasuredEvalRowHeight = 40.0;

  // Chỉ số trang hiện tại (mặc định trang 0 -> pageNumber = 1)
  final int _currentPageIndex = 0;

  // Chế độ nhập liệu hiện tại: Chỉ xem (viewOnly), Bàn phím (keyboard), hoặc Viết bút (pen)
  NoteInputMode _inputMode = NoteInputMode.keyboard;

  bool get _isViewOnlyMode => _inputMode == NoteInputMode.viewOnly;
  bool get _isKeyboardMode => _inputMode == NoteInputMode.keyboard;
  bool get _isPenMode => _inputMode == NoteInputMode.pen;
  bool get _isPenFreehandMode => _isPenMode && !_isPenTypedHandwritingMode;
  bool get _isPenTypedMode => _isPenMode && _isPenTypedHandwritingMode;

  // Dòng đang được người dùng bấm chọn để viết (null = chưa chọn dòng nào)
  int? _selectedRowIndex;

  // Tỷ lệ phóng to / thu nhỏ màn hình trang vở (mặc định 1.0 = 100%, hỗ trợ từ 1.0 đến 3.0)
  static const double _minZoomScale = 1.0;
  static const double _maxZoomScale = 3.0;
  static const double _zoomStep = 0.25;
  double _zoomScale = 1.0;

  // Trạng thái đang xuất file PDF hoặc Word từ RAM lên thư mục Export File trên Google Drive
  bool _isExportingFile = false;

  /// Mã định danh biểu mẫu / mẫu giấy hiện tại của tệp
  String get _activeTemplateId =>
      _notebook?.paperTemplate ?? widget.fileItem.paperTemplate;

  /// Kiểm tra xem tệp đang mở có phải là biểu mẫu Sổ dự giờ ("Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học") không
  bool get _isPrimaryEvalTemplate =>
      widget.tabIndex == 1 ||
      PrimarySchoolEvaluationTemplate.isObservationTemplate(_activeTemplateId);

  /// Lấy giới hạn dòng đầu - dòng cuối của vùng chứa `rowIndex`
  ({int minRow, int maxRow, bool isSingleLine}) _getRowSectionBounds(
    int rowIndex,
  ) {
    if (_isPrimaryEvalTemplate) {
      return PrimarySchoolEvaluationTemplate.getSectionBoundsForRow(rowIndex);
    }
    return (
      minRow: 0,
      maxRow: 999999,
      isSingleLine: false,
    );
  }

  /// Kiểm tra xem `rowIndex` có cần ký tự neo `_kZeroWidthSpace` ở đầu dòng để bắt phím Backspace không
  bool _rowUsesBackspaceSentinel(int rowIndex) {
    final bounds = _getRowSectionBounds(rowIndex);
    if (bounds.isSingleLine) return false;
    return rowIndex > bounds.minRow;
  }

  /// Loại bỏ ký tự ẩn Zero-Width Space để lấy chuỗi văn bản thực tế
  String _cleanText(String rawText) {
    return rawText.replaceAll(_kZeroWidthSpace, '');
  }

  /// Đặt văn bản cho dòng `rowIndex` kèm ký tự neo `_kZeroWidthSpace` (nếu không phải dòng đầu vùng) để bắt phím Backspace
  void _setRowCleanText(
    int rowIndex,
    String cleanText, {
    int? cursorCleanOffset,
    bool forceSentinel = false,
  }) {
    final TextEditingController controller = _getOrCreateRowController(rowIndex);
    _lastCleanRowTexts[rowIndex] = cleanText;

    if (!_rowUsesBackspaceSentinel(rowIndex)) {
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

  /// Tính tổng số cụm nét chữ viết tay đã viết trên trang hiện tại (Sổ dự giờ)
  int _getTotalHandwritingClustersCount() {
    int total = 0;
    for (final clusters in _rowHandwritingMap.values) {
      total += clusters.length;
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
    _freehandCanvasRepaintVersion.dispose();
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

  /// Đồng bộ dữ liệu mảng `lines` (chữ đánh máy + cụm nét viết tay Sổ dự giờ) và `freehandStrokes` (nét vẽ tự do Ghi chú) từ JSON vào RAM
  void _applyNotebookToRowControllers(
    NotebookModel notebook, {
    required int pageIndex,
  }) {
    _lastCleanRowTexts.clear();
    _rowTextColorMap.clear();
    _typedPenUndoStack.clear();
    _rowHandwritingMap.clear();
    _pageFreehandStrokes.clear();
    _freehandUndoStack.clear();
    _activeFreehandPoints.clear();
    _pendingPenSpaceCount = 0;

    for (final controller in _rowControllers.values) {
      controller.clear();
    }

    if (notebook.pages.isEmpty) {
      _freehandCanvasRepaintVersion.value++;
      return;
    }
    final int safeIndex = pageIndex.clamp(0, notebook.pages.length - 1);
    final PageModel page = notebook.pages[safeIndex];

    for (final LineModel line in page.lines) {
      final String clean = _cleanText(line.text);
      if (clean.isNotEmpty) {
        _setRowCleanText(line.rowIndex, clean);
      }
      if (line.textColorValue != null) {
        _rowTextColorMap[line.rowIndex] = line.textColorValue!;
      }
      if (line.handwritingClusters.isNotEmpty) {
        _rowHandwritingMap[line.rowIndex] =
            List<HandwritingClusterModel>.from(line.handwritingClusters);
      }
    }

    if (page.freehandStrokes.isNotEmpty) {
      _pageFreehandStrokes.addAll(page.freehandStrokes);
    }
    _freehandCanvasRepaintVersion.value++;
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
            if (_isViewOnlyMode || !_rowUsesBackspaceSentinel(rowIndex)) {
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
          if (_isViewOnlyMode || _isPenMode) {
            node.unfocus();
            return;
          }
          if (node.hasFocus && _isKeyboardMode && mounted) {
            if (_rowUsesBackspaceSentinel(rowIndex)) {
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
                _pendingPenSpaceCount = 0;
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
        (_rowUsesBackspaceSentinel(rowIndex) && raw.startsWith(_kZeroWidthSpace))
            ? rawOffset - 1
            : rawOffset;
    return cleanOffset.clamp(0, clean.length);
  }

  /// Tính chính xác vị trí ký tự (cleanOffset) tại điểm chạm ngang `tapLocalDx` trên câu
  /// (Hỗ trợ cả trường căn trái `TextAlign.left` và trường căn giữa `TextAlign.center` như Ô điểm, Ngày/Tháng/Năm)
  int _calculateCleanOffsetFromTapDx({
    required String cleanText,
    required double tapLocalDx,
    required double horizontalPadding,
    required TextStyle rowTextStyle,
    TextAlign textAlign = TextAlign.left,
    double? maxFieldTextWidth,
    bool isDraggingCursor = false,
  }) {
    if (cleanText.isEmpty) return 0;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: cleanText, style: rowTextStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(minWidth: 0, maxWidth: double.infinity);

    double textStartX = horizontalPadding;
    if (textAlign == TextAlign.center && maxFieldTextWidth != null) {
      textStartX += math.max(0.0, (maxFieldTextWidth - painter.width) / 2.0);
      // Nếu người dùng chỉ chạm đơn (không phải kéo con trỏ) vào khoảng trống bên trái chữ căn giữa
      // thì ưu tiên đặt con trỏ về cuối chuỗi để nhập tiếp thay vì nhảy về đầu chuỗi
      if (!isDraggingCursor && tapLocalDx < textStartX - 4.0) {
        return cleanText.length;
      }
    }

    final double textX = (tapLocalDx - textStartX).clamp(0.0, double.infinity);

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
      _isPenSheetOpen = false;
    });
  }

  /// Hàm chọn 1 dòng trên trang vở và đặt con trỏ đúng vào vị trí điểm chạm trên câu (dành cho chế độ Bàn phím & Viết bút - Nét đánh máy)
  void _handleSelectRow(
    int rowIndex,
    double rowHeight, {
    double? tapLocalDx,
    double? horizontalPadding,
    TextStyle? rowTextStyle,
    TextAlign textAlign = TextAlign.left,
    double? maxFieldTextWidth,
    bool isDraggingCursor = false,
  }) {
    // Nếu đang ở chế độ "Chỉ xem", lỗi bộ nhớ RAM, hoặc đang ở chế độ "Nét viết tự nhiên" (vẽ trực tiếp trên mặt giấy) -> Không chọn dòng
    if (_isViewOnlyMode ||
        _syncRepository.hasRamErrorNotifier.value ||
        _isPenFreehandMode) {
      FocusScope.of(context).unfocus();
      return;
    }

    final TextEditingController ctrl = _getOrCreateRowController(rowIndex);
    final String clean = _cleanText(ctrl.text);
    final bool wasRowAlreadySelected = _selectedRowIndex == rowIndex;

    // Xác định vị trí con trỏ:
    // - Nếu người dùng mới chạm chọn vào một ô căn giữa (Ô điểm 500..511, Ngày/Tháng/Năm 601..603, Họ tên ký 604)
    //   thì luôn đặt con trỏ trỏ về phía sau cùng (clean.length) để nhập tiếp ngay lập tức.
    // - Khi ô đã được chọn, người dùng có thể chạm trực tiếp lên chữ hoặc nắm kéo ngang con trỏ đến mọi vị trí ký tự.
    final int targetCleanOffset;
    if (!wasRowAlreadySelected &&
        !isDraggingCursor &&
        textAlign == TextAlign.center) {
      targetCleanOffset = clean.length;
    } else if (tapLocalDx != null &&
        horizontalPadding != null &&
        rowTextStyle != null) {
      targetCleanOffset = _calculateCleanOffsetFromTapDx(
        cleanText: clean,
        tapLocalDx: tapLocalDx,
        horizontalPadding: horizontalPadding,
        rowTextStyle: rowTextStyle,
        textAlign: textAlign,
        maxFieldTextWidth: maxFieldTextWidth,
        isDraggingCursor: isDraggingCursor,
      );
    } else {
      targetCleanOffset = clean.length;
    }

    _setRowCleanText(
      rowIndex,
      clean,
      cursorCleanOffset: targetCleanOffset,
      forceSentinel: _rowUsesBackspaceSentinel(rowIndex),
    );

    setState(() {
      if (_selectedRowIndex != rowIndex) {
        _pendingPenSpaceCount = 0;
      }
      _selectedRowIndex = rowIndex;
      if (_isPenTypedMode) {
        _isPenSheetOpen = true;
      }
    });

    if (_isPenTypedMode) {
      FocusScope.of(context).unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      if (_isNotePenEraserMode && !isDraggingCursor) {
        _handlePenBackspace();
      }
      return;
    }

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

  /// Đo tổng chiều ngang (pixel) của danh sách các cụm nét chữ viết tay đã chuẩn hóa trên dòng `lineHeight`
  double _measureHandwritingClustersWidth(
    List<HandwritingClusterModel> clusters,
    double lineHeight, {
    bool hasLeadingText = false,
  }) {
    if (clusters.isEmpty) return 0.0;
    double total = 0.0;
    for (int i = 0; i < clusters.length; i++) {
      final HandwritingClusterModel c = clusters[i];
      if (i > 0 || hasLeadingText) {
        total += c.getLeadingGap(lineHeight);
      }
      total += c.getRenderedWidth(lineHeight);
    }
    return total;
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

  /// Xử lý khi người dùng xóa hết chữ ở dòng `rowIndex` hoặc bấm Xóa ở đầu dòng:
  /// Tự động nhảy con trỏ ngược lên cuối dòng phía trên (`rowIndex - 1`) và dồn các dòng dưới lên
  void _jumpOrMergeToPreviousRow({
    required int rowIndex,
    required String remainingCleanOnCurrentRow,
    double? maxLineTextWidth,
    TextStyle? rowTextStyle,
    double? rowHeight,
  }) {
    final bounds = _getRowSectionBounds(rowIndex);
    if (bounds.isSingleLine || rowIndex <= bounds.minRow) return;

    _isWrappingLine = true;
    try {
      final int prevRow = rowIndex - 1;
      final String prevClean =
          _cleanText(_getOrCreateRowController(prevRow).text);

      // Dịch chuyển các dòng phía dưới `rowIndex` lên 1 bậc trong cùng vùng nếu dòng `rowIndex` bị xóa trống
      final int maxRowIdx = _isPrimaryEvalTemplate
          ? bounds.maxRow
          : (_rowControllers.keys.isEmpty
              ? rowIndex
              : _rowControllers.keys.reduce(math.max));

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
          forceSentinel: _rowUsesBackspaceSentinel(prevRow),
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
          forceSentinel: _rowUsesBackspaceSentinel(prevRow),
        );
        if (rowHeight != null && !_isPrimaryEvalTemplate) {
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
          forceSentinel: _rowUsesBackspaceSentinel(prevRow),
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
            forceSentinel: _rowUsesBackspaceSentinel(prevRow),
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
    final bounds = _getRowSectionBounds(startRowIndex);
    if (bounds.isSingleLine) return;

    int currentRow = startRowIndex;
    int? targetFocusRow = keepFocusOnRow;
    int targetCursorCleanOffset = keepCursorCleanOffset ?? 0;

    while (true) {
      if (currentRow >= bounds.maxRow) {
        break;
      }
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
        forceSentinel: _rowUsesBackspaceSentinel(focusRow),
      );
      if (!_isPrimaryEvalTemplate) {
        _ensureRowVisible(focusRow, rowHeight);
      }
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

    final bounds = _getRowSectionBounds(rowIndex);
    final bool usesSentinel = _rowUsesBackspaceSentinel(rowIndex);
    final String prevClean = _lastCleanRowTexts[rowIndex] ?? '';
    final String currentClean = _cleanText(rawNewText);

    // 1. Kiểm tra nếu người dùng bấm Xóa (Backspace) ở dòng có ký tự neo:
    // - Hoặc đã xóa mất ký tự neo `_kZeroWidthSpace` ở đầu dòng
    // - Hoặc vừa xóa hết ký tự cuối cùng của dòng (`prevClean` có chữ -> `currentClean` rỗng)
    if (usesSentinel) {
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

    // Nếu đang nhập điểm tiêu chí (500 -> 511) trên Phiếu đánh giá tiết dạy Tiểu học:
    // Kiểm tra không vượt quá điểm tối đa, tự động cộng Tổng điểm và tự động xét loại tiết dạy
    if (_isPrimaryEvalTemplate &&
        PrimarySchoolEvaluationTemplate.isScoreRow(rowIndex)) {
      _handlePrimaryEvalScoreUpdated(rowIndex, currentClean);
      await _saveLinesToRamAndScheduleDriveSync();
      return;
    }

    if (!bounds.isSingleLine) {
      // 2. Nếu người dùng xóa bớt ký tự trên dòng hiện tại mà dòng kế tiếp (`rowIndex + 1`) trong cùng vùng đang có chữ:
      // Tự động kéo chữ từ dòng dưới lên để lấp đầy chiều ngang như Word
      if (currentClean.length < prevClean.length && rowIndex < bounds.maxRow) {
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
                (usesSentinel ? rawOffset - 1 : rawOffset)
                    .clamp(0, currentClean.length);

            final String combined = '$currentClean$nextClean';
            _setRowCleanText(rowIndex + 1, '');
            _setRowCleanText(
              rowIndex,
              combined,
              cursorCleanOffset: cleanCursorOffset,
              forceSentinel: usesSentinel,
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

      // 3. Nếu người dùng viết hết chiều ngang dòng/cột -> Tự động ngắt chữ chuyển xuống dòng tiếp theo trong vùng
      if (rowIndex < bounds.maxRow &&
          _measureTextWidth(currentClean, rowTextStyle) > maxLineTextWidth) {
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
    }

    await _saveLinesToRamAndScheduleDriveSync();
  }

  /// Tự động kiểm tra điểm tối đa, tính lại Tổng điểm và tự động điền Xếp loại tiết dạy khi nhập điểm tiêu chí
  void _handlePrimaryEvalScoreUpdated(int scoreRowIndex, String currentClean) {
    final int specIdx =
        scoreRowIndex - PrimarySchoolEvaluationTemplate.scoreStartRow;
    if (specIdx >= 0 &&
        specIdx < PrimarySchoolEvaluationTemplate.criteriaList.length) {
      final ObservationCriterionSpec spec =
          PrimarySchoolEvaluationTemplate.criteriaList[specIdx];
      final double? parsed =
          PrimarySchoolEvaluationTemplate.parseScoreString(currentClean);
      if (parsed != null && parsed > spec.maxScore) {
        final String clampedStr =
            PrimarySchoolEvaluationTemplate.formatScoreVi(spec.maxScore);
        _isWrappingLine = true;
        try {
          _setRowCleanText(
            scoreRowIndex,
            clampedStr,
            cursorCleanOffset: clampedStr.length,
          );
        } finally {
          _isWrappingLine = false;
        }
      }
    }

    final eval = PrimarySchoolEvaluationTemplate.evaluateScores(
      (int idx) => _cleanText(_rowControllers[idx]?.text ?? ''),
    );

    if (eval.suggestedRating != null) {
      final String currentRating = _cleanText(
        _rowControllers[PrimarySchoolEvaluationTemplate.rowEvaluatedRating]
                ?.text ??
            '',
      ).trim();
      const Set<String> autoRatings = <String>{
        '',
        'Giỏi',
        'Khá',
        'Trung bình',
        'Chưa đạt',
      };
      if (autoRatings.contains(currentRating)) {
        _isWrappingLine = true;
        try {
          _setRowCleanText(
            PrimarySchoolEvaluationTemplate.rowEvaluatedRating,
            eval.suggestedRating!,
            cursorCleanOffset: eval.suggestedRating!.length,
          );
        } finally {
          _isWrappingLine = false;
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Đóng gói dữ liệu sạch của các dòng vào JSON (RAM 0ms + hẹn 30 giây đẩy lên Google Drive)
  Future<void> _saveLinesToRamAndScheduleDriveSync({
    bool forceSave = false,
  }) async {
    if ((!forceSave && _isViewOnlyMode) ||
        _syncRepository.hasRamErrorNotifier.value) {
      return;
    }

    final NotebookModel? currentNotebook = _notebook;
    if (currentNotebook == null) return;

    // Gom tất cả các dòng có nội dung chữ hoặc cụm nét chữ viết tay trên trang hiện tại thành mảng JSON `lines`
    final List<LineModel> updatedLines = <LineModel>[];
    final Set<int> allRowIndices = <int>{
      ..._rowControllers.keys,
      ..._rowHandwritingMap.keys,
    };
    final List<int> sortedRowIndices = allRowIndices.toList()..sort();

    for (final int idx in sortedRowIndices) {
      final String textValue = _cleanText(_rowControllers[idx]?.text ?? '');
      final List<HandwritingClusterModel> clusters =
          _rowHandwritingMap[idx] ?? const <HandwritingClusterModel>[];
      if (textValue.trim().isNotEmpty || clusters.isNotEmpty) {
        updatedLines.add(
          LineModel(
            rowIndex: idx,
            text: textValue,
            textColorValue: _rowTextColorMap[idx],
            handwritingClusters: List<HandwritingClusterModel>.from(clusters),
          ),
        );
      }
    }

    final List<FreehandPageStrokeModel> currentFreehand =
        List<FreehandPageStrokeModel>.from(_pageFreehandStrokes);

    final List<PageModel> updatedPages =
        List<PageModel>.from(currentNotebook.pages);
    if (updatedPages.isEmpty) {
      updatedPages.add(
        PageModel(
          pageNumber: 1,
          lines: updatedLines,
          freehandStrokes: currentFreehand,
        ),
      );
    } else {
      updatedPages[_currentPageIndex] =
          updatedPages[_currentPageIndex].copyWith(
        lines: updatedLines,
        freehandStrokes: currentFreehand,
      );
    }

    final String effectiveTemplate = _isPrimaryEvalTemplate
        ? PrimarySchoolEvaluationTemplate.templateId
        : _activeTemplateId;

    final NotebookModel updatedNotebook = currentNotebook.copyWith(
      paperTemplate: effectiveTemplate,
      updatedAt: DateTime.now().toIso8601String(),
      pages: updatedPages,
    );

    _notebook = updatedNotebook;

    // Lưu tức thì vào RAM (0ms) và đặt bộ đếm 30 giây tự động ghi đè JSON lên Google Drive
    try {
      await _syncRepository.onUserWritingChanged(
        documentId: widget.fileItem.id,
        fileName: widget.fileItem.displayName,
        tabIndex: widget.tabIndex,
        parentFolderId: widget.fileItem.parentFolderId,
        existingDriveFileId: widget.fileItem.id,
        updatedJsonData: updatedNotebook.toJson(),
      );
    } catch (_) {
      // Nếu không lưu được vào RAM -> Báo "Có lỗi bộ nhớ" và khóa chọn dòng ngay lập tức
      _syncRepository.hasRamErrorNotifier.value = true;
      _closeKeyboardAndDeselectRow();
      if (mounted) {
        setState(() {});
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

  /// Tạo bản chụp (Snapshot) NotebookModel mới nhất trên RAM từ các dòng & nét bút đang hiển thị trên màn hình
  /// để phục vụ xuất file PDF / Word chuẩn xác 100% nội dung vừa nhập
  NotebookModel _buildLatestNotebookSnapshotInRam() {
    final List<LineModel> currentLines = <LineModel>[];
    final Set<int> allRowIndices = <int>{
      ..._rowControllers.keys,
      ..._rowHandwritingMap.keys,
    };
    final List<int> sortedRowIndices = allRowIndices.toList()..sort();

    for (final int idx in sortedRowIndices) {
      final String textValue = _cleanText(_rowControllers[idx]?.text ?? '');
      final List<HandwritingClusterModel> clusters =
          _rowHandwritingMap[idx] ?? const <HandwritingClusterModel>[];
      if (textValue.trim().isNotEmpty || clusters.isNotEmpty) {
        currentLines.add(
          LineModel(
            rowIndex: idx,
            text: textValue,
            textColorValue: _rowTextColorMap[idx],
            handwritingClusters: List<HandwritingClusterModel>.from(clusters),
          ),
        );
      }
    }

    final List<FreehandPageStrokeModel> currentFreehand =
        List<FreehandPageStrokeModel>.from(_pageFreehandStrokes);

    final NotebookModel? baseNotebook = _notebook;
    final String effectiveTemplate = _isPrimaryEvalTemplate
        ? PrimarySchoolEvaluationTemplate.templateId
        : _activeTemplateId;

    if (baseNotebook == null) {
      return NotebookModel(
        id: widget.fileItem.id,
        title: widget.fileItem.displayName,
        paperTemplate: effectiveTemplate,
        updatedAt: DateTime.now().toIso8601String(),
        pages: <PageModel>[
          PageModel(
            pageNumber: 1,
            lines: currentLines,
            freehandStrokes: currentFreehand,
          ),
        ],
      );
    }

    final List<PageModel> updatedPages =
        List<PageModel>.from(baseNotebook.pages);
    if (updatedPages.isEmpty) {
      updatedPages.add(
        PageModel(
          pageNumber: 1,
          lines: currentLines,
          freehandStrokes: currentFreehand,
        ),
      );
    } else {
      updatedPages[_currentPageIndex] =
          updatedPages[_currentPageIndex].copyWith(
        lines: currentLines,
        freehandStrokes: currentFreehand,
      );
    }

    return baseNotebook.copyWith(
      paperTemplate: effectiveTemplate,
      updatedAt: DateTime.now().toIso8601String(),
      pages: updatedPages,
    );
  }

  /// Hiển thị hộp thoại chọn định dạng Xuất file (PDF hoặc Word)
  /// và đẩy thẳng file xuất từ RAM vào thư mục `MeetingBook/Export File/Ghi chú` hoặc `MeetingBook/Export File/Sổ dự giờ`
  Future<void> _showExportFileDialog() async {
    if (_isExportingFile || _isLoadingJson) return;

    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');

    final int effectiveTabIndex =
        (widget.tabIndex == 1 || _isPrimaryEvalTemplate) ? 1 : 0;
    final String subFolderLabel =
        effectiveTabIndex == 1 ? 'Sổ dự giờ' : 'Ghi chú';
    final String currentTitle = _notebook?.title ?? widget.fileItem.displayName;

    final String? selectedFormat = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        final double titleSize =
            AppTheme.getResponsiveFontSize(dialogContext, 18);
        final double bodySize =
            AppTheme.getResponsiveFontSize(dialogContext, 14);
        final double subSize =
            AppTheme.getResponsiveFontSize(dialogContext, 12.5);

        return Dialog(
          backgroundColor: AppColors.creamBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(
              color: AppColors.primaryBlue,
              width: 2,
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.ios_share_rounded,
                          color: AppColors.basicWhite,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Xuất tệp lên Google Drive',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.basicBlack,
                        ),
                        tooltip: 'Đóng',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.basicWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tệp đang mở: $currentTitle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.basicBlack,
                            fontSize: bodySize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.folder_special_outlined,
                              color: AppColors.primaryBlue,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Nơi lưu: MeetingBook / Export File / $subFolderLabel',
                                style: TextStyle(
                                  color: AppColors.primaryBlue,
                                  fontSize: subSize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chọn định dạng tệp muốn xuất:',
                    style: TextStyle(
                      color: AppColors.basicBlack,
                      fontSize: subSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Lựa chọn 1: Xuất file PDF
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(dialogContext).pop('pdf'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.basicWhite,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primaryBlue,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.creamBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: AppColors.primaryBlue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Xuất file PDF',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: bodySize * 1.04,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primaryBlue,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Lựa chọn 2: Xuất file Word
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(dialogContext).pop('word'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.basicWhite,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primaryBlue,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.creamBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.description_rounded,
                              color: AppColors.primaryBlue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Xuất file Word',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontSize: bodySize * 1.04,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primaryBlue,
                          ),
                        ],
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

    if (!mounted || selectedFormat == null) return;
    await _handleExportFile(isPdf: selectedFormat == 'pdf');
  }

  /// Đo đạc tọa độ thực tế của 3 trang biểu mẫu & ô chữ ký Người dự giờ ngay trên màn hình hiện tại
  EvaluationExportLayoutBounds _measureEvaluationExportLayoutBounds() {
    final RenderObject? stackObj =
        _evalFormStackKey.currentContext?.findRenderObject();
    if (stackObj is! RenderBox ||
        !stackObj.hasSize ||
        _lastMeasuredEvalPaperWidth <= 0 ||
        _lastMeasuredEvalRowHeight <= 0) {
      return const EvaluationExportLayoutBounds();
    }

    ({double startNx, double endNx, double startRy, double endRy})? measureBox(
      GlobalKey key,
    ) {
      final RenderObject? ro = key.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize) return null;
      final Offset topLeft = ro.localToGlobal(Offset.zero, ancestor: stackObj);
      final Size sz = ro.size;
      return (
        startNx: (topLeft.dx / _lastMeasuredEvalPaperWidth).clamp(0.0, 1.0),
        endNx:
            ((topLeft.dx + sz.width) / _lastMeasuredEvalPaperWidth).clamp(0.0, 1.0),
        startRy: math.max(0.0, topLeft.dy / _lastMeasuredEvalRowHeight),
        endRy: math.max(
          0.1,
          (topLeft.dy + sz.height) / _lastMeasuredEvalRowHeight,
        ),
      );
    }

    final p1 = measureBox(_evalPage1Key);
    final p2 = measureBox(_evalPage2Key);
    final p3 = measureBox(_evalPage3Key);
    final sig = measureBox(_evalSignatureBoxKey);

    const defaults = EvaluationExportLayoutBounds();
    return EvaluationExportLayoutBounds(
      page1StartRy: p1?.startRy ?? defaults.page1StartRy,
      page1EndRy: p1?.endRy ?? defaults.page1EndRy,
      page2StartRy: p2?.startRy ?? defaults.page2StartRy,
      page2EndRy: p2?.endRy ?? defaults.page2EndRy,
      page3StartRy: p3?.startRy ?? defaults.page3StartRy,
      page3EndRy: p3?.endRy ?? defaults.page3EndRy,
      sigStartNx: sig?.startNx ?? defaults.sigStartNx,
      sigEndNx: sig?.endNx ?? defaults.sigEndNx,
      sigStartRy: sig?.startRy ?? defaults.sigStartRy,
      sigEndRy: sig?.endRy ?? defaults.sigEndRy,
    );
  }

  /// Xử lý tạo mảng byte PDF / Word ngay trên RAM (không lưu ổ cứng)
  /// và đẩy thẳng lên thư mục `MeetingBook/Export File/Ghi chú` hoặc `MeetingBook/Export File/Sổ dự giờ`
  Future<void> _handleExportFile({required bool isPdf}) async {
    if (_isExportingFile) return;

    setState(() {
      _isExportingFile = true;
    });

    try {
      // Đồng bộ dữ liệu mới nhất vào RAM trước khi xuất
      if (!_isViewOnlyMode) {
        await _saveLinesToRamAndScheduleDriveSync();
      }

      final NotebookModel snapshot = _buildLatestNotebookSnapshotInRam();
      final int effectiveTabIndex =
          (widget.tabIndex == 1 || _isPrimaryEvalTemplate) ? 1 : 0;
      final String subFolderLabel =
          effectiveTabIndex == 1 ? 'Sổ dự giờ' : 'Ghi chú';
      final String baseName = snapshot.title.trim().isNotEmpty
          ? snapshot.title.trim()
          : widget.fileItem.displayName;

      // 1. Khởi tạo byte PDF hoặc Word trực tiếp trên RAM
      final EvaluationExportLayoutBounds? evalLayoutBounds =
          effectiveTabIndex == 1
              ? _measureEvaluationExportLayoutBounds()
              : null;
      final Uint8List exportedBytes = isPdf
          ? await PdfExportService.generatePdfBytes(
              notebook: snapshot,
              tabIndex: effectiveTabIndex,
              evalLayoutBounds: evalLayoutBounds,
            )
          : WordExportService.generateWordBytes(
              notebook: snapshot,
              tabIndex: effectiveTabIndex,
              evalLayoutBounds: evalLayoutBounds,
            );

      final String extension = isPdf ? '.pdf' : '.doc';
      final String mimeType =
          isPdf ? 'application/pdf' : 'application/msword';

      // 2. Đẩy thẳng từ RAM lên đúng thư mục con trong `MeetingBook/Export File/` trên Google Drive
      await _driveDatasource.uploadExportedFileToDrive(
        tabIndex: effectiveTabIndex,
        baseFileName: baseName,
        extension: extension,
        mimeType: mimeType,
        fileBytes: exportedBytes,
      );

      if (mounted) {
        setState(() {
          _isExportingFile = false;
        });

        final String exportedFullName = baseName.toLowerCase().endsWith(extension)
            ? baseName
            : '$baseName$extension';

        await showCenterNotification(
          context: context,
          title: isPdf
              ? 'Xuất file PDF thành công'
              : 'Xuất file Word thành công',
          message:
              'Đã xuất "$exportedFullName" chuẩn định dạng lên Google Drive tại:\nMeetingBook / Export File / $subFolderLabel',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isExportingFile = false;
        });
        await showCenterNotification(
          context: context,
          title: 'Xuất file thất bại',
          message:
              'Không thể xuất tệp lên Google Drive. Vui lòng kiểm tra kết nối mạng và thử lại!',
          isError: true,
        );
      }
    }
  }

  /// Hộp thoại xác nhận "Làm sạch" toàn bộ nội dung hiện tại trong tệp (áp dụng cho cả Ghi chú & Sổ dự giờ)
  /// Khi bấm "Đồng ý" -> Xóa sạch toàn bộ nội dung trong tệp và hiển thị thông báo Thành công kèm nút "Hoàn tác"
  Future<void> _showClearContentConfirmDialog() async {
    if (_isLoadingJson || _isExportingFile) return;

    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');

    final String itemTypeLabel =
        _isPrimaryEvalTemplate ? 'sổ dự giờ' : 'ghi chú';
    final String fileDisplayName = widget.fileItem.displayName;
    bool isClearing = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final Size screenSize = MediaQuery.sizeOf(dialogContext);
        final double dialogWidth =
            (screenSize.width * 0.68).clamp(320.0, 540.0);
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
            Future<void> confirmClearContent() async {
              setDialogState(() => isClearing = true);

              // Lưu bản chụp (Snapshot) toàn bộ nội dung trước khi làm sạch để hỗ trợ Hoàn tác 100%
              final NotebookModel backupSnapshot =
                  _buildLatestNotebookSnapshotInRam();

              try {
                _lastCleanRowTexts.clear();
                _rowTextColorMap.clear();
                _typedPenUndoStack.clear();
                _rowHandwritingMap.clear();
                _pageFreehandStrokes.clear();
                _freehandUndoStack.clear();
                _activeFreehandPoints.clear();
                _pendingPenSpaceCount = 0;
                for (final TextEditingController ctrl
                    in _rowControllers.values) {
                  ctrl.clear();
                }
                _freehandCanvasRepaintVersion.value++;

                if (mounted) {
                  setState(() {
                    _selectedRowIndex = null;
                  });
                }

                await _saveLinesToRamAndScheduleDriveSync(forceSave: true);
                await _syncRepository.syncOnPageExit();

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }

                if (mounted) {
                  await showCenterNotification(
                    context: this.context,
                    title: 'Thành công',
                    message:
                        'Đã làm sạch nội dung tệp $itemTypeLabel "$fileDisplayName"',
                    onUndo: () async {
                      _applyNotebookToRowControllers(
                        backupSnapshot,
                        pageIndex: _currentPageIndex,
                      );
                      if (mounted) {
                        setState(() {
                          _notebook = backupSnapshot;
                        });
                      }
                      await _saveLinesToRamAndScheduleDriveSync(
                        forceSave: true,
                      );
                      await _syncRepository.syncOnPageExit();
                    },
                  );
                }
              } catch (_) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  await showCenterNotification(
                    context: this.context,
                    title: 'Thất bại',
                    message:
                        'Không thể làm sạch nội dung tệp "$fileDisplayName"',
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
                        'Xác nhận làm sạch nội dung',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Bạn có chắc chắn muốn xóa toàn bộ nội dung hiện tại trong tệp $itemTypeLabel "$fileDisplayName" không?',
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
                            onPressed: isClearing
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
                            onPressed: isClearing ? null : confirmClearContent,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.dangerRed,
                              foregroundColor: AppColors.basicWhite,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: isClearing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: AppColors.basicWhite,
                                    ),
                                  )
                                : Text(
                                    'Đồng ý',
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

  @override
  Widget build(BuildContext context) {
    final String activeTemplate = _activeTemplateId;
    final bool isNote4x = activeTemplate == Note4x.templateId;
    final bool isPrimaryEval = _isPrimaryEvalTemplate;

    final Size screenSize = MediaQuery.sizeOf(context);
    final double titleFontSize = AppTheme.getResponsiveFontSize(context, 16);
    final double badgeFontSize = AppTheme.getResponsiveFontSize(context, 12);

    // Chiều ngang trang giấy phụ thuộc vào màn hình máy và mức phóng to (_zoomScale):
    // - Nếu máy đủ to và ở 100%: hiển thị toàn bộ chiều ngang giấy.
    // - Nếu màn nhỏ hoặc đang phóng to (> 100%): hiện thêm con lăn trái/phải và cho phép giữ chuột kéo qua đủ chỗ.
    final double paperWidth = isPrimaryEval
        ? PrimarySchoolEvaluationTemplate.getResponsivePaperWidth(
            screenSize.width,
          )
        : (isNote4x
            ? Note4x.getResponsivePaperWidth(screenSize.width)
            : Note5x.getResponsivePaperWidth(screenSize.width));
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
        backgroundColor: isPrimaryEval
            ? PrimarySchoolEvaluationTemplate.getPaperBackgroundColor()
            : (isNote4x
                ? Note4x.getPaperBackgroundColor()
                : Note5x.getPaperBackgroundColor()),
        body: ValueListenableBuilder<bool>(
          valueListenable: _syncRepository.hasRamErrorNotifier,
          builder: (context, hasRamError, _) {
            return Stack(
              children: [
                Column(
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
                                          maxWidth: screenSize.width * 0.45,
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
                                                padding:
                                                    const EdgeInsets.symmetric(
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.arrow_back_rounded,
                                                      color:
                                                          AppColors.basicWhite,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      'Quay lại',
                                                      style: TextStyle(
                                                        color: AppColors
                                                            .basicWhite,
                                                        fontSize:
                                                            badgeFontSize *
                                                                1.05,
                                                        fontWeight:
                                                            FontWeight.w600,
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
                                              fontSize: badgeFontSize,
                                            ),
                                            const SizedBox(width: 8),

                                            // 1. Nút Lưu JSON ngay lập tức
                                            ValueListenableBuilder<bool>(
                                              valueListenable: _syncRepository
                                                  .isSyncingDriveNotifier,
                                              builder:
                                                  (context, isSyncing, _) {
                                                return InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(18),
                                                  onTap:
                                                      (isSyncing || hasRamError)
                                                          ? null
                                                          : _handleManualSaveNow,
                                                  child: Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 12,
                                                      vertical: 7,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          AppColors.basicWhite,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        18,
                                                      ),
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
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Text(
                                                          isSyncing
                                                              ? 'Đang lưu...'
                                                              : 'Lưu',
                                                          style: TextStyle(
                                                            color: AppColors
                                                                .primaryBlue,
                                                            fontSize:
                                                                badgeFontSize,
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

                                            // 3. Nút Menu 3 gạch nằm sát bên phải (Gom các nút: Chỉ xem, Bàn phím, Viết bút, Xuất file, Làm mới)
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

                    // 2. Vùng thân: Mặt giấy kẻ ngang hoặc Biểu mẫu dự giờ có bộ cuộn lướt bình thường (Chặn thao tác ngay nếu có lỗi RAM)
                    Expanded(
                      child: IgnorePointer(
                        ignoring: hasRamError,
                        child: _buildPaperBody(
                          isNote4x: isNote4x,
                          isPrimaryEval: isPrimaryEval,
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

                    // 4b. Bảng viết bút Bottom Sheet khi chọn chế độ "Nét đánh máy" trong Bong bóng Bút
                    if (_isPenTypedMode &&
                        _selectedRowIndex != null &&
                        _isPenSheetOpen &&
                        !hasRamError)
                      _buildPenWritingBottomSheet(fontSize: badgeFontSize),
                  ],
                ),

                // 5. Bong bóng công cụ Bút viết nổi kéo thả tự do (Dùng chung cho cả Tab Ghi chú & Tab Sổ dự giờ ở chế độ Viết bút)
                if (_isPenMode && !hasRamError)
                  Positioned.fill(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _freehandCanvasRepaintVersion,
                      builder: (context, _, child) {
                        final bool canUndoPen =
                            _typedPenUndoStack.isNotEmpty ||
                                _freehandUndoStack.isNotEmpty ||
                                _pageFreehandStrokes.isNotEmpty ||
                                _observationPenUndoStack.isNotEmpty ||
                                _getTotalHandwritingClustersCount() > 0;
                        final int currentCount = _pageFreehandStrokes.length +
                            _getTotalHandwritingClustersCount();

                        return FloatingPenBubbleWidget(
                          selectedColorValue: _selectedPenColorValue,
                          selectedStrokeWidth: _selectedPenStrokeWidth,
                          selectedPenStyle: _selectedPenStyle,
                          isEraserMode: _isNotePenEraserMode,
                          isRulerVisible: _isRulerVisible,
                          isTypedHandwritingMode: _isPenTypedHandwritingMode,
                          canUndo: canUndoPen,
                          strokeOrClusterCount: currentCount,
                          isObservationMode: isPrimaryEval,
                          onColorChanged: (int newColor) {
                            setState(() {
                              _selectedPenColorValue = newColor;
                              if (_isPenTypedMode &&
                                  _selectedRowIndex != null) {
                                _rowTextColorMap[_selectedRowIndex!] = newColor;
                              }
                            });
                            if (_isPenTypedMode && _selectedRowIndex != null) {
                              _saveLinesToRamAndScheduleDriveSync();
                            }
                          },
                          onStrokeWidthChanged: (double newWidth) {
                            setState(() {
                              _selectedPenStrokeWidth = newWidth;
                            });
                          },
                          onPenStyleChanged: (String newStyle) {
                            setState(() {
                              _selectedPenStyle = newStyle;
                            });
                          },
                          onEraserModeChanged: (bool isEraser) {
                            setState(() {
                              _isNotePenEraserMode = isEraser;
                              if (!isEraser) {
                                _currentEraserCursorOffset = null;
                              }
                            });
                          },
                          onTypedHandwritingModeChanged: (bool isTypedMode) {
                            FocusScope.of(context).unfocus();
                            SystemChannels.textInput
                                .invokeMethod('TextInput.hide');
                            setState(() {
                              _isPenTypedHandwritingMode = isTypedMode;
                              if (isTypedMode) {
                                _selectedRowIndex ??= 0;
                                _isPenSheetOpen = true;
                                _isRulerVisible = false;
                                _activeRulerSnapEdgeSign = null;
                              } else {
                                _isPenSheetOpen = false;
                                _selectedRowIndex = null;
                                _pendingPenSpaceCount = 0;
                              }
                            });
                          },
                          onRulerVisibilityChanged: (bool visible) {
                            setState(() {
                              if (visible && _isPenTypedHandwritingMode) {
                                _isPenTypedHandwritingMode = false;
                                _isPenSheetOpen = false;
                                _selectedRowIndex = null;
                              }
                              _isRulerVisible = visible;
                              _activeRulerSnapEdgeSign = null;
                              if (visible) {
                                final double scrollY =
                                    _scrollController.hasClients
                                        ? (_scrollController.offset /
                                            _zoomScale)
                                        : 0.0;
                                final double scrollX =
                                    _horizontalScrollController.hasClients
                                        ? (_horizontalScrollController.offset /
                                            _zoomScale)
                                        : 0.0;
                                final double visibleW = math.min(
                                  paperWidth,
                                  screenSize.width / _zoomScale,
                                );
                                final double visibleH = math.max(
                                  200.0,
                                  (screenSize.height - 110.0) / _zoomScale,
                                );
                                _rulerCenterOnPaper = Offset(
                                  (scrollX + visibleW * 0.5).clamp(
                                    80.0,
                                    math.max(80.0, paperWidth - 80.0),
                                  ),
                                  math.max(90.0, scrollY + visibleH * 0.42),
                                );
                              }
                            });
                          },
                          onUndoPressed: _handleUndoFreehandStroke,
                        );
                      },
                    ),
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

  /// Xây dựng mặt giấy kẻ ngang hoặc Biểu mẫu dự giờ 3 trang có tích hợp bộ cuộn (`Scrollbar` + `SingleChildScrollView`)
  /// và giới hạn chiều ngang viết tự động xuống dòng khi viết hết chiều ngang giấy
  Widget _buildPaperBody({
    required bool isNote4x,
    required bool isPrimaryEval,
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
        final double paperWidth = isPrimaryEval
            ? PrimarySchoolEvaluationTemplate.getResponsivePaperWidth(
                constraints.maxWidth,
              )
            : (isNote4x
                ? Note4x.getResponsivePaperWidth(constraints.maxWidth)
                : Note5x.getResponsivePaperWidth(constraints.maxWidth));
        final double scaledPaperWidth = paperWidth * _zoomScale;
        final bool enableHorizontalScroll =
            scaledPaperWidth > constraints.maxWidth + 1.0;
        final bool isZoomedIn = _zoomScale > 1.01;

        // Tính chiều cao mỗi dòng kẻ ngang dựa trên mẫu vở 5 ô ly (note5x), 4 ô ly (note4x) hoặc biểu mẫu Sổ dự giờ
        final double rowHeight = isPrimaryEval
            ? PrimarySchoolEvaluationTemplate.getResponsiveRowHeight(
                context,
                maxWidth: paperWidth,
              )
            : (isNote4x
                ? Note4x.getResponsiveRowHeight(
                    context,
                    maxWidth: paperWidth,
                  )
                : Note5x.getResponsiveRowHeight(
                    context,
                    maxWidth: paperWidth,
                  ));

        final double horizontalPadding = isPrimaryEval
            ? PrimarySchoolEvaluationTemplate.getResponsiveHorizontalPadding(
                paperWidth,
              )
            : (isNote4x
                ? Note4x.getResponsiveHorizontalPadding(paperWidth)
                : Note5x.getResponsiveHorizontalPadding(paperWidth));

        // Chiều ngang vùng viết tối đa giữa 2 bên lề (căn đều 2 bên lề như Word)
        final double maxLineTextWidth = math.max(
          120.0,
          paperWidth - (horizontalPadding * 2) - 2.0,
        );

        final double lineFontSize = (rowHeight * 0.42).clamp(15.0, 22.0);
        final TextStyle effectiveRowTextStyle =
            (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(
          color: isPrimaryEval
              ? PrimarySchoolEvaluationTemplate.getTextColor()
              : (isNote4x ? Note4x.getTextColor() : Note5x.getTextColor()),
          fontSize: lineFontSize,
          fontWeight: FontWeight.w500,
          height: 1.15,
        );

        // Nếu đang mở biểu mẫu "Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học" (3 trang):
        // Render trực tiếp bố cục 3 trang biểu mẫu tương tác kèm lớp vẽ bút trực tiếp 60-120fps như Ghi chú
        if (isPrimaryEval) {
          _lastMeasuredEvalPaperWidth = paperWidth;
          _lastMeasuredEvalRowHeight = rowHeight;
          final double maxEvalPaperHeight = rowHeight * 250.0;
          final Widget primaryFormContent = Stack(
            key: _evalFormStackKey,
            children: [
              IgnorePointer(
                ignoring: _isViewOnlyMode || _isPenFreehandMode,
                child: PrimarySchoolEvaluationFormWidget(
                  paperWidth: paperWidth,
                  rowHeight: rowHeight,
                  bodyTextStyle: effectiveRowTextStyle,
                  page1ContentKey: _evalPage1Key,
                  page2ContentKey: _evalPage2Key,
                  page3ContentKey: _evalPage3Key,
                  signatureBoxKey: _evalSignatureBoxKey,
                  getRowCleanText: (int rIdx) =>
                      _cleanText(_rowControllers[rIdx]?.text ?? ''),
                  onApplySuggestedRating: () {
                    final eval = PrimarySchoolEvaluationTemplate.evaluateScores(
                      (int rIdx) =>
                          _cleanText(_rowControllers[rIdx]?.text ?? ''),
                    );
                    if (eval.suggestedRating != null) {
                      _setRowCleanText(
                        PrimarySchoolEvaluationTemplate.rowEvaluatedRating,
                        eval.suggestedRating!,
                        cursorCleanOffset: eval.suggestedRating!.length,
                      );
                      setState(() {});
                      _saveLinesToRamAndScheduleDriveSync();
                    }
                  },
                  buildInteractiveField: ({
                    required int rowIndex,
                    required double width,
                    required double height,
                    required TextStyle textStyle,
                    double horizontalPadding = 6.0,
                    TextAlign textAlign = TextAlign.left,
                    String? hintText,
                    TextInputType? keyboardType,
                    double bottomContentPadding = 4.0,
                  }) {
                    return _buildInteractiveObservationField(
                      rowIndex: rowIndex,
                      width: width,
                      height: height,
                      textStyle: textStyle,
                      hasRamError: hasRamError,
                      horizontalPadding: horizontalPadding,
                      textAlign: textAlign,
                      hintText: hintText,
                      keyboardType: keyboardType,
                      bottomContentPadding: bottomContentPadding,
                    );
                  },
                ),
              ),

              // Lớp vẽ bút tự do trực tiếp lên mặt giấy Sổ dự giờ 3 trang (60-120fps, như ứng dụng Paint)
              // Khi ở chế độ Bàn phím, Chỉ xem hoặc Nét đánh máy: IgnorePointer = true để chạm chọn dòng bình thường nhưng vẫn giữ nguyên nét vẽ
              Positioned.fill(
                child: IgnorePointer(
                  ignoring:
                      !_isPenFreehandMode || _isViewOnlyMode || hasRamError,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (PointerDownEvent event) =>
                        _handleNoteFreehandPointerDown(
                      event,
                      paperWidth: paperWidth,
                      rowHeight: rowHeight,
                      totalPaperHeight: maxEvalPaperHeight,
                    ),
                    onPointerMove: (PointerMoveEvent event) =>
                        _handleNoteFreehandPointerMove(
                      event,
                      paperWidth: paperWidth,
                      rowHeight: rowHeight,
                      totalPaperHeight: maxEvalPaperHeight,
                    ),
                    onPointerUp: (PointerUpEvent event) =>
                        _handleNoteFreehandPointerUp(event),
                    onPointerCancel: (PointerCancelEvent event) =>
                        _handleNoteFreehandPointerCancel(event),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _NotePageFreehandCanvasPainter(
                          committedStrokes: _pageFreehandStrokes,
                          activePoints: _activeFreehandPoints,
                          activeColorValue: _selectedPenColorValue,
                          activeStrokeWidth: _selectedPenStrokeWidth,
                          activePenStyle: _selectedPenStyle,
                          paperWidth: paperWidth,
                          rowHeight: rowHeight,
                          eraserCursorOffset: _isNotePenEraserMode
                              ? _currentEraserCursorOffset
                              : null,
                          repaint: _freehandCanvasRepaintVersion,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),

              // Cây thước kẻ ảo trên mặt giấy Sổ dự giờ (xoay 360°, tự động hít nét bút thẳng theo mép thước)
              if (_isPenFreehandMode &&
                  _isRulerVisible &&
                  !_isViewOnlyMode &&
                  !hasRamError)
                VirtualRulerOverlayWidget(
                  rulerCenter: _rulerCenterOnPaper,
                  rulerAngleRad: _rulerAngleRad,
                  rulerLength: _getRulerLength(paperWidth),
                  rulerHeight: _kRulerHeight,
                  onCenterChanged: (Offset nextCenter) {
                    setState(() {
                      _rulerCenterOnPaper = Offset(
                        nextCenter.dx.clamp(
                          40.0,
                          math.max(40.0, paperWidth - 40.0),
                        ),
                        nextCenter.dy.clamp(
                          36.0,
                          math.max(36.0, maxEvalPaperHeight - 36.0),
                        ),
                      );
                    });
                  },
                  onAngleChanged: (double nextAngleRad) {
                    setState(() {
                      _rulerAngleRad = nextAngleRad;
                    });
                  },
                  onCloseRuler: () {
                    setState(() {
                      _isRulerVisible = false;
                      _activeRulerSnapEdgeSign = null;
                    });
                  },
                ),
            ],
          );

          final Widget zoomedFormWidget = isZoomedIn
              ? SizedBox(
                  width: scaledPaperWidth,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: paperWidth,
                      child: primaryFormContent,
                    ),
                  ),
                )
              : primaryFormContent;

          final bool enableFree2DPan =
              !_isPenFreehandMode && (isZoomedIn || enableHorizontalScroll);

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
                        final double nextHoriz =
                            (_horizontalScrollController.offset -
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
                physics: (_isPenFreehandMode || enableFree2DPan)
                    ? const NeverScrollableScrollPhysics()
                    : const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                child: enableHorizontalScroll
                    ? SingleChildScrollView(
                        controller: _horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: zoomedFormWidget,
                      )
                    : zoomedFormWidget,
              ),
            ),
          );
        }

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

        // Tính tổng số dòng sao cho luôn phủ kín màn hình và tự giãn thêm khi viết dài hoặc vẽ nét bút xuống dưới
        final int minRowsToFillScreen =
            (constraints.maxHeight / rowHeight).ceil() + 4;
        final int defaultMinRows =
            isNote4x ? Note4x.defaultLineCount : Note5x.defaultLineCount;
        final int highestUsedRow = _rowControllers.keys.isEmpty
            ? 0
            : (_rowControllers.keys.reduce(math.max) + 6);
        int highestStrokeRow = 0;
        for (final stroke in _pageFreehandStrokes) {
          for (final pt in stroke.points) {
            final int r = pt.ry.ceil() + 4;
            if (r > highestStrokeRow) {
              highestStrokeRow = r;
            }
          }
        }
        final int totalRows = math.max(
          math.max(minRowsToFillScreen, defaultMinRows),
          math.max(highestUsedRow, highestStrokeRow),
        );

        final double totalPaperHeight = totalRows * rowHeight;
        final double scaledPaperHeight = totalPaperHeight * _zoomScale;

        final Widget paperSheetContent = SizedBox(
          width: paperWidth,
          height: totalPaperHeight,
          child: IgnorePointer(
            // Chế độ "Chỉ xem": cho phép cuộn trang vở mượt mà nhưng chặn hoàn toàn chọn dòng / chỉnh sửa
            ignoring: _isViewOnlyMode,
            child: Stack(
              children: [
                CustomPaint(
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
                      final bool isRowSelected = !_isViewOnlyMode &&
                          !_isPenFreehandMode &&
                          _selectedRowIndex == rowIndex;
                      final TextStyle rowTextStyleWithColor =
                          _rowTextColorMap.containsKey(rowIndex)
                              ? effectiveRowTextStyle.copyWith(
                                  color: Color(_rowTextColorMap[rowIndex]!),
                                )
                              : effectiveRowTextStyle;

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (_isViewOnlyMode || _isPenFreehandMode)
                            ? null
                            : (TapUpDetails details) => _handleSelectRow(
                                  rowIndex,
                                  rowHeight,
                                  tapLocalDx: details.localPosition.dx,
                                  horizontalPadding: horizontalPadding,
                                  rowTextStyle: rowTextStyleWithColor,
                                ),
                        onHorizontalDragUpdate: (_isViewOnlyMode ||
                                _isPenFreehandMode ||
                                !isRowSelected)
                            ? null
                            : (DragUpdateDetails details) => _handleSelectRow(
                                  rowIndex,
                                  rowHeight,
                                  tapLocalDx: details.localPosition.dx,
                                  horizontalPadding: horizontalPadding,
                                  rowTextStyle: rowTextStyleWithColor,
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
                                  ignoring: _isViewOnlyMode ||
                                      !isRowSelected ||
                                      _isPenMode,
                                  child: TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    readOnly: _isViewOnlyMode ||
                                        _isPenMode ||
                                        hasRamError,
                                    showCursor:
                                        _isKeyboardMode && isRowSelected,
                                    cursorColor: AppColors.primaryBlue,
                                    cursorWidth: 2.2,
                                    maxLines: 1,
                                    scrollPhysics:
                                        const NeverScrollableScrollPhysics(),
                                    textInputAction: TextInputAction.next,
                                    onTap: (_isViewOnlyMode || _isPenMode)
                                        ? null
                                        : () => _handleSelectRow(
                                              rowIndex,
                                              rowHeight,
                                            ),
                                    onChanged: (value) => _onRowTextChanged(
                                      rowIndex,
                                      value,
                                      maxLineTextWidth: maxLineTextWidth,
                                      rowTextStyle: rowTextStyleWithColor,
                                      rowHeight: rowHeight,
                                    ),
                                    onSubmitted: (_) {
                                      _handleSelectRow(
                                        rowIndex + 1,
                                        rowHeight,
                                      );
                                    },
                                    style: rowTextStyleWithColor,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.only(
                                        bottom: rowHeight * 0.14,
                                      ),
                                      hintText: (rowIndex == 0 &&
                                              !_isViewOnlyMode &&
                                              _pageFreehandStrokes.isEmpty)
                                          ? (_isPenFreehandMode
                                              ? 'Đặt bút hoặc kéo trực tiếp lên trang giấy để viết/vẽ...'
                                              : 'Chạm vào dòng kẻ ngang để viết nội dung...')
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
                              // Con trỏ trực quan khi chọn dòng ở chế độ "Nét đánh máy" trên trang Ghi chú
                              if (_isPenTypedMode && isRowSelected)
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: controller,
                                  builder: (context, textValue, _) {
                                    final String clean =
                                        _cleanText(textValue.text);
                                    final int cleanCursor =
                                        _getRowCleanCursorOffset(rowIndex)
                                            .clamp(0, clean.length);
                                    final String textBeforeCursor =
                                        clean.substring(0, cleanCursor);
                                    final double beforeCursorWidth =
                                        _measureTextWidth(
                                      textBeforeCursor,
                                      rowTextStyleWithColor,
                                    );
                                    final double cursorX = beforeCursorWidth
                                        .clamp(0.0, maxLineTextWidth);
                                    return Positioned(
                                      left: (cursorX - 4.0)
                                          .clamp(-4.0, maxLineTextWidth - 4.0),
                                      bottom: rowHeight * 0.04,
                                      child: IgnorePointer(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 2.4,
                                              height: rowHeight * 0.56,
                                              decoration: BoxDecoration(
                                                color: Color(
                                                  _selectedPenColorValue,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                            Container(
                                              width: 9,
                                              height: 9,
                                              decoration: BoxDecoration(
                                                color: Color(
                                                  _selectedPenColorValue,
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: AppColors.basicWhite,
                                                  width: 1.4,
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

                // Lớp vẽ bút tự do trực tiếp lên mặt giấy Ghi chú (60-120fps, như ứng dụng Paint)
                // Khi ở chế độ Bàn phím, Chỉ xem hoặc Nét đánh máy: IgnorePointer = true để chạm chọn dòng bình thường nhưng vẫn giữ nguyên nét vẽ
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring:
                        !_isPenFreehandMode || _isViewOnlyMode || hasRamError,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (PointerDownEvent event) =>
                          _handleNoteFreehandPointerDown(
                        event,
                        paperWidth: paperWidth,
                        rowHeight: rowHeight,
                        totalPaperHeight: totalPaperHeight,
                      ),
                      onPointerMove: (PointerMoveEvent event) =>
                          _handleNoteFreehandPointerMove(
                        event,
                        paperWidth: paperWidth,
                        rowHeight: rowHeight,
                        totalPaperHeight: totalPaperHeight,
                      ),
                      onPointerUp: (PointerUpEvent event) =>
                          _handleNoteFreehandPointerUp(event),
                      onPointerCancel: (PointerCancelEvent event) =>
                          _handleNoteFreehandPointerCancel(event),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _NotePageFreehandCanvasPainter(
                            committedStrokes: _pageFreehandStrokes,
                            activePoints: _activeFreehandPoints,
                            activeColorValue: _selectedPenColorValue,
                            activeStrokeWidth: _selectedPenStrokeWidth,
                            activePenStyle: _selectedPenStyle,
                            paperWidth: paperWidth,
                            rowHeight: rowHeight,
                            eraserCursorOffset: _isNotePenEraserMode
                                ? _currentEraserCursorOffset
                                : null,
                            repaint: _freehandCanvasRepaintVersion,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),

                // Cây thước kẻ ảo trên mặt giấy Ghi chú (xoay 360°, tự động hít nét bút thẳng theo mép thước)
                if (_isPenFreehandMode &&
                    _isRulerVisible &&
                    !_isViewOnlyMode &&
                    !hasRamError)
                  VirtualRulerOverlayWidget(
                    rulerCenter: _rulerCenterOnPaper,
                    rulerAngleRad: _rulerAngleRad,
                    rulerLength: _getRulerLength(paperWidth),
                    rulerHeight: _kRulerHeight,
                    onCenterChanged: (Offset nextCenter) {
                      setState(() {
                        _rulerCenterOnPaper = Offset(
                          nextCenter.dx.clamp(
                            40.0,
                            math.max(40.0, paperWidth - 40.0),
                          ),
                          nextCenter.dy.clamp(
                            36.0,
                            math.max(36.0, totalPaperHeight - 36.0),
                          ),
                        );
                      });
                    },
                    onAngleChanged: (double nextAngleRad) {
                      setState(() {
                        _rulerAngleRad = nextAngleRad;
                      });
                    },
                    onCloseRuler: () {
                      setState(() {
                        _isRulerVisible = false;
                        _activeRulerSnapEdgeSign = null;
                      });
                    },
                  ),
              ],
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

        // Khi đang phóng to hoặc màn hình nhỏ có cuộn ngang (ở chế độ Bàn phím / Chỉ xem / Nét đánh máy):
        // hỗ trợ giữ chuột / giữ tay kéo tự do 360 độ qua mọi góc.
        // Ở chế độ Nét viết tự nhiên: 1 ngón/bút dùng để vẽ trực tiếp, 2 ngón dùng để cuộn trang.
        final bool enableFree2DPan =
            !_isPenFreehandMode && (isZoomedIn || enableHorizontalScroll);

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
              physics: (_isPenFreehandMode || enableFree2DPan)
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

  /// Xây dựng 1 ô nhập liệu / dòng viết tương tác dùng chung cho mọi trường trên Biểu mẫu dự giờ 3 trang
  /// (Hỗ trợ cả Bàn phím, Viết bút - Nét đánh máy nhận diện chữ viết tay và chế độ Chỉ xem)
  Widget _buildInteractiveObservationField({
    required int rowIndex,
    required double width,
    required double height,
    required TextStyle textStyle,
    required bool hasRamError,
    double horizontalPadding = 6.0,
    TextAlign textAlign = TextAlign.left,
    String? hintText,
    TextInputType? keyboardType,
    double bottomContentPadding = 4.0,
  }) {
    final TextEditingController controller =
        _getOrCreateRowController(rowIndex);
    final FocusNode focusNode = _getOrCreateRowFocusNode(rowIndex);
    final bool isRowSelected = !_isViewOnlyMode &&
        !_isPenFreehandMode &&
        _selectedRowIndex == rowIndex;
    final TextStyle effectiveFieldTextStyle =
        _rowTextColorMap.containsKey(rowIndex)
            ? textStyle.copyWith(color: Color(_rowTextColorMap[rowIndex]!))
            : textStyle;
    final double innerFieldWidth = math.max(
      16.0,
      width - (horizontalPadding * 2),
    );
    final double maxFieldTextWidth = math.max(
      24.0,
      innerFieldWidth - 2.0,
    );
    final bounds = _getRowSectionBounds(rowIndex);
    final List<HandwritingClusterModel> rowClusters =
        _rowHandwritingMap[rowIndex] ?? const <HandwritingClusterModel>[];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (_isViewOnlyMode || _isPenFreehandMode)
          ? null
          : (TapUpDetails details) {
              _handleSelectRow(
                rowIndex,
                height,
                tapLocalDx: details.localPosition.dx,
                horizontalPadding: horizontalPadding,
                rowTextStyle: effectiveFieldTextStyle,
                textAlign: textAlign,
                maxFieldTextWidth: innerFieldWidth,
              );
            },
      onHorizontalDragUpdate:
          (_isViewOnlyMode || _isPenFreehandMode || !isRowSelected)
              ? null
              : (DragUpdateDetails details) => _handleSelectRow(
                    rowIndex,
                    height,
                    tapLocalDx: details.localPosition.dx,
                    horizontalPadding: horizontalPadding,
                    rowTextStyle: effectiveFieldTextStyle,
                    textAlign: textAlign,
                    maxFieldTextWidth: innerFieldWidth,
                    isDraggingCursor: true,
                  ),
      child: Container(
        width: width,
        height: height,
        color: isRowSelected
            ? AppColors.primaryBlue.withValues(alpha: 0.10)
            : Colors.transparent,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomLeft,
          children: [
            Align(
              alignment: textAlign == TextAlign.center
                  ? Alignment.bottomCenter
                  : Alignment.bottomLeft,
              child: IgnorePointer(
                // Để GestureDetector bên ngoài bắt 100% điểm chạm & thao tác kéo ngang con trỏ
                // cho cả chế độ Bàn phím và Viết bút (không bị TextField chặn kéo hoặc nhảy con trỏ về đầu)
                ignoring: true,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: _isViewOnlyMode || _isPenMode || hasRamError,
                  showCursor: false,
                  cursorColor: AppColors.primaryBlue,
                  cursorWidth: 2.2,
                  maxLines: 1,
                  textAlign: textAlign,
                  keyboardType: keyboardType,
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  textInputAction: TextInputAction.next,
                  onChanged: (value) => _onRowTextChanged(
                    rowIndex,
                    value,
                    maxLineTextWidth: maxFieldTextWidth,
                    rowTextStyle: effectiveFieldTextStyle,
                    rowHeight: height,
                  ),
                  onSubmitted: (_) {
                    if (!bounds.isSingleLine && rowIndex < bounds.maxRow) {
                      _handleSelectRow(rowIndex + 1, height);
                    } else if ((rowIndex >= 0 && rowIndex < 4) ||
                        (rowIndex >= PrimarySchoolEvaluationTemplate.scoreStartRow &&
                            rowIndex <
                                PrimarySchoolEvaluationTemplate.scoreStartRow +
                                    PrimarySchoolEvaluationTemplate
                                        .scoreRowCount -
                                    1)) {
                      _handleSelectRow(
                        rowIndex + 1,
                        height,
                        textAlign: PrimarySchoolEvaluationTemplate.isScoreRow(
                          rowIndex + 1,
                        )
                            ? TextAlign.center
                            : TextAlign.left,
                      );
                    } else {
                      _closeKeyboardAndDeselectRow();
                    }
                  },
                  style: effectiveFieldTextStyle,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.only(
                      bottom: bottomContentPadding,
                    ),
                    hintText: (!_isViewOnlyMode &&
                            rowClusters.isEmpty &&
                            (!isRowSelected || textAlign != TextAlign.center))
                        ? hintText
                        : null,
                    hintStyle: TextStyle(
                      color: AppColors.primaryBlue.withValues(alpha: 0.35),
                      fontSize: (textStyle.fontSize ?? 14.0) * 0.9,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),

            // Hiển thị các cụm nét chữ viết tay đã chuẩn hóa vừa khít chiều cao dòng (Sổ dự giờ)
            if (rowClusters.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, textValue, _) {
                      final String clean = _cleanText(textValue.text);
                      final double typedWidth =
                          _measureTextWidth(clean, textStyle);
                      final double clustersWidth =
                          _measureHandwritingClustersWidth(
                        rowClusters,
                        height,
                        hasLeadingText: clean.isNotEmpty,
                      );
                      final double totalWidth = (typedWidth + clustersWidth)
                          .clamp(0.0, innerFieldWidth);
                      final double startX = textAlign == TextAlign.center
                          ? math.max(
                                0.0,
                                (innerFieldWidth - totalWidth) / 2.0,
                              ) +
                              typedWidth
                          : typedWidth;

                      return CustomPaint(
                        painter: _RowHandwritingClustersPainter(
                          clusters: rowClusters,
                          startX: startX,
                          lineHeight: height,
                          bottomPadding: bottomContentPadding,
                          hasLeadingText: clean.isNotEmpty,
                          inkColor: AppColors.primaryBlue,
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Con trỏ + nút nắm kéo (Handle) hiển thị trực quan trên ô đang chọn (cả Bàn phím & Viết bút)
            // Tự động căn đúng toạ độ chữ kể cả khi ô căn giữa (TextAlign.center) hoặc có cụm nét chữ viết tay
            if (isRowSelected)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, textValue, _) {
                  final String clean = _cleanText(textValue.text);
                  final int cleanCursor =
                      _getRowCleanCursorOffset(rowIndex).clamp(0, clean.length);
                  final String textBeforeCursor =
                      clean.substring(0, cleanCursor);
                  final double typedWidth = _measureTextWidth(clean, textStyle);
                  final double clustersWidth = _measureHandwritingClustersWidth(
                    rowClusters,
                    height,
                    hasLeadingText: clean.isNotEmpty,
                  );
                  final double pendingSpaceOffset = _isPenMode
                      ? (_pendingPenSpaceCount * height * 0.22)
                      : 0.0;
                  final double fullContentWidth =
                      (typedWidth + clustersWidth + pendingSpaceOffset)
                          .clamp(0.0, innerFieldWidth);
                  final double contentStartX = textAlign == TextAlign.center
                      ? math.max(
                          0.0,
                          (innerFieldWidth - fullContentWidth) / 2.0,
                        )
                      : 0.0;
                  final double beforeCursorWidth = _measureTextWidth(
                    textBeforeCursor,
                    textStyle,
                  );
                  final double cursorX = (_isPenMode ||
                          cleanCursor == clean.length)
                      ? (contentStartX +
                              typedWidth +
                              clustersWidth +
                              pendingSpaceOffset)
                          .clamp(0.0, innerFieldWidth)
                      : (contentStartX + beforeCursorWidth)
                          .clamp(0.0, innerFieldWidth);

                  return Positioned(
                    left: (cursorX - 5.0).clamp(-5.0, innerFieldWidth - 5.0),
                    bottom: height * 0.04,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 2.4,
                            height: height * 0.56,
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
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
                        _isPrimaryEvalTemplate
                            ? 'Đang chọn: ${PrimarySchoolEvaluationTemplate.getFieldDisplayName(selectedRow)}'
                            : 'Đang chọn dòng ${selectedRow + 1}',
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

  /// Bảng viết bút cảm ứng (Bottom Sheet) khi người dùng chọn chế độ "Nét đánh máy" trong Bong bóng Bút:
  /// - Cao đúng nửa màn hình (50% chiều cao màn hình) như thiết kế gốc ban đầu
  /// - Nền màu trắng (AppColors.basicWhite), bo góc trên 24px, chỉ đóng bằng nút X
  /// - Viết bằng bút cảm ứng/ngón tay với đúng màu chữ, kiểu nét, độ dày nét của Bong bóng Bút
  /// - Sau 1 nhịp nghỉ (650ms), tự động nhận diện nét chữ viết tay thành chữ đánh máy chuẩn (Google ML Kit)
  ///   và chèn thẳng vào dòng đang chọn kèm màu chữ của Bong bóng Bút.
  Widget _buildPenWritingBottomSheet({required double fontSize}) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final double sheetHeight = (screenSize.height * 0.5).clamp(220.0, 560.0);
    final int selectedRow = _selectedRowIndex ?? 0;
    final TextEditingController activeController =
        _getOrCreateRowController(selectedRow);
    final double titleFontSize = AppTheme.getResponsiveFontSize(context, 15);
    final double badgeFontSize = AppTheme.getResponsiveFontSize(context, 12);

    return Container(
      width: double.infinity,
      height: sheetHeight,
      decoration: BoxDecoration(
        color: AppColors.basicWhite,
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
          // Hàng tiêu đề trên cùng của Bottom Sheet Viết bút (Có nút Cách, Xóa lùi và dấu X để đóng)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: activeController,
              builder: (context, value, _) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedRowIndex != null
                            ? (_isPrimaryEvalTemplate
                                ? 'Viết bút - ${PrimarySchoolEvaluationTemplate.getFieldDisplayName(_selectedRowIndex!)}'
                                : 'Viết bút - Dòng ${_selectedRowIndex! + 1}')
                            : 'Viết bút',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                        ),
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
                    // Nút Xóa lùi (Backspace) xóa nhanh ký tự trước đó
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
                              'Xóa lùi',
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
                          _pendingPenSpaceCount = 0;
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

          // Mặt giấy viết bút cảm ứng (tự nhận diện nét chữ thành chữ đánh máy)
          Expanded(
            child: PenHandwritingPadWidget(
              onCommitRecognizedText: _handleInsertRecognizedPenText,
              preContextProvider: () {
                final int r = _selectedRowIndex ?? 0;
                return _cleanText(_getOrCreateRowController(r).text);
              },
              selectedColorValue: _selectedPenColorValue,
              selectedStrokeWidth: _selectedPenStrokeWidth,
              selectedPenStyle: _selectedPenStyle,
              isEraserMode: _isNotePenEraserMode,
              onEraseClusterFromPad: _handlePenBackspace,
            ),
          ),
        ],
      ),
    );
  }

  /// Lưu bản chụp trạng thái chữ & màu của các dòng trước khi chèn/xóa bằng chế độ "Nét đánh máy" để Hoàn tác
  void _pushTypedPenUndoSnapshot() {
    if (_typedPenUndoStack.length >= 30) {
      _typedPenUndoStack.removeAt(0);
    }
    final Map<int, String> rowTexts = <int, String>{};
    for (final MapEntry<int, TextEditingController> entry
        in _rowControllers.entries) {
      final String clean = _cleanText(entry.value.text);
      if (clean.isNotEmpty) {
        rowTexts[entry.key] = clean;
      }
    }
    _typedPenUndoStack.add((
      rowTexts: rowTexts,
      rowColors: Map<int, int>.from(_rowTextColorMap),
      selectedRow: _selectedRowIndex,
    ));
  }

  /// Chèn chuỗi chữ đánh máy vừa được AI nhận diện từ nét viết trên Bottom Sheet vào dòng đang chọn
  void _handleInsertRecognizedPenText(
    String recognizedWord, {
    required bool leadingSpace,
  }) {
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) return;
    final String trimmedWord = recognizedWord.trim();
    if (trimmedWord.isEmpty) return;

    _pushTypedPenUndoSnapshot();

    final int targetRow = _selectedRowIndex ?? 0;
    _rowTextColorMap[targetRow] = _selectedPenColorValue;

    final TextEditingController ctrl = _getOrCreateRowController(targetRow);
    final String clean = _cleanText(ctrl.text);
    final int cursorOffset =
        _getRowCleanCursorOffset(targetRow).clamp(0, clean.length);
    final String before = clean.substring(0, cursorOffset);
    final String after = clean.substring(cursorOffset);

    String spacePrefix = '';
    if (_pendingPenSpaceCount > 0) {
      spacePrefix = ' ' * _pendingPenSpaceCount;
      _pendingPenSpaceCount = 0;
    } else if (before.isNotEmpty && !before.endsWith(' ')) {
      // Nếu phía trước con trỏ đã có chữ và người dùng ngừng nhịp (hoặc mới đặt bút viết từ mới), tự cách 1 khoảng trắng
      if (leadingSpace || clean.isNotEmpty) {
        spacePrefix = ' ';
      }
    }

    final String inserted = '$spacePrefix$trimmedWord';
    final String updatedClean = '$before$inserted$after';
    final int newCursorOffset =
        (before.length + inserted.length).clamp(0, updatedClean.length);

    _setRowCleanText(
      targetRow,
      updatedClean,
      cursorCleanOffset: newCursorOffset,
      forceSentinel: _rowUsesBackspaceSentinel(targetRow),
    );

    final Size screenSize = MediaQuery.sizeOf(context);
    final bool isNote4x = _activeTemplateId == Note4x.templateId;
    final bool isPrimaryEval = _isPrimaryEvalTemplate;
    final double paperWidth = isPrimaryEval
        ? PrimarySchoolEvaluationTemplate.getResponsivePaperWidth(
            screenSize.width,
          )
        : (isNote4x
            ? Note4x.getResponsivePaperWidth(screenSize.width)
            : Note5x.getResponsivePaperWidth(screenSize.width));
    final double rowHeight = isPrimaryEval
        ? PrimarySchoolEvaluationTemplate.getResponsiveRowHeight(
            context,
            maxWidth: paperWidth,
          )
        : (isNote4x
            ? Note4x.getResponsiveRowHeight(context, maxWidth: paperWidth)
            : Note5x.getResponsiveRowHeight(context, maxWidth: paperWidth));
    final double horizontalPadding = isPrimaryEval
        ? PrimarySchoolEvaluationTemplate.getResponsiveHorizontalPadding(
            paperWidth,
          )
        : (isNote4x
            ? Note4x.getResponsiveHorizontalPadding(paperWidth)
            : Note5x.getResponsiveHorizontalPadding(paperWidth));
    final double lineFontSize = (rowHeight * 0.42).clamp(15.0, 22.0);
    final TextStyle rowTextStyle =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: Color(_selectedPenColorValue),
      fontSize: lineFontSize,
      fontWeight: FontWeight.w500,
      height: 1.15,
    );
    final double maxLineTextWidth = isPrimaryEval
        ? PrimarySchoolEvaluationTemplate.getMaxTextWidthForRow(
            targetRow,
            paperWidth: paperWidth,
          )
        : math.max(120.0, paperWidth - (horizontalPadding * 2) - 2.0);

    if (isPrimaryEval &&
        PrimarySchoolEvaluationTemplate.isScoreRow(targetRow)) {
      _handlePrimaryEvalScoreUpdated(targetRow, updatedClean);
    } else {
      final bounds = _getRowSectionBounds(targetRow);
      if (!bounds.isSingleLine &&
          targetRow < bounds.maxRow &&
          _measureTextWidth(updatedClean, rowTextStyle) > maxLineTextWidth) {
        _isWrappingLine = true;
        try {
          _wrapOverflowFromRow(
            startRowIndex: targetRow,
            maxLineTextWidth: maxLineTextWidth,
            rowTextStyle: rowTextStyle,
            rowHeight: rowHeight,
          );
          if (_selectedRowIndex != null) {
            _rowTextColorMap[_selectedRowIndex!] = _selectedPenColorValue;
          }
        } finally {
          _isWrappingLine = false;
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
    _freehandCanvasRepaintVersion.value++;
    _saveLinesToRamAndScheduleDriveSync();
  }

  /// Chèn khoảng trắng khi bấm nút "Cách" trên thanh tiêu đề Bottom Sheet viết bút
  void _handlePenInsertSpace() {
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) return;
    _pushTypedPenUndoSnapshot();
    final int targetRow = _selectedRowIndex ?? 0;
    final TextEditingController ctrl = _getOrCreateRowController(targetRow);
    final String clean = _cleanText(ctrl.text);
    final int cursorOffset =
        _getRowCleanCursorOffset(targetRow).clamp(0, clean.length);
    final String before = clean.substring(0, cursorOffset);
    final String after = clean.substring(cursorOffset);
    final String updated = '$before $after';
    _setRowCleanText(
      targetRow,
      updated,
      cursorCleanOffset: cursorOffset + 1,
      forceSentinel: _rowUsesBackspaceSentinel(targetRow),
    );
    if (mounted) {
      setState(() {});
    }
    _freehandCanvasRepaintVersion.value++;
    _saveLinesToRamAndScheduleDriveSync();
  }

  /// Xóa lùi 1 từ/ký tự phía trước con trỏ khi bấm nút "Xóa lùi" hoặc dùng Cục tẩy ở chế độ "Nét đánh máy"
  void _handlePenBackspace() {
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) return;
    final int targetRow = _selectedRowIndex ?? 0;
    final TextEditingController ctrl = _getOrCreateRowController(targetRow);
    final String clean = _cleanText(ctrl.text);
    final int cursorOffset =
        _getRowCleanCursorOffset(targetRow).clamp(0, clean.length);

    if (clean.isEmpty || cursorOffset <= 0) {
      final bounds = _getRowSectionBounds(targetRow);
      if (!bounds.isSingleLine && targetRow > bounds.minRow) {
        _pushTypedPenUndoSnapshot();
        _jumpOrMergeToPreviousRow(
          rowIndex: targetRow,
          remainingCleanOnCurrentRow: clean,
        );
        _freehandCanvasRepaintVersion.value++;
      }
      return;
    }

    _pushTypedPenUndoSnapshot();
    final String before = clean.substring(0, cursorOffset);
    final String after = clean.substring(cursorOffset);
    final String shortenedBefore = before.substring(0, before.length - 1);
    final String updatedClean = '$shortenedBefore$after';

    _setRowCleanText(
      targetRow,
      updatedClean,
      cursorCleanOffset: shortenedBefore.length,
      forceSentinel: _rowUsesBackspaceSentinel(targetRow),
    );

    if (_isPrimaryEvalTemplate &&
        PrimarySchoolEvaluationTemplate.isScoreRow(targetRow)) {
      _handlePrimaryEvalScoreUpdated(targetRow, updatedClean);
    }

    if (mounted) {
      setState(() {});
    }
    _freehandCanvasRepaintVersion.value++;
    _saveLinesToRamAndScheduleDriveSync();
  }

  // ===========================================================================
  // 5. CƠ CHẾ VẼ BÚT TRỰC TIẾP TRÊN MẶT GIẤY GHI CHÚ & SỔ DỰ GIỜ (NHƯ ỨNG DỤNG PAINT 60-120FPS)
  // ===========================================================================

  /// Hoàn tác nét vẽ hoặc chữ nhận diện vừa thực hiện trên trang Ghi chú / Sổ dự giờ
  void _handleUndoFreehandStroke() {
    if (_isViewOnlyMode || _syncRepository.hasRamErrorNotifier.value) return;

    // Nếu đang ở chế độ "Nét đánh máy" và có lịch sử hoàn tác chữ nhận diện -> ưu tiên hoàn tác chữ đánh máy
    if (_isPenTypedMode && _typedPenUndoStack.isNotEmpty) {
      final snapshot = _typedPenUndoStack.removeLast();
      _isWrappingLine = true;
      try {
        for (final TextEditingController ctrl in _rowControllers.values) {
          ctrl.clear();
        }
        _lastCleanRowTexts.clear();
        _rowTextColorMap
          ..clear()
          ..addAll(snapshot.rowColors);
        for (final MapEntry<int, String> entry in snapshot.rowTexts.entries) {
          _setRowCleanText(entry.key, entry.value);
        }
        if (snapshot.selectedRow != null) {
          _selectedRowIndex = snapshot.selectedRow;
        }
      } finally {
        _isWrappingLine = false;
      }
      _freehandCanvasRepaintVersion.value++;
      if (mounted) {
        setState(() {});
      }
      _saveLinesToRamAndScheduleDriveSync();
      return;
    }

    if (_freehandUndoStack.isNotEmpty) {
      final List<FreehandPageStrokeModel> previousState =
          _freehandUndoStack.removeLast();
      _pageFreehandStrokes
        ..clear()
        ..addAll(previousState);
      _freehandCanvasRepaintVersion.value++;
      if (mounted) {
        setState(() {});
      }
      _saveLinesToRamAndScheduleDriveSync();
    } else if (_pageFreehandStrokes.isNotEmpty) {
      _pageFreehandStrokes.removeLast();
      _freehandCanvasRepaintVersion.value++;
      if (mounted) {
        setState(() {});
      }
      _saveLinesToRamAndScheduleDriveSync();
    } else if (_observationPenUndoStack.isNotEmpty) {
      final Map<int, List<HandwritingClusterModel>> previousState =
          _observationPenUndoStack.removeLast();
      setState(() {
        _rowHandwritingMap
          ..clear()
          ..addAll(previousState);
      });
      _saveLinesToRamAndScheduleDriveSync();
    } else if (_rowHandwritingMap.isNotEmpty) {
      final List<int> keys = _rowHandwritingMap.keys.toList()..sort();
      final int lastRowKey = keys.last;
      final List<HandwritingClusterModel>? clusters =
          _rowHandwritingMap[lastRowKey];
      if (clusters != null && clusters.isNotEmpty) {
        setState(() {
          clusters.removeLast();
          if (clusters.isEmpty) {
            _rowHandwritingMap.remove(lastRowKey);
          }
        });
        _saveLinesToRamAndScheduleDriveSync();
      }
    }
  }

  void _pushFreehandUndoSnapshot() {
    if (_freehandUndoStack.length >= 30) {
      _freehandUndoStack.removeAt(0);
    }
    _freehandUndoStack.add(
      List<FreehandPageStrokeModel>.from(_pageFreehandStrokes),
    );
  }

  /// Tính chiều dài Cây thước kẻ ảo tự động co giãn theo chiều rộng trang giấy
  double _getRulerLength(double paperWidth) {
    return (paperWidth * 0.72).clamp(280.0, 620.0);
  }

  /// Kiểm tra xem điểm đặt bút `localPos` có nằm gần mép trên (-1.0) hoặc mép dưới (+1.0) của Cây thước kẻ không
  double? _detectNearRulerEdgeSign(Offset localPos, double paperWidth) {
    if (!_isRulerVisible) return null;
    final double rulerLen = _getRulerLength(paperWidth);
    final double halfLen = rulerLen * 0.5;
    final double halfH = _kRulerHeight * 0.5;
    final double cosA = math.cos(_rulerAngleRad);
    final double sinA = math.sin(_rulerAngleRad);
    final Offset d = localPos - _rulerCenterOnPaper;

    // s: tọa độ dọc theo thân thước; t: khoảng cách vuông góc tới trục giữa thước
    final double s = d.dx * cosA + d.dy * sinA;
    final double t = -d.dx * sinA + d.dy * cosA;

    final double distTop = (t - (-halfH)).abs();
    final double distBottom = (t - halfH).abs();
    final double minDist = math.min(distTop, distBottom);

    if (s.abs() <= halfLen + 28.0 && minDist <= 42.0) {
      return (distTop <= distBottom) ? -1.0 : 1.0;
    }
    return null;
  }

  /// Chiếu vuông góc điểm `localPos` lên đúng đường thẳng mép trên hoặc mép dưới của Cây thước kẻ
  Offset _projectPointOntoRulerEdge(
    Offset localPos, {
    required double paperWidth,
    required double totalPaperHeight,
    required double edgeSign,
  }) {
    final double rulerLen = _getRulerLength(paperWidth);
    final double halfLen = rulerLen * 0.5;
    final double halfH = _kRulerHeight * 0.5;
    final double cosA = math.cos(_rulerAngleRad);
    final double sinA = math.sin(_rulerAngleRad);
    final Offset d = localPos - _rulerCenterOnPaper;

    final double s =
        (d.dx * cosA + d.dy * sinA).clamp(-halfLen, halfLen);
    final double targetT = edgeSign * (halfH + 1.5);

    final double projX =
        _rulerCenterOnPaper.dx + s * cosA - targetT * sinA;
    final double projY =
        _rulerCenterOnPaper.dy + s * sinA + targetT * cosA;

    return Offset(
      projX.clamp(0.0, paperWidth),
      projY.clamp(0.0, totalPaperHeight),
    );
  }

  void _handleNoteFreehandPointerDown(
    PointerDownEvent event, {
    required double paperWidth,
    required double rowHeight,
    required double totalPaperHeight,
  }) {
    if (!_isPenMode ||
        _isViewOnlyMode ||
        _syncRepository.hasRamErrorNotifier.value) {
      return;
    }

    _activeCanvasPointers[event.pointer] = event.position;

    // Nếu người dùng đặt từ 2 ngón tay trở lên -> Chuyển sang chế độ cuộn trang 2 ngón tay
    if (_activeCanvasPointers.length >= 2) {
      _isMultiTouchPanning = true;
      _activeRulerSnapEdgeSign = null;
      if (_activeFreehandPoints.length <= 12) {
        _activeFreehandPoints.clear();
      }
      _currentEraserCursorOffset = null;
      _freehandCanvasRepaintVersion.value++;
      return;
    }

    _isMultiTouchPanning = false;
    _didModifyStrokesInCurrentEraseGesture = false;

    Offset local = Offset(
      event.localPosition.dx.clamp(0.0, paperWidth),
      event.localPosition.dy.clamp(0.0, totalPaperHeight),
    );

    if (_isNotePenEraserMode) {
      _activeRulerSnapEdgeSign = null;
      _currentEraserCursorOffset = local;
      _eraseFreehandStrokesAt(
        local,
        paperWidth: paperWidth,
        rowHeight: rowHeight,
      );
      _freehandCanvasRepaintVersion.value++;
    } else {
      // Nếu đang bật Cây thước kẻ và đặt bút gần mép thước -> Tự động khóa hít nét bút vào mép thước
      _activeRulerSnapEdgeSign = _detectNearRulerEdgeSign(local, paperWidth);
      if (_activeRulerSnapEdgeSign != null) {
        local = _projectPointOntoRulerEdge(
          local,
          paperWidth: paperWidth,
          totalPaperHeight: totalPaperHeight,
          edgeSign: _activeRulerSnapEdgeSign!,
        );
      }

      _activeFreehandPoints
        ..clear()
        ..add(
          StrokePointModel(
            nx: (local.dx / paperWidth).clamp(0.0, 1.0),
            ry: math.max(0.0, local.dy / rowHeight),
          ),
        );
      _freehandCanvasRepaintVersion.value++;
    }
  }

  void _handleNoteFreehandPointerMove(
    PointerMoveEvent event, {
    required double paperWidth,
    required double rowHeight,
    required double totalPaperHeight,
  }) {
    if (!_isPenMode ||
        _isViewOnlyMode ||
        _syncRepository.hasRamErrorNotifier.value) {
      return;
    }

    if (!_activeCanvasPointers.containsKey(event.pointer)) return;
    _activeCanvasPointers[event.pointer] = event.position;

    // Nếu đang dùng 2 ngón tay -> Cuộn trang vở mượt mà theo cả chiều dọc & chiều ngang
    if (_isMultiTouchPanning || _activeCanvasPointers.length >= 2) {
      final int pointerCount = math.max(1, _activeCanvasPointers.length);
      final double dy = event.delta.dy / pointerCount;
      final double dx = event.delta.dx / pointerCount;

      if (_scrollController.hasClients) {
        final double nextVert = (_scrollController.offset - dy).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(nextVert);
      }
      if (_horizontalScrollController.hasClients) {
        final double nextHoriz =
            (_horizontalScrollController.offset - dx).clamp(
          0.0,
          _horizontalScrollController.position.maxScrollExtent,
        );
        _horizontalScrollController.jumpTo(nextHoriz);
      }
      return;
    }

    Offset local = Offset(
      event.localPosition.dx.clamp(0.0, paperWidth),
      event.localPosition.dy.clamp(0.0, totalPaperHeight),
    );

    if (_isNotePenEraserMode) {
      _currentEraserCursorOffset = local;
      _eraseFreehandStrokesAt(
        local,
        paperWidth: paperWidth,
        rowHeight: rowHeight,
      );
      _freehandCanvasRepaintVersion.value++;
    } else {
      // Nếu đang kẻ dọc theo mép Cây thước kẻ -> Giữ nét bút thẳng tuyệt đối 100% theo cạnh thước
      if (_activeRulerSnapEdgeSign != null && _activeFreehandPoints.isNotEmpty) {
        final Offset snappedEnd = _projectPointOntoRulerEdge(
          local,
          paperWidth: paperWidth,
          totalPaperHeight: totalPaperHeight,
          edgeSign: _activeRulerSnapEdgeSign!,
        );
        final StrokePointModel startModel = _activeFreehandPoints.first;
        final Offset startOffset = Offset(
          startModel.nx * paperWidth,
          startModel.ry * rowHeight,
        );
        final double dist = (snappedEnd - startOffset).distance;
        final int steps = math.max(1, (dist / 4.0).ceil());

        _activeFreehandPoints
          ..clear()
          ..add(startModel);
        for (int i = 1; i <= steps; i++) {
          final double t = i / steps;
          final double ix = startOffset.dx + (snappedEnd.dx - startOffset.dx) * t;
          final double iy = startOffset.dy + (snappedEnd.dy - startOffset.dy) * t;
          _activeFreehandPoints.add(
            StrokePointModel(
              nx: (ix / paperWidth).clamp(0.0, 1.0),
              ry: math.max(0.0, iy / rowHeight),
            ),
          );
        }
        _freehandCanvasRepaintVersion.value++;
        return;
      }

      if (_activeFreehandPoints.isNotEmpty) {
        final StrokePointModel lastPt = _activeFreehandPoints.last;
        final double prevX = lastPt.nx * paperWidth;
        final double prevY = lastPt.ry * rowHeight;
        if ((local - Offset(prevX, prevY)).distance < 0.75) {
          return;
        }
      }
      _activeFreehandPoints.add(
        StrokePointModel(
          nx: (local.dx / paperWidth).clamp(0.0, 1.0),
          ry: math.max(0.0, local.dy / rowHeight),
        ),
      );
      _freehandCanvasRepaintVersion.value++;
    }
  }

  void _handleNoteFreehandPointerUp(PointerUpEvent event) {
    _activeCanvasPointers.remove(event.pointer);
    if (_activeCanvasPointers.isEmpty) {
      if (!_isMultiTouchPanning) {
        if (_isNotePenEraserMode) {
          _currentEraserCursorOffset = null;
          _freehandCanvasRepaintVersion.value++;
          if (_didModifyStrokesInCurrentEraseGesture) {
            _saveLinesToRamAndScheduleDriveSync();
          }
        } else if (_activeFreehandPoints.isNotEmpty) {
          _pushFreehandUndoSnapshot();
          _pageFreehandStrokes.add(
            FreehandPageStrokeModel(
              points: List<StrokePointModel>.from(_activeFreehandPoints),
              colorValue: _selectedPenColorValue,
              strokeWidth: _selectedPenStrokeWidth,
              penStyle: _selectedPenStyle,
            ),
          );
          _activeFreehandPoints.clear();
          _freehandCanvasRepaintVersion.value++;
          if (mounted) {
            setState(() {});
          }
          _saveLinesToRamAndScheduleDriveSync();
        }
      }
      _activeRulerSnapEdgeSign = null;
      _isMultiTouchPanning = false;
      _didModifyStrokesInCurrentEraseGesture = false;
    }
  }

  void _handleNoteFreehandPointerCancel(PointerCancelEvent event) {
    _activeCanvasPointers.remove(event.pointer);
    if (_activeCanvasPointers.isEmpty) {
      _activeFreehandPoints.clear();
      _currentEraserCursorOffset = null;
      _activeRulerSnapEdgeSign = null;
      _isMultiTouchPanning = false;
      _didModifyStrokesInCurrentEraseGesture = false;
      _freehandCanvasRepaintVersion.value++;
    }
  }

  /// Xóa các nét vẽ tự do nằm trong bán kính của Cục tẩy khi chạm hoặc kéo qua
  void _eraseFreehandStrokesAt(
    Offset localPos, {
    required double paperWidth,
    required double rowHeight,
  }) {
    if (_pageFreehandStrokes.isEmpty) return;
    const double eraserRadius = 16.0;
    const double eraserRadiusSq = eraserRadius * eraserRadius;

    final List<int> indicesToRemove = <int>[];
    for (int s = 0; s < _pageFreehandStrokes.length; s++) {
      final List<StrokePointModel> pts = _pageFreehandStrokes[s].points;
      bool hit = false;
      for (int i = 0; i < pts.length; i++) {
        final Offset p = Offset(
          pts[i].nx * paperWidth,
          pts[i].ry * rowHeight,
        );
        if ((p - localPos).distanceSquared <= eraserRadiusSq) {
          hit = true;
          break;
        }
        if (i > 0) {
          final Offset prev = Offset(
            pts[i - 1].nx * paperWidth,
            pts[i - 1].ry * rowHeight,
          );
          final Offset mid = Offset(
            (prev.dx + p.dx) * 0.5,
            (prev.dy + p.dy) * 0.5,
          );
          if ((mid - localPos).distanceSquared <= eraserRadiusSq) {
            hit = true;
            break;
          }
        }
      }
      if (hit) {
        indicesToRemove.add(s);
      }
    }

    if (indicesToRemove.isNotEmpty) {
      if (!_didModifyStrokesInCurrentEraseGesture) {
        _pushFreehandUndoSnapshot();
        _didModifyStrokesInCurrentEraseGesture = true;
      }
      for (int i = indicesToRemove.length - 1; i >= 0; i--) {
        _pageFreehandStrokes.removeAt(indicesToRemove[i]);
      }
    }
  }

  /// Ô trạng thái nằm kế bên nút Lưu:
  /// - Khi đang xuất file PDF/Word: Hiển thị "Đang xuất file..."
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
        : (_isExportingFile
            ? 'Đang xuất file...'
            : (_isViewOnlyMode ? 'Chế độ chỉ xem' : 'Đang tự động lưu'));
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
          if (_isExportingFile)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.basicWhite,
              ),
            )
          else
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

  /// Nút Menu 3 gạch nằm sát góc phải Header (Gom các nút: "Chỉ xem", "Bàn phím", "Viết bút", "Xuất file" và "Làm mới")
  Widget _buildInputModeMenuButton({
    required bool hasRamError,
    required double fontSize,
  }) {
    final double menuTextSize = AppTheme.getResponsiveFontSize(context, 14);

    return PopupMenuButton<NoteInputMode>(
      enabled: !hasRamError && !_isExportingFile,
      tooltip: 'Menu chế độ & tác vụ',
      offset: const Offset(0, 44),
      color: AppColors.basicWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      onSelected: (NoteInputMode selectedMode) {
        if (selectedMode == NoteInputMode.exportFile) {
          _showExportFileDialog();
          return;
        }
        if (selectedMode == NoteInputMode.refresh) {
          _handleRefreshNoteFromDrive();
          return;
        }
        if (selectedMode == NoteInputMode.clearContent) {
          _showClearContentConfirmDialog();
          return;
        }
        if (selectedMode == NoteInputMode.viewOnly) {
          // Chế độ "Chỉ xem": Đóng bàn phím, bỏ chọn dòng,
          // và hủy mọi bộ đếm kiểm tra cập nhật dữ liệu lên Drive để không tốn API
          FocusScope.of(context).unfocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          _syncRepository.cancelPendingSyncTimer();
          setState(() {
            _inputMode = NoteInputMode.viewOnly;
            _selectedRowIndex = null;
            _isPenSheetOpen = false;
            _pendingPenSpaceCount = 0;
          });
        } else if (selectedMode == NoteInputMode.pen) {
          // Chế độ "Viết bút" (Dùng chung cho cả Ghi chú & Sổ dự giờ):
          // Hỗ trợ chuyển đổi giữa "Nét viết tự nhiên" (vẽ trực tiếp lên mặt giấy) và "Nét đánh máy" (chọn dòng + mở Bottom Sheet)
          FocusScope.of(context).unfocus();
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          setState(() {
            _inputMode = NoteInputMode.pen;
            if (_isPenTypedHandwritingMode) {
              _selectedRowIndex ??= 0;
              _isPenSheetOpen = true;
            } else {
              _selectedRowIndex = null;
              _isPenSheetOpen = false;
            }
            _pendingPenSpaceCount = 0;
            _isNotePenEraserMode = false;
          });
        } else {
          final int targetRow = _selectedRowIndex ?? 0;
          setState(() {
            _inputMode = NoteInputMode.keyboard;
            _selectedRowIndex = targetRow;
            _isPenSheetOpen = false;
            _pendingPenSpaceCount = 0;
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
        // Tùy chọn 4: Xuất file (Xuất PDF .pdf hoặc Word .doc vào thư mục Export File trên Google Drive)
        PopupMenuItem<NoteInputMode>(
          value: NoteInputMode.exportFile,
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
                  Icons.ios_share_rounded,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Xuất file',
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
        // Tùy chọn 5: Làm mới (Tải lại dữ liệu mới nhất từ Google Drive giống ngoài màn hình Home)
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
        // Tùy chọn 6: Làm sạch (Nằm dưới nút Làm mới, nền màu đỏ AppColors.dangerRed, có xác nhận & Hoàn tác)
        PopupMenuItem<NoteInputMode>(
          value: NoteInputMode.clearContent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.dangerRed,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cleaning_services_rounded,
                  color: AppColors.basicWhite,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Làm sạch',
                    style: TextStyle(
                      color: AppColors.basicWhite,
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

// ===========================================================================
// BỘ VẼ CÁC CỤM NÉT CHỮ VIẾT TAY ĐÃ CHUẨN HÓA KÍCH CỠ LÊN DÒNG BIỂU MẪU (SỔ DỰ GIỜ)
// ===========================================================================
class _RowHandwritingClustersPainter extends CustomPainter {
  final List<HandwritingClusterModel> clusters;
  final double startX;
  final double lineHeight;
  final double bottomPadding;
  final bool hasLeadingText;
  final Color inkColor;

  _RowHandwritingClustersPainter({
    required this.clusters,
    required this.startX,
    required this.lineHeight,
    required this.bottomPadding,
    required this.hasLeadingText,
    required this.inkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (clusters.isEmpty) return;

    final double targetHeight = lineHeight * 0.74;
    final double topY =
        (size.height - bottomPadding - targetHeight).clamp(1.0, size.height);

    double currentX = startX;
    for (int i = 0; i < clusters.length; i++) {
      final HandwritingClusterModel cluster = clusters[i];
      if (i > 0 || hasLeadingText) {
        currentX += cluster.getLeadingGap(lineHeight);
      }
      final double targetWidth = cluster.getRenderedWidth(lineHeight);
      final double scaledStrokeWidth =
          ((cluster.strokeWidth / 2.6) * (lineHeight * 0.056)).clamp(1.1, 4.2);

      for (final stroke in cluster.strokes) {
        final List<StrokePointModel> pts = stroke.points;
        if (pts.isEmpty) continue;
        final List<Offset> scaledPts = pts
            .map(
              (StrokePointModel pt) => Offset(
                currentX + pt.nx * targetWidth,
                topY + pt.ry * targetHeight,
              ),
            )
            .toList(growable: false);

        PenStrokeStyle.paintScaledPoints(
          canvas,
          scaledPts,
          colorValue: cluster.colorValue,
          strokeWidth: scaledStrokeWidth,
          penStyle: cluster.penStyle,
        );
      }

      currentX += targetWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _RowHandwritingClustersPainter oldDelegate) {
    return true;
  }
}

// ===========================================================================
// BỘ VẼ NÉT BÚT TỰ DO TRỰC TIẾP LÊN MẶT GIẤY GHI CHÚ (NHƯ ỨNG DỤNG PAINT)
// ===========================================================================
class _NotePageFreehandCanvasPainter extends CustomPainter {
  final List<FreehandPageStrokeModel> committedStrokes;
  final List<StrokePointModel> activePoints;
  final int activeColorValue;
  final double activeStrokeWidth;
  final String activePenStyle;
  final double paperWidth;
  final double rowHeight;
  final Offset? eraserCursorOffset;

  _NotePageFreehandCanvasPainter({
    required this.committedStrokes,
    required this.activePoints,
    required this.activeColorValue,
    required this.activeStrokeWidth,
    required this.activePenStyle,
    required this.paperWidth,
    required this.rowHeight,
    required this.eraserCursorOffset,
    required Listenable repaint,
  }) : super(repaint: repaint);

  void _drawNormalizedStroke(
    Canvas canvas,
    List<StrokePointModel> points, {
    required int colorValue,
    required double strokeWidth,
    required String penStyle,
  }) {
    if (points.isEmpty) return;
    final List<Offset> scaledPts = points
        .map(
          (StrokePointModel pt) => Offset(
            pt.nx * paperWidth,
            pt.ry * rowHeight,
          ),
        )
        .toList(growable: false);

    PenStrokeStyle.paintScaledPoints(
      canvas,
      scaledPts,
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      penStyle: penStyle,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final FreehandPageStrokeModel stroke in committedStrokes) {
      _drawNormalizedStroke(
        canvas,
        stroke.points,
        colorValue: stroke.colorValue,
        strokeWidth: stroke.strokeWidth,
        penStyle: stroke.penStyle,
      );
    }

    if (activePoints.isNotEmpty) {
      _drawNormalizedStroke(
        canvas,
        activePoints,
        colorValue: activeColorValue,
        strokeWidth: activeStrokeWidth,
        penStyle: activePenStyle,
      );
    }

    if (eraserCursorOffset != null) {
      final Paint eraserFill = Paint()
        ..color = AppColors.dangerRed.withValues(alpha: 0.14)
        ..style = PaintingStyle.fill;
      final Paint eraserBorder = Paint()
        ..color = AppColors.dangerRed.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(eraserCursorOffset!, 16.0, eraserFill);
      canvas.drawCircle(eraserCursorOffset!, 16.0, eraserBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _NotePageFreehandCanvasPainter oldDelegate) {
    return oldDelegate.paperWidth != paperWidth ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.activeColorValue != activeColorValue ||
        oldDelegate.activeStrokeWidth != activeStrokeWidth ||
        oldDelegate.activePenStyle != activePenStyle ||
        oldDelegate.eraserCursorOffset != eraserCursorOffset;
  }
}
