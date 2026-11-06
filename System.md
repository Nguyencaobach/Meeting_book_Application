# TÀI LIỆU KỸ THUẬT: ỨNG DỤNG VỞ GHI CHÉP Ô LY THÔNG MINH TRÊN TABLET ANDROID (FLUTTER)

## Note
1. Phải dùng các thuộc tính tự co dãn
2. Phải dùng theo màu theme
3. Phải dùng bộ font chữ theo theme (`Be Vietnam Pro` kiểu Google Drive) và hàm tự động co giãn cỡ chữ (`AppTheme.getResponsiveFontSize(context, baseFontSize)`)
4. **Không lưu nội dung vở/ghi chú xuống ổ cứng của máy:** Khi đang viết chỉ lưu tạm trên **RAM (`_ramCache`)**, sau đó đồng bộ thẳng từ **RAM lên Google Drive** (ở 3 thời điểm hoặc khi bấm nút Lưu). Bộ nhớ máy (`SharedPreferences`) chỉ dùng duy nhất để nhớ phiên đăng nhập Gmail.

---

## 1. Tổng quan & Yêu cầu hệ thống
* **Thiết bị mục tiêu:** Máy tính bảng Android Xiaomi Pad 8 (Màn hình 11.2 inch, độ phân giải 2136 x 3200 pixels, tỷ lệ 3:2) và các dòng Tablet Android có hỗ trợ bút cảm ứng (Stylus).
* **Mô hình hoạt động:** **Local-First & On-Device AI** (Chạy độc lập 100% trên thiết bị, không cần Backend Server riêng, chỉ sử dụng kết nối mạng để tải gói ngôn ngữ lần đầu và đồng bộ sao lưu lên Google Drive cá nhân của người dùng).
* **Tính năng cốt lõi:**
  1. Hiển thị trang giấy phân trang giống Microsoft Word nhưng được kẻ sẵn lưới ô ly (4 ô ly, 5 ô ly, kẻ ngang) chuẩn vở học sinh Việt Nam.
  2. Ưu tiên nhập liệu bằng **Bút cảm ứng (Stylus)** kèm tính năng chống tì tay (Palm Rejection).
  3. Tự động xác định dòng người dùng đang viết, hiển thị nét mực thời gian thực và dùng AI trên thiết bị (Google ML Kit) để chuyển nét vẽ thành văn bản chuẩn điền thẳng vào dòng kẻ đó.
  4. Lưu trữ cấu trúc dữ liệu dạng JSON/Local Database siêu nhẹ, dễ dàng đổi mẫu giấy (Template) và xuất file PDF vector sắc nét để in ấn/chia sẻ.

---

## 2. Cấu hình Máy ảo (AVD) Xiaomi Pad 8 trên Android Studio
Để giả lập chính xác không gian hiển thị và bộ dịch vụ Google cho AI nhận diện chữ viết:

* **Thông số Hardware Profile:**
  * **Device Name:** `Xiaomi Pad 8`
  * **Device Type:** `Phone/Tablet`
  * **Screen Size:** `11,2` inch *(Lưu ý: dùng dấu phẩy `,` hoặc dấu chấm `.` tùy theo định dạng vùng của Windows)*
  * **Resolution:** `2136 x 3200` px (Tỷ lệ 3:2, `Size: xlarge`, `Ratio: notlong`, `Density: xhdpi`)
  * **RAM:** `4096 MB`
  * **Input:** Bỏ tích *Has Hardware Buttons*, Tích chọn *Has Hardware Keyboard*.
  * **Supported device states:** Tích chọn cả *Portrait* và *Landscape*.
* **System Image (Hệ điều hành):**
  * Chọn **`Google APIs Tablet Intel x86_64 Atom System Image`** (API 34, 35 hoặc 36).
  * *Lưu ý:* Không chọn bản `16 KB Page Size` để đảm bảo tương thích tốt nhất với các thư viện C++/NDK của Google ML Kit trên máy ảo `x86_64`.

---

## 3. Giải pháp Kiến trúc & Kỹ thuật Trọng tâm

### 3.1. Giao diện Trang giấy chuẩn tỷ lệ & Tự động co giãn (Responsive Paper)
Không kéo giãn tự do lưới ô ly theo màn hình để tránh làm méo ô vuông và lệch tọa độ nét bút khi xoay máy. Áp dụng nguyên tắc **Khung ngoài co giãn + Trang giấy giữ hệ tọa độ logic cố định**:
* **Kích thước logic chuẩn A4:** Rộng `800.0` px $\times$ Cao `1131.0` px (Tỷ lệ $1 : \sqrt{2} \approx 210 / 297$).
* **Cố định chiều cao dòng (`lineHeight`):** Ví dụ `40.0` logical pixels/dòng (chia làm 25–28 dòng mỗi trang).
* **Widgets bao bọc:** Dùng `InteractiveViewer` (hỗ trợ dùng 2 ngón tay phóng to/thu nhỏ trang giấy) $\rightarrow$ `AspectRatio(aspectRatio: 210 / 297)` $\rightarrow$ `FittedBox(fit: BoxFit.contain)` $\rightarrow$ `SizedBox(width: 800, height: 1131)`.
* **Cấu hình Android (`AndroidManifest.xml`):** Thêm `android:resizeableActivity="true"` vào thẻ `<activity>` để chạy toàn màn hình trên HyperOS/Android Tablet.

### 3.2. Xử lý Bút cảm ứng (Stylus) & Chống tì tay (Palm Rejection)
Sử dụng Widget `Listener` của Flutter để lọc sự kiện đầu vào phần cứng:
* **Chỉ nhận tín hiệu bút & chuột (khi test trên Emulator):**
  ```dart
  bool isStylusOrMouse(PointerEvent event) {
    return event.kind == PointerDeviceKind.stylus ||
           event.kind == PointerDeviceKind.invertedStylus ||
           event.kind == PointerDeviceKind.mouse;
  }
  ```
* **Chặn cảm ứng tay (`PointerDeviceKind.touch`) trên lớp vẽ:** Khi người dùng tì bàn tay lên màn hình để viết bút, các điểm chạm `touch` sẽ bị bỏ qua trên Canvas vẽ mực, hoặc chỉ dùng cho cử chỉ 2 ngón tay cuộn/zoom trang giấy.
* **Tính chỉ số dòng tự động theo tọa độ chạm bút:**
  $$\text{rowIndex} = \left\lfloor \frac{Y_{\text{local}} - \text{topMargin}}{\text{lineHeight}} \right\rfloor$$

