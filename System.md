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

### 3.4. Lưu trữ Dữ liệu, Đổi mẫu giấy & Xuất file PDF (Thay thế LaTeX)
Thay vì dùng trình biên dịch LaTeX (`.tex`) nặng nề và gây trễ khi vẽ thời gian thực, sử dụng kiến trúc **JSON + `CustomPainter` + Package `pdf`**:
* **Định dạng dữ liệu nhẹ (Lightweight JSON):** Lưu cấu trúc Thư mục $\rightarrow$ Sổ tay $\rightarrow$ Trang $\rightarrow$ Dòng dưới dạng **JSON** (chỉ nặng vài KB, không gây nặng bộ nhớ máy).
* **Đổi kiểu mẫu giấy (Template Switching):** Chỉ cần thay đổi thuộc tính `"paperTemplate"` (`"oly_5_ly"`, `"oly_4_ly"`, `"ruled_line"`, `"cornell"`), `CustomPainter` trên màn hình và bộ xuất `pdf` sẽ tự động vẽ lại nền giấy tương ứng mà giữ nguyên toàn bộ các dòng chữ đã viết.
* **Cấu trúc JSON mẫu của một trang vở:**
  ```json
  {
    "pageNumber": 1,
    "paperTemplate": "oly_5_ly",
    "fontFamily": "PatrickHand",
    "fontSize": 22.0,
    "lines": [
      { "rowIndex": 0, "text": "Thứ Tư, ngày 4 tháng 11 năm 2026" },
      { "rowIndex": 1, "text": "Bài 1: Kiến trúc ứng dụng vở ô ly Flutter" },
      { "rowIndex": 2, "text": "Ghi chép bằng bút cảm ứng tự động chuyển thành chữ." }
    ]
  }
  ```
* **Xuất file PDF Vector (Khi cần chia sẻ/in ấn):** Dùng package `pdf` và `printing` của Dart để vẽ lại lưới ô ly và các dòng chữ ra file `.pdf` chuẩn A4 trong chưa đầy 0.5 giây.

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

## 4. Cấu trúc Thư mục Dự án (`lib/`)

Dự án được tổ chức theo kiến trúc **Feature-First kết hợp Clean Architecture rút gọn (Layered Architecture)**, giúp tách biệt rõ ràng giữa giao diện (UI/Painters), logic điều khiển (Controllers), dịch vụ hệ thống/AI (Services) và tầng dữ liệu (Data).

### 4.1. Sơ đồ cây thư mục

