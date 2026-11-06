import 'line_model.dart';
import 'stroke_point_model.dart';

// ===========================================================================
// MODEL DỮ LIỆU MỘT TRANG GIẤY TRONG FILE GHI CHÚ / SỔ DỰ GIỜ (PAGE MODEL)
// Công dụng:
// - Quản lý số thứ tự trang (pageNumber), danh sách các dòng có nội dung (lines)
//   và danh sách các nét bút vẽ tự do trực tiếp trên trang vở (freehandStrokes).
// - Chỉ những dòng/nét có nội dung mới lưu vào JSON trên RAM & Google Drive.
// ===========================================================================
class PageModel {
  final int pageNumber;
  final List<LineModel> lines;
  final List<FreehandPageStrokeModel> freehandStrokes;

  const PageModel({
    required this.pageNumber,
    required this.lines,
    this.freehandStrokes = const <FreehandPageStrokeModel>[],
  });

  /// Tạo bản sao PageModel với danh sách dòng / nét vẽ mới
  PageModel copyWith({
    int? pageNumber,
    List<LineModel>? lines,
    List<FreehandPageStrokeModel>? freehandStrokes,
  }) {
    return PageModel(
      pageNumber: pageNumber ?? this.pageNumber,
      lines: lines ?? this.lines,
      freehandStrokes: freehandStrokes ?? this.freehandStrokes,
    );
  }

  /// Chuyển đổi trang giấy sang Map JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pageNumber': pageNumber,
      'lines': lines.map((line) => line.toJson()).toList(),
      if (freehandStrokes.isNotEmpty)
        'freehandStrokes':
            freehandStrokes.map((s) => s.toJson()).toList(),
    };
  }

  /// Khởi tạo PageModel từ Map JSON
  factory PageModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawLines =
        (json['lines'] as List<dynamic>?) ?? <dynamic>[];
    final List<dynamic> rawFreehand =
        (json['freehandStrokes'] as List<dynamic>?) ?? <dynamic>[];
    return PageModel(
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 1,
      lines: rawLines
          .whereType<Map<String, dynamic>>()
          .map(LineModel.fromJson)
          .toList(),
      freehandStrokes: rawFreehand
          .whereType<Map<String, dynamic>>()
          .map(FreehandPageStrokeModel.fromJson)
          .toList(),
    );
  }
}
