import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/stroke_point_model.dart';

// ===========================================================================
// BONG BÓNG CÔNG CỤ BÚT VIẾT NỔI KÉO THẢ TỰ DO (FLOATING PEN BUBBLE WIDGET)
// Dùng chung cho cả 2 Tab: Ghi chú (note5x/note4x) & Sổ dự giờ (primary_school_eval_v1)
// Công dụng:
// - Hiển thị nút bong bóng (Bubble) nhỏ gọn có icon Bút viết (hoặc Cục tẩy khi đang bật tẩy),
//   người dùng kéo thả tự do đến bất kỳ vị trí nào trên màn hình.
// - Khi bấm vào bong bóng sẽ mở Form công cụ Bút viết gồm:
//   + Màu chữ: Chọn nhanh màu mực viết (Xanh mực, Đen, Đỏ, Xanh lá, Tím, Cam đậm).
//   + Nét chữ: Bấm vào mở bộ công cụ 5 kiểu nét vẽ (Bút bi, Bút máy thanh đậm,
//     Bút lông, Bút dạ quang tô sáng, Nét đứt) + chọn cỡ độ dày nét kèm khung xem trước.
//   + Nút tẩy (Cục tẩy): Bật/tắt chế độ cục tẩy (đổi icon bong bóng sang hình cục tẩy
//     và dùng lại logic chạm/kéo xóa nét hoặc xóa lùi từ nhận diện).
//   + Hoàn tác: Bấm hoàn tác liên tục nhiều lần mà không tự đóng form.
//   + Chế độ hiển thị nét viết (Nét viết tự nhiên <-> Nét đánh máy):
//     * Nét viết tự nhiên: Viết/vẽ trực tiếp lên mặt giấy ở tốc độ 60-120fps.
//     * Nét đánh máy: Chạm chọn dòng/ô và mở Bottom Sheet viết bút để nhận diện
//       nét chữ viết tay thành chữ đánh máy chuẩn (áp dụng đầy đủ màu chữ của bong bóng).
//   + Cây thước kẻ: Bật/tắt thước kẻ ảo trên mặt giấy (kéo di chuyển, xoay 360°,
//     kẻ đường thẳng tự động bám sát mép thước).
// - Form chỉ đóng lại thành bong bóng khi người dùng chủ động bấm nút "X".
// ===========================================================================
class FloatingPenBubbleWidget extends StatefulWidget {
  final int selectedColorValue;
  final double selectedStrokeWidth;
  final String selectedPenStyle;
  final bool isEraserMode;
  final bool isRulerVisible;
  final bool isTypedHandwritingMode;
  final bool canUndo;
  final int strokeOrClusterCount;
  final bool isObservationMode;

  final ValueChanged<int> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final ValueChanged<String> onPenStyleChanged;
  final ValueChanged<bool> onEraserModeChanged;
  final ValueChanged<bool> onRulerVisibilityChanged;
  final ValueChanged<bool> onTypedHandwritingModeChanged;
  final VoidCallback onUndoPressed;

  const FloatingPenBubbleWidget({
    super.key,
    required this.selectedColorValue,
    required this.selectedStrokeWidth,
    required this.selectedPenStyle,
    required this.isEraserMode,
    required this.isRulerVisible,
    required this.isTypedHandwritingMode,
    required this.canUndo,
    required this.strokeOrClusterCount,
    required this.isObservationMode,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onPenStyleChanged,
    required this.onEraserModeChanged,
    required this.onRulerVisibilityChanged,
    required this.onTypedHandwritingModeChanged,
    required this.onUndoPressed,
  });

  @override
  State<FloatingPenBubbleWidget> createState() =>
      _FloatingPenBubbleWidgetState();
}

class _FloatingPenBubbleWidgetState extends State<FloatingPenBubbleWidget> {
  /// Vị trí bong bóng theo tỷ lệ màn hình (0.0 -> 1.0) để khi xoay ngang/dọc không bị văng khỏi màn hình
  double _normX = 0.88;
  double _normY = 0.14;

  /// Trạng thái mở Form công cụ (Chỉ tắt khi bấm nút X)
  bool _isFormOpen = false;

