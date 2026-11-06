import 'stroke_point_model.dart';

// ===========================================================================
// MODEL DỮ LIỆU TỪNG DÒNG VIẾT TRÊN TRANG GIẤY / Ô BIỂU MẪU (LINE MODEL)
// Công dụng:
// - Lưu trữ chỉ số dòng (rowIndex: dòng thứ mấy tính từ 0), nội dung chữ bàn phím (text)
//   và danh sách các cụm nét chữ viết tay đã chuẩn hóa (handwritingClusters).
// - Hỗ trợ chuyển đổi qua lại sang JSON để lưu lên Google Drive và đọc lại để render.
// ===========================================================================
class LineModel {
  final int rowIndex;
  final String text;
  final int? textColorValue;
  final List<HandwritingClusterModel> handwritingClusters;

  const LineModel({
    required this.rowIndex,
    required this.text,
    this.textColorValue,
    this.handwritingClusters = const <HandwritingClusterModel>[],
  });

  /// Tạo bản sao LineModel với nội dung mới
  LineModel copyWith({
    int? rowIndex,
    String? text,
    int? textColorValue,
    List<HandwritingClusterModel>? handwritingClusters,
  }) {
    return LineModel(
      rowIndex: rowIndex ?? this.rowIndex,
      text: text ?? this.text,
      textColorValue: textColorValue ?? this.textColorValue,
      handwritingClusters: handwritingClusters ?? this.handwritingClusters,
    );
  }

  /// Chuyển đổi dữ liệu dòng sang Map JSON
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'rowIndex': rowIndex,
      'text': text,
      if (textColorValue != null) 'color': textColorValue,
      if (handwritingClusters.isNotEmpty)
        'clusters':
            handwritingClusters.map((c) => c.toJson()).toList(),
    };
  }

  /// Khởi tạo LineModel từ Map JSON tải về từ Google Drive hoặc RAM
  factory LineModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawClusters =
        (json['clusters'] as List<dynamic>?) ?? <dynamic>[];
    return LineModel(
      rowIndex: (json['rowIndex'] as num?)?.toInt() ?? 0,
      text: (json['text'] as String?) ?? '',
      textColorValue: (json['color'] as num?)?.toInt(),
      handwritingClusters: rawClusters
          .whereType<Map<String, dynamic>>()
          .map(HandwritingClusterModel.fromJson)
          .toList(),
    );
  }
}
