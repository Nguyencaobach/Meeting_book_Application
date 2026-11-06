import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/stroke_point_model.dart';
import '../../../../services/handwriting_recognition_service.dart';
import '../../../../services/stylus_input_filter.dart';

// ===========================================================================
// BẢNG VIẾT BÚT CẢM ỨNG TRONG BOTTOM SHEET DÀNH CHO CHẾ ĐỘ "NÉT ĐÁNH MÁY"
// (PEN HANDWRITING PAD WIDGET - TỐI ƯU 0MS LAG VỚI REPAINTBOUNDARY)
// Công dụng:
// - Hiển thị mặt giấy viết phóng lớn có đường kẻ ngang dẫn hướng.
// - Đồng bộ trực tiếp với Bong bóng Bút viết nổi (FloatingPenBubbleWidget):
//   + Hiển thị đúng Màu chữ (selectedColorValue), Kiểu nét (selectedPenStyle)
//     và Độ dày nét (selectedStrokeWidth) người dùng đã chọn trong bong bóng.
//   + Hỗ trợ chế độ Cục tẩy (isEraserMode): chạm hoặc kéo trên bảng viết để xóa
//     từ/ký tự trên dòng đang chọn.
// - Khi nhấc bút nghỉ 1 nhịp (650ms): Gọi Google ML Kit Digital Ink Recognition ('vi')
//   nhận diện nét chữ viết tay thành chữ đánh máy chuẩn (onCommitRecognizedText)
//   và chèn thẳng lên dòng đang chọn với đúng màu chữ của bong bóng.
// ===========================================================================
class PenHandwritingPadWidget extends StatefulWidget {
  /// Callback khi người dùng viết xong 1 cụm nét và AI nhận diện thành chữ đánh máy
  final void Function(String recognizedText, {required bool leadingSpace})?
      onCommitRecognizedText;

  /// Callback cung cấp ngữ cảnh chữ đứng trước trên dòng đang chọn để tăng độ chính xác nhận diện Tiếng Việt
  final String Function()? preContextProvider;

  /// Callback tùy chọn khi dùng chế độ cụm nét vẽ thu phóng
  final void Function(HandwritingClusterModel cluster)?
      onCommitHandwritingCluster;

  /// Màu mực hiện tại từ Bong bóng công cụ Bút
  final int selectedColorValue;

  /// Độ dày nét vẽ hiện tại từ Bong bóng công cụ Bút
  final double selectedStrokeWidth;

  /// Kiểu nét bút hiện tại (`ballpoint`, `fountain`, `marker`, `highlighter`, `dashed`)
  final String selectedPenStyle;

  /// Đang bật chế độ Cục tẩy trong Bong bóng công cụ Bút hay không
  final bool isEraserMode;

  /// Callback xóa từ/cụm chữ trên dòng đang chọn khi quẹt tẩy trên bảng viết
  final VoidCallback? onEraseClusterFromPad;

  const PenHandwritingPadWidget({
    super.key,
    this.onCommitRecognizedText,
    this.preContextProvider,
    this.onCommitHandwritingCluster,
    this.selectedColorValue = 0xFF263BAA,
    this.selectedStrokeWidth = 2.6,
    this.selectedPenStyle = PenStrokeStyle.ballpoint,
    this.isEraserMode = false,
    this.onEraseClusterFromPad,
  });

  @override
  State<PenHandwritingPadWidget> createState() =>
      _PenHandwritingPadWidgetState();
}