  /// Trạng thái mở rộng bộ công cụ "2. Nét chữ" bên trong Form
  bool _isStrokeToolkitExpanded = false;

  /// Danh sách bảng màu mực bút tiêu chuẩn
  static const List<_InkColorOption> _inkColors = <_InkColorOption>[
    _InkColorOption(value: 0xFF263BAA, label: 'Xanh mực'),
    _InkColorOption(value: 0xFF000000, label: 'Đen'),
    _InkColorOption(value: 0xFFE53935, label: 'Đỏ'),
    _InkColorOption(value: 0xFF2E7D32, label: 'Xanh lá'),
    _InkColorOption(value: 0xFF6A1B9A, label: 'Tím'),
    _InkColorOption(value: 0xFFE65100, label: 'Cam đậm'),
  ];

  /// Các mức độ dày nét chọn nhanh
  static const List<_StrokeWidthPreset> _widthPresets = <_StrokeWidthPreset>[
    _StrokeWidthPreset(width: 1.6, label: 'Mảnh'),
    _StrokeWidthPreset(width: 2.6, label: 'Vừa'),
    _StrokeWidthPreset(width: 4.0, label: 'Đậm'),
    _StrokeWidthPreset(width: 5.8, label: 'Rất đậm'),
  ];

  void _handleDragUpdate(
    DragUpdateDetails details,
    Size viewportSize,
    double widgetWidth,
    double widgetHeight,
  ) {
    final double availW = math.max(1.0, viewportSize.width - widgetWidth);
    final double availH = math.max(1.0, viewportSize.height - widgetHeight);

    final double currentLeft = _normX * availW;
    final double currentTop = _normY * availH;

    final double nextLeft = (currentLeft + details.delta.dx).clamp(0.0, availW);
    final double nextTop = (currentTop + details.delta.dy).clamp(0.0, availH);

    setState(() {
      _normX = (nextLeft / availW).clamp(0.0, 1.0);
      _normY = (nextTop / availH).clamp(0.0, 1.0);
    });
  }