```text
lib/
├── main.dart
├── app.dart
│
├── core/                                    # Cấu hình & hằng số dùng chung toàn app
│   ├── constants/
│   │   ├── app_colors.dart                  # Bảng màu chuẩn theo Theme (#263BAA, #FFF4D6, #FFFFFF, #000000)
│   │   ├── note5x.dart                      # Định dạng vở 5 ô ly (chỉ vẽ đường ngang, tự co giãn theo 5 ô ly)
│   │   └── note4x.dart                      # Định dạng vở 4 ô ly (chỉ vẽ đường ngang, tự co giãn theo 4 ô ly)
│   ├── theme/
│   │   └── app_theme.dart                   # Cấu hình font chữ Be Vietnam Pro, hàm tự động co giãn cỡ chữ
│   └── utils/
│       └── coordinate_converter.dart        # Hàm chuyển đổi tọa độ Y của bút -> chỉ số dòng (rowIndex)
│
├── data/                                    # Tầng dữ liệu (RAM tạm thời & Đồng bộ Google Drive)
│   ├── models/
│   │   ├── notebook_model.dart              # Thông tin cuốn vở (id, tên, loại mẫu giấy, ngày tạo)
│   │   ├── page_model.dart                  # Thông tin trang giấy (số trang, danh sách dòng)
│   │   ├── line_model.dart                  # Dữ liệu từng dòng (rowIndex, text đã nhận diện)
│   │   └── stroke_point_model.dart          # Tọa độ nét bút tạm (x, y, pressure, timestamp)
│   ├── datasources/
│   │   ├── local_storage_datasource.dart    # Lưu tạm dữ liệu JSON tức thì trên RAM (_ramCache, 0ms, không ghi ổ cứng máy)
│   │   └── google_drive_datasource.dart     # Đồng bộ sao lưu lên Google Drive cá nhân
│   └── repositories/
│       └── data_sync_repository.dart        # Trung gian đồng bộ RAM & Google Drive (Bộ đếm 30s & 3 thời điểm)
│
├── services/                                # Các dịch vụ xử lý độc lập với giao diện
│   ├── handwriting_recognition_service.dart # Gọi Google ML Kit chuyển nét vẽ thành chuỗi văn bản
│   ├── pdf_export_service.dart              # Vẽ lại lưới ô ly + chữ và xuất ra file .pdf chuẩn A4
│   └── stylus_input_filter.dart             # Lọc sự kiện chỉ nhận Bút cảm ứng & Chuột, chặn cảm ứng tay
│
├── widgets/                                 # Các Widget dùng chung cho toàn bộ ứng dụng
│   ├── app_header_widget.dart               # Header dùng chung (Ô tìm kiếm + Icon User + Thanh chuyển Tab)
│   └── user_profile_dialog.dart             # Hộp thoại hiển thị Email đăng nhập & nút Đăng xuất
│
└── features/                                # Chia theo các mô-đun màn hình tính năng
    ├── auth/                                # Màn hình Đăng nhập & Xác thực Google Drive
    │   ├── service/
    │   │   └── auth_service.dart            # Logic đăng nhập, kiểm tra phiên và đăng xuất
    │   └── views/
    │       └── login_screen.dart            # Giao diện màn hình Đăng nhập Google Drive
    │
    ├── home/                                # Màn hình Home chính của ứng dụng
    │   ├── controllers/
    │   │   └── home_controller.dart         # Quản lý trạng thái màn hình Home
    │   ├── service/                         # Tầng xử lý logic riêng của màn hình Home
    │   │   └── home_service.dart            # Xử lý logic tìm kiếm, đổi tab, mở Bottom Sheet tạo mới
    │   └── views/
    │       ├── home_screen.dart             # Giao diện chính của màn hình Home
    │       └── widgets/                     # Các widget con chỉ dùng riêng trong màn hình Home
    │           └── create_item_bottom_sheet.dart # Bottom Sheet trượt lên khi bấm nút (+)
    │
    ├── notes/                               # Tab 1: Màn hình Ghi chú
    │   ├── controllers/
    │   │   └── notes_controller.dart
    │   └── views/
    │       ├── notes_screen.dart
    │       └── widgets/
    │
    └── observation_book/                    # Tab 2: Màn hình Sổ dự giờ
        ├── controllers/
        │   └── observation_book_controller.dart
        └── views/
            ├── observation_book_screen.dart
            └── widgets/
```

### 4.2. Giải thích chi tiết từng phân tầng & tệp tin

#### A. Khởi tạo ứng dụng (`Root`)
* **`main.dart`**: Điểm bắt đầu của ứng dụng (`void main()`), khởi tạo `WidgetsFlutterBinding`, cấu hình hướng màn hình, tải trước các tài nguyên thiết yếu (như kiểm tra gói ngôn ngữ ML Kit tiếng Việt) và chạy `runApp()`.
* **`app.dart`**: Chứa Widget gốc (`MaterialApp`), thiết lập `AppTheme`, cấu hình điều hướng (Routing) giữa màn hình Kệ sách (`LibraryScreen`) và màn hình Viết vở (`NotebookEditorScreen`).

#### B. Tầng `core/` (Cấu hình, Hằng số & Tiện ích dùng chung)
Chứa các giá trị bất biến và hàm tính toán thuần túy được sử dụng xuyên suốt từ lúc vẽ UI cho đến lúc xuất PDF:
* **`constants/paper_dimensions.dart`**: Định nghĩa hệ tọa độ logic chuẩn A4 (`width = 800.0`, `height = 1131.0`), chiều cao mỗi dòng kẻ lớn (`lineHeight = 40.0`), lề trên (`topMargin`), lề trái đường kẻ đỏ (`leftMargin`), và số ô ly nhỏ trong một dòng (4 hoặc 5 ô ly).
* **`constants/app_colors.dart`**: Quản lý bảng màu chuẩn của vở học sinh Việt Nam (màu nền giấy vàng kem chống mỏi mắt `#FDFBF7`, màu xanh cyan của dòng kẻ ô ly, màu đỏ của đường lề dọc, màu mực bút xanh/đen/đỏ).
* **`theme/app_theme.dart`**: Thiết lập giao diện tổng thể cho ứng dụng và cấu hình các bộ font chữ viết tay tiếng Việt (như *Patrick Hand*, *Mali*, hoặc *Caveat*) để văn bản sau khi nhận diện có cảm giác tự nhiên như chữ viết thật.
* **`utils/coordinate_converter.dart`**: Chứa các hàm toán học chuyển đổi tọa độ điểm chạm thực tế $(X, Y)$ của bút cảm ứng trên vùng trang giấy sang chỉ số dòng (`rowIndex`) và kiểm tra xem điểm chạm có nằm trong vùng viết hợp lệ hay không.

