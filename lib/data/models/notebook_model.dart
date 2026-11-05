import '../../core/constants/note4x.dart';
import '../../core/constants/note5x.dart';
import 'page_model.dart';

// ===========================================================================
// MODEL DỮ LIỆU TỔNG THỂ CỦA MỘT FILE GHI CHÚ JSON (NOTEBOOK MODEL)
// Công dụng:
// - Đại diện cho cấu trúc file .json lưu trên Google Drive và bộ nhớ RAM.
// - Chứa thông tin định danh (id), tên file (title), loại mẫu giấy đã chọn
//   ('note5x' cho vở 5 ô ly hoặc 'note4x' cho vở 4 ô ly), thời gian cập nhật,
//   và danh sách các trang giấy kèm dữ liệu từng dòng.
// ===========================================================================
class NotebookModel {
  final String id;
  final String title;
  final String paperTemplate;
  final String updatedAt;
  final List<PageModel> pages;

  const NotebookModel({
    required this.id,
    required this.title,
    required this.paperTemplate,
    required this.updatedAt,
    required this.pages,
  });

  /// Kiểm tra xem file ghi chú này có đang dùng mẫu vở 4 ô ly (note4x) hay không
  bool get isNote4x => paperTemplate == Note4x.templateId;

  /// Tạo mới một cấu trúc NotebookModel rỗng khi người dùng vừa tạo file mới
  factory NotebookModel.createInitial({
    required String id,
    required String title,
    required String paperTemplate,
  }) {
    return NotebookModel(
      id: id,
      title: title,
      paperTemplate: paperTemplate.isEmpty ? Note5x.templateId : paperTemplate,
      updatedAt: DateTime.now().toIso8601String(),
      pages: const <PageModel>[
        PageModel(pageNumber: 1, lines: <Never>[]),
      ],
    );
  }

  /// Tạo bản sao NotebookModel khi cập nhật nội dung dòng hoặc tiêu đề
  NotebookModel copyWith({
    String? id,
    String? title,
    String? paperTemplate,
    String? updatedAt,
    List<PageModel>? pages,
  }) {
    return NotebookModel(
      id: id ?? this.id,
      title: title ?? this.title,
      paperTemplate: paperTemplate ?? this.paperTemplate,
      updatedAt: updatedAt ?? this.updatedAt,
      pages: pages ?? this.pages,
    );
  }

  /// Chuyển đổi toàn bộ cuốn vở sang Map JSON để gửi lên Google Drive
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'paperTemplate': paperTemplate,
      'updatedAt': updatedAt,
      'pages': pages.map((page) => page.toJson()).toList(),
    };
  }

  /// Đọc dữ liệu Map JSON từ Google Drive hoặc RAM để dựng lại giao diện
  factory NotebookModel.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawPages = (json['pages'] as List<dynamic>?) ?? <dynamic>[];
    final List<PageModel> parsedPages = rawPages
        .whereType<Map<String, dynamic>>()
        .map(PageModel.fromJson)
        .toList();

    return NotebookModel(
      id: (json['id'] as String?) ??
          'note_${DateTime.now().millisecondsSinceEpoch}',
      title: (json['title'] as String?) ?? 'Ghi chú không tên',
      paperTemplate: (json['paperTemplate'] as String?) ?? Note5x.templateId,
      updatedAt:
          (json['updatedAt'] as String?) ?? DateTime.now().toIso8601String(),
      pages: parsedPages.isEmpty
          ? const <PageModel>[PageModel(pageNumber: 1, lines: <Never>[])]
          : parsedPages,
    );
  }
}