### 3.3. Nhận diện Chữ viết tay thành Văn bản (Handwriting-to-Text)
* **Thư viện:** `google_mlkit_digital_ink_recognition` kết hợp với `perfect_freehand` (hiển thị nét mực mượt theo lực nhấn `pressure`).
* **Luồng hoạt động (Pipeline):**
  1. Người dùng đặt bút viết lên một dòng (`rowIndex`). Các điểm tọa độ $(x, y, t)$ được thu thập liên tục và vẽ tạm lên `ActiveInkPainter`.
  2. Mỗi khi bút nhấc lên (`onPointerUp`), khởi động bộ đếm chờ **`Debounce Timer` (600ms – 800ms)**. Nếu người dùng tiếp tục viết nét mới (ví dụ đánh dấu tiếng Việt) trước khi hết giờ, hủy Timer cũ và cộng dồn nét vẽ.
  3. Khi Timer đếm xong (người dùng đã ngừng viết chữ đó), gửi toàn bộ mảng nét vẽ vào `DigitalInkRecognizer` (model tiếng Việt `vi`).
  4. Nhận chuỗi `String` kết quả $\rightarrow$ Xóa nét mực tạm trên Canvas $\rightarrow$ Nối chuỗi văn bản vừa nhận diện vào đúng dòng `rowIndex` trên trang giấy (hiển thị bằng font chữ viết tay hoặc font chuẩn nằm khớp trên đường kẻ đậm).
  5. Nếu độ dài văn bản vượt quá chiều rộng dòng, tự động ngắt từ đẩy xuống `rowIndex + 1` (hoặc sang trang mới nếu đã ở dòng cuối cùng).

### 3.4. Lưu trữ Dữ liệu, Đổi mẫu giấy & Xuất file PDF / Word (Thay thế LaTeX)
Thay vì dùng trình biên dịch LaTeX (`.tex`) nặng nề và gây trễ khi vẽ thời gian thực, sử dụng kiến trúc **JSON + `CustomPainter` + Template Dart (`pdf` & `WordML`)**:
* **Định dạng dữ liệu nhẹ (Lightweight JSON):** Lưu cấu trúc Thư mục $\rightarrow$ Sổ tay $\rightarrow$ Trang $\rightarrow$ Dòng dưới dạng **JSON** (chỉ nặng vài KB, không gây nặng bộ nhớ máy).
* **Đổi kiểu mẫu giấy (Template Switching):** Dựa vào thuộc tính `"paperTemplate"` (`"note5x"` cho vở 5 ô ly, `"note4x"` cho vở 4 ô ly, `"primary_school_eval_v1"` cho Phiếu đánh giá tiết dạy cấp Tiểu học 3 trang), giao diện trên màn hình và bộ xuất `PDF` / `Word` tự động dựng đúng mẫu biểu tương ứng.
* **Cấu trúc JSON mẫu của một trang vở:**
  ```json
  {
    "pageNumber": 1,
    "paperTemplate": "note5x",
    "lines": [
      { "rowIndex": 0, "text": "Thứ Tư, ngày 4 tháng 11 năm 2026" },
      { "rowIndex": 1, "text": "Bài 1: Kiến trúc ứng dụng vở ô ly Flutter" },
      { "rowIndex": 2, "text": "Ghi chép bằng bút cảm ứng tự động chuyển thành chữ." }
    ]
  }
  ```
* **Xuất file PDF (`.pdf`) và Word (`.doc`) trực tiếp trên RAM lên Google Drive:**
  * Dùng `PdfExportService` (package `pdf` + `printing` với bộ đệm font `Be Vietnam Pro` trên RAM) và `WordExportService` (chuẩn WordML Print-View A4 có UTF-8 BOM) để dựng mảng byte `Uint8List` ngay trên RAM và tải thẳng lên thư mục `MeetingBook/Export File/Ghi chú` hoặc `MeetingBook/Export File/Sổ dự giờ`.

### 3.5. Cơ chế Lưu tạm RAM & Đồng bộ JSON thông minh lên Google Drive (Bộ đếm 30s & 3 Thời điểm vàng)
Để đảm bảo màn hình viết bút cảm ứng đạt tốc độ 60–120fps mượt mà, tiết kiệm pin và không vượt hạn mức ghi đè của Google Drive API (`Rate Limit`), ứng dụng **không gửi Real-time từng nét bút** mà áp dụng quy trình **Lưu tức thì vào RAM + Đẩy lên Google Drive ở 3 thời điểm**:

1. **Khi người dùng đang viết / thao tác (Lưu tức thì vào RAM & Reset bộ đếm 30 giây):**
   * Mỗi khi người dùng viết chữ hoặc chỉnh sửa nội dung, dữ liệu chỉ được cập nhật tức thì (0ms) vào **RAM (`LocalStorageDatasource._ramCache`)** (không ghi xuống ổ cứng của máy), đồng thời bật cờ `isDirty = true`.
   * Khởi động bộ đếm chờ **`Debounce Timer` (30 giây)**.
   * **Nếu bộ đếm 30 giây đang chạy mà người dùng tiếp tục viết/thao tác tiếp:** Hệ thống lập tức **hủy bộ đếm 30 giây cũ**, lưu tiếp dữ liệu mới vào RAM và **đếm lại 30 giây từ đầu** kể từ lúc người dùng dừng bút hẳn.
2. **Chỉ gọi Google Drive API để ghi đè file JSON ở đúng 3 thời điểm:**
   * **Thời điểm 1 (Định kỳ thưa hơn - Sau 30 giây dừng bút):** Khi người dùng ngừng thao tác đủ 30 giây liên tục và có nội dung mới (`isDirty == true`), hệ thống mới đóng gói JSON và gửi ngầm lên ghi đè trên Google Drive.
   * **Thời điểm 2 (Khi đóng trang vở):** Ngay khi người dùng bấm nút **Quay lại (`Back`)** để thoát khỏi trang ghi chú về màn hình Home (`syncOnPageExit()`).
   * **Thời điểm 3 (Khi tắt màn hình / ẩn App):** Ngay khi người dùng bấm nút nguồn tắt màn hình hoặc vuốt thoát/ẩn ứng dụng xuống nền (`AppLifecycleState.paused`).
3. **Xử lý Mất mạng giữa chừng (Khóa thao tác tức thì):**
   * Ứng dụng lắng nghe trạng thái mạng liên tục qua `connectivity_plus`.
   * Nếu đang thao tác mà mất mạng đột ngột: Toàn bộ chữ vừa viết đã nằm an toàn trong RAM, ứng dụng **lập tức hiển thị thông báo khóa màn hình thao tác** cho đến khi có mạng trở lại để tự động đẩy bù gói JSON từ RAM lên Google Drive.

