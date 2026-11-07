import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Mô hình dữ liệu một mục trong tài liệu Hướng dẫn sử dụng
class UserGuideSectionData {
  final String numberLabel;
  final String title;
  final String summary;
  final List<UserGuideItemData> items;

  const UserGuideSectionData({
    required this.numberLabel,
    required this.title,
    required this.summary,
    required this.items,
  });
}

/// Mô hình một ý hướng dẫn ngắn gọn trong từng phần
class UserGuideItemData {
  final String heading;
  final List<String> points;

  const UserGuideItemData({
    required this.heading,
    required this.points,
  });
}

/// Màn hình Hướng dẫn sử dụng ứng dụng
/// Thiết kế tối giản, trang nhã, không dùng icon rườm rà, tập trung vào văn bản
/// ngắn gọn, rõ ràng, dễ đọc và tự động co giãn theo mọi kích thước màn hình.
class UserGuideScreen extends StatefulWidget {
  const UserGuideScreen({super.key});

  /// Nội dung tài liệu Hướng dẫn sử dụng đã được biên tập ngắn gọn, dễ đọc
  static const List<UserGuideSectionData> sections = [
    UserGuideSectionData(
      numberLabel: 'Phần 1',
      title: 'Đăng nhập và liên kết Google Drive',
      summary:
          'Ứng dụng lưu trữ toàn bộ tài liệu trực tiếp trên Google Drive cá nhân của bạn, giúp bảo mật dữ liệu và không làm đầy bộ nhớ máy.',
      items: [
        UserGuideItemData(
          heading: '1. Đăng nhập lần đầu',
          points: [
            'Bấm nút "Kết nối tài khoản Google" ở màn hình đăng nhập và chọn tài khoản Gmail của bạn.',
            'Tích chọn ô cấp quyền truy cập Google Drive và bấm Tiếp tục (Continue).',
            'Từ lần mở ứng dụng tiếp theo, hệ thống tự động đăng nhập thẳng vào màn hình chính.',
          ],
        ),
        UserGuideItemData(
          heading: '2. Thư mục tự động tạo trên Google Drive',
          points: [
            'MeetingBook/Ghi_Chu: Lưu các thư mục và tệp của tab Ghi chú.',
            'MeetingBook/So_Du_Gio: Lưu các thư mục và tệp của tab Sổ dự giờ.',
            'MeetingBook/Export File: Lưu các tệp PDF (.pdf) và Word (.doc) khi bạn xuất tài liệu.',
          ],
        ),
        UserGuideItemData(
          heading: '3. Xem tài khoản và Đăng xuất',
          points: [
            'Bấm vào nút tròn góc bên phải thanh tìm kiếm để xem tên, địa chỉ Gmail đang dùng hoặc bấm "Đăng xuất" khi muốn đổi tài khoản.',
          ],
        ),
      ],
    ),
    UserGuideSectionData(
      numberLabel: 'Phần 2',
      title: 'Quản lý thư mục, tệp và tìm kiếm ở màn hình chính',
      summary:
          'Màn hình chính gồm 2 tab độc lập: "Ghi chú" và "Sổ dự giờ" để bạn phân loại và tra cứu tài liệu nhanh chóng.',
      items: [
        UserGuideItemData(
          heading: '1. Thanh tìm kiếm nhanh',
          points: [
            'Nhập tên thư mục hoặc tên tệp vào ô tìm kiếm (hỗ trợ gõ Tiếng Việt có dấu hoặc không dấu).',
            'Hệ thống tự động tìm xuyên suốt cả các tệp nằm bên trong thư mục con và hiển thị dòng chú thích "Trong: <Tên thư mục>".',
            'Bấm nút "X" bên phải ô tìm kiếm để xóa nhanh từ khóa.',
          ],
        ),
        UserGuideItemData(
          heading: '2. Tạo mới thư mục và tệp tài liệu (Nút dấu + góc dưới phải)',
          points: [
            'Thư mục mới: Tạo thư mục phân loại tài liệu (hỗ trợ tạo nhiều cấp thư mục con bên trong thư mục cha, tự động báo nếu trùng tên).',
            'Tệp ghi chú mới (Tab Ghi chú): Đặt tên tệp và chọn Mẫu vở 5 ô ly hoặc Mẫu vở 4 ô ly.',
            'Tệp sổ dự giờ mới (Tab Sổ dự giờ): Đặt tên tệp và chọn biểu mẫu Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học (3 trang).',
          ],
        ),
        UserGuideItemData(
          heading: '3. Đổi tên, Di chuyển và Xóa (Nút chữ "i" trên mỗi mục)',
          points: [
            'Đổi tên: Đặt lại tên mới cho thư mục hoặc tệp (tự động kiểm tra chống trùng tên).',
            'Di chuyển: Chọn thư mục đích trực tiếp trên sơ đồ cây thư mục để chuyển vị trí.',
            'Xóa: Đưa thư mục hoặc tệp vào thùng rác Google Drive.',
            'Hoàn tác: Ngay sau khi Xóa hoặc Di chuyển, bạn có thể bấm nút "Hoàn tác" trên hộp thông báo nếu thao tác nhầm.',
          ],
        ),
      ],
    ),
    UserGuideSectionData(
      numberLabel: 'Phần 3',
      title: 'Soạn thảo Vở Ghi chú (Vở 5 ô ly và 4 ô ly)',
      summary:
          'Trang vở được kẻ ô ly chuẩn, hỗ trợ phóng to thu nhỏ và chuyển đổi linh hoạt giữa gõ bàn phím hoặc viết bút.',
      items: [
        UserGuideItemData(
          heading: '1. Phóng to, thu nhỏ và trượt trang vở',
          points: [
            'Bấm nút "-" hoặc "+" trên thanh tiêu đề để thu phóng mặt giấy từ 100% đến 220%.',
            'Khi phóng to, bạn có thể kéo trượt trang giấy hoặc dùng thanh cuộn ngang ở đáy màn hình.',
          ],
        ),
        UserGuideItemData(
          heading: '2. Các chế độ trong menu soạn thảo',
          points: [
            'Bàn phím: Chạm vào dòng kẻ để đặt con trỏ "|" và gõ chữ (hỗ trợ gõ Tiếng Việt kiểu Telex, tự động xuống dòng và nối dòng như Word, kéo nút giọt nước dưới con trỏ để di chuyển vị trí chữ).',
            'Viết bút: Hiển thị Bong bóng công cụ bút viết nổi trên màn hình.',
            'Chỉ xem: Khóa chỉnh sửa để đọc và cuộn trang an toàn, tránh chạm nhầm làm lệch nội dung.',
            'Làm mới: Tải lại dữ liệu mới nhất của tệp từ Google Drive.',
            'Làm sạch: Xóa toàn bộ nội dung trên trang hiện tại (có nút Hoàn tác để khôi phục ngay).',
          ],
        ),
      ],
    ),
    UserGuideSectionData(
      numberLabel: 'Phần 4',
      title: 'Bong bóng công cụ Bút viết và Thước kẻ',
      summary:
          'Dùng chung cho cả tab Ghi chú và Sổ dự giờ. Bạn có thể kéo bong bóng đến bất kỳ vị trí nào thuận tay trên màn hình.',
      items: [
        UserGuideItemData(
          heading: '1. Mở và đóng bảng công cụ bút',
          points: [
            'Bấm vào bong bóng tròn để mở bảng công cụ bút viết.',
            'Bảng công cụ chỉ đóng khi bạn bấm nút "X" ở góc phải tiêu đề, giúp bạn thuận tiện bấm Hoàn tác nhiều lần hoặc đổi màu, đổi nét liên tục.',
          ],
        ),
        UserGuideItemData(
          heading: '2. Màu chữ, Nét chữ và Độ dày nét',
          points: [
            'Màu chữ: Chọn nhanh 6 màu mực (Xanh mực, Đen, Đỏ, Xanh lá, Tím, Cam đậm).',
            'Nét chữ: Bấm vào để chọn 1 trong 5 kiểu bút (Bút bi, Bút máy thanh đậm, Bút lông, Bút dạ quang tô sáng, Nét đứt) và chỉnh độ dày nét từ Mảnh đến Rất đậm.',
          ],
        ),
        UserGuideItemData(
          heading: '3. Chế độ Nét viết tự nhiên và Nét đánh máy',
          points: [
            'Nét viết tự nhiên: Dùng 1 ngón tay hoặc bút cảm ứng viết/vẽ trực tiếp lên mặt giấy; dùng 2 ngón tay để cuộn trang lên xuống.',
            'Nét đánh máy: Chạm chọn dòng trên giấy để mở bảng viết tay ở nửa dưới màn hình. Khi bạn viết chữ Tiếng Việt vào bảng và dừng tay một nhịp ngắn, ứng dụng tự động nhận diện và chuyển thành chữ đánh máy điền thẳng lên dòng đang chọn.',
          ],
        ),
        UserGuideItemData(
          heading: '4. Cục tẩy, Hoàn tác và Cây thước kẻ',
          points: [
            'Nút tẩy: Chạm hoặc kéo qua nét vẽ trên giấy để xóa nét đó.',
            'Hoàn tác: Quay lại từng nét vẽ hoặc chữ vừa viết trước đó.',
            'Cây thước kẻ: Bật thước kẻ trên mặt giấy, giữ thân thước để kéo di chuyển, giữ 2 đầu thước để xoay góc (hoặc bấm Xoay 90° / Về 0°). Khi kéo bút dọc gần mép thước, nét vẽ sẽ tự động bám thẳng theo cạnh thước.',
          ],
        ),
      ],
    ),
    UserGuideSectionData(
      numberLabel: 'Phần 5',
      title: 'Sử dụng biểu mẫu Sổ dự giờ (3 trang)',
      summary:
          'Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học gồm 3 trang liên tiếp, hỗ trợ tự động cộng tổng điểm và gợi ý xếp loại tiết dạy.',
      items: [
        UserGuideItemData(
          heading: '1. Trang 1: Thông tin chung và Bảng tiến trình tiết dạy',
          points: [
            'Điền thông tin: Họ tên người dạy, Lớp, Trường, Bài dạy, Môn.',
            'Ghi chép vào bảng 3 cột: Nội dung các hoạt động | Biểu hiện của học sinh | Nguyên nhân - Biện pháp.',
          ],
        ),
        UserGuideItemData(
          heading: '2. Trang 2: Nhận xét chung và Bảng chấm điểm 12 tiêu chí',
          points: [
            'Ghi nhận xét, đánh giá chung về tiết dạy.',
            'Nhập điểm vào cột Điểm của 12 tiêu chí (từ 1.1 đến 3.4). Hệ thống tự động chặn nếu nhập vượt điểm tối đa của tiêu chí và tự động cộng Tổng điểm (trên thang 20,0).',
          ],
        ),
        UserGuideItemData(
          heading: '3. Trang 3: Tự động xếp loại và Ký tên người dự giờ',
          points: [
            'Dựa vào điểm số ở Trang 2, ứng dụng tự động đối chiếu quy chuẩn và hiện nút gợi ý xếp loại (Giỏi, Khá, Trung bình, Chưa đạt). Bấm vào nút "Điền: <Loại>" để điền nhanh kết quả.',
            'Điền ngày tháng năm, chuyển sang chế độ Viết bút (Nét viết tự nhiên) để ký tên trực tiếp vào khoảng trống dưới mục "Người dự giờ (Ký, ghi rõ họ tên)", sau đó ghi rõ họ tên ở dòng dưới cùng.',
          ],
        ),
      ],
    ),
    UserGuideSectionData(
      numberLabel: 'Phần 6',
      title: 'Tự động lưu và Bảo vệ dữ liệu khi mất mạng',
      summary:
          'Mọi thao tác viết và gõ chữ đều được lưu tức thời trên bộ nhớ RAM và đồng bộ tự động lên Google Drive.',
      items: [
        UserGuideItemData(
          heading: '1. Tự động lưu lên Google Drive ở 3 thời điểm',
          points: [
            'Sau 30 giây kể từ khi bạn ngừng viết hoặc gõ chữ.',
            'Ngay khi bạn bấm nút "Quay lại" để đóng trang vở.',
            'Ngay khi bạn ẩn ứng dụng hoặc tắt màn hình thiết bị.',
            'Ngoài ra, bạn có thể bấm nút "Lưu" trên thanh công cụ bất cứ lúc nào.',
          ],
        ),
        UserGuideItemData(
          heading: '2. Bảo vệ dữ liệu khi mất kết nối mạng',
          points: [
            'Nếu mất Wi-Fi / 4G khi đang viết, toàn bộ nội dung vừa viết vẫn được giữ nguyên trên RAM và ứng dụng tạm khóa màn hình để bảo vệ bài viết.',
            'Ngay khi có mạng trở lại, ứng dụng tự động mở khóa và đồng bộ toàn bộ dữ liệu lên Google Drive.',
          ],
        ),
      ],
    ),
    UserGuideSectionData(
      numberLabel: 'Phần 7',
      title: 'Xuất tệp PDF (.pdf) và Word (.doc)',
      summary:
          'Xuất tài liệu ra định dạng chuẩn A4 để in ấn hoặc chia sẻ, giữ nguyên bố cục dòng kẻ, màu mực, nét vẽ và chữ ký.',
      items: [
        UserGuideItemData(
          heading: '1. Cách xuất tệp',
          points: [
            'Trong màn hình soạn thảo Ghi chú hoặc Sổ dự giờ, bấm nút "Xuất file" ở góc trên bên phải.',
            'Chọn "Xuất file PDF" hoặc "Xuất file Word".',
          ],
        ),
        UserGuideItemData(
          heading: '2. Vị trí lưu tệp sau khi xuất',
          points: [
            'Tệp xuất ra giữ nguyên 100% nội dung đánh máy, nét vẽ tay, chữ ký người dự giờ (hoặc tự động chừa khoảng trống ký tên nếu để trống).',
            'Tệp được lưu trực tiếp lên Google Drive của bạn tại thư mục: MeetingBook/Export File/Ghi chú hoặc MeetingBook/Export File/Sổ dự giờ.',
          ],
        ),
      ],
    ),
  ];

