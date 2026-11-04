# TÀI LIỆU KỸ THUẬT: ỨNG DỤNG VỞ GHI CHÉP Ô LY THÔNG MINH TRÊN TABLET ANDROID (FLUTTER)

## Note
1. Phải dùng các thuộc tính tự co dãn
2. Phải dùng theo màu theme

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
* **Lưu trữ trên thiết bị (Local Storage):** Lưu cấu trúc Sổ tay $\rightarrow$ Trang $\rightarrow$ Dòng dưới dạng **JSON** (hoặc cơ sở dữ liệu nội bộ **Isar / SQLite**).
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
* **Sao lưu đám mây không cần Server (Cloud Backup):** Tích hợp `google_sign_in` và `googleapis` để tự động đồng bộ file JSON/Database vào thư mục ẩn `appDataFolder` trên **Google Drive cá nhân** của chính người dùng khi có kết nối mạng.
* **Xuất file PDF Vector:** Dùng package `pdf` và `printing` của Dart để vẽ lại lưới ô ly và các dòng chữ ra file `.pdf` chuẩn A4 trong chưa đầy 0.5 giây.

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
│   │   ├── paper_dimensions.dart            # Kích thước chuẩn A4 (800x1131), chiều cao dòng (lineHeight = 40)
│   │   └── app_colors.dart                  # Màu đường kẻ ô ly xanh, lề đỏ, màu nền giấy chống mỏi mắt
│   ├── theme/
│   │   └── app_theme.dart                   # Cấu hình font chữ (font viết tay), theme sáng/tối
│   └── utils/
│       └── coordinate_converter.dart        # Hàm chuyển đổi tọa độ Y của bút -> chỉ số dòng (rowIndex)
│
├── data/                                    # Tầng dữ liệu (Local JSON / SQLite / Cloud)
│   ├── models/
│   │   ├── notebook_model.dart              # Thông tin cuốn vở (id, tên, loại mẫu giấy, ngày tạo)
│   │   ├── page_model.dart                  # Thông tin trang giấy (số trang, danh sách dòng)
│   │   ├── line_model.dart                  # Dữ liệu từng dòng (rowIndex, text đã nhận diện)
│   │   └── stroke_point_model.dart          # Tọa độ nét bút tạm (x, y, pressure, timestamp)
│   ├── datasources/
│   │   ├── local_storage_datasource.dart    # Đọc/ghi file JSON hoặc Database trên bộ nhớ máy
│   │   └── google_drive_datasource.dart     # Đồng bộ sao lưu lên Google Drive cá nhân
│   └── repositories/
│       └── notebook_repository.dart         # Trung gian cung cấp dữ liệu cho tầng Controller
│
├── services/                                # Các dịch vụ xử lý độc lập với giao diện
│   ├── handwriting_recognition_service.dart # Gọi Google ML Kit chuyển nét vẽ thành chuỗi văn bản
│   ├── pdf_export_service.dart              # Vẽ lại lưới ô ly + chữ và xuất ra file .pdf chuẩn A4
│   └── stylus_input_filter.dart             # Lọc sự kiện chỉ nhận Bút cảm ứng & Chuột, chặn cảm ứng tay
│
├── widgets/                                 # Các Widget dùng chung cho toàn bộ ứng dụng
│
└── features/                                # Chia theo các mô-đun màn hình tính năng
    └── home/                                # Màn hình Home chính của ứng dụng
        ├── controllers/
        │   └── home_controller.dart         # Quản lý trạng thái và logic màn hình Home
        └── views/
            ├── home_screen.dart             # Giao diện chính của màn hình Home
            └── widgets/                     # Các widget con chỉ dùng riêng trong màn hình Home
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
  * **`local_storage_datasource.dart`**: Trực tiếp đọc/ghi dữ liệu cuốn vở xuống bộ nhớ thiết bị dưới dạng file `.json` (hoặc SQLite/Isar) để đảm bảo tốc độ mở vở tức thì khi không có mạng.
  * **`google_drive_datasource.dart`**: Giao tiếp với Google Drive REST API (vào vùng ẩn `appDataFolder`) để sao lưu và khôi phục các file JSON của người dùng.
