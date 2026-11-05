import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/stroke_point_model.dart';
import '../../../../services/handwriting_recognition_service.dart';
import '../../../../services/stylus_input_filter.dart';

// ===========================================================================
// BẢNG VIẾT BÚT CẢM ỨNG NHƯ ỨNG DỤNG PAINT & GIẤY THẬT TRONG BOTTOM SHEET
// (PEN HANDWRITING PAD WIDGET - TỐI ƯU 0MS LAG VỚI REPAINTBOUNDARY)
// Công dụng:
// - Hiển thị mặt giấy viết phóng lớn có đường kẻ ngang dẫn hướng.
// - Khi người dùng bấm giữ chuột kéo (trên máy ảo) hoặc viết bằng Bút cảm ứng / Tay:
//   + Vẽ nét mực tức thì như ứng dụng Paint (60-120fps) qua ValueNotifier + CustomPainter
//     mà KHÔNG gọi setState() làm vẽ lại màn hình vở bên trên (chống lag 100%).
//   + Viết liên tục (nhấc bút < 650ms hoặc viết nối tiếp ngay sau khi nét ẩn):
//     Tự động nối liền các ký tự với nhau thành 1 từ hoàn chỉnh.
//   + Ngừng một khoảnh khắc (>= 650ms sau khi nét trước đã lên dòng):
//     Tự động cách ra 1 khoảng trắng (' ') trước từ tiếp theo.
//   + Sau khi chữ được điền vào dòng vở bên trên, nét vẽ trên Bottom Sheet
//     tự động mờ dần và ẩn đi để trả lại mặt giấy trắng viết tiếp ngay tại chỗ.
// ===========================================================================
class PenHandwritingPadWidget extends StatefulWidget {
  /// Chuỗi văn bản hiện có trên dòng đang chọn (dùng làm ngữ cảnh preContext cho AI)
  final String Function() getCurrentRowCleanText;

  /// Callback khi AI nhận diện xong nét vẽ để điền vào dòng đang chọn
  final void Function(String recognizedText, {required bool insertLeadingSpace})
      onCommitRecognizedText;

  const PenHandwritingPadWidget({
    super.key,
    required this.getCurrentRowCleanText,
    required this.onCommitRecognizedText,
  });

  @override
  State<PenHandwritingPadWidget> createState() =>
      _PenHandwritingPadWidgetState();
}