---

## 4. Cấu trúc Thư mục Dự án (`lib/`) & Cây Thư mục Google Drive (`MeetingBook/`)

Dự án được tổ chức theo kiến trúc **Feature-First kết hợp Clean Architecture rút gọn (Layered Architecture)**, giúp tách biệt rõ ràng giữa giao diện (UI/Painters), logic điều khiển (Controllers/Services), dịch vụ hệ thống/AI/Xuất file (Services) và tầng dữ liệu (Data).

### 4.1. Sơ đồ cây thư mục mã nguồn dự án (`lib/` - Đầy đủ 40 tệp thực tế)

```text
lib/
├── main.dart                                # Điểm khởi chạy ứng dụng, cấu hình hệ thống & gọi runApp()
├── app.dart                                 # MaterialApp gốc, cấu hình AppTheme & AuthGateScreen kiểm tra phiên đăng nhập
│
├── core/                                    # Cấu hình, hằng số, mẫu giấy & tiện ích dùng chung toàn app
│   ├── constants/
│   │   ├── app_colors.dart                  # Bảng màu chuẩn theo Theme (#263BAA, #FFF4D6, #FFFFFF, #000000)
│   │   ├── note_templates/                  # Thư mục gom các định dạng giấy ô ly cho Tab Ghi chú
│   │   │   ├── note5x.dart                  # Định dạng vở 5 ô ly (Note5xHorizontalPaperPainter vẽ dòng kẻ ngang co giãn)
│   │   │   └── note4x.dart                  # Định dạng vở 4 ô ly (Note4xHorizontalPaperPainter vẽ dòng kẻ ngang co giãn)
│   │   └── observation_templates/           # Thư mục gom các biểu mẫu cho Tab Sổ dự giờ
│   │       └── primary_school_evaluation_template.dart # Biểu mẫu 3 trang "Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học" & danh sách biểu mẫu (availableTemplates)
│   ├── theme/
│   │   └── app_theme.dart                   # Cấu hình font chữ Be Vietnam Pro & hàm getResponsiveFontSize()
│   └── utils/
│       └── coordinate_converter.dart        # Hàm chuyển đổi tọa độ Y của bút -> chỉ số dòng (rowIndex)
│
├── data/                                    # Tầng dữ liệu (RAM tạm thời 0ms & Đồng bộ Google Drive cá nhân)
│   ├── models/
│   │   ├── notebook_model.dart              # Thông tin cuốn vở/file ghi chú (id, title, paperTemplate, updatedAt, pages)
│   │   ├── page_model.dart                  # Thông tin trang giấy (pageNumber, paperTemplate, danh sách dòng lines)
│   │   ├── line_model.dart                  # Dữ liệu từng dòng kẻ ngang / ô biểu mẫu (rowIndex, chuỗi text)
│   │   └── stroke_point_model.dart          # Tọa độ điểm nét bút tạm (x, y, pressure, timestamp)
│   ├── datasources/
│   │   ├── local_storage_datasource.dart    # Chỉ lưu tạm JSON trên bộ nhớ RAM (_ramCache, 0ms), không ghi ổ cứng máy
│   │   └── google_drive_datasource.dart     # Kết nối Google Drive API: tạo/đổi tên/xóa/di chuyển cây thư mục, hoàn tác, đọc/ghi .json & xuất file vào Export File
│   └── repositories/
│       └── data_sync_repository.dart        # Trung gian đồng bộ RAM -> Google Drive (Bộ đếm 30s, 3 thời điểm vàng, nút Lưu & khóa mất mạng)
│
├── services/                                # Các dịch vụ xử lý độc lập với giao diện (AI nhận diện bút, Lọc bút, Xuất PDF & Word)
│   ├── handwriting_recognition_service.dart # Gọi Google ML Kit Digital Ink (model 'vi') chuyển nét vẽ viết tay thành văn bản tiếng Việt
│   ├── pdf_export_service.dart              # Template Dart xuất vở ô ly & biểu mẫu 3 trang ra file .pdf chuẩn A4 trên RAM (có cache font)
│   ├── word_export_service.dart             # Template Dart xuất vở ô ly & biểu mẫu 3 trang ra file Word (.doc) chuẩn A4 trên RAM
│   └── stylus_input_filter.dart             # Lọc sự kiện Bút cảm ứng / Chuột / Chạm và chống tì tay (Palm Rejection)
│
├── widgets/                                 # Các Widget & Hộp thoại dùng chung cho toàn bộ ứng dụng
│   ├── app_header_widget.dart               # Header dùng chung (Ô tìm kiếm + Icon User + Thanh chuyển Tab)
│   ├── center_notification_dialog.dart      # Hộp thoại thông báo Thành công / Thất bại giữa màn hình (hỗ trợ nút Hoàn tác)
│   ├── create_folder_dialog.dart            # Hộp thoại tạo Thư mục mới trên Google Drive (tối đa 150 ký tự, chống trùng tên)
│   ├── create_note_dialog.dart              # Hộp thoại tạo Tệp ghi chú mới (.json) kèm chọn mẫu vở 5 ô ly / 4 ô ly
│   ├── create_observation_book_dialog.dart  # Hộp thoại tạo Tệp sổ dự giờ mới (.json) kèm chọn biểu mẫu hiển thị dạng Danh sách (List)
│   ├── drive_folder_section_widget.dart     # Khu vực hiển thị Thư mục & Tệp kiểu Google Drive (Lưới ô / Danh sách, điều hướng đa cấp, Làm mới)
│   ├── item_actions_bottom_sheet.dart       # Bottom Sheet nút "i" (Đổi tên chống trùng, Xóa có hoàn tác, Di chuyển dạng Cây thư mục)
│   ├── network_lock_overlay_widget.dart     # Màn hình khóa thao tác tức thì khi mất kết nối mạng hoặc lỗi bộ nhớ RAM
│   └── user_profile_dialog.dart             # Hộp thoại hiển thị thông tin tài khoản Gmail đang liên kết & nút Đăng xuất
│
└── features/                                # Chia theo các mô-đun màn hình tính năng
    ├── auth/                                # Mô-đun Đăng nhập & Xác thực Google Drive
    │   ├── service/
    │   │   └── auth_service.dart            # Logic kiểm tra mạng, đăng nhập OAuth2 Google Drive, khôi phục phiên & đăng xuất
    │   └── views/
    │       └── login_screen.dart            # Giao diện màn hình Đăng nhập & Liên kết Google Drive
    │
    ├── home/                                # Mô-đun Màn hình Home chính của ứng dụng
    │   ├── controllers/
    │   │   └── home_controller.dart         # Quản lý trạng thái điều khiển màn hình Home
    │   ├── service/
    │   │   └── home_service.dart            # Xử lý tìm kiếm theo Tab, mở thông tin User, mở Bottom Sheet tạo Thư mục / Ghi chú / Sổ dự giờ
    │   └── views/
    │       ├── home_screen.dart             # Giao diện chính của màn hình Home (Header + TabBarView + Nút nổi '+' + Footer)
    │       └── widgets/
    │           └── create_item_bottom_sheet.dart # Bottom Sheet trượt lên khi bấm nút (+) để chọn Tạo tệp mới hoặc Tạo thư mục mới
    │
    ├── notes/                               # Tab 1: Mô-đun Ghi chú & Trình soạn thảo Trang vở / Biểu mẫu
    │   ├── controllers/
    │   │   └── notes_controller.dart        # Quản lý trạng thái danh sách Ghi chú
    │   └── views/
    │       ├── notes_screen.dart            # Màn hình danh sách Thư mục & Tệp ghi chú (.json) trong MeetingBook/Ghi_Chu
    │       ├── note_editor_screen.dart      # Màn hình Trang vở & Biểu mẫu (note5x/note4x/primary_school_eval_v1): Bàn phím Telex, Viết bút, Chỉ xem, Làm mới, Xuất file PDF/Word & Lưu Google Drive
    │       └── widgets/
    │           └── pen_handwriting_pad_widget.dart # Bảng giấy viết bút 60-120fps (RepaintBoundary): vẽ nét mực mượt, tự nối chữ/cách từ & tự mờ nét sau khi chèn chữ
    │
    └── observation_book/                    # Tab 2: Mô-đun Sổ dự giờ
        ├── controllers/
        │   └── observation_book_controller.dart # Quản lý trạng thái danh sách Sổ dự giờ
        └── views/
            └── observation_book_screen.dart # Màn hình danh sách Thư mục & Tệp sổ dự giờ (.json) trong MeetingBook/So_Du_Gio (mở thư mục đa cấp & mở biểu mẫu)
```

