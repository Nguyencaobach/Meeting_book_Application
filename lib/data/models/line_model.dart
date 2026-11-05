// ===========================================================================
// MODEL DỮ LIỆU TỪNG DÒNG VIẾT TRÊN TRANG GIẤY (LINE MODEL)
// Công dụng:
// - Lưu trữ chỉ số dòng (rowIndex: dòng thứ mấy tính từ 0) và nội dung chữ (text)
//   trên dòng kẻ ngang tương ứng của trang vở note5x hoặc note4x.
// - Hỗ trợ chuyển đổi qua lại sang JSON để lưu lên Google Drive và đọc lại để render.
// ===========================================================================
class LineModel {
  final int rowIndex;
  final String text;

  const LineModel({
    required this.rowIndex,
    required this.text,
  });

  /// Tạo bản sao LineModel với nội dung mới
  LineModel copyWith({
    int? rowIndex,
    String? text,
  }) {
    return LineModel(
      rowIndex: rowIndex ?? this.rowIndex,
      text: text ?? this.text,
    );
  }

  /// Chuyển đổi dữ liệu dòng sang Map JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'rowIndex': rowIndex,
      'text': text,
    };
  }

  /// Khởi tạo LineModel từ Map JSON tải về từ Google Drive hoặc RAM
  factory LineModel.fromJson(Map<String, dynamic> json) {
    return LineModel(
      rowIndex: (json['rowIndex'] as num?)?.toInt() ?? 0,
      text: (json['text'] as String?) ?? '',
    );
  }
}