#### C. Tầng `data/` (Quản lý Dữ liệu & Lưu trữ)
Đảm nhận việc định nghĩa cấu trúc dữ liệu, lưu trữ nội bộ (Offline) và đồng bộ đám mây (Cloud):
* **`models/`**:
  * **`notebook_model.dart`**: Đối tượng đại diện cho một cuốn vở (gồm `id`, `title`, `paperTemplate`, `createdAt`, `updatedAt`, và danh sách các trang).
  * **`page_model.dart`**: Đối tượng đại diện cho một trang giấy cụ thể trong cuốn vở (gồm `pageNumber`, `paperTemplate` riêng nếu có, và danh sách ` List<LineModel>`).
  * **`line_model.dart`**: Lưu nội dung văn bản của một dòng kẻ (`rowIndex`, chuỗi `text` đã được AI nhận diện, kiểu căn lề hoặc màu chữ).
  * **`stroke_point_model.dart`**: Lưu tọa độ điểm của nét bút tạm thời (`x`, `y`, lực nhấn `pressure`, thời gian `timestamp`) phục vụ cho việc dựng nét mực mượt và gửi sang bộ nhận diện ML Kit.
* **`datasources/`**:
  * **`local_storage_datasource.dart`**: Chỉ lưu tạm nội dung vở đang viết trực tiếp trên bộ nhớ RAM (`_ramCache`, tốc độ `0ms`), tuyệt đối không ghi nội dung vở xuống ổ cứng của máy.
  * **`google_drive_datasource.dart`**: Giao tiếp với Google Drive REST API để lưu trữ và đồng bộ các file JSON trên Google Drive cá nhân của người dùng.
* **`repositories/`**:
  * **`data_sync_repository.dart`**: Lớp trung gian quản lý lưu tức thì trên RAM (`local_storage_datasource`) và đồng bộ lên Google Drive (`google_drive_datasource`) ở 3 thời điểm vàng hoặc khi bấm nút Lưu.

#### D. Tầng `services/` (Các Dịch vụ Xử lý Chuyên biệt)
Chứa các mô-đun xử lý kỹ thuật độc lập, không phụ thuộc vào trạng thái của Widget:
* **`handwriting_recognition_service.dart`**: Quản lý vòng đời của `DigitalInkRecognizer` (Google ML Kit). Đảm nhận việc kiểm tra/tải model ngôn ngữ tiếng Việt (`vi`), nhận danh sách các nét vẽ (`List<StrokePointModel>`) và trả về chuỗi văn bản hoàn chỉnh.
* **`pdf_export_service.dart`**: Sử dụng thư viện `pdf` để tái tạo lại chính xác hệ thống lưới ô ly (hoặc dòng kẻ ngang) và in từng dòng chữ (`LineModel`) lên trang PDF vector chuẩn A4 để xuất file hoặc in ấn.
* **`stylus_input_filter.dart`**: Bộ lọc phần cứng giúp phân biệt tín hiệu từ Bút cảm ứng (`stylus`, `invertedStylus`) và Chuột (`mouse`) với cảm ứng ngón tay/bàn tay (`touch`), thực hiện cơ chế chống tì tay (Palm Rejection) khi viết.