* **`repositories/`**:
  * **`notebook_repository.dart`**: Lớp trung gian gom nhóm `local_storage_datasource` và `google_drive_datasource`. Các Controller ở tầng giao diện chỉ cần gọi hàm của Repository (ví dụ: `savePage()`, `getAllNotebooks()`) mà không cần quan tâm dữ liệu được lưu cụ thể như thế nào.

#### D. Tầng `services/` (Các Dịch vụ Xử lý Chuyên biệt)
Chứa các mô-đun xử lý kỹ thuật độc lập, không phụ thuộc vào trạng thái của Widget:
* **`handwriting_recognition_service.dart`**: Quản lý vòng đời của `DigitalInkRecognizer` (Google ML Kit). Đảm nhận việc kiểm tra/tải model ngôn ngữ tiếng Việt (`vi`), nhận danh sách các nét vẽ (`List<StrokePointModel>`) và trả về chuỗi văn bản hoàn chỉnh.
* **`pdf_export_service.dart`**: Sử dụng thư viện `pdf` để tái tạo lại chính xác hệ thống lưới ô ly (hoặc dòng kẻ ngang) và in từng dòng chữ (`LineModel`) lên trang PDF vector chuẩn A4 để xuất file hoặc in ấn.
* **`stylus_input_filter.dart`**: Bộ lọc phần cứng giúp phân biệt tín hiệu từ Bút cảm ứng (`stylus`, `invertedStylus`) và Chuột (`mouse`) với cảm ứng ngón tay/bàn tay (`touch`), thực hiện cơ chế chống tì tay (Palm Rejection) khi viết.

#### E. Tầng `features/` (Các Mô-đun Tính năng Giao diện & Điều khiển)
Chia ứng dụng thành 2 màn hình chức năng độc lập:

1. **`features/library/` (Mô-đun Kệ sách)**:
   * **`controllers/library_controller.dart`**: Quản lý trạng thái danh sách các cuốn vở, xử lý các thao tác: tạo vở mới, đổi tên vở, xóa vở, hoặc kích hoạt đồng bộ Google Drive.
   * **`views/library_screen.dart`**: Giao diện chính hiển thị lưới (Grid) các cuốn vở của người dùng.
   * **`views/widgets/notebook_card_widget.dart`**: Widget hiển thị bìa của từng cuốn vở kèm tên, ngày chỉnh sửa gần nhất và nhãn loại giấy (4 ô ly / 5 ô ly).

