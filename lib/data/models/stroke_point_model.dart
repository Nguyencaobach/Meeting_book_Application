import 'dart:math' as math;
import 'dart:ui';

// ===========================================================================
// MÔ HÌNH ĐIỂM TỌA ĐỘ NÉT BÚT, BỘ CÔNG CỤ KIỂU NÉT VẼ & DỮ LIỆU CHỮ VIẾT TAY TRÊN RAM
// (STROKE POINT / PEN STROKE STYLE / HANDWRITING CLUSTER / FREEHAND PAGE STROKE)
// Công dụng:
// 1. StrokePointModel & InkStrokeModel:
//    - Lưu tọa độ (x, y), thời gian thực (timestampMs), lực nhấn (pressure),
//      màu mực (colorValue), độ dày nét (strokeWidth) và kiểu nét (penStyle)
//      khi người dùng đang viết thời gian thực (60-120fps, 0ms lag).
// 2. PenStrokeStyle:
//    - Cung cấp bộ công cụ 5 kiểu nét vẽ vector phần cứng (Bút bi, Bút máy thanh đậm,
//      Bút lông đậm, Bút dạ quang tô sáng, Nét đứt) hoạt động ở 60-120fps.
// 3. HandwritingClusterModel (Dùng cho Sổ dự giờ):
//    - Đóng gói cụm nét chữ người dùng viết trên Bottom Sheet thành khung chuẩn hóa
//      [0..1] kèm tỷ lệ khung (aspectRatio), màu mực, cỡ nét và kiểu bút.
// 4. FreehandPageStrokeModel (Dùng cho Ghi chú):
//    - Lưu nét bút vẽ trực tiếp lên trang giấy vở ô ly theo hệ tọa độ chuẩn hóa
//      (nx = x / paperWidth, ry = y / rowHeight) kèm màu mực, cỡ nét và kiểu bút.
// ===========================================================================

class PenStrokeStyle {
  PenStrokeStyle._();

  static const String ballpoint = 'ballpoint';
  static const String fountain = 'fountain';
  static const String marker = 'marker';
  static const String highlighter = 'highlighter';
  static const String dashed = 'dashed';

  static const List<String> allStyles = <String>[
    ballpoint,
    fountain,
    marker,
    highlighter,
    dashed,
  ];

  static String getLabel(String style) {
    switch (style) {
      case fountain:
        return 'Bút máy';
      case marker:
        return 'Bút lông';
      case highlighter:
        return 'Dạ quang';
      case dashed:
        return 'Nét đứt';
      case ballpoint:
      default:
        return 'Bút bi';
    }
  }