### 4.2. Sơ đồ cây thư mục tự động khởi tạo trên Google Drive cá nhân (`MeetingBook/`)

Khi người dùng đăng nhập Gmail, hàm `GoogleDriveDatasource.ensureAppFolderStructure()` tự động kiểm tra và tạo sẵn cây thư mục chuẩn trên Google Drive của người dùng:

```text
MeetingBook/                                 # Thư mục gốc của ứng dụng trên Google Drive
├── Ghi_Chu/                                 # Lưu trữ các thư mục con & tệp dữ liệu gốc (.json) của Tab Ghi chú (Vở 5 ô ly / 4 ô ly)
├── So_Du_Gio/                               # Lưu trữ các thư mục con & tệp dữ liệu gốc (.json) của Tab Sổ dự giờ (Phiếu đánh giá tiết dạy Tiểu học)
└── Export File/                             # Thư mục chứa các tệp xuất bản (.pdf / .doc) khi người dùng bấm nút "Xuất file"
    ├── Ghi chú/                             # Chứa các file PDF (.pdf) và Word (.doc) xuất ra từ Tab Ghi chú
    └── Sổ dự giờ/                           # Chứa các file PDF (.pdf) và Word (.doc) xuất ra từ Tab Sổ dự giờ
```

### 4.3. Giải thích chi tiết từng phân tầng & tệp tin

#### A. Khởi tạo ứng dụng (`Root`)
* **`main.dart`**: Điểm bắt đầu của ứng dụng (`void main()`), khởi tạo `WidgetsFlutterBinding` và chạy `runApp(const MeetingBookApp())`.
* **`app.dart`**: Chứa Widget gốc (`MaterialApp`), thiết lập `AppTheme` (font `Be Vietnam Pro`, bảng màu chuẩn) và `AuthGateScreen` tự động kiểm tra phiên đăng nhập Google Drive để điều hướng thẳng vào `HomeScreen` hoặc `LoginScreen`.

#### B. Tầng `core/` (Cấu hình, Hằng số, Thư mục Mẫu giấy Ô ly & Thư mục Biểu mẫu Sổ dự giờ)
Chứa các giá trị bất biến, thông số dòng kẻ và hàm tính toán co giãn dùng xuyên suốt ứng dụng:
* **`constants/app_colors.dart`**: Quản lý bảng màu chuẩn theo Theme (`primaryBlue` `#263BAA`, `creamBackground` `#FFF4D6`, `basicWhite` `#FFFFFF`, `basicBlack` `#000000`, `paperMarginRed` `#E53935`).
* **`constants/note_templates/` (Thư mục gom các mẫu ô ly cho Ghi chú)**:
  * **`note5x.dart`**: Định nghĩa thông số tỷ lệ và `Note5xHorizontalPaperPainter` vẽ trang giấy kẻ ngang theo chuẩn tỷ lệ vở **5 ô ly** (`note5x`), tự động co giãn chiều cao dòng và cỡ chữ theo màn hình.
  * **`note4x.dart`**: Định nghĩa thông số tỷ lệ và `Note4xHorizontalPaperPainter` vẽ trang giấy kẻ ngang theo chuẩn tỷ lệ vở **4 ô ly** (`note4x`), tự động co giãn chiều cao dòng và cỡ chữ theo màn hình.
* **`constants/observation_templates/` (Thư mục gom các biểu mẫu cho Sổ dự giờ)**:
  * **`primary_school_evaluation_template.dart`**: Định nghĩa `ObservationTemplateItem`, danh sách biểu mẫu `availableTemplates` và tái tạo 100% biểu mẫu 3 trang nền trắng **"Phiếu đánh giá tiết dạy giáo viên cấp Tiểu học"** (`primary_school_eval_v1`) gồm: Quốc hiệu & thông tin người dạy, Bảng ghi chép tiến trình 3 cột (28 dòng nét đứt), Nhận xét chung (5 dòng chấm), Bảng thang điểm 12 tiêu chí (`1.1` -> `3.4`, tự động cộng tổng điểm trên `20,0`), quy định 4 mức xếp loại, tự động xét loại tiết dạy và mục ký tên Người dự giờ.
* **`theme/app_theme.dart`**: Thiết lập `ThemeData` tổng thể với bộ font chữ `Be Vietnam Pro` kiểu Google Drive và hàm `AppTheme.getResponsiveFontSize(context, baseFontSize)` tự động co giãn cỡ chữ theo kích thước thiết bị.
* **`utils/coordinate_converter.dart`**: Chứa các hàm toán học chuyển đổi tọa độ điểm chạm thực tế $(X, Y)$ trên trang giấy sang chỉ số dòng (`rowIndex`).