#### E. Tầng `widgets/` & `features/` (Các Mô-đun Tính năng Giao diện & Điều khiển)
* **`widgets/app_header_widget.dart`**: Widget Header dùng chung toàn ứng dụng, tích hợp ô tìm kiếm tự co giãn, nút Menu 3 gạch và thanh chuyển đổi Tab (`TabBar`).
* **`features/home/` (Màn hình Home chính)**:
  * **`service/home_service.dart`**: Chứa toàn bộ logic xử lý của màn hình Home (xác định chữ gợi ý tìm kiếm theo từng Tab, mở Bottom Sheet tương ứng với Tab đang chọn, xử lý tạo Ghi chú mới / Sổ dự giờ mới / Thêm thư mục mới).
  * **`controllers/home_controller.dart`**: Quản lý trạng thái dữ liệu của màn hình Home.
  * **`views/home_screen.dart`**: Giao diện khung chính kết nối Header, vùng nội dung `TabBarView`, nút nổi `+` và thanh Footer.
  * **`views/widgets/create_item_bottom_sheet.dart`**: Giao diện Bottom Sheet trượt từ dưới lên (hỗ trợ vuốt tắt, nút `X` đóng bên phải, tràn full chiều ngang màn hình).
* **`features/notes/` (Mô-đun Tab Ghi chú)**: Quản lý giao diện và chức năng riêng của danh sách Ghi chú / Nhật ký.
* **`features/observation_book/` (Mô-đun Tab Sổ dự giờ)**: Quản lý giao diện và chức năng riêng của danh sách Sổ dự giờ.

---

## 5. Các lệnh Khởi tạo Nhanh (Dùng trong Git Bash / Terminal)

### 5.1. Lệnh tạo tự động toàn bộ cây thư mục và file rỗng
Chạy lệnh sau tại thư mục gốc của project Flutter:

```bash
mkdir -p lib/core/{constants,theme,utils} \
         lib/data/{models,datasources,repositories} \
         lib/services \
         lib/features/library/{controllers,views/widgets} \
         lib/features/notebook_editor/{controllers,views/{painters,widgets}} && \
touch lib/app.dart \
      lib/core/constants/{paper_dimensions.dart,app_colors.dart} \
      lib/core/utils/coordinate_converter.dart \
      lib/data/models/{notebook_model.dart,page_model.dart,line_model.dart,stroke_point_model.dart} \
      lib/services/{handwriting_recognition_service.dart,pdf_export_service.dart,stylus_input_filter.dart} \
      lib/features/notebook_editor/controllers/{editor_controller.dart,ink_canvas_controller.dart} \
      lib/features/notebook_editor/views/notebook_editor_screen.dart \
      lib/features/notebook_editor/views/painters/{oly_grid_painter.dart,active_ink_painter.dart} \
      lib/features/notebook_editor/views/widgets/{page_sheet_widget.dart,editor_toolbar_widget.dart}
```

### 5.2. Danh sách các Thư viện (Packages) sử dụng trong Dự án & Lệnh cài đặt

#### A. Các thư viện đã cài đặt và đang sử dụng:
* **`google_fonts`**: Cung cấp bộ font chữ chuẩn Google Drive (`Be Vietnam Pro`) hỗ trợ tiếng Việt và chữ viết tay.
* **`google_sign_in` (`^6.2.2`)**: Xác thực và đăng nhập tài khoản Google trên thiết bị Android.
* **`googleapis`**: Cung cấp bộ thư viện `DriveApi` (`v3`) để tạo thư mục, tải lên và ghi đè file JSON trên Google Drive cá nhân.
* **`http`**: Tạo `GoogleAuthClient` đính kèm mã xác thực OAuth vào các yêu cầu gọi Google Drive REST API.
* **`shared_preferences`**: Lưu trạng thái duy trì đăng nhập (`is_logged_in`, `user_email`, `user_display_name`, `user_photo_url`) trên máy cho đến khi người dùng bấm Đăng xuất.
* **`connectivity_plus`**: Kiểm tra trạng thái kết nối mạng (Wi-Fi / Dữ liệu di động) khi đăng nhập và theo dõi đứt mạng giữa chừng để khóa thao tác bảo vệ dữ liệu.

```bash
flutter pub add google_fonts "google_sign_in:^6.2.2" googleapis http shared_preferences connectivity_plus
```

