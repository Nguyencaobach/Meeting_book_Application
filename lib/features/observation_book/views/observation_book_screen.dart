import 'package:flutter/material.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../../widgets/drive_folder_section_widget.dart';

/// Giao diện màn hình Sổ dự giờ (Hiển thị các thư mục trong MeetingBook/So_Du_Gio từ Google Drive)
class ObservationBookScreen extends StatelessWidget {
  const ObservationBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final driveDatasource = GoogleDriveDatasource.instance;

    return DriveFolderSectionWidget(
      foldersListenable: driveDatasource.observationFoldersNotifier,
      onRefresh: () => driveDatasource.refreshAllTabFolders(),
      emptyMessage:
          'Chưa có thư mục hay sổ dự giờ nào.\nBấm nút (+) góc dưới bên phải để tạo mới.',
      onFolderTap: (folder) {
        // Xử lý mở thư mục con sau này
      },
    );
  }
}
