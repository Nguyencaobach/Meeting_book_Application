import 'package:flutter/material.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../../widgets/drive_folder_section_widget.dart';

/// Giao diện màn hình Ghi chú (Hiển thị các thư mục trong MeetingBook/Ghi_Chu từ Google Drive)
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final driveDatasource = GoogleDriveDatasource.instance;

    return DriveFolderSectionWidget(
      foldersListenable: driveDatasource.notesFoldersNotifier,
      onRefresh: () => driveDatasource.refreshAllTabFolders(),
      emptyMessage:
          'Chưa có thư mục hay ghi chú nào.\nBấm nút (+) góc dưới bên phải để tạo mới.',
      onFolderTap: (folder) {
        // Xử lý mở thư mục con sau này
      },
    );
  }
}