class _PenHandwritingPadWidgetState extends State<PenHandwritingPadWidget>
    with SingleTickerProviderStateMixin {
  /// Thời gian chờ sau khi nhấc bút/chuột để chốt cụm nét vẽ lên dòng (650ms)
  static const Duration _strokeCommitDelay = Duration(milliseconds: 650);

  /// Thời gian ngừng một khoảnh khắc sau khi nét cũ đã ẩn để tự động cách từ mới (650ms)
  static const Duration _wordSpacePauseDelay = Duration(milliseconds: 650);

  /// Danh sách các nét mực đang hiển thị trên bảng viết hiện tại
  final List<InkStrokeModel> _activeStrokes = <InkStrokeModel>[];
  InkStrokeModel? _currentStroke;
  int? _activePointerId;
  bool _isStylusActive = false;
  bool _didEraseInCurrentGesture = false;

  /// Bộ báo hiệu vẽ lại chỉ riêng lớp mực CustomPainter (0ms lag, không rebuild Widget)
  final ValueNotifier<int> _inkRepaintNotifier = ValueNotifier<int>(0);

  /// Trạng thái hiển thị hướng dẫn nhỏ ở góc bảng viết
  final ValueNotifier<String> _statusHintNotifier = ValueNotifier<String>(
    'Viết chữ lên bảng bên dưới • Tự động chuyển thành chữ đánh máy lên dòng đang chọn...',
  );

  Timer? _commitTimer;
  Timer? _autoSpaceTimer;

  /// Cờ đánh dấu có tự động chèn khoảng cách trước cụm nét đang viết hay không
  bool _insertSpaceBeforeCurrentGroup = false;

  /// Đánh dấu đã từng chốt ít nhất 1 cụm chữ trong phiên mở bảng viết này chưa
  bool _hasCommittedAtLeastOnce = false;

  late final AnimationController _fadeOutController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: 1.0,
  )..addListener(() {
      _inkRepaintNotifier.value++;
    });

  Size _padSize = Size.zero;

  @override
  void initState() {
    super.initState();
    if (widget.onCommitRecognizedText != null) {
      HandwritingRecognitionService.instance.ensureModelDownloaded();
    }
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

    // Nếu đang bật Cục tẩy trên Bong bóng Bút:
    if (widget.isEraserMode) {
      _commitTimer?.cancel();
      _activePointerId = event.pointer;
      _didEraseInCurrentGesture = false;
      if (_activeStrokes.isNotEmpty) {
        _activeStrokes.clear();
        _inkRepaintNotifier.value++;
        _didEraseInCurrentGesture = true;
        _statusHintNotifier.value = 'Đã tẩy nét đang viết trên bảng...';
      } else {
        widget.onEraseClusterFromPad?.call();
        _didEraseInCurrentGesture = true;
        _statusHintNotifier.value =
            'Đã tẩy cụm nét chữ trên dòng đang chọn...';
      }
      return;
    }

    _commitTimer?.cancel();

    // Nếu nét cũ đang trong quá trình mờ dần (vừa mới chốt xong mà người dùng viết tiếp ngay) ->
    // Dọn ngay nét cũ và giữ chế độ NỐI LIỀN (không cách từ)
    if (_fadeOutController.isAnimating || _fadeOutController.value < 1.0) {
      _fadeOutController.stop();
      _fadeOutController.value = 1.0;
      _activeStrokes.clear();
    }

    // Nếu người dùng đặt bút viết tiếp TRƯỚC khi bộ đếm nghỉ (_autoSpaceTimer) kết thúc ->
    // Hủy bộ đếm cách từ để xếp cụm nét mới sát vào cụm vừa viết
    if (_autoSpaceTimer != null && _autoSpaceTimer!.isActive) {
      _autoSpaceTimer!.cancel();
      if (_activeStrokes.isEmpty) {
        _insertSpaceBeforeCurrentGroup = false;
      }
    }

    // Hoàn tất nét trước nếu có
    _currentStroke?.finishStroke();

    _activePointerId = event.pointer;
    final InkStrokeModel newStroke = InkStrokeModel(
      colorValue: widget.selectedColorValue,
      strokeWidth: widget.selectedStrokeWidth,
      penStyle: widget.selectedPenStyle,
    )..addPoint(
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
        ? 'Đang viết cụm chữ mới (đã tự cách)...'
        : 'Đang viết nét chữ (${PenStrokeStyle.getLabel(widget.selectedPenStyle)})...';

    _inkRepaintNotifier.value++;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointerId) return;

    if (widget.isEraserMode) {
      if (!_didEraseInCurrentGesture) {
        widget.onEraseClusterFromPad?.call();
        _didEraseInCurrentGesture = true;
      }
      return;
    }

    if (_currentStroke == null) return;

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

    if (widget.isEraserMode) {
      _activePointerId = null;
      _didEraseInCurrentGesture = false;
      if (StylusInputFilter.isHardwareStylus(event)) {
        _isStylusActive = false;
      }
      return;
    }

    _currentStroke?.finishStroke();
    _currentStroke = null;
    _activePointerId = null;
    if (StylusInputFilter.isHardwareStylus(event)) {
      _isStylusActive = false;
    }
    _inkRepaintNotifier.value++;

    // Khởi động bộ đếm chờ 650ms:
    // - Nếu người dùng đặt bút viết tiếp trước 650ms (đánh dấu tiếng Việt / viết chữ kế tiếp) -> gom chung nét.
    // - Nếu ngừng đủ 650ms -> cắt khung bao cụm nét, chuẩn hóa kích cỡ và đẩy lên dòng đang chọn.
    _commitTimer?.cancel();
    _commitTimer = Timer(_strokeCommitDelay, _commitActiveStrokesToRow);
  }

  Future<void> _commitActiveStrokesToRow() async {
    if (_activeStrokes.isEmpty || !mounted) return;

    final List<InkStrokeModel> strokesToCommit =
        List<InkStrokeModel>.from(_activeStrokes);
    final bool shouldInsertSpace =
        _hasCommittedAtLeastOnce && _insertSpaceBeforeCurrentGroup;

    // 1. Nếu đang dùng chế độ "Nét đánh máy" (onCommitRecognizedText != null):
    //    Nhận diện nét chữ viết tay thành văn bản Tiếng Việt đánh máy bằng Google ML Kit
    if (widget.onCommitRecognizedText != null) {
      _statusHintNotifier.value = 'Đang nhận diện nét chữ thành chữ đánh máy...';
      final String recognizedText =
          await HandwritingRecognitionService.instance.recognizeStrokes(
        strokes: strokesToCommit,
        preContext: widget.preContextProvider?.call(),
        writingAreaWidth: _padSize.width,
        writingAreaHeight: _padSize.height,
      );

      if (recognizedText.isNotEmpty && mounted) {
        widget.onCommitRecognizedText!(
          recognizedText,
          leadingSpace: shouldInsertSpace,
        );
        _hasCommittedAtLeastOnce = true;
      } else if (mounted) {
        _statusHintNotifier.value =
            'Chưa nhận diện rõ chữ • Hãy viết rõ nét hơn trên bảng viết...';
      }
    } else if (widget.onCommitHandwritingCluster != null) {
      // 2. Nhánh dự phòng cụm nét vẽ
      final HandwritingClusterModel? cluster =
          HandwritingClusterModel.fromInkStrokes(
        strokesToCommit,
        padHeight: _padSize.height,
        leadingSpace: shouldInsertSpace,
        colorValue: widget.selectedColorValue,
        strokeWidth: widget.selectedStrokeWidth,
        penStyle: widget.selectedPenStyle,
      );

      if (cluster != null && mounted) {
        widget.onCommitHandwritingCluster!(cluster);
        _hasCommittedAtLeastOnce = true;
      }
    }

    if (_activePointerId == null &&
        _activeStrokes.length == strokesToCommit.length) {
      // Làm mờ dần nét vẽ trên Bottom Sheet rồi xóa sạch (150ms)
      await _fadeOutController.reverse(from: 1.0);
      if (!mounted) return;
      if (_activePointerId == null) {
        _activeStrokes.clear();
        _fadeOutController.value = 1.0;
        _inkRepaintNotifier.value++;

        // Bắt đầu đếm nhịp nghỉ sau khi nét đã ẩn:
        // - Nếu người dùng viết tiếp ngay (< 650ms) -> xếp sát cụm vừa viết
        // - Nếu ngừng một khoảnh khắc (>= 650ms) -> tự động bật cờ cách khoảng trắng
        _insertSpaceBeforeCurrentGroup = false;
        _statusHintNotifier.value =
            'Viết tiếp ngay để nối sát • Ngừng 1 nhịp để cách từ';

        _autoSpaceTimer?.cancel();
        _autoSpaceTimer = Timer(_wordSpacePauseDelay, () {
          if (!mounted) return;
          _insertSpaceBeforeCurrentGroup = true;
          _statusHintNotifier.value =
              'Đã tự động cách chữ • Đặt bút để viết từ tiếp theo';
        });
      }
    } else {
      for (final s in strokesToCommit) {
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
                child: ValueListenableBuilder<String>(
                  valueListenable: _statusHintNotifier,
                  builder: (context, statusText, _) {
                    return Text(
                      widget.isEraserMode
                          ? 'Đang bật Cục tẩy: Chạm vào đây hoặc chạm lên dòng biểu mẫu để xóa cụm chữ viết tay'
                          : statusText,
                      style: TextStyle(
                        color: widget.isEraserMode
                            ? AppColors.dangerRed
                            : AppColors.primaryBlue.withValues(alpha: 0.55),
                        fontSize: hintFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
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

    // 2. Vẽ các nét mực của người dùng theo đúng Màu chữ, Kiểu nét & Độ dày nét đã chọn trong Bong bóng
    if (strokes.isEmpty) return;

    final double opacity = fadeOpacityAnimation.value.clamp(0.0, 1.0);

    for (final InkStrokeModel stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final List<Offset> scaledPts = stroke.points
          .map((StrokePointModel pt) => Offset(pt.x, pt.y))
          .toList(growable: false);
      PenStrokeStyle.paintScaledPoints(
        canvas,
        scaledPts,
        colorValue: stroke.colorValue,
        strokeWidth: (stroke.strokeWidth * 1.45).clamp(2.0, 9.5),
        penStyle: stroke.penStyle,
        opacityMultiplier: opacity,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PenSheetPaperAndInkPainter oldDelegate) {
    return true;
  }
}