  /// Vẽ danh sách tọa độ điểm thực tế `scaledPoints` lên `Canvas` theo đúng:
  /// - Màu mực (`colorValue`)
  /// - Độ dày nét (`strokeWidth`)
  /// - Kiểu nét bút (`penStyle`: Bút bi, Bút máy, Bút lông, Dạ quang, Nét đứt)
  static void paintScaledPoints(
    Canvas canvas,
    List<Offset> scaledPoints, {
    required int colorValue,
    required double strokeWidth,
    required String penStyle,
    double opacityMultiplier = 1.0,
  }) {
    if (scaledPoints.isEmpty) return;

    final Color baseColor = Color(colorValue);
    final double effectiveAlpha = (penStyle == highlighter
            ? 0.34 * opacityMultiplier
            : baseColor.a * opacityMultiplier)
        .clamp(0.0, 1.0);
    final Color effectiveColor = baseColor.withValues(alpha: effectiveAlpha);

    final double effectiveWidth = penStyle == highlighter
        ? strokeWidth * 3.0
        : (penStyle == marker ? strokeWidth * 1.45 : strokeWidth);

    final StrokeCap strokeCap = penStyle == marker
        ? StrokeCap.square
        : (penStyle == highlighter ? StrokeCap.butt : StrokeCap.round);
    final StrokeJoin strokeJoin =
        penStyle == marker ? StrokeJoin.bevel : StrokeJoin.round;

    final Paint strokePaint = Paint()
      ..color = effectiveColor
      ..strokeWidth = effectiveWidth
      ..strokeCap = strokeCap
      ..strokeJoin = strokeJoin
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (scaledPoints.length == 1) {
      final Paint dotPaint = Paint()
        ..color = effectiveColor
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawCircle(
        scaledPoints.first,
        effectiveWidth * 0.55,
        dotPaint,
      );
      return;
    }

    // Kiểu 1: Bút máy (Nét thanh nét đậm mềm mại theo góc kéo bút Calligraphic)
    if (penStyle == fountain) {
      final Path mainPath = _buildSmoothBezierPath(scaledPoints);
      strokePaint.strokeWidth = effectiveWidth * 0.85;
      canvas.drawPath(mainPath, strokePaint);

      // Tạo hiệu ứng ngòi bút máy nghiêng 35 độ (nét xuống đậm, nét ngang/lên thanh)
      final Offset nibShift = Offset(
        effectiveWidth * 0.32,
        effectiveWidth * 0.22,
      );
      final List<Offset> shiftedPoints = scaledPoints
          .map((Offset pt) => pt + nibShift)
          .toList(growable: false);
      final Path nibPath = _buildSmoothBezierPath(shiftedPoints);
      final Paint nibPaint = Paint()
        ..color = effectiveColor.withValues(
          alpha: (effectiveAlpha * 0.78).clamp(0.0, 1.0),
        )
        ..strokeWidth = effectiveWidth * 0.68
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      canvas.drawPath(nibPath, nibPaint);
      return;
    }

    final Path smoothPath = _buildSmoothBezierPath(scaledPoints);

    // Kiểu 2: Nét đứt (Dashed stroke)
    if (penStyle == dashed) {
      final double dashLength = math.max(4.0, effectiveWidth * 2.6);
      final double gapLength = math.max(3.0, effectiveWidth * 1.9);
      final Path dashedPath = Path();
      for (final PathMetric metric in smoothPath.computeMetrics()) {
        double distance = 0.0;
        while (distance < metric.length) {
          final double next = math.min(distance + dashLength, metric.length);
          dashedPath.addPath(
            metric.extractPath(distance, next),
            Offset.zero,
          );
          distance = next + gapLength;
        }
      }
      canvas.drawPath(dashedPath, strokePaint);
      return;
    }

    // Kiểu 3, 4, 5: Bút bi (ballpoint), Bút lông (marker), Dạ quang (highlighter)
    canvas.drawPath(smoothPath, strokePaint);
  }

  static Path _buildSmoothBezierPath(List<Offset> pts) {
    final Path path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      path.lineTo(pts.last.dx, pts.last.dy);
      return path;
    }
    for (int i = 1; i < pts.length - 1; i++) {
      final Offset curr = pts[i];
      final Offset next = pts[i + 1];
      final Offset mid = Offset(
        (curr.dx + next.dx) * 0.5,
        (curr.dy + next.dy) * 0.5,
      );
      path.quadraticBezierTo(curr.dx, curr.dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);
    return path;
  }
}

class StrokePointModel {
  final double x;
  final double y;
  final int timestampMs;
  final double pressure;

  const StrokePointModel({
    double? x,
    double? y,
    double? nx,
    double? ry,
    this.timestampMs = 0,
    this.pressure = 0.5,
  })  : x = x ?? nx ?? 0.0,
        y = y ?? ry ?? 0.0;

  double get nx => x;
  double get ry => y;
  double get dx => x;
  double get dy => y;
}

/// Đại diện cho 1 nét bút hoàn chỉnh (từ lúc đặt bút xuống đến lúc nhấc bút lên)
class InkStrokeModel {
  final List<StrokePointModel> points;
  final Path path = Path();
  final int colorValue;
  final double strokeWidth;
  final String penStyle;

