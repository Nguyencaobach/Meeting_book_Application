import 'package:flutter/material.dart';
import '../../../data/datasources/google_drive_datasource.dart';
import '../../../widgets/drive_folder_section_widget.dart';

/// Giao diện màn hình Sổ dự giờ (Hiển thị các thư mục trong MeetingBook/So_Du_Gio từ Google Drive)
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
                ? 'Thư mục "${activeFolder.displayName}" chưa có mục nào.\nBấm nút (+) góc dưới bên phải để tạo mới.'
                : 'Chưa có thư mục hay sổ dự giờ nào.\nBấm nút (+) góc dưới bên phải để tạo mới.',
            onFolderTap: (folder) {
              if (folder.isFolder) {
                driveDatasource.openObservationFolder(folder);
              }
            },
          ),
        );
      },
    );
  }
}
