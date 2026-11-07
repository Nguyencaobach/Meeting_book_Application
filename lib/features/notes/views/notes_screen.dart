import 'package:flutter/material.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../../widgets/drive_folder_section_widget.dart';
import 'note_editor_screen.dart';

// ===========================================================================
// GIAO DIỆN MÀN HÌNH TAB GHI CHÚ (NOTES SCREEN)
// Công dụng:
// - Hiển thị danh sách các Thư mục và Tệp ghi chú (.json) ở ngoài màn hình chính
//   (MeetingBook/Ghi_Chu) hoặc bên trong thư mục đã chọn.
// - Khi người dùng bấm vào một Thư mục -> Mở vào bên trong thư mục đó để xem
//   danh sách tệp và có thể tạo tệp ghi chú mới ngay trong thư mục đó.
// - Khi người dùng bấm vào một Tệp ghi chú -> Mở màn hình NoteEditorScreen để
//   gọi dữ liệu JSON lên và render lên mặt giấy kẻ ngang (note5x hoặc note4x).
// ===========================================================================
class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final driveDatasource = GoogleDriveDatasource.instance;

    return ValueListenableBuilder<DriveFolderItem?>(
      valueListenable: driveDatasource.activeNotesFolderNotifier,
      builder: (context, activeFolder, _) {
        final bool isInsideFolder = activeFolder != null;

        return PopScope(
          canPop: !isInsideFolder,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && isInsideFolder) {
              driveDatasource.exitCurrentNotesFolder();
            }
          },
          child: DriveFolderSectionWidget(
            foldersListenable: driveDatasource.notesFoldersNotifier,
            allTabItemsListenable: driveDatasource.allNotesItemsNotifier,
            activeFolderListenable: driveDatasource.activeNotesFolderNotifier,
            searchKeywordListenable: driveDatasource.notesSearchKeywordNotifier,
            onRefresh: () => driveDatasource.refreshCurrentNotesView(),
            onExitFolder: () => driveDatasource.exitCurrentNotesFolder(),
            emptyMessage: isInsideFolder
                ? 'Thư mục "${activeFolder.displayName}" chưa có tệp ghi chú nào.\nBấm nút (+) góc dưới bên phải để tạo tệp ghi chú mới trong thư mục này.'
                : 'Chưa có thư mục hay tệp ghi chú nào.\nBấm nút (+) góc dưới bên phải để tạo mới.',
            onFolderTap: (item) {
              if (item.isFolder) {
                // Bấm vào Thư mục -> Đi vào bên trong thư mục đó
                driveDatasource.openNotesFolder(item);
              } else {
                // Bấm vào Tệp ghi chú -> Mở giao diện trang vở để render dữ liệu JSON
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditorScreen(fileItem: item),
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