#### C. Tầng `data/` (Quản lý Dữ liệu RAM & Đồng bộ Google Drive)
Đảm nhận định nghĩa cấu trúc dữ liệu JSON, lưu tạm tốc độ cao trên RAM và đồng bộ đám mây Google Drive:
* **`models/`**:
  * **`notebook_model.dart`**: Đại diện cho một tệp ghi chú / sổ dự giờ (`id`, `title`, `paperTemplate` (`note5x`, `note4x`, `primary_school_eval_v1`), `updatedAt`, `pages`).
  * **`page_model.dart`**: Đại diện cho một trang giấy trong vở (`pageNumber`, `paperTemplate`, và danh sách `List<LineModel> lines`).
  * **`line_model.dart`**: Lưu nội dung văn bản của từng dòng kẻ ngang hoặc từng ô biểu mẫu (`rowIndex`, chuỗi `text`).
  * **`stroke_point_model.dart`**: Lưu tọa độ điểm của nét bút viết tay (`x`, `y`, `pressure`, `timestamp`) phục vụ vẽ mực thời gian thực và gửi sang Google ML Kit.
* **`datasources/`**:
  * **`local_storage_datasource.dart`**: Chỉ lưu tạm dữ liệu JSON của cuốn vở đang mở trực tiếp trên **bộ nhớ RAM (`_ramCache`, tốc độ `0ms`)**, tuyệt đối không ghi nội dung vở xuống ổ cứng của máy.
  * **`google_drive_datasource.dart`**: Quản lý toàn bộ kết nối Google Drive API (`MeetingBook/Ghi_Chu`, `MeetingBook/So_Du_Gio` và `MeetingBook/Export File/{Ghi chú, Sổ dự giờ}`):
    * Tự động làm mới Access Token khi gặp lỗi `401`.
    * Điều hướng mở thư mục đa cấp ở cả 2 Tab (ngăn xếp `_notesFolderStack`, `_observationFolderStack`).
    * Tạo thư mục mới (`createFolderInTab`), tạo tệp ghi chú `.json` (`createNoteFileInNotesTab`), tạo tệp sổ dự giờ `.json` (`createObservationFileInTab`), đọc nội dung `.json` (ưu tiên RAM hoặc tải mới từ Drive khi bấm **Làm mới**).
    * Xuất file trực tiếp từ RAM lên Google Drive (`uploadExportedFileToDrive`) vào đúng thư mục `MeetingBook/Export File/Ghi chú` hoặc `MeetingBook/Export File/Sổ dự giờ`.
    * Bộ 3 chức năng quản lý mục: **Đổi tên** (`renameItemInTab` chống trùng tên), **Xóa** (`deleteItemInTab` & `restoreDeletedItemInTab` hoàn tác xóa), và **Di chuyển dạng Cây thư mục** (`fetchFolderTreeForMove`, `moveItemInTab` & `undoMoveItemInTab` hoàn tác di chuyển).
* **`repositories/`**:
  * **`data_sync_repository.dart`**: Quản lý quy trình lưu tức thì trên RAM và đồng bộ lên Google Drive ở **3 thời điểm vàng** (sau 30 giây dừng thao tác, khi thoát trang vở, khi ẩn app/tắt màn hình) hoặc khi bấm nút **Lưu**; đồng thời lắng nghe `connectivity_plus` để khóa màn hình ngay khi rớt mạng hoặc lỗi RAM.

#### D. Tầng `services/` (Các Dịch vụ Xử lý Chuyên biệt)
* **`handwriting_recognition_service.dart`**: Quản lý `DigitalInkRecognizer` của Google ML Kit (ngôn ngữ `vi` - Tiếng Việt), tự động kiểm tra/tải gói ngôn ngữ và nhận diện danh sách nét bút (`List<List<StrokePointModel>>`) thành chuỗi văn bản tiếng Việt.
* **`stylus_input_filter.dart`**: Bộ lọc phần cứng phân biệt tín hiệu Bút cảm ứng (`stylus`, `invertedStylus`), Chuột (`mouse`) và Chạm (`touch`), tự động chặn cảm ứng tì tay khi đầu bút đang chạm màn hình.
* **`pdf_export_service.dart`**: Template Dart sử dụng `pdf` + `PdfGoogleFonts.beVietnamPro*` (có bộ đệm font trên RAM `_getOrLoadFontsInRam`) dựng mảng byte `.pdf` chuẩn A4 trực tiếp trên RAM, giữ nguyên 100% bố cục 3 trang Phiếu đánh giá tiết dạy Tiểu học và vở 5 ô ly / 4 ô ly.
* **`word_export_service.dart`**: Template Dart dựng mảng byte Word `.doc` (WordML Print-View chuẩn A4 kèm UTF-8 BOM `\uFEFF`) trực tiếp trên RAM, giữ nguyên khung bảng, dòng kẻ đứt, gộp ô `rowspan`/`colspan` và ngắt trang.

#### E. Tầng `widgets/` (Các Widget & Hộp thoại Dùng chung Toàn App)
* **`app_header_widget.dart`**: Thanh Header dùng chung gồm ô tìm kiếm tự co giãn, nút thông tin User góc phải và thanh chuyển đổi 2 Tab (`Ghi chú`, `Sổ dự giờ`).
* **`center_notification_dialog.dart`**: Hộp thoại thông báo ngắn gọn chính giữa màn hình (`Thành công` tích xanh lá / `Thất bại` chữ X đỏ), tích hợp nút **`Hoàn tác`** cho thao tác Xóa và Di chuyển.
* **`create_folder_dialog.dart`**: Hộp thoại nhập tên tạo Thư mục mới (tối đa 150 ký tự, kiểm tra chống trùng tên).
* **`create_note_dialog.dart`**: Hộp thoại tạo Tệp ghi chú mới (nhập tên tối đa 150 ký tự, chống trùng tên, chọn mẫu **Vở 5 ô ly** hoặc **Vở 4 ô ly**).
* **`create_observation_book_dialog.dart`**: Hộp thoại tạo Tệp sổ dự giờ mới (nhập tên tối đa 150 ký tự, chống trùng tên, hiển thị biểu mẫu Sổ dự giờ từ `observation_templates/` theo **dạng Danh sách (List)** kèm tên biểu mẫu).
* **`drive_folder_section_widget.dart`**: Widget hiển thị danh sách Thư mục & Tệp theo chế độ **Lưới ô (2/4/6 cột)** hoặc **Danh sách**, kèm thanh điều hướng **Quay lại** thư mục cha, nút **Làm mới** và nút chữ **`i`** trên mỗi mục.
* **`item_actions_bottom_sheet.dart`**: Bottom Sheet khi bấm nút **`i`** trên Tệp/Thư mục, cung cấp 3 chức năng: **Đổi tên** (kiểm tra trùng tên), **Xóa** (có nút Hoàn tác), và **Di chuyển** (hiển thị **Cây thư mục Google Drive** đóng/mở đa cấp kèm nút Hoàn tác).
* **`network_lock_overlay_widget.dart`**: Lớp phủ khóa màn hình bảo vệ dữ liệu khi phát hiện mất mạng hoặc lỗi bộ nhớ tạm RAM.
* **`user_profile_dialog.dart`**: Hộp thoại hiển thị ảnh đại diện, tên, Email Google Drive đang đăng nhập và nút **Đăng xuất**.