  InkStrokeModel({
    List<StrokePointModel>? points,
    this.colorValue = 0xFF263BAA,
    this.strokeWidth = 2.6,
    this.penStyle = PenStrokeStyle.ballpoint,
  }) : points = points ?? <StrokePointModel>[];

  double minX = double.infinity;
  double maxX = double.negativeInfinity;
  double minY = double.infinity;
  double maxY = double.negativeInfinity;

  /// Thêm điểm mới vào nét vẽ và nối mượt bằng đường cong bậc 2 (Quadratic Bezier)
  /// ngay lập tức để khi vẽ lại không phải tính toán lại từ đầu (0ms lag)
  void addPoint(StrokePointModel pt) {
    if (pt.x < minX) minX = pt.x;
    if (pt.x > maxX) maxX = pt.x;
    if (pt.y < minY) minY = pt.y;
    if (pt.y > maxY) maxY = pt.y;

    final int len = points.length;
    if (len == 0) {
      path.moveTo(pt.x, pt.y);
      // Vẽ chấm nhỏ ngay khi vừa chạm bút xuống
      path.lineTo(pt.x + 0.1, pt.y + 0.1);
    } else if (len == 1) {
      final StrokePointModel p0 = points[0];
      final double midX = (p0.x + pt.x) * 0.5;
      final double midY = (p0.y + pt.y) * 0.5;
      path.lineTo(midX, midY);
    } else {
      final StrokePointModel prev = points[len - 1];
      final double midX = (prev.x + pt.x) * 0.5;
      final double midY = (prev.y + pt.y) * 0.5;
      path.quadraticBezierTo(prev.x, prev.y, midX, midY);
    }
    points.add(pt);
  }

  /// Hoàn tất nét vẽ khi nhấc bút
  void finishStroke() {
    if (points.length >= 2) {
      final StrokePointModel last = points.last;
      path.lineTo(last.x, last.y);
    }
  }
}

// ===========================================================================
// MÔ HÌNH CỤM NÉT CHỮ VIẾT TAY CHUẨN HÓA THEO DÒNG (DÙNG CHO SỔ DỰ GIỜ)
// ===========================================================================
class HandwritingClusterModel {
  /// Tỷ lệ chiều rộng / chiều cao chuẩn hóa của cụm nét chữ
  final double aspectRatio;

  /// Có cách 1 khoảng trắng trước cụm nét này hay không (khi nghỉ bút >= 650ms)
  final bool leadingSpace;

  /// Danh sách các nét vẽ trong cụm; mỗi điểm StrokePointModel(x/nx, y/ry) đã chuẩn hóa về [0.0 .. 1.0]
  final List<InkStrokeModel> strokes;

  /// Màu mực của cụm nét chữ (ARGB int)
  final int colorValue;

  /// Độ dày nét chữ khi người dùng chọn trong bong bóng bút
  final double strokeWidth;

  /// Kiểu nét bút (`ballpoint`, `fountain`, `marker`, `highlighter`, `dashed`)
  final String penStyle;

  const HandwritingClusterModel({
    required this.aspectRatio,
    required this.leadingSpace,
    required this.strokes,
    this.colorValue = 0xFF1A237E,
    this.strokeWidth = 2.6,
    this.penStyle = PenStrokeStyle.ballpoint,
  });

  /// Tạo cụm nét chuẩn hóa từ danh sách nét vẽ thực tế trên Bottom Sheet
  /// - Tự động cắt sát khung bao (bounding box) và co giãn về kích thước chuẩn của dòng
  ///   để dù người dùng viết rất to trên Bottom Sheet thì lên dòng vẫn đều đẹp.
  static HandwritingClusterModel? fromInkStrokes(
    List<InkStrokeModel> rawStrokes, {
    required double padHeight,
    required bool leadingSpace,
    int? colorValue,
    double? strokeWidth,
    String? penStyle,
  }) {
    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final InkStrokeModel s in rawStrokes) {
      for (final StrokePointModel p in s.points) {
        if (p.x < minX) minX = p.x;
        if (p.x > maxX) maxX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
    }

    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      return null;
    }

