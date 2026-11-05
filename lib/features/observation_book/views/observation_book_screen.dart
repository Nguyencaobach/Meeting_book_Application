import 'package:flutter/material.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../../widgets/drive_folder_section_widget.dart';
import '../../notes/views/note_editor_screen.dart';

// ===========================================================================
// GIAO DIỆN MÀN HÌNH TAB SỔ DỰ GIỜ (OBSERVATION BOOK SCREEN)
// Công dụng:
// - Hiển thị danh sách các Thư mục và Tệp sổ dự giờ (.json) ở ngoài màn hình chính
//   (MeetingBook/So_Du_Gio) hoặc bên trong thư mục đã chọn.
// - Khi người dùng bấm vào một Thư mục -> Mở vào bên trong thư mục đó để xem
//   danh sách tệp và có thể tạo tệp sổ dự giờ mới ngay trong thư mục đó.
// - Khi người dùng bấm vào một Tệp sổ dự giờ -> Mở màn hình NoteEditorScreen
//   (tabIndex: 1) để gọi dữ liệu JSON lên và render lên biểu mẫu sổ dự giờ đã chọn.
// ===========================================================================
class ObservationBookScreen extends StatelessWidget {
  const ObservationBookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final driveDatasource = GoogleDriveDatasource.instance;

    return ValueListenableBuilder<DriveFolderItem?>(
      valueListenable: driveDatasource.activeObservationFolderNotifier,
      builder: (context, activeFolder, _) {
        final bool isInsideFolder = activeFolder != null;

        return PopScope(
          canPop: !isInsideFolder,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && isInsideFolder) {
              driveDatasource.exitCurrentObservationFolder();
            }
          },
          child: DriveFolderSectionWidget(
            tabIndex: 1,
            foldersListenable: driveDatasource.observationFoldersNotifier,
            activeFolderListenable:
                driveDatasource.activeObservationFolderNotifier,
            searchKeywordListenable:
                driveDatasource.observationSearchKeywordNotifier,
            onRefresh: () => driveDatasource.refreshCurrentObservationView(),
            onExitFolder: () => driveDatasource.exitCurrentObservationFolder(),
            emptyMessage: isInsideFolder
                ? 'Thư mục "${activeFolder.displayName}" chưa có tệp sổ dự giờ nào.\nBấm nút (+) góc dưới bên phải để tạo sổ dự giờ mới trong thư mục này.'
                : 'Chưa có thư mục hay sổ dự giờ nào.\nBấm nút (+) góc dưới bên phải để tạo mới.',
            onFolderTap: (item) {
              if (item.isFolder) {
                // Bấm vào Thư mục -> Đi vào bên trong thư mục đó
                driveDatasource.openObservationFolder(item);
              } else {
                // Bấm vào Tệp sổ dự giờ (.json) -> Mở giao diện trang biểu mẫu để render dữ liệu JSON
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(
                      fileItem: item,
                      tabIndex: 1,
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}
