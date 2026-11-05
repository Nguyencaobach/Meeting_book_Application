import 'line_model.dart';

// ===========================================================================
// MODEL DỮ LIỆU MỘT TRANG GIẤY TRONG FILE GHI CHÚ (PAGE MODEL)
// Công dụng:
// - Quản lý số thứ tự trang (pageNumber) và danh sách các dòng có chữ (lines).
// - Chỉ những dòng có nội dung mới cần lưu vào mảng JSON để tối ưu dung lượng,
//   khi render lên giao diện sẽ đặt đúng vào vị trí rowIndex tương ứng.
// ===========================================================================
class PageModel {
  final int pageNumber;
  final List<LineModel> lines;

  const PageModel({
    required this.pageNumber,
    required this.lines,
  });

  /// Tạo bản sao PageModel với danh sách dòng mới
  PageModel copyWith({
    int? pageNumber,
    List<LineModel>? lines,
  }) {
    return PageModel(
      pageNumber: pageNumber ?? this.pageNumber,
      lines: lines ?? this.lines,
    );
  }

  /// Chuyển đổi trang giấy sang Map JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pageNumber': pageNumber,
      'lines': lines.map((line) => line.toJson()).toList(),
    };
  }

  /// Khởi tạo PageModel từ Map JSON
  factory PageModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawLines = (json['lines'] as List<dynamic>?) ?? <dynamic>[];
    return PageModel(
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 1,
      lines: rawLines
          .whereType<Map<String, dynamic>>()
          .map(LineModel.fromJson)
          .toList(),
    );
  }
}