#### F. Tầng `features/` (Các Mô-đun Màn hình Tính năng)
* **`features/auth/`**:
  * **`service/auth_service.dart`** & **`views/login_screen.dart`**: Kiểm tra mạng, đăng nhập tài khoản Google, cấp quyền Google Drive và đăng xuất.
* **`features/home/`**:
  * **`service/home_service.dart`**, **`controllers/home_controller.dart`**, **`views/home_screen.dart`** & **`views/widgets/create_item_bottom_sheet.dart`**: Quản lý màn hình chính, tìm kiếm theo Tab và mở Bottom Sheet tạo mới (Ghi chú mới, Sổ dự giờ mới, Thư mục mới) khi bấm nút `+`.
* **`features/notes/`**:
  * **`views/notes_screen.dart`**: Hiển thị cây thư mục và các tệp ghi chú trong Tab Ghi chú; bấm vào thư mục để đi sâu vào trong, bấm vào tệp để mở trang vở.
  * **`views/note_editor_screen.dart`**: Màn hình soạn thảo trang vở & biểu mẫu thông minh:
    * Tích hợp nút **Xuất file** trên thanh Header cho phép xuất tệp đang mở ra **PDF (`.pdf`)** hoặc **Word (`.doc`)** từ RAM thẳng lên `MeetingBook/Export File/Ghi chú` hoặc `MeetingBook/Export File/Sổ dự giờ`.
    * Menu chọn chế độ: **Bàn phím** (hỗ trợ gõ Tiếng Việt kiểu Telex tích hợp sẵn), **Viết bút**, **Chỉ xem** (tiết kiệm API, chặn chỉnh sửa nhưng vẫn cho phép Zoom/cuộn trang), và **Làm mới** (tải lại JSON mới nhất từ Drive).
    * Hiển thị **con trỏ dọc `|` kèm nút nắm tròn** trên dòng đang chọn để người dùng chạm hoặc kéo ngang con trỏ đến vị trí cần thêm/sửa chữ.
    * Tự động nối dòng, ngắt từ xuống dòng như Microsoft Word và tự dàn lại chữ khi xoay ngang/dọc màn hình.
  * **`views/widgets/pen_handwriting_pad_widget.dart`**: Bảng giấy viết tay ở nửa dưới màn hình (cách ly bằng `RepaintBoundary` + `ValueNotifier` đạt 60–120fps không lag): viết liên tục tự nối chữ, dừng 1 nhịp (`650ms`) tự cách khoảng trắng, hiển thị nét mực và tự làm mờ nét vẽ sau khi đẩy chữ lên dòng kẻ.
* **`features/observation_book/`**:
  * **`views/observation_book_screen.dart`** & **`controllers/observation_book_controller.dart`**: Quản lý cây thư mục và các tệp Sổ dự giờ (`.json`) trong Tab Sổ dự giờ (`MeetingBook/So_Du_Gio`); bấm vào thư mục để mở vào trong, bấm vào tệp sổ dự giờ để mở màn hình biểu mẫu soạn thảo.

---

## 5. Các lệnh Khởi tạo Nhanh & Danh sách Thư viện

### 5.1. Lệnh tạo tự động toàn bộ cây thư mục và file của dự án
Chạy lệnh sau tại thư mục gốc của project Flutter (Git Bash):

```bash
mkdir -p lib/core/constants/{note_templates,observation_templates} \
         lib/core/{theme,utils} \
         lib/data/{models,datasources,repositories} \
         lib/services \
         lib/widgets \
         lib/features/auth/{service,views} \
         lib/features/home/{controllers,service,views/widgets} \
         lib/features/notes/{controllers,views/widgets} \
         lib/features/observation_book/{controllers,views} && \
touch lib/app.dart \
      lib/core/constants/app_colors.dart \
      lib/core/constants/note_templates/{note5x.dart,note4x.dart} \
      lib/core/constants/observation_templates/primary_school_evaluation_template.dart \
      lib/core/theme/app_theme.dart \
      lib/core/utils/coordinate_converter.dart \
      lib/data/models/{notebook_model.dart,page_model.dart,line_model.dart,stroke_point_model.dart} \
      lib/data/datasources/{local_storage_datasource.dart,google_drive_datasource.dart} \
      lib/data/repositories/data_sync_repository.dart \
      lib/services/{handwriting_recognition_service.dart,pdf_export_service.dart,word_export_service.dart,stylus_input_filter.dart} \
      lib/widgets/{app_header_widget.dart,center_notification_dialog.dart,create_folder_dialog.dart,create_note_dialog.dart,create_observation_book_dialog.dart,drive_folder_section_widget.dart,item_actions_bottom_sheet.dart,network_lock_overlay_widget.dart,user_profile_dialog.dart} \
      lib/features/auth/service/auth_service.dart \
      lib/features/auth/views/login_screen.dart \
      lib/features/home/controllers/home_controller.dart \
      lib/features/home/service/home_service.dart \
      lib/features/home/views/home_screen.dart \
      lib/features/home/views/widgets/create_item_bottom_sheet.dart \
      lib/features/notes/controllers/notes_controller.dart \
      lib/features/notes/views/{notes_screen.dart,note_editor_screen.dart} \
      lib/features/notes/views/widgets/pen_handwriting_pad_widget.dart \
      lib/features/observation_book/controllers/observation_book_controller.dart \
      lib/features/observation_book/views/observation_book_screen.dart
```

### 5.2. Danh sách các Thư viện (Packages) sử dụng trong Dự án & Lệnh cài đặt