    final double rawW = math.max(4.0, maxX - minX);
    final double rawH = math.max(4.0, maxY - minY);

    // Chiều cao tham chiếu tối thiểu (28% chiều cao bảng viết) để các dấu chấm/gạch ngang
    // không bị phóng đại quá mức, còn chữ viết to sẽ tự động thu nhỏ vừa khít dòng
    final double minRefH =
        (padHeight > 0 ? padHeight * 0.28 : 42.0).clamp(26.0, 88.0);
    final double refH = math.max(rawH, minRefH);
    final double yOffset = (refH - rawH) * 0.5;
    final double aspect = (rawW / refH).clamp(0.12, 10.0);

    final int resolvedColor = colorValue ??
        (rawStrokes.isNotEmpty ? rawStrokes.last.colorValue : 0xFF1A237E);
    final double resolvedWidth = strokeWidth ??
        (rawStrokes.isNotEmpty ? rawStrokes.last.strokeWidth : 2.6);
    final String resolvedStyle = penStyle ??
        (rawStrokes.isNotEmpty
            ? rawStrokes.last.penStyle
            : PenStrokeStyle.ballpoint);

    final List<InkStrokeModel> normalizedStrokes = <InkStrokeModel>[];
    for (final InkStrokeModel s in rawStrokes) {
      if (s.points.isEmpty) continue;
      final List<StrokePointModel> normPts = <StrokePointModel>[];
      StrokePointModel? lastKept;

      for (int i = 0; i < s.points.length; i++) {
        final StrokePointModel pt = s.points[i];
        if (lastKept != null && i < s.points.length - 1) {
          final double dx = pt.x - lastKept.x;
          final double dy = pt.y - lastKept.y;
          if ((dx * dx + dy * dy) < 1.4) {
            continue;
          }
        }
        lastKept = pt;
        final double u = ((pt.x - minX) / rawW).clamp(0.0, 1.0);
        final double v = ((pt.y - minY + yOffset) / refH).clamp(0.0, 1.0);
        normPts.add(StrokePointModel(nx: u, ry: v));
      }

      if (normPts.isNotEmpty) {
        normalizedStrokes.add(
          InkStrokeModel(
            points: normPts,
            colorValue: s.colorValue,
            strokeWidth: s.strokeWidth,
            penStyle: s.penStyle,
          ),
        );
      }
    }

    if (normalizedStrokes.isEmpty) return null;