#### B. Các thư viện phục vụ Viết bút cảm ứng, AI Nhận diện & Xuất PDF (Cài đặt ở giai đoạn làm trang vở):
* **`google_mlkit_digital_ink_recognition`**: AI trên thiết bị (On-Device) chuyển nét vẽ viết tay thành văn bản tiếng Việt.
* **`perfect_freehand`**: Nội suy nét mực mượt mà theo lực nhấn của bút cảm ứng (Stylus).
* **`pdf` & `printing`**: Vẽ lại lưới ô ly và xuất trang vở ra file `.pdf` vector chuẩn A4.
* **`path_provider`**: Truy xuất đường dẫn bộ nhớ đệm tạm thời trên thiết bị.

```bash
flutter pub add google_mlkit_digital_ink_recognition perfect_freehand pdf printing path_provider
```

---

## 6. Lộ trình Triển khai Đề xuất (5 Giai đoạn)
1. **Giai đoạn 1 (UI Nền tảng):** Viết `paper_dimensions.dart` và `oly_grid_painter.dart` để hiển thị mặt giấy kẻ ô ly chuẩn tỷ lệ A4 lên máy ảo Xiaomi Pad 8.
2. **Giai đoạn 2 (Bút cảm ứng & Nét vẽ):** Viết `stylus_input_filter.dart` và `active_ink_painter.dart` để dùng chuột/bút vẽ nét mực mượt lên dòng kẻ và tính chính xác `rowIndex` nơi bút đang chạm.
3. **Giai đoạn 3 (Tích hợp AI Nhận diện chữ):** Kết nối `handwriting_recognition_service.dart` với bộ đếm `Debounce 600ms` để biến nét vẽ thành văn bản tiếng Việt và điền tự động vào dòng kẻ.
4. **Giai đoạn 4 (Phân trang & Lưu trữ):** Hoàn thiện `editor_controller.dart` để tự động đẩy chữ tràn sang dòng/trang mới và lưu toàn bộ cuốn vở thành file JSON trong bộ nhớ máy.
5. **Giai đoạn 5 (Xuất PDF & Đồng bộ Google Drive):** Hoàn thiện `pdf_export_service.dart` để xuất file PDF có kèm lưới ô ly và sao lưu tự động lên Google Drive.

---

## 7. Hướng dẫn Cấu hình Kết nối Google Drive Cá nhân (Google Cloud Console)

Dịch vụ hoàn toàn **miễn phí 100%** và sử dụng trực tiếp dung lượng 15GB có sẵn trên Google Drive của người đăng nhập. Bất kỳ thiết bị Android nào cài ứng dụng đều có thể đăng nhập Gmail cá nhân để tự lưu dữ liệu vào Drive của chính mình.

### 7.1. Bước 1: Tạo Project & Bật Google Drive API
1. Truy cập [Google Cloud Console](https://console.cloud.google.com/) và đăng nhập bằng tài khoản Gmail.
2. Bấm vào ô chọn dự án ở góc trên bên trái $\rightarrow$ Chọn **New Project** $\rightarrow$ Đặt tên dự án (ví dụ: `Meeting Booking`) $\rightarrow$ Bấm **Create**.
3. Vào menu bên trái: **APIs & Services** $\rightarrow$ **Library**.
4. Tìm kiếm **`Google Drive API`** $\rightarrow$ Bấm chọn và nhấn **Enable (Bật)**.

### 7.2. Bước 2: Thiết lập Google Auth Platform (OAuth Consent Screen)
Vào **APIs & Services** $\rightarrow$ **OAuth consent screen** (giao diện **Google Auth Platform**):
1. **Mục `Overview`:**
   * Bấm nút **Get started** (Bắt đầu).
   * **App name:** Điền `Meeting Book`.
   * **User support email:** Chọn Gmail của bạn.
   * **Audience:** Chọn **External** (Cho phép mọi tài khoản Gmail cá nhân đăng nhập).
   * **Contact Information:** Nhập email liên hệ $\rightarrow$ Tích đồng ý điều khoản và bấm **Create**.
2. **Mục `Audience`:**
   * Kéo xuống phần **Test users** $\rightarrow$ Bấm **+ Add users**.
   * Nhập địa chỉ Gmail cá nhân sẽ dùng để đăng nhập trên máy tính bảng/điện thoại (tối đa 100 Gmail thử nghiệm, hoặc bấm **Publish App** nếu muốn mở cho mọi Gmail không cần thêm tay) $\rightarrow$ Bấm **Save**.

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