#### Các thư viện đã cài đặt và đang chạy trong `pubspec.yaml`:
* **`google_fonts` (`^8.2.1`)**: Cung cấp bộ font chữ chuẩn Google Drive (`Be Vietnam Pro`) hỗ trợ tiếng Việt.
* **`google_sign_in` (`6.2.2`)**: Xác thực và đăng nhập tài khoản Google trên thiết bị Android.
* **`googleapis` (`^17.0.0`)**: Cung cấp bộ thư viện `DriveApi` (`v3`) để quản lý cây thư mục, tải lên và ghi đè file JSON / PDF / Word trên Google Drive cá nhân.
* **`http` (`^1.6.0`)**: Tạo `GoogleAuthClient` đính kèm mã xác thực OAuth vào các yêu cầu gọi Google Drive REST API.
* **`shared_preferences` (`^2.5.6`)**: Chỉ dùng để lưu trạng thái duy trì phiên đăng nhập Gmail (`is_logged_in`, `user_email`, `user_display_name`, `user_photo_url`) và ID các thư mục gốc.
* **`connectivity_plus` (`^7.3.2`)**: Kiểm tra trạng thái kết nối mạng khi đăng nhập và theo dõi đứt mạng giữa chừng để khóa thao tác bảo vệ dữ liệu.
* **`google_mlkit_digital_ink_recognition` (`^0.16.1`)**: AI trên thiết bị (On-Device) chuyển nét vẽ viết tay trên bảng viết bút thành văn bản tiếng Việt (`vi`).
* **`pdf` (`^3.13.1`) & `printing` (`^5.15.1`)**: Dựng trang vở ô ly và biểu mẫu dự giờ 3 trang thành mảng byte `.pdf` chuẩn A4 hỗ trợ đầy đủ Unicode Tiếng Việt (`PdfGoogleFonts`).

```bash
flutter pub add google_fonts "google_sign_in:6.2.2" googleapis http shared_preferences connectivity_plus google_mlkit_digital_ink_recognition pdf printing
```

---

## 6. Lộ trình Triển khai Dự án (5 Giai đoạn)
1. **Giai đoạn 1 (Đăng nhập & Cây thư mục Google Drive):** Hoàn thiện `login_screen.dart`, `auth_service.dart`, `google_drive_datasource.dart`, `home_screen.dart`, `drive_folder_section_widget.dart` và `item_actions_bottom_sheet.dart` (Tạo mới, Đổi tên chống trùng, Xóa có hoàn tác, Di chuyển dạng Cây thư mục có hoàn tác).
2. **Giai đoạn 2 (Giao diện Trang giấy 5 ô ly / 4 ô ly & Soạn thảo như Word):** Hoàn thiện `note5x.dart`, `note4x.dart` và `note_editor_screen.dart` để hiển thị mặt giấy kẻ ngang tự co giãn, hỗ trợ gõ Bàn phím Telex, tự xuống dòng/nối dòng và Chế độ Chỉ xem.
3. **Giai đoạn 3 (Bảng viết Bút cảm ứng & AI Nhận diện chữ viết tay):** Hoàn thiện `pen_handwriting_pad_widget.dart`, `stylus_input_filter.dart` và `handwriting_recognition_service.dart` (Google ML Kit Digital Ink `vi`) để viết nét mực mượt 60–120fps, tự nối chữ/cách từ và trỏ/kéo con trỏ thêm chữ bù vào bất kỳ vị trí nào trên câu.
4. **Giai đoạn 4 (Đồng bộ RAM 0ms $\rightarrow$ Google Drive):** Hoàn thiện `local_storage_datasource.dart` (chỉ lưu trên RAM `_ramCache`) và `data_sync_repository.dart` (đồng bộ ở 3 thời điểm vàng, nút Lưu thủ công và khóa màn hình khi mất mạng).
5. **Giai đoạn 5 (Biểu mẫu Sổ dự giờ & Xuất file PDF / Word lên Google Drive):** Hoàn thiện `observation_book_screen.dart`, biểu mẫu 3 trang `primary_school_evaluation_template.dart`, cùng 2 dịch vụ `pdf_export_service.dart` và `word_export_service.dart` để kết xuất file `.pdf` / `.doc` trực tiếp trên RAM và đẩy thẳng vào thư mục `MeetingBook/Export File/{Ghi chú, Sổ dự giờ}` trên Google Drive.

---

## 7. Hướng dẫn Cấu hình Kết nối Google Drive Cá nhân (Google Cloud Console)

Dịch vụ hoàn toàn **miễn phí 100%** và sử dụng trực tiếp dung lượng 15GB có sẵn trên Google Drive của người đăng nhập. Bất kỳ thiết bị Android nào cài ứng dụng đều có thể đăng nhập Gmail cá nhân để tự lưu dữ liệu vào Drive của chính mình.