    return HandwritingClusterModel(
      aspectRatio: aspect,
      leadingSpace: leadingSpace,
      strokes: normalizedStrokes,
      colorValue: resolvedColor,
      strokeWidth: resolvedWidth,
      penStyle: resolvedStyle,
    );
  }

  /// Tính chiều rộng hiển thị (px) của cụm nét khi đặt vào dòng có chiều cao `lineHeight`
  double getRenderedWidth(double lineHeight) {
    final double targetH = lineHeight * 0.74;
    return (targetH * aspectRatio).clamp(lineHeight * 0.14, lineHeight * 8.0);
  }

  /// Tính khoảng cách đệm phía trước cụm nét (px) trên dòng
  double getLeadingGap(double lineHeight, {bool isFirstOnLine = false}) {
    if (isFirstOnLine) return 0.0;
    return leadingSpace ? lineHeight * 0.28 : lineHeight * 0.08;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'a': double.parse(aspectRatio.toStringAsFixed(3)),
      if (leadingSpace) 's': true,
      if (colorValue != 0xFF1A237E) 'c': colorValue,
      if ((strokeWidth - 2.6).abs() > 0.05)
        'w': double.parse(strokeWidth.toStringAsFixed(2)),
      if (penStyle != PenStrokeStyle.ballpoint) 'st': penStyle,
      'p': strokes
          .map(
            (InkStrokeModel stroke) => stroke.points
                .map(
                  (StrokePointModel pt) => <double>[
                    double.parse(pt.nx.toStringAsFixed(3)),
                    double.parse(pt.ry.toStringAsFixed(3)),
                  ],
                )
                .toList(),
          )
          .toList(),
    };
  }

  factory HandwritingClusterModel.fromJson(Map<String, dynamic> json) {
    final double aspect = (json['a'] as num?)?.toDouble() ?? 0.5;
    final bool space = (json['s'] as bool?) ?? false;
    final int colorVal = (json['c'] as num?)?.toInt() ?? 0xFF1A237E;
    final double widthVal = (json['w'] as num?)?.toDouble() ?? 2.6;
    final String styleVal =
        (json['st'] as String?) ?? PenStrokeStyle.ballpoint;
    final List<dynamic> rawStrokes =
        (json['p'] as List<dynamic>?) ?? <dynamic>[];

    final List<InkStrokeModel> parsedStrokes = <InkStrokeModel>[];
    for (final dynamic s in rawStrokes) {
      if (s is List<dynamic>) {
        final List<StrokePointModel> pts = <StrokePointModel>[];
        for (final dynamic pt in s) {
          if (pt is List<dynamic> && pt.length >= 2) {
            final double u = (pt[0] as num?)?.toDouble() ?? 0.0;
            final double v = (pt[1] as num?)?.toDouble() ?? 0.0;
            pts.add(
              StrokePointModel(
                nx: u.clamp(0.0, 1.0),
                ry: v.clamp(0.0, 1.0),
              ),
            );
          }
        }
        if (pts.isNotEmpty) {
          parsedStrokes.add(
            InkStrokeModel(
              points: pts,
              colorValue: colorVal,
              strokeWidth: widthVal,
              penStyle: styleVal,
            ),
          );
        }
      }
    }

    return HandwritingClusterModel(
      aspectRatio: aspect.clamp(0.12, 10.0),
      leadingSpace: space,
      strokes: parsedStrokes,
      colorValue: colorVal,
      strokeWidth: widthVal.clamp(1.0, 10.0),
      penStyle: styleVal,
    );
  }
}

// ===========================================================================
// MÔ HÌNH NÉT VẼ TỰ DO TRỰC TIẾP TRÊN TRANG VỞ Ô LY (DÙNG CHO GHI CHÚ)
// ===========================================================================
class FreehandPageStrokeModel {
  /// Tọa độ các điểm của nét vẽ:
  /// - nx (x): Tỷ lệ ngang trên trang giấy (x / paperWidth, từ 0.0 -> 1.0)
  /// - ry (y): Vị trí dọc tính theo đơn vị dòng (y / rowHeight, ví dụ dòng 2.5)
  final List<StrokePointModel> points;

  /// Màu mực của nét vẽ (ARGB int)
  final int colorValue;

  /// Độ dày nét vẽ (px)
  final double strokeWidth;

  /// Kiểu nét vẽ (`ballpoint`, `fountain`, `marker`, `highlighter`, `dashed`)
  final String penStyle;

  const FreehandPageStrokeModel({
    required this.points,
    this.colorValue = 0xFF263BAA,
    this.strokeWidth = 2.6,
    this.penStyle = PenStrokeStyle.ballpoint,
  });