2. **`features/notebook_editor/` (Mô-đun Viết vở & Vẽ ô ly - Trái tim của ứng dụng)**:
   * **`controllers/`**:
     * **`editor_controller.dart`**: Quản lý trạng thái của cuốn vở đang mở (trang hiện tại, thêm trang mới, đổi mẫu giấy `paperTemplate`). Đặc biệt, chịu trách nhiệm nhận chuỗi văn bản từ AI, chèn vào đúng `rowIndex`, tự động ngắt dòng (`word-wrap`) xuống `rowIndex + 1` nếu chữ tràn lề phải, và tự động lưu xuống máy.
     * **`ink_canvas_controller.dart`**: Quản lý mảng nét bút tươi đang được viết trên màn hình và điều khiển bộ đếm **`Debounce Timer` (600ms)**. Khi hết thời gian chờ mà người dùng không viết thêm nét mới, Controller này sẽ gửi nét vẽ sang `HandwritingRecognitionService`, xóa nét mực tạm và chuyển văn bản kết quả sang `EditorController`.
   * **`views/`**:
     * **`notebook_editor_screen.dart`**: Bố cục màn hình soạn thảo gồm thanh công cụ ở trên (`EditorToolbarWidget`) và vùng không gian chứa trang giấy ở giữa hỗ trợ phóng to/thu nhỏ (`InteractiveViewer`).
   * **`views/painters/` (Tối ưu hóa đồ họa 60–120fps)**:
     * **`base_paper_painter.dart`**: Lớp trừu tượng (`abstract class`) định nghĩa khung vẽ nền giấy, đường lề đỏ dọc và phần tiêu đề trang.
     * **`oly_grid_painter.dart`**: Kế thừa từ `BasePaperPainter`, dùng vòng lặp vẽ hệ thống đường kẻ ngang/dọc nét đậm và nét đứt/mảnh để tạo thành lưới **vở 4 ô ly hoặc 5 ô ly** chuẩn Việt Nam.
     * **`ruled_line_painter.dart`**: Kế thừa từ `BasePaperPainter`, chỉ vẽ các đường kẻ ngang đơn giản dành cho chế độ ghi chép nhanh/họp hành.
     * **`active_ink_painter.dart`**: Lớp vẽ nằm đè lên trên cùng, kết hợp thuật toán `perfect_freehand` để vẽ nét mực tươi mềm mại theo lực nhấn của bút cảm ứng trong thời gian thực (chỉ vẽ lại lớp này khi bút di chuyển, không vẽ lại nền giấy ô ly bên dưới).
   * **`views/widgets/`**:
     * **`page_sheet_widget.dart`**: Tổ hợp một trang giấy hoàn chỉnh bằng `Stack`, xếp chồng 3 lớp theo thứ tự từ dưới lên:
       1. Lớp nền giấy ô ly (`CustomPaint` với `OlyGridPainter` / `RuledLinePainter`).
       2. Lớp hiển thị các dòng văn bản đã nhận diện (`List<LineTextSlotWidget>`).
       3. Lớp bắt sự kiện bút cảm ứng (`Listener` dùng `StylusInputFilter`) và hiển thị nét mực đang viết (`ActiveInkPainter`).
     * **`line_text_slot_widget.dart`**: Đặt cố định tại tọa độ `top = topMargin + rowIndex * lineHeight`, căn chỉnh baseline của chữ sao cho chân chữ nằm khớp hoàn hảo ngay trên đường kẻ ngang đậm của dòng ô ly đó (đồng thời cho phép chạm đúp để sửa lại bằng bàn phím nếu cần).
     * **`editor_toolbar_widget.dart`**: Thanh công cụ phía trên cho phép chuyển trang, đổi mẫu giấy tức thì (4 ô ly $\leftrightarrow$ 5 ô ly $\leftrightarrow$ Kẻ ngang), chọn màu mực, xóa dòng và bấm xuất file PDF.

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

### 5.2. Lệnh cài đặt các thư viện (Packages) cốt lõi
```bash
flutter pub add google_mlkit_digital_ink_recognition perfect_freehand pdf printing path_provider google_fonts
```

---

## 6. Lộ trình Triển khai Đề xuất (5 Giai đoạn)
1. **Giai đoạn 1 (UI Nền tảng):** Viết `paper_dimensions.dart` và `oly_grid_painter.dart` để hiển thị mặt giấy kẻ ô ly chuẩn tỷ lệ A4 lên máy ảo Xiaomi Pad 8.
2. **Giai đoạn 2 (Bút cảm ứng & Nét vẽ):** Viết `stylus_input_filter.dart` và `active_ink_painter.dart` để dùng chuột/bút vẽ nét mực mượt lên dòng kẻ và tính chính xác `rowIndex` nơi bút đang chạm.
3. **Giai đoạn 3 (Tích hợp AI Nhận diện chữ):** Kết nối `handwriting_recognition_service.dart` với bộ đếm `Debounce 600ms` để biến nét vẽ thành văn bản tiếng Việt và điền tự động vào dòng kẻ.
4. **Giai đoạn 4 (Phân trang & Lưu trữ):** Hoàn thiện `editor_controller.dart` để tự động đẩy chữ tràn sang dòng/trang mới và lưu toàn bộ cuốn vở thành file JSON trong bộ nhớ máy.
5. **Giai đoạn 5 (Xuất PDF & Đồng bộ Google Drive):** Hoàn thiện `pdf_export_service.dart` để xuất file PDF có kèm lưới ô ly và sao lưu tự động lên Google Drive.