### 7.1. Bước 1: Tạo Project & Bật Google Drive API
1. Truy cập [Google Cloud Console](https://console.cloud.google.com/) và đăng nhập bằng tài khoản Gmail.
2. Bấm vào ô chọn dự án ở góc trên bên trái $\rightarrow$ Chọn **New Project** $\rightarrow$ Đặt tên dự án (ví dụ: `Meeting Booking`) $\rightarrow$ Bấm **Create**.
3. Vào menu bên trái: **APIs & Services** $\rightarrow$ **Library**.
4. Tìm kiếm **`Google Drive API`** $\rightarrow$ Bấm chọn và nhấn **Enable (Bật)**.

### 7.2. Bước 2: Thiết lập Google Auth Platform (OAuth Consent Screen) & Cấp quyền cho người khác đăng nhập
Vào **APIs & Services** $\rightarrow$ **OAuth consent screen** (giao diện **Google Auth Platform**):
1. **Mục `Overview`:**
   * Bấm nút **Get started** (Bắt đầu).
   * **App name:** Điền `Meeting Book`.
   * **User support email:** Chọn Gmail của bạn.
   * **Audience:** Chọn **External** (Cho phép mọi tài khoản Gmail cá nhân đăng nhập).
   * **Contact Information:** Nhập email liên hệ $\rightarrow$ Tích đồng ý điều khoản và bấm **Create**.
2. **Mục `Audience` (Chọn 1 trong 2 cách để cấp quyền cho người khác cài `.apk` và đăng nhập):**
   * **Cách 1 — Nhanh nhất & không hiện cảnh báo khi đăng nhập (Khuyên dùng nếu gửi cho dưới 100 người):**
     1. Ở mục **Test users**, bấm nút **`+ Add users`**.
     2. Nhập địa chỉ Gmail của những người mà bạn gửi file `.apk` cho họ $\rightarrow$ bấm **Save**.
     3. Người đó cài file `.apk` xong đăng nhập bằng Gmail đó là vào thẳng ứng dụng cực kỳ mượt!
   * **Cách 2 — Mở khóa nút `Publish app` để ai cài `.apk` cũng tự đăng nhập được (Không cần thêm Gmail từng người):**
     * Nếu nút **`Publish app`** ở mục *Publishing status* đang bị mờ kèm thông báo *"To publish your app, you must complete your configuration on the Branding page"*, để bật sáng nút này:
     1. Bấm vào dòng chữ màu xanh **`Branding page`** ngay dưới nút `Publish app` (hoặc bấm mục **`Branding`** ở menu bên trái).
     2. Kiểm tra và điền các mục bắt buộc còn trống:
        * **App name:** Tên ứng dụng (ví dụ: `Meeting Book`)
        * **User support email:** Chọn `caobach19112005@gmail.com`
        * Kéo xuống mục **Developer contact information** (Email liên hệ nhà phát triển): Nhập `caobach19112005@gmail.com`
        * Bấm nút **`Save`** ở dưới cùng.
     3. Quay lại trang **`Audience`**, lúc này nút **`Publish app`** sẽ sáng lên $\rightarrow$ bấm vào **`Publish app`** $\rightarrow$ chọn **`Confirm`** để chuyển sang trạng thái **In production** là hoàn tất!

### 7.3. Bước 3: Tạo khóa kết nối Android (`Clients`)
1. Ở menu trái của Google Auth Platform, chọn **`Clients`** $\rightarrow$ Bấm **+ Create Client** (hoặc trong **Credentials** $\rightarrow$ **+ Create Credentials** $\rightarrow$ **OAuth client ID**).
2. **Application type:** Chọn **`Android`**.
3. Điền 2 thông số định danh ứng dụng:
   * **Package name:**
     ```text
     com.example.meeting_book_application
     ```
   * **SHA-1 certificate fingerprint (Mã khóa máy hiện tại):**
     ```text
     4C:D3:2A:DA:6D:DA:71:91:32:3A:B7:56:B1:B2:E3:A3:D0:CC:76:DC
     ```
4. Bấm **Create** để hoàn tất (không cần tải file JSON về máy vì Android tự xác thực qua cặp `Package name` + `SHA-1`).

> **Mẹo lấy mã SHA-1 khi chuyển sang máy tính khác để lập trình:**
> Mở PowerShell trên Windows và chạy lệnh sau để lấy mã SHA-1 của máy tính mới rồi thêm vào mục `Clients` trên Google Cloud:
> ```powershell
> & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -keypass android | Select-String "SHA1"
> ```

### 7.4. Lệnh cài đặt thư viện kết nối Google Drive & Kiểm tra mạng trong Flutter
```bash
flutter pub add google_fonts "google_sign_in:^6.2.2" googleapis http shared_preferences connectivity_plus
```

### 7.5. Nguyên lý Hoạt động của Cơ chế Đăng nhập & Kết nối Google Drive
1. **Kiểm tra mạng & Mở bảng chọn tài khoản Google chính thống (`LoginScreen` & `AuthService`):**
   * Trên màn hình `LoginScreen`, khi người dùng bấm nút **"Kết nối tài khoản Google"**, ứng dụng kiểm tra kết nối mạng thực tế qua `connectivity_plus` + phân giải DNS `google.com`. Nếu mất mạng, chặn đăng nhập và báo lỗi ngay trên màn hình.
   * Khi có mạng, ứng dụng bật trực tiếp bảng chọn tài khoản Google chính thống của Android (*"Choose an account"*).
2. **Ủy quyền OAuth2 & Liên kết `DriveApi` (`GoogleDriveDatasource`):**
   * Gọi `GoogleSignIn` với quyền `DriveApi.driveFileScope` (cho phép ứng dụng tạo, xem, chỉnh sửa và xóa các tệp/thư mục do chính ứng dụng tạo trên Google Drive của người dùng).
   * Ở lần đăng nhập đầu tiên, người dùng chọn tài khoản Gmail, tích chọn ô cấp quyền truy cập Google Drive và bấm **Continue**.
   * Hệ thống lấy `authHeaders` từ tài khoản vừa chọn gắn vào `GoogleAuthClient` để khởi tạo đối tượng `drive.DriveApi`.
3. **Duy trì đăng nhập tự động (`SharedPreferences` & `signInSilently`):**
   * Sau khi liên kết thành công, thông tin phiên (`is_logged_in`, `user_email`, `user_display_name`, `user_photo_url`) được lưu vào `SharedPreferences`.
   * Ở những lần mở ứng dụng tiếp theo, `AuthGateScreen` (`app.dart`) tự động kiểm tra phiên đã lưu và gọi `signInSilently()` để nối lại `DriveApi` ngầm, đưa người dùng vào thẳng màn hình `HomeScreen` mà không cần đăng nhập lại.
4. **Quản lý Tài khoản & Đăng xuất (`UserProfileDialog`):**
   * Tại góc bên phải của ô tìm kiếm trên Header có nút **Icon User**. Khi bấm vào sẽ hiển thị tên, địa chỉ Email đang đăng nhập, trạng thái liên kết Google Drive và nút **Đăng xuất**.
   * Chỉ khi người dùng chủ động bấm **Đăng xuất**, ứng dụng mới ngắt phiên `GoogleSignIn`, xóa `SharedPreferences` và quay trở về màn hình `LoginScreen`.

### 7.6. Hướng dẫn Xuất file `.apk` để gửi cho người khác cài đặt & sử dụng
1. **Chạy lệnh đóng gói `.apk` tại Terminal dự án:**
   ```powershell
   flutter build apk --release
   ```
2. **Đường dẫn lấy file `.apk` sau khi xuất xong:**
   * `build\app\outputs\flutter-apk\app-release.apk`
3. **Lưu ý về chữ ký SHA-1, R8 Minifier & Quyền đăng nhập:**
   * Cấu hình `release` trong `android/app/build.gradle.kts` đã tắt `isMinifyEnabled = false` và `isShrinkResources = false` (tránh R8 cắt nhầm class `WorkDatabase` của Google ML Kit gây văng app khi khởi chạy) và dùng chung chữ ký `signingConfigs.getByName("debug")` trên máy tính phát triển, nên file `app-release.apk` xuất ra giữ nguyên mã **SHA-1** đã khai báo trên Google Cloud Console.
   * Trong `android/app/src/main/AndroidManifest.xml` đã khai báo đầy đủ quyền `INTERNET`, `ACCESS_NETWORK_STATE` và `android:resizeableActivity="true"`.
   * Bất kỳ thiết bị Android nào cài file `.apk` này đều đăng nhập Gmail và tự động khởi tạo cây thư mục `MeetingBook/` riêng trên Google Drive của người đó (kết hợp với **Cách 1** hoặc **Cách 2** tại mục **7.2**).