  @override
  State<UserGuideScreen> createState() => _UserGuideScreenState();
}

class _UserGuideScreenState extends State<UserGuideScreen> {
  /// -1: Xem tất cả các phần; >= 0: Chỉ xem phần được chọn
  int _selectedSectionIndex = -1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double titleFontSize = AppTheme.getResponsiveFontSize(context, 17);
    final double filterFontSize = AppTheme.getResponsiveFontSize(context, 13);
    final double sectionBadgeFontSize =
        AppTheme.getResponsiveFontSize(context, 12.5);
    final double sectionTitleFontSize =
        AppTheme.getResponsiveFontSize(context, 16.5);
    final double summaryFontSize =
        AppTheme.getResponsiveFontSize(context, 14);
    final double itemHeadingFontSize =
        AppTheme.getResponsiveFontSize(context, 14.5);
    final double bodyFontSize = AppTheme.getResponsiveFontSize(context, 14);

    final List<UserGuideSectionData> displayedSections =
        _selectedSectionIndex < 0
            ? UserGuideScreen.sections
            : [UserGuideScreen.sections[_selectedSectionIndex]];

    return Scaffold(
      backgroundColor: AppColors.basicWhite,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double horizontalPadding =
              (constraints.maxWidth * 0.04).clamp(14.0, 36.0);
          final double maxContentWidth =
              (constraints.maxWidth * 0.92).clamp(320.0, 960.0);

          return Column(
            children: [
              // 1. Thanh tiêu đề đơn giản, đồng bộ màu xanh chủ đạo (#263BAA)
              Container(
                width: double.infinity,
                color: theme.colorScheme.primary,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.basicWhite.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.creamBackground
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              'Quay lại',
                              style: TextStyle(
                                color: AppColors.basicWhite,
                                fontSize: filterFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Hướng dẫn sử dụng',
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

              // 2. Thanh chọn mục lục nhanh (chỉ dùng chữ gọn gàng, không icon)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.creamSurface,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _buildSectionFilterChip(
                        label: 'Tất cả (${UserGuideScreen.sections.length} phần)',
                        isSelected: _selectedSectionIndex == -1,
                        fontSize: filterFontSize,
                        onTap: () {
                          setState(() {
                            _selectedSectionIndex = -1;
                          });
                        },
                      ),
                      for (int i = 0;
                          i < UserGuideScreen.sections.length;
                          i++) ...[
                        const SizedBox(width: 8),
                        _buildSectionFilterChip(
                          label:
                              '${UserGuideScreen.sections[i].numberLabel}: ${UserGuideScreen.sections[i].title}',
                          isSelected: _selectedSectionIndex == i,
                          fontSize: filterFontSize,
                          onTap: () {
                            setState(() {
                              _selectedSectionIndex = i;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // 3. Nội dung văn bản hướng dẫn sử dụng trình bày thoáng, rõ ràng, dễ đọc
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth),
                    child: ListView.separated(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 20,
                      ),
                      itemCount: displayedSections.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 18),
                      itemBuilder: (context, index) {
                        final section = displayedSections[index];
                        return _buildSectionCard(
                          section: section,
                          sectionBadgeFontSize: sectionBadgeFontSize,
                          sectionTitleFontSize: sectionTitleFontSize,
                          summaryFontSize: summaryFontSize,
                          itemHeadingFontSize: itemHeadingFontSize,
                          bodyFontSize: bodyFontSize,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Nút chọn nhanh từng phần hướng dẫn (thiết kế phẳng, chỉ văn bản, không icon)
  Widget _buildSectionFilterChip({
    required String label,
    required bool isSelected,
    required double fontSize,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : AppColors.basicWhite,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlue
                : AppColors.primaryBlue.withValues(alpha: 0.22),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.basicWhite : AppColors.basicBlack,
            fontSize: fontSize,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Khung trình bày từng phần hướng dẫn (Nền trắng, viền mảnh, chữ đen dễ đọc)
  Widget _buildSectionCard({
    required UserGuideSectionData section,
    required double sectionBadgeFontSize,
    required double sectionTitleFontSize,
    required double summaryFontSize,
    required double itemHeadingFontSize,
    required double bodyFontSize,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.basicWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tiêu đề phần
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.creamBackground,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    section.numberLabel.toUpperCase(),
                    style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontSize: sectionBadgeFontSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  section.title,
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: sectionTitleFontSize,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  section.summary,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: summaryFontSize,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Danh sách các mục con trong phần
          for (int i = 0; i < section.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Text(
              section.items[i].heading,
              style: TextStyle(
                color: AppColors.basicBlack,
                fontSize: itemHeadingFontSize,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            for (final String point in section.items[i].points)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•  ',
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontSize: bodyFontSize,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        point,
                        style: TextStyle(
                          color: AppColors.basicBlack,
                          fontSize: bodyFontSize,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