class _PenHandwritingPadWidgetState extends State<PenHandwritingPadWidget>
    with SingleTickerProviderStateMixin {
  final HandwritingRecognitionService _recognitionService =
      HandwritingRecognitionService.instance;

  /// Thời gian chờ sau khi nhấc bút/chuột để chốt nét vẽ thành chữ lên dòng (650ms)
  static const Duration _strokeCommitDelay = Duration(milliseconds: 650);

  /// Thời gian ngừng một khoảnh khắc sau khi nét cũ đã ẩn để tự động cách từ mới (650ms)
  static const Duration _wordSpacePauseDelay = Duration(milliseconds: 650);

  /// Danh sách các nét mực đang hiển thị trên bảng viết hiện tại
  final List<InkStrokeModel> _activeStrokes = <InkStrokeModel>[];
  InkStrokeModel? _currentStroke;
  int? _activePointerId;
  bool _isStylusActive = false;

  /// Bộ báo hiệu vẽ lại chỉ riêng lớp mực CustomPainter (0ms lag, không rebuild Widget)
  final ValueNotifier<int> _inkRepaintNotifier = ValueNotifier<int>(0);

  /// Trạng thái hiển thị hướng dẫn nhỏ ở góc bảng viết
  final ValueNotifier<String> _statusHintNotifier = ValueNotifier<String>(
    'Giữ chuột hoặc dùng bút viết lên bảng trắng bên dưới...',
  );

  Timer? _commitTimer;
  Timer? _autoSpaceTimer;

  /// Cờ đánh dấu có tự động chèn dấu cách (' ') trước cụm nét đang viết hay không
  bool _insertSpaceBeforeCurrentGroup = false;

  /// Đánh dấu đã từng chốt ít nhất 1 cụm chữ trong phiên mở bảng viết này chưa
  bool _hasCommittedAtLeastOnce = false;

  late final AnimationController _fadeOutController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1.0,
  )..addListener(() {
      _inkRepaintNotifier.value++;
    });

  Size _padSize = Size.zero;

  @override
  void initState() {
    super.initState();
    // Tải trước model Tiếng Việt ('vi') ngầm ngay khi mở bảng viết bút
    _recognitionService.ensureModelDownloaded();
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    _autoSpaceTimer?.cancel();
    _fadeOutController.dispose();
    _inkRepaintNotifier.dispose();
    _statusHintNotifier.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (StylusInputFilter.isHardwareStylus(event)) {
      _isStylusActive = true;
    }
    if (!StylusInputFilter.isValidWritingPointer(
      event,
      isStylusActive: _isStylusActive,
    )) {
      return;
    }

    _commitTimer?.cancel();

    // Nếu nét cũ đang trong quá trình mờ dần (vừa mới chốt xong mà người dùng viết tiếp ngay) ->
    // Dọn ngay nét cũ và giữ chế độ NỐI LIỀN KÝ TỰ (không cách từ)
    if (_fadeOutController.isAnimating || _fadeOutController.value < 1.0) {
      _fadeOutController.stop();
      _fadeOutController.value = 1.0;
      _activeStrokes.clear();
    }

    // Nếu người dùng đặt bút viết tiếp TRƯỚC khi bộ đếm nghỉ (_autoSpaceTimer) kết thúc ->
    // Hủy bộ đếm cách từ để NỐI LIỀN ký tự mới vào từ vừa viết!
    if (_autoSpaceTimer != null && _autoSpaceTimer!.isActive) {
      _autoSpaceTimer!.cancel();
      if (_activeStrokes.isEmpty) {
        _insertSpaceBeforeCurrentGroup = false;
      }
    }

    // Hoàn tất nét trước nếu có
    _currentStroke?.finishStroke();

    _activePointerId = event.pointer;
    final InkStrokeModel newStroke = InkStrokeModel()
      ..addPoint(
        StrokePointModel(
          x: event.localPosition.dx,
          y: event.localPosition.dy,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          pressure: event.pressure,
        ),
      );
    _currentStroke = newStroke;
    _activeStrokes.add(newStroke);

    _statusHintNotifier.value = _insertSpaceBeforeCurrentGroup
        ? 'Đang viết từ mới (đã tự cách)...'
        : 'Đang viết nối liền ký tự...';

    _inkRepaintNotifier.value++;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointerId || _currentStroke == null) return;

    _currentStroke!.addPoint(
      StrokePointModel(
        x: event.localPosition.dx,
        y: event.localPosition.dy,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        pressure: event.pressure,
      ),
    );
    _inkRepaintNotifier.value++;
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    if (event.pointer != _activePointerId) return;

    _currentStroke?.finishStroke();
    _currentStroke = null;
    _activePointerId = null;
    if (StylusInputFilter.isHardwareStylus(event)) {
      _isStylusActive = false;
    }
    _inkRepaintNotifier.value++;

    // Khởi động bộ đếm chờ 650ms:
    // - Nếu người dùng đặt bút viết tiếp trước 650ms (đánh dấu tiếng Việt / viết chữ kế tiếp) -> gom chung nét.
    // - Nếu ngừng đủ 650ms -> nhận diện chữ, đẩy lên dòng vở và làm mờ ẩn nét vẽ.
    _commitTimer?.cancel();
    _commitTimer = Timer(_strokeCommitDelay, _commitActiveStrokesToRow);
  }

  Future<void> _commitActiveStrokesToRow() async {
    if (_activeStrokes.isEmpty || !mounted) return;

    final List<InkStrokeModel> strokesToRecognize =
        List<InkStrokeModel>.from(_activeStrokes);
    final bool shouldInsertSpace =
        _hasCommittedAtLeastOnce && _insertSpaceBeforeCurrentGroup;

    final String preContext = widget.getCurrentRowCleanText();
    final String recognized = await _recognitionService.recognizeStrokes(
      strokes: strokesToRecognize,
      preContext: preContext,
      writingAreaWidth: _padSize.width,
      writingAreaHeight: _padSize.height,
    );

    if (!mounted) return;

    if (recognized.isNotEmpty) {
      widget.onCommitRecognizedText(
        recognized,
        insertLeadingSpace: shouldInsertSpace,
      );
      _hasCommittedAtLeastOnce = true;
    }

    if (_activePointerId == null &&
        _activeStrokes.length == strokesToRecognize.length) {
      // Làm mờ dần nét vẽ trên Bottom Sheet rồi xóa sạch (160ms)
      await _fadeOutController.reverse(from: 1.0);
      if (!mounted) return;
      if (_activePointerId == null) {
        _activeStrokes.clear();
        _fadeOutController.value = 1.0;
        _inkRepaintNotifier.value++;

        // Bắt đầu đếm nhịp nghỉ sau khi nét đã ẩn:
        // - Nếu người dùng viết tiếp ngay (< 650ms) -> nối liền vào từ vừa viết
        // - Nếu ngừng một khoảnh khắc (>= 650ms) -> tự động bật cờ cách từ (' ')
        _insertSpaceBeforeCurrentGroup = false;
        _statusHintNotifier.value =
            'Viết tiếp ngay để nối liền • Ngừng 1 nhịp để cách từ';

        _autoSpaceTimer?.cancel();
        _autoSpaceTimer = Timer(_wordSpacePauseDelay, () {
          if (!mounted) return;
          _insertSpaceBeforeCurrentGroup = true;
          _statusHintNotifier.value =
              'Đã tự động cách từ • Đặt bút để viết từ tiếp theo';
        });
      }
    } else {
      // Người dùng đã vẽ đè nét mới ngay lập tức -> xóa các nét cũ đã chốt
      for (final s in strokesToRecognize) {
        _activeStrokes.remove(s);
      }
      _insertSpaceBeforeCurrentGroup = false;
      _inkRepaintNotifier.value++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double hintFontSize = AppTheme.getResponsiveFontSize(context, 12);

    return LayoutBuilder(
      builder: (context, constraints) {
        _padSize = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Lớp bảng vẽ bút cảm ứng cô lập bằng RepaintBoundary (60-120fps, 0ms lag)
            RepaintBoundary(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUpOrCancel,
                onPointerCancel: _onPointerUpOrCancel,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _PenSheetPaperAndInkPainter(
                    repaint: Listenable.merge(
                      <Listenable>[_inkRepaintNotifier, _fadeOutController],
                    ),
                    strokes: _activeStrokes,
                    fadeOpacityAnimation: _fadeOutController,
                  ),
                ),
              ),
            ),

            // 2. Nhãn trạng thái nhỏ gọn ở góc trên bên trái mặt giấy viết (IgnorePointer để không cản nét bút)
            Positioned(
              left: 16,
              top: 8,
              right: 16,
              child: IgnorePointer(
                child: Row(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable:
                          _recognitionService.isDownloadingModelNotifier,
                      builder: (context, isDownloading, _) {
                        if (isDownloading) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.creamBackground,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryBlue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Đang tải gói AI nhận diện chữ Tiếng Việt lần đầu (~20MB)...',
                                  style: TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontSize: hintFontSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ValueListenableBuilder<String>(
                          valueListenable: _statusHintNotifier,
                          builder: (context, statusText, _) {
                            return Text(
                              statusText,
                              style: TextStyle(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.55),
                                fontSize: hintFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// CustomPainter vẽ mặt giấy kẻ ngang phóng lớn + nét mực thời gian thực như ứng dụng Paint (0ms lag)
class _PenSheetPaperAndInkPainter extends CustomPainter {
  final List<InkStrokeModel> strokes;
  final Animation<double> fadeOpacityAnimation;

  _PenSheetPaperAndInkPainter({
    required Listenable repaint,
    required this.strokes,
    required this.fadeOpacityAnimation,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Vẽ nền giấy trắng và các đường kẻ ngang dẫn hướng phóng lớn như tờ giấy thật
    final Paint bgPaint = Paint()..color = AppColors.basicWhite;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final Paint subLinePaint = Paint()
      ..color = AppColors.primaryBlue.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;

    final Paint baseLinePaint = Paint()
      ..color = AppColors.primaryBlue.withValues(alpha: 0.28)
      ..strokeWidth = 1.6;

    // Chia mặt giấy viết thành 4 khoảng ô ly phóng lớn, đường kẻ đậm nằm ở khoảng 75% chiều cao để dễ viết chữ có dấu
    final double stepY = size.height / 4.0;
    for (int i = 1; i <= 3; i++) {
      final double y = stepY * i;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i == 3 ? baseLinePaint : subLinePaint,
      );
    }

    // 2. Vẽ các nét mực của người dùng đậm nét như Paint với hiệu ứng mờ dần khi tự động ẩn
    if (strokes.isEmpty) return;

    final double opacity = fadeOpacityAnimation.value.clamp(0.0, 1.0);
    final Paint inkPaint = Paint()
      ..color = AppColors.primaryBlue.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.5;

    final Paint dotPaint = Paint()
      ..color = AppColors.primaryBlue.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    for (final InkStrokeModel stroke in strokes) {
      if (stroke.points.length == 1) {
        final StrokePointModel pt = stroke.points.first;
        canvas.drawCircle(Offset(pt.x, pt.y), 2.5, dotPaint);
      } else if (stroke.points.length > 1) {
        canvas.drawPath(stroke.path, inkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PenSheetPaperAndInkPainter oldDelegate) {
    return true;
  }
}
