import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;
import '../data/models/stroke_point_model.dart';

// ===========================================================================
// DỊCH VỤ AI NHẬN DIỆN CHỮ VIẾT TAY TIẾNG VIỆT TRÊN THIẾT BỊ (GOOGLE ML KIT)
// Công dụng:
// - Tự động kiểm tra và tải gói ngôn ngữ Tiếng Việt ('vi') của Google ML Kit
//   về thiết bị ở lần sử dụng đầu tiên (chạy Offline 100% ở các lần sau).
// - Nhận danh sách các nét bút (List<InkStrokeModel>) kèm ngữ cảnh chữ đứng trước
//   (preContext) và kích thước vùng viết (WritingArea) để chuyển nét vẽ thành
//   chuỗi văn bản Tiếng Việt có dấu chuẩn xác.
// ===========================================================================
class HandwritingRecognitionService {
  HandwritingRecognitionService._internal();
  static final HandwritingRecognitionService instance =
      HandwritingRecognitionService._internal();

  static const String _vietnameseLanguageTag = 'vi';

  final mlkit.DigitalInkRecognizerModelManager _modelManager =
      mlkit.DigitalInkRecognizerModelManager();
  mlkit.DigitalInkRecognizer? _recognizer;

  /// Trạng thái đang tải gói nhận diện chữ viết tay Tiếng Việt lần đầu
  final ValueNotifier<bool> isDownloadingModelNotifier =
      ValueNotifier<bool>(false);

  /// Trạng thái gói ngôn ngữ Tiếng Việt đã sẵn sàng trên máy
  final ValueNotifier<bool> isModelReadyNotifier = ValueNotifier<bool>(false);

  bool _isCheckingModel = false;

  /// Kiểm tra và tải trước gói AI nhận diện chữ viết tay Tiếng Việt ('vi') nếu chưa có
  Future<bool> ensureModelDownloaded() async {
    if (isModelReadyNotifier.value && _recognizer != null) {
      return true;
    }
    if (_isCheckingModel) {
      // Đợi nếu đang có tiến trình kiểm tra/tải model chạy song song
      while (_isCheckingModel) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      return isModelReadyNotifier.value;
    }

    _isCheckingModel = true;
    try {
      _recognizer ??= mlkit.DigitalInkRecognizer(
        languageCode: _vietnameseLanguageTag,
      );

      final bool isDownloaded =
          await _modelManager.isModelDownloaded(_vietnameseLanguageTag);
      if (!isDownloaded) {
        isDownloadingModelNotifier.value = true;
        final bool success = await _modelManager.downloadModel(
          _vietnameseLanguageTag,
          isWifiRequired: false,
        );
        isDownloadingModelNotifier.value = false;
        isModelReadyNotifier.value = success;
        return success;
      }

      isModelReadyNotifier.value = true;
      return true;
    } catch (e) {
      debugPrint('Lỗi kiểm tra/tải model nhận diện chữ viết tay Tiếng Việt: $e');
      isDownloadingModelNotifier.value = false;
      return false;
    } finally {
      _isCheckingModel = false;
    }
  }

  /// Chuyển đổi mảng nét vẽ trên Bottom Sheet thành chuỗi văn bản Tiếng Việt
  Future<String> recognizeStrokes({
    required List<InkStrokeModel> strokes,
    String? preContext,
    double? writingAreaWidth,
    double? writingAreaHeight,
  }) async {
    if (strokes.isEmpty) return '';

    final bool ready = await ensureModelDownloaded();
    if (!ready || _recognizer == null) {
      return '';
    }

    final mlkit.Ink ink = mlkit.Ink();
    for (final InkStrokeModel strokeModel in strokes) {
      if (strokeModel.points.isEmpty) continue;
      final mlkit.Stroke mlStroke = mlkit.Stroke();
      for (final StrokePointModel pt in strokeModel.points) {
        mlStroke.points.add(
          mlkit.StrokePoint(
            x: pt.x,
            y: pt.y,
            t: pt.timestampMs,
          ),
        );
      }
      ink.strokes.add(mlStroke);
    }

    if (ink.strokes.isEmpty) return '';

    try {
      final mlkit.WritingArea? area = (writingAreaWidth != null &&
              writingAreaHeight != null &&
              writingAreaWidth > 0 &&
              writingAreaHeight > 0)
          ? mlkit.WritingArea(
              width: writingAreaWidth,
              height: writingAreaHeight,
            )
          : null;

      final String? cleanPreContext =
          (preContext != null && preContext.isNotEmpty)
              ? (preContext.length > 20
                  ? preContext.substring(preContext.length - 20)
                  : preContext)
              : null;

      final List<mlkit.RecognitionCandidate> candidates =
          await _recognizer!.recognize(
        ink,
        context: mlkit.DigitalInkRecognitionContext(
          preContext: cleanPreContext,
          writingArea: area,
        ),
      );

      if (candidates.isNotEmpty) {
        return candidates.first.text.trim();
      }
    } catch (e) {
      debugPrint('Lỗi khi nhận diện nét bút: $e');
    }
    return '';
  }

  Future<void> disposeService() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