  /// Chuyển từ nét vẽ thực tế trên Canvas sang nét vẽ chuẩn hóa lưu vào RAM/JSON
  static FreehandPageStrokeModel? fromInkStroke(
    InkStrokeModel stroke, {
    required double paperWidth,
    required double rowHeight,
  }) {
    if (stroke.points.isEmpty || paperWidth <= 0 || rowHeight <= 0) {
      return null;
    }

    final List<StrokePointModel> normPts = <StrokePointModel>[];
    StrokePointModel? lastKept;

    for (int i = 0; i < stroke.points.length; i++) {
      final StrokePointModel pt = stroke.points[i];
      if (lastKept != null && i < stroke.points.length - 1) {
        final double dx = pt.x - lastKept.x;
        final double dy = pt.y - lastKept.y;
        if ((dx * dx + dy * dy) < 1.2) {
          continue;
        }
      }
      lastKept = pt;
      final double nx = (pt.x / paperWidth).clamp(0.0, 1.0);
      final double ry = math.max(0.0, pt.y / rowHeight);
      normPts.add(StrokePointModel(nx: nx, ry: ry));
    }

    if (normPts.isEmpty) return null;
    return FreehandPageStrokeModel(
      points: normPts,
      colorValue: stroke.colorValue,
      strokeWidth: stroke.strokeWidth,
      penStyle: stroke.penStyle,
    );
  }

  /// Dựng đường cong `Path` mượt trên kích thước trang giấy thực tế (`paperWidth`, `rowHeight`)
  Path buildScaledPath({
    required double paperWidth,
    required double rowHeight,
  }) {
    final Path path = Path();
    if (points.isEmpty) return path;

    final double x0 = points.first.nx * paperWidth;
    final double y0 = points.first.ry * rowHeight;
    path.moveTo(x0, y0);

    if (points.length == 1) {
      path.lineTo(x0 + 0.1, y0 + 0.1);
      return path;
    }

    for (int i = 1; i < points.length; i++) {
      final double prevX = points[i - 1].nx * paperWidth;
      final double prevY = points[i - 1].ry * rowHeight;
      final double currX = points[i].nx * paperWidth;
      final double currY = points[i].ry * rowHeight;
      final double midX = (prevX + currX) * 0.5;
      final double midY = (prevY + currY) * 0.5;
      if (i == 1) {
        path.lineTo(midX, midY);
      } else {
        path.quadraticBezierTo(prevX, prevY, midX, midY);
      }
    }

    final StrokePointModel last = points.last;
    path.lineTo(last.nx * paperWidth, last.ry * rowHeight);
    return path;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (colorValue != 0xFF263BAA) 'c': colorValue,
      if ((strokeWidth - 2.6).abs() > 0.05)
        'w': double.parse(strokeWidth.toStringAsFixed(2)),
      if (penStyle != PenStrokeStyle.ballpoint) 'st': penStyle,
      'pts': points
          .map(
            (StrokePointModel pt) => <double>[
              double.parse(pt.nx.toStringAsFixed(4)),
              double.parse(pt.ry.toStringAsFixed(4)),
            ],
          )
          .toList(),
    };
  }

  factory FreehandPageStrokeModel.fromJson(Map<String, dynamic> json) {
    final int colorVal = (json['c'] as num?)?.toInt() ?? 0xFF263BAA;
    final double widthVal = (json['w'] as num?)?.toDouble() ?? 2.6;
    final String styleVal =
        (json['st'] as String?) ?? PenStrokeStyle.ballpoint;
    final List<dynamic> rawPts =
        (json['pts'] as List<dynamic>?) ?? <dynamic>[];
    final List<StrokePointModel> parsed = <StrokePointModel>[];
    for (final dynamic p in rawPts) {
      if (p is List<dynamic> && p.length >= 2) {
        final double nx = (p[0] as num?)?.toDouble() ?? 0.0;
        final double ry = (p[1] as num?)?.toDouble() ?? 0.0;
        parsed.add(
          StrokePointModel(
            nx: nx.clamp(0.0, 1.0),
            ry: math.max(0.0, ry),
          ),
        );
      }
    }
    return FreehandPageStrokeModel(
      points: parsed,
      colorValue: colorVal,
      strokeWidth: widthVal.clamp(1.0, 10.0),
      penStyle: styleVal,
    );
  }
}