  IconData _getPenStyleIcon(String style) {
    switch (style) {
      case PenStrokeStyle.fountain:
        return Icons.history_edu_rounded;
      case PenStrokeStyle.marker:
        return Icons.brush_rounded;
      case PenStrokeStyle.highlighter:
        return Icons.border_color_rounded;
      case PenStrokeStyle.dashed:
        return Icons.power_input_rounded;
      case PenStrokeStyle.ballpoint:
      default:
        return Icons.edit_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        final double bubbleSize =
            (viewportSize.shortestSide * 0.11).clamp(50.0, 62.0);
        final double formWidth =
            (viewportSize.width * 0.42).clamp(290.0, 365.0);
        final double estimatedFormHeight =
            _isStrokeToolkitExpanded ? 545.0 : 395.0;

        final double activeW = _isFormOpen ? formWidth : bubbleSize;
        final double activeH = _isFormOpen
            ? math.min(estimatedFormHeight, viewportSize.height - 16.0)
            : bubbleSize;

        final double availW = math.max(8.0, viewportSize.width - activeW - 8.0);
        final double availH =
            math.max(8.0, viewportSize.height - activeH - 8.0);

        final double left = (_normX * availW).clamp(8.0, availW);
        final double top = (_normY * availH).clamp(8.0, availH);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: left,
              top: top,
              child: _isFormOpen
                  ? _buildExpandedToolkitForm(
                      context: context,
                      viewportSize: viewportSize,
                      formWidth: formWidth,
                      maxFormHeight: viewportSize.height - 16.0,
                    )
                  : _buildCollapsedBubble(
                      context: context,
                      viewportSize: viewportSize,
                      bubbleSize: bubbleSize,
                    ),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // 1. TRẠNG THÁI THU GỌN: BONG BÓNG BÚT / TẨY NỔI KÉO ĐI MỌI NƠI TRÊN MÀN HÌNH
  // ===========================================================================
  Widget _buildCollapsedBubble({
    required BuildContext context,
    required Size viewportSize,
    required double bubbleSize,
  }) {
    final Color activeInkColor = Color(widget.selectedColorValue);
    final bool isEraser = widget.isEraserMode;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (DragUpdateDetails details) => _handleDragUpdate(
        details,
        viewportSize,
        bubbleSize,
        bubbleSize,
      ),
      onTap: () {
        setState(() {
          _isFormOpen = true;
        });
      },
      child: Container(
        width: bubbleSize,
        height: bubbleSize,
        decoration: BoxDecoration(
          color: isEraser ? AppColors.dangerRed : AppColors.primaryBlue,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.creamBackground,
            width: 2.6,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.basicBlack.withValues(alpha: 0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              isEraser
                  ? Icons.cleaning_services_rounded
                  : _getPenStyleIcon(widget.selectedPenStyle),
              color: AppColors.basicWhite,
              size: bubbleSize * 0.48,
            ),
            // Chấm hiển thị màu mực đang chọn ở góc dưới bên phải bong bóng
            if (!isEraser)
              Positioned(
                right: 5,
                bottom: 5,
                child: Container(
                  width: bubbleSize * 0.25,
                  height: bubbleSize * 0.25,
                  decoration: BoxDecoration(
                    color: activeInkColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.basicWhite,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
            // Huy hiệu nhỏ báo đang bật Cây thước kẻ hoặc Nét đánh máy ở góc trên bên trái bong bóng
            if (widget.isRulerVisible || widget.isTypedHandwritingMode)
              Positioned(
                left: 3,
                top: 3,
                child: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: AppColors.creamBackground,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryBlue,
                      width: 1.4,
                    ),
                  ),
                  child: Icon(
                    widget.isRulerVisible
                        ? Icons.straighten_rounded
                        : Icons.text_fields_rounded,
                    color: AppColors.primaryBlue,
                    size: bubbleSize * 0.22,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TRẠNG THÁI MỞ FORM: CÁC CÔNG CỤ BÚT VIẾT + NÚT X
  // ===========================================================================
  Widget _buildExpandedToolkitForm({
    required BuildContext context,
    required Size viewportSize,
    required double formWidth,
    required double maxFormHeight,
  }) {
    final double titleFontSize = AppTheme.getResponsiveFontSize(context, 14.5);
    final double labelFontSize = AppTheme.getResponsiveFontSize(context, 13.0);
    final double smallFontSize = AppTheme.getResponsiveFontSize(context, 11.5);

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: formWidth,
          maxHeight: maxFormHeight.clamp(220.0, 560.0),
        ),
        child: Container(
          width: formWidth,
          decoration: BoxDecoration(
            color: AppColors.basicWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.primaryBlue,
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.basicBlack.withValues(alpha: 0.24),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thanh tiêu đề Form (Có thể nắm kéo di chuyển Form + Nút X đóng Form)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (DragUpdateDetails details) => _handleDragUpdate(
                  details,
                  viewportSize,
                  formWidth,
                  280.0,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.isEraserMode
                            ? Icons.cleaning_services_rounded
                            : Icons.edit_rounded,
                        color: AppColors.creamBackground,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isObservationMode
                              ? 'Công cụ Bút (Sổ dự giờ)'
                              : 'Công cụ Bút (Ghi chú)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.basicWhite,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Nút X: Bấm vào mới tắt Form về lại bong bóng
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          setState(() {
                            _isFormOpen = false;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.basicWhite.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: AppColors.basicWhite,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Nội dung các mục công cụ bên trong Form (Tự động cuộn nếu màn hình thấp)
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // -------------------------------------------------------
                      // MÀU CHỮ
                      // -------------------------------------------------------
                      Row(
                        children: [
                          Text(
                            'Màu chữ',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontSize: labelFontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _inkColors
                                .firstWhere(
                                  (c) => c.value == widget.selectedColorValue,
                                  orElse: () => _inkColors.first,
                                )
                                .label,
                            style: TextStyle(
                              color: Color(widget.selectedColorValue),
                              fontSize: smallFontSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _inkColors.map((_InkColorOption option) {
                          final bool isSelected = !widget.isEraserMode &&
                              widget.selectedColorValue == option.value;
                          return GestureDetector(
                            onTap: () {
                              if (widget.isEraserMode) {
                                widget.onEraserModeChanged(false);
                              }
                              widget.onColorChanged(option.value);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Color(option.value),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.creamBackground
                                      : AppColors.basicWhite,
                                  width: isSelected ? 3.0 : 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected
                                        ? Color(option.value)
                                            .withValues(alpha: 0.45)
                                        : AppColors.basicBlack
                                            .withValues(alpha: 0.15),
                                    blurRadius: isSelected ? 6 : 3,
                                  ),
                                ],
                              ),
                              child: isSelected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: AppColors.basicWhite,
                                      size: 18,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 12),

                      // -------------------------------------------------------
                      // NÉT CHỮ (BẤM VÀO HIỂN THỊ BỘ CÔNG CỤ CÁC NÉT VẼ)
                      // -------------------------------------------------------
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          if (widget.isEraserMode) {
                            widget.onEraserModeChanged(false);
                          }
                          setState(() {
                            _isStrokeToolkitExpanded =
                                !_isStrokeToolkitExpanded;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: _isStrokeToolkitExpanded
                                ? AppColors.creamBackground
                                : AppColors.creamBackground
                                    .withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.primaryBlue
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _getPenStyleIcon(widget.selectedPenStyle),
                                color: AppColors.primaryBlue,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Nét chữ: ${PenStrokeStyle.getLabel(widget.selectedPenStyle)} (${widget.selectedStrokeWidth.toStringAsFixed(1)}px)',
                                  style: TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontSize: labelFontSize,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Icon(
                                _isStrokeToolkitExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                color: AppColors.primaryBlue,
                                size: 22,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Bộ công cụ các nét vẽ mở rộng khi bấm vào "Nét chữ"
                      if (_isStrokeToolkitExpanded) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.basicWhite,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.primaryBlue
                                  .withValues(alpha: 0.28),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chọn kiểu nét bút:',
                                style: TextStyle(
                                  color: AppColors.basicBlack,
                                  fontSize: smallFontSize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: PenStrokeStyle.allStyles
                                    .map((String style) {
                                  final bool isSelectedStyle =
                                      widget.selectedPenStyle == style &&
                                          !widget.isEraserMode;
                                  return InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () {
                                      if (widget.isEraserMode) {
                                        widget.onEraserModeChanged(false);
                                      }
                                      widget.onPenStyleChanged(style);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelectedStyle
                                            ? AppColors.primaryBlue
                                            : AppColors.creamBackground,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.primaryBlue
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _getPenStyleIcon(style),
                                            size: 15,
                                            color: isSelectedStyle
                                                ? AppColors.basicWhite
                                                : AppColors.primaryBlue,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            PenStrokeStyle.getLabel(style),
                                            style: TextStyle(
                                              color: isSelectedStyle
                                                  ? AppColors.basicWhite
                                                  : AppColors.primaryBlue,
                                              fontSize: smallFontSize,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Độ dày nét vẽ:',
                                style: TextStyle(
                                  color: AppColors.basicBlack,
                                  fontSize: smallFontSize,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: _widthPresets
                                    .map((_StrokeWidthPreset preset) {
                                  final bool isPresetSelected =
                                      (widget.selectedStrokeWidth -
                                                  preset.width)
                                              .abs() <
                                          0.25;
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2.5,
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () {
                                          if (widget.isEraserMode) {
                                            widget.onEraserModeChanged(false);
                                          }
                                          widget.onStrokeWidthChanged(
                                            preset.width,
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isPresetSelected
                                                ? AppColors.primaryBlue
                                                : AppColors.creamBackground,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            preset.label,
                                            style: TextStyle(
                                              color: isPresetSelected
                                                  ? AppColors.basicWhite
                                                  : AppColors.primaryBlue,
                                              fontSize: smallFontSize * 0.95,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              SizedBox(
                                height: 28,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    activeTrackColor: AppColors.primaryBlue,
                                    inactiveTrackColor: AppColors.primaryBlue
                                        .withValues(alpha: 0.2),
                                    thumbColor: AppColors.primaryBlue,
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 7,
                                    ),
                                  ),
                                  child: Slider(
                                    value: widget.selectedStrokeWidth
                                        .clamp(1.2, 6.5),
                                    min: 1.2,
                                    max: 6.5,
                                    onChanged: (double val) {
                                      if (widget.isEraserMode) {
                                        widget.onEraserModeChanged(false);
                                      }
                                      widget.onStrokeWidthChanged(val);
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Khung xem trước nét vẽ thực tế (Live Stroke Preview)
                              Container(
                                height: 34,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: AppColors.creamBackground
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.primaryBlue
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                child: CustomPaint(
                                  painter: _StrokePreviewPainter(
                                    colorValue: widget.selectedColorValue,
                                    strokeWidth: widget.selectedStrokeWidth,
                                    penStyle: widget.selectedPenStyle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),

                      // -------------------------------------------------------
                      // NÚT TẨY (CỤC TẨY) & NÚT HOÀN TÁC NÉT
                      // -------------------------------------------------------
                      Row(
                        children: [
                          // Nút Tẩy
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                widget.onEraserModeChanged(
                                  !widget.isEraserMode,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.isEraserMode
                                      ? AppColors.dangerRed
                                      : AppColors.creamBackground,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: widget.isEraserMode
                                        ? AppColors.dangerRed
                                        : AppColors.primaryBlue
                                            .withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cleaning_services_rounded,
                                      size: 17,
                                      color: widget.isEraserMode
                                          ? AppColors.basicWhite
                                          : AppColors.primaryBlue,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        widget.isEraserMode
                                            ? 'Đang tẩy'
                                            : 'Nút tẩy',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: widget.isEraserMode
                                              ? AppColors.basicWhite
                                              : AppColors.primaryBlue,
                                          fontSize: labelFontSize * 0.96,
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

                          // Nút Hoàn tác nét
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap:
                                  widget.canUndo ? widget.onUndoPressed : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.canUndo
                                      ? AppColors.creamBackground
                                      : AppColors.creamBackground
                                          .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: widget.canUndo
                                        ? AppColors.primaryBlue
                                        : AppColors.primaryBlue
                                            .withValues(alpha: 0.22),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.undo_rounded,
                                      size: 18,
                                      color: widget.canUndo
                                          ? AppColors.primaryBlue
                                          : AppColors.primaryBlue
                                              .withValues(alpha: 0.38),
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        'Hoàn tác',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: widget.canUndo
                                              ? AppColors.primaryBlue
                                              : AppColors.primaryBlue
                                                  .withValues(alpha: 0.38),
                                          fontSize: labelFontSize * 0.96,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // -------------------------------------------------------
                      // CHẾ ĐỘ HIỂN THỊ NÉT VIẾT: NÉT VIẾT TỰ NHIÊN <-> NÉT ĐÁNH MÁY
                      // -------------------------------------------------------
                      Text(
                        'Chế độ hiển thị nét viết',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: BoxDecoration(
                          color: AppColors.creamBackground
                              .withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primaryBlue.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Chế độ Nét viết tự nhiên (Vẽ trực tiếp lên màn hình)
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(11),
                                onTap: () {
                                  if (widget.isTypedHandwritingMode) {
                                    widget.onTypedHandwritingModeChanged(false);
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !widget.isTypedHandwritingMode
                                        ? AppColors.primaryBlue
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.gesture_rounded,
                                        size: 16,
                                        color: !widget.isTypedHandwritingMode
                                            ? AppColors.basicWhite
                                            : AppColors.primaryBlue,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'Nét viết tự nhiên',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: !widget.isTypedHandwritingMode
                                                ? AppColors.basicWhite
                                                : AppColors.primaryBlue,
                                            fontSize: smallFontSize,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Chế độ Nét đánh máy (Chọn dòng + Mở Bottom Sheet nhận diện chữ đánh máy)
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(11),
                                onTap: () {
                                  if (!widget.isTypedHandwritingMode) {
                                    widget.onTypedHandwritingModeChanged(true);
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: widget.isTypedHandwritingMode
                                        ? AppColors.primaryBlue
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.text_fields_rounded,
                                        size: 16,
                                        color: widget.isTypedHandwritingMode
                                            ? AppColors.basicWhite
                                            : AppColors.primaryBlue,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'Nét đánh máy',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: widget.isTypedHandwritingMode
                                                ? AppColors.basicWhite
                                                : AppColors.primaryBlue,
                                            fontSize: smallFontSize,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      // -------------------------------------------------------
                      // CÂY THƯỚC KẺ (KẺ ĐƯỜNG THẲNG, XOAY GÓC 360°)
                      // -------------------------------------------------------
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          widget.onRulerVisibilityChanged(
                            !widget.isRulerVisible,
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isRulerVisible
                                ? AppColors.primaryBlue
                                : AppColors.creamBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.primaryBlue,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.straighten_rounded,
                                size: 19,
                                color: widget.isRulerVisible
                                    ? AppColors.basicWhite
                                    : AppColors.primaryBlue,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  widget.isRulerVisible
                                      ? 'Đang bật Cây thước kẻ (Chạm để tắt)'
                                      : 'Cây thước kẻ (Kẻ đường thẳng)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: widget.isRulerVisible
                                        ? AppColors.basicWhite
                                        : AppColors.primaryBlue,
                                    fontSize: labelFontSize * 0.96,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
  }
}

// ===========================================================================
// CÂY THƯỚC KẺ ẢO TRÊN MẶT GIẤY (VIRTUAL RULER OVERLAY WIDGET)
// Công dụng:
// - Hiển thị cây thước kẻ trong suốt có vạch chia cm/mm ở cả 2 mép trên & dưới.
// - Giữ kéo phần thân giữa của thước (hoặc dùng 2 ngón tay) để di chuyển thước đến bất kỳ đâu.
// - Giữ kéo 2 nút xoay tròn ở 2 đầu thước (hoặc xoay 2 ngón tay) để xoay thước 360°
//   (tự động hít nhẹ ở các góc chuẩn 0°, ±30°, ±45°, ±60°, ±90°).
// - Khi đặt bút kéo dọc theo gần mép trên hoặc mép dưới của cây thước, nét bút sẽ
//   tự động hít thẳng tắp theo đúng cạnh thước (Magnetic Ruler Edge Snap).
// ===========================================================================
class VirtualRulerOverlayWidget extends StatefulWidget {
  final Offset rulerCenter;
  final double rulerAngleRad;
  final double rulerLength;
  final double rulerHeight;
  final ValueChanged<Offset> onCenterChanged;
  final ValueChanged<double> onAngleChanged;
  final VoidCallback onCloseRuler;

  const VirtualRulerOverlayWidget({
    super.key,
    required this.rulerCenter,
    required this.rulerAngleRad,
    required this.rulerLength,
    this.rulerHeight = 68.0,
    required this.onCenterChanged,
    required this.onAngleChanged,
    required this.onCloseRuler,
  });

  @override
  State<VirtualRulerOverlayWidget> createState() =>
      _VirtualRulerOverlayWidgetState();
}

class _VirtualRulerOverlayWidgetState extends State<VirtualRulerOverlayWidget> {
  double _gestureStartAngleRad = 0.0;
  Offset _gestureStartFocalPoint = Offset.zero;
  Offset _gestureStartCenter = Offset.zero;

  /// Chuẩn hóa góc về khoảng (-pi, pi] và tự động hít nhẹ (snap) vào các góc đặc biệt (0°, ±30°, ±45°, ±60°, ±90°, ±135°, 180°)
  double _normalizeAndSnapAngle(double rawRad) {
    double angle = rawRad;
    while (angle <= -math.pi) {
      angle += math.pi * 2.0;
    }
    while (angle > math.pi) {
      angle -= math.pi * 2.0;
    }

    const List<int> snapDegrees = <int>[
      -180,
      -135,
      -90,
      -60,
      -45,
      -30,
      0,
      30,
      45,
      60,
      90,
      135,
      180,
    ];
    final double deg = angle * 180.0 / math.pi;
    for (final int targetDeg in snapDegrees) {
      if ((deg - targetDeg).abs() <= 1.6) {
        return targetDeg * math.pi / 180.0;
      }
    }
    return angle;
  }

  /// Xử lý khi người dùng nắm kéo 1 trong 2 đầu xoay của cây thước
  void _handleRotateKnobPanUpdate(
    DragUpdateDetails details, {
    required bool isRightEnd,
  }) {
    // Đổi vector kéo cục bộ trên thân thước sang độ lệch góc xoay
    final double deltaPerp = details.delta.dy;
    final double armLength = math.max(80.0, widget.rulerLength * 0.42);
    final double dTheta =
        (isRightEnd ? 1.0 : -1.0) * (deltaPerp / armLength);
    final double nextAngle =
        _normalizeAndSnapAngle(widget.rulerAngleRad + dTheta);
    widget.onAngleChanged(nextAngle);
  }

  @override
  Widget build(BuildContext context) {
    final double halfW = widget.rulerLength * 0.5;
    final double halfH = widget.rulerHeight * 0.5;
    final int angleDeg = (widget.rulerAngleRad * 180.0 / math.pi).round();
    final double badgeFontSize = AppTheme.getResponsiveFontSize(context, 11.5);

    // Chừa 9px ở mép trên và 9px ở mép dưới cho phép đầu bút đặt sát vạch chia thước mà không bị tính là kéo thước
    const double edgeSnapPassthroughMargin = 9.0;

    return Positioned(
      left: widget.rulerCenter.dx - halfW,
      top: widget.rulerCenter.dy - halfH,
      width: widget.rulerLength,
      height: widget.rulerHeight,
      child: Transform.rotate(
        angle: widget.rulerAngleRad,
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Phần hiển thị mặt thước trong suốt + vạch chia cm/mm ở cả 2 cạnh trên & dưới
            //    (IgnorePointer = true để mép trên/dưới nhận nét bút kẻ thẳng mượt 100%)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.creamBackground.withValues(alpha: 0.84),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.primaryBlue,
                      width: 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.basicBlack.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _VirtualRulerGraduationPainter(),
                  ),
                ),
              ),
            ),

            // 2. Dải điều khiển ở giữa thân thước:
            //    - Nắm kéo giữa thân thước để di chuyển thước (hoặc dùng 2 ngón tay vừa kéo vừa xoay)
            //    - 2 nút tròn ở 2 đầu thước để nắm xoay góc 360°
            //    - Nút đặt nhanh góc 0° / 90° và nút X đóng thước
            Positioned(
              left: 0,
              right: 0,
              top: edgeSnapPassthroughMargin,
              bottom: edgeSnapPassthroughMargin,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  // Nút nắm xoay đầu trái
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (DragUpdateDetails details) =>
                        _handleRotateKnobPanUpdate(
                      details,
                      isRightEnd: false,
                    ),
                    child: Tooltip(
                      message: 'Giữ kéo lên/xuống để xoay thước',
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.basicWhite,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.rotate_left_rounded,
                          color: AppColors.basicWhite,
                          size: 19,
                        ),
                      ),
                    ),
                  ),

                  // Thân giữa thước: Giữ kéo để di chuyển thước, hoặc dùng 2 ngón tay xoay thước
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (ScaleStartDetails details) {
                        _gestureStartAngleRad = widget.rulerAngleRad;
                        _gestureStartFocalPoint = details.focalPoint;
                        _gestureStartCenter = widget.rulerCenter;
                      },
                      onScaleUpdate: (ScaleUpdateDetails details) {
                        final Offset deltaGlobal =
                            details.focalPoint - _gestureStartFocalPoint;
                        widget.onCenterChanged(
                          _gestureStartCenter + deltaGlobal,
                        );
                        if (details.pointerCount >= 2 &&
                            details.rotation.abs() > 0.005) {
                          final double nextAngle = _normalizeAndSnapAngle(
                            _gestureStartAngleRad + details.rotation,
                          );
                          widget.onAngleChanged(nextAngle);
                        }
                      },
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Huy hiệu hiển thị góc nghiêng hiện tại của thước
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBlue,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.open_with_rounded,
                                      color: AppColors.basicWhite,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Thước $angleDeg°',
                                      style: TextStyle(
                                        color: AppColors.basicWhite,
                                        fontSize: badgeFontSize,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Nút xoay nhanh Ngang (0°) <-> Dọc (90°)
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () {
                                  final bool isNearZero =
                                      angleDeg.abs() <= 2;
                                  widget.onAngleChanged(
                                    isNearZero ? (math.pi / 2.0) : 0.0,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.basicWhite,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.primaryBlue,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: Text(
                                    angleDeg.abs() <= 2 ? 'Xoay 90°' : 'Về 0°',
                                    style: TextStyle(
                                      color: AppColors.primaryBlue,
                                      fontSize: badgeFontSize * 0.95,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),

                              // Nút X tắt nhanh Cây thước kẻ ngay trên thân thước
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: widget.onCloseRuler,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.dangerRed,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.basicWhite,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: AppColors.basicWhite,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Nút nắm xoay đầu phải
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (DragUpdateDetails details) =>
                        _handleRotateKnobPanUpdate(
                      details,
                      isRightEnd: true,
                    ),
                    child: Tooltip(
                      message: 'Giữ kéo lên/xuống để xoay thước',
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.basicWhite,
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.rotate_right_rounded,
                          color: AppColors.basicWhite,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter vẽ các vạch chia cm / mm dọc theo cả 2 mép trên và dưới của Cây thước kẻ
class _VirtualRulerGraduationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint tickPaint = Paint()
      ..color = AppColors.primaryBlue.withValues(alpha: 0.85)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final Paint majorTickPaint = Paint()
      ..color = AppColors.primaryBlue
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    // Mỗi 1cm ~ 38 logical pixels (mỗi 1mm ~ 3.8px)
    const double mmSpacing = 3.8;
    const double marginX = 16.0;
    final double usableWidth = math.max(0.0, size.width - marginX * 2.0);
    final int totalMm = (usableWidth / mmSpacing).floor();

    for (int mm = 0; mm <= totalMm; mm++) {
      final double x = marginX + mm * mmSpacing;
      final bool isCm = mm % 10 == 0;
      final bool isHalfCm = mm % 5 == 0;
      final double tickLen = isCm ? 11.0 : (isHalfCm ? 7.5 : 4.5);
      final Paint activePaint = isCm ? majorTickPaint : tickPaint;

      // Vạch chia mép trên
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, tickLen),
        activePaint,
      );

      // Vạch chia mép dưới
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, size.height - tickLen),
        activePaint,
      );

      if (isCm) {
        final int cmNumber = mm ~/ 10;
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: '$cmNumber',
            style: const TextStyle(
              color: AppColors.primaryBlue,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x - tp.width * 0.5, tickLen + 1.0),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VirtualRulerGraduationPainter oldDelegate) {
    return false;
  }
}

class _InkColorOption {
  final int value;
  final String label;

  const _InkColorOption({
    required this.value,
    required this.label,
  });
}

class _StrokeWidthPreset {
  final double width;
  final String label;

  const _StrokeWidthPreset({
    required this.width,
    required this.label,
  });
}

/// CustomPainter vẽ đường cong mẫu xem trước trực tiếp (Live Preview) trong bộ công cụ "2. Nét chữ"
class _StrokePreviewPainter extends CustomPainter {
  final int colorValue;
  final double strokeWidth;
  final String penStyle;

  const _StrokePreviewPainter({
    required this.colorValue,
    required this.strokeWidth,
    required this.penStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final List<Offset> samplePoints = <Offset>[];
    const int steps = 28;
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double x = 14.0 + t * (size.width - 28.0);
      final double y = (size.height * 0.5) +
          math.sin(t * math.pi * 2.0) * (size.height * 0.24);
      samplePoints.add(Offset(x, y));
    }

    PenStrokeStyle.paintScaledPoints(
      canvas,
      samplePoints,
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      penStyle: penStyle,
    );
  }

  @override
  bool shouldRepaint(covariant _StrokePreviewPainter oldDelegate) {
    return oldDelegate.colorValue != colorValue ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.penStyle != penStyle;
  }
}
