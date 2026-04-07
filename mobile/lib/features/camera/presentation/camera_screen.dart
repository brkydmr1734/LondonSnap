import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:londonsnaps/core/theme/app_theme.dart';
import 'package:londonsnaps/features/auth/providers/auth_provider.dart';
import 'package:londonsnaps/core/api/api_service.dart';
import 'package:londonsnaps/core/errors/error_handler.dart';
import 'package:londonsnaps/core/errors/app_exceptions.dart';
import 'package:londonsnaps/features/social/providers/social_provider.dart';
import 'package:londonsnaps/features/memories/providers/memory_provider.dart';
import 'package:londonsnaps/shared/widgets/avatar_widget.dart';
import 'package:video_player/video_player.dart';
import 'package:londonsnaps/features/camera/widgets/overlay_models.dart';
import 'package:londonsnaps/features/camera/widgets/camera_text_overlay.dart';
import 'package:londonsnaps/features/camera/widgets/camera_drawing_overlay.dart';
import 'package:londonsnaps/features/camera/widgets/camera_sticker_overlay.dart';
import 'package:londonsnaps/features/camera/widgets/image_renderer.dart';

// ── Filters ──
enum CameraFilter { none, warm, cool, vintage, mono, vivid }

extension CameraFilterMatrix on CameraFilter {
  ColorFilter? get colorFilter {
    switch (this) {
      case CameraFilter.none:
        return null;
      case CameraFilter.warm:
        return const ColorFilter.matrix(<double>[
          1.2, 0, 0, 0, 20, 0, 1.0, 0, 0, 0,
          0, 0, 0.8, 0, 0, 0, 0, 0, 1, 0,
        ]);
      case CameraFilter.cool:
        return const ColorFilter.matrix(<double>[
          0.8, 0, 0, 0, 0, 0, 1.0, 0, 0, 0,
          0, 0, 1.2, 0, 20, 0, 0, 0, 1, 0,
        ]);
      case CameraFilter.vintage:
        return const ColorFilter.matrix(<double>[
          0.9, 0.1, 0.1, 0, 0, 0.1, 0.8, 0.1, 0, 0,
          0.1, 0.1, 0.6, 0, 0, 0, 0, 0, 1, 0,
        ]);
      case CameraFilter.mono:
        return const ColorFilter.matrix(<double>[
          0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0,
          0.33, 0.33, 0.33, 0, 0, 0, 0, 0, 1, 0,
        ]);
      case CameraFilter.vivid:
        return const ColorFilter.matrix(<double>[
          1.4, -0.1, -0.1, 0, 0, -0.1, 1.4, -0.1, 0, 0,
          -0.1, -0.1, 1.4, 0, 0, 0, 0, 0, 1, 0,
        ]);
    }
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  final AuthProvider _authProvider = AuthProvider();
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isFrontCamera = false;
  FlashMode _flashMode = FlashMode.off;
  final CameraFilter _selectedFilter = CameraFilter.none;
  bool _screenFlashActive = false;

  // Captured state
  File? _capturedImage;
  File? _capturedVideo;
  bool _isUploading = false;

  // Video recording state
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  static const int _maxRecordingSeconds = 60;

  // Video preview
  VideoPlayerController? _videoPlayerController;
  bool _isVideoPlaying = true;

  // Overlay state
  List<TextOverlayItem> _textOverlays = [];
  List<DrawingPath> _drawingPaths = [];
  List<StickerItem> _stickers = [];
  String? _activeOverlayMode; // 'text', 'draw', or null
  
  // Drawing state
  Color _drawingColor = Colors.white;
  double _drawingStrokeWidth = 5.0;
  DrawingPath? _currentDrawingPath;
  DrawingTool _drawingTool = DrawingTool.pen;

  // Trash zone state
  bool _showTrashZone = false;

  // Text editing state
  TextOverlayItem? _editingTextItem;
    
  // For preview size calculation
  final GlobalKey _previewKey = GlobalKey();
  
  // Snapchat-style zoom levels with pinch-to-zoom
  double _currentZoom = 1.0;
  double _baseZoom = 1.0; // For pinch gesture tracking
  double _minZoom = 1.0;
  double _maxZoom = 10.0;
  bool _showZoomIndicator = false;
  Timer? _zoomIndicatorTimer;
  final List<double> _zoomPresets = [1.0, 2.0]; // Quick-tap presets
  
  // Tap-to-focus state
  Offset? _focusPoint;
  bool _showFocusIndicator = false;
  late AnimationController _focusAnimationController;
  late Animation<double> _focusAnimation;
  Timer? _focusTimer;
  
  // Exposure control
  double _exposureOffset = 0.0;
  double _minExposure = -2.0;
  double _maxExposure = 2.0;
  bool _showExposureSlider = false;
  Timer? _exposureTimer;
  
  // Camera switch animation
  late AnimationController _cameraSwitchController;
  late Animation<double> _cameraSwitchAnimation;
  bool _isSwitchingCamera = false;
  
  // Front flash animation
  late AnimationController _flashAnimationController;
  late Animation<double> _flashAnimation;
  
  // Capture button animation
  late AnimationController _captureAnimationController;
  late Animation<double> _captureScaleAnimation;
  
  // Preview aspect ratio saved at capture time to match photo display to live preview
  double _savedPreviewAspect = 0;
  
  // Filter category tabs
  int _selectedFilterTab = 1; // "For You" selected by default
  final List<String> _filterTabs = ['You', 'Look', 'Awesome', 'Today!'];
  
  // Recent gallery photos
  List<AssetEntity> _recentPhotos = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize animation controllers
    _focusAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusAnimation = Tween<double>(begin: 1.5, end: 1.0).animate(
      CurvedAnimation(parent: _focusAnimationController, curve: Curves.easeOut),
    );
    
    _cameraSwitchController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _cameraSwitchAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _cameraSwitchController, curve: Curves.easeInOut),
    );
    
    _flashAnimationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _flashAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 40), // Fade in
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 20), // Hold
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40), // Fade out
    ]).animate(_flashAnimationController);
    
    _captureAnimationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _captureScaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _captureAnimationController, curve: Curves.easeInOut),
    );
    
    _initCamera();
    _loadRecentPhotos();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _recordingTimer?.cancel();
    _videoPlayerController?.dispose();
    _zoomIndicatorTimer?.cancel();
    _focusTimer?.cancel();
    _exposureTimer?.cancel();
    _focusAnimationController.dispose();
    _cameraSwitchController.dispose();
    _flashAnimationController.dispose();
    _captureAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final cam = _isFrontCamera
          ? _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front,
              orElse: () => _cameras.first)
          : _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => _cameras.first);

      // veryHigh (1080p) for front camera keeps preview smooth while still
      // capturing high-res photos. max for rear camera for full sensor quality.
      final controller = CameraController(
        cam,
        _isFrontCamera ? ResolutionPreset.veryHigh : ResolutionPreset.max,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(_flashMode);
      
      // Initialize zoom range
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _currentZoom = 1.0;
      _baseZoom = 1.0;
      
      // Initialize exposure range
      _minExposure = await controller.getMinExposureOffset();
      _maxExposure = await controller.getMaxExposureOffset();
      _exposureOffset = 0.0;
      
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _isInitialized = true;
        _isSwitchingCamera = false;
      });
      
      // Finish camera switch animation
      if (_cameraSwitchController.value > 0) {
        _cameraSwitchController.reverse();
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
      setState(() => _isSwitchingCamera = false);
    }
  }

  Future<void> _loadRecentPhotos() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) return;
      
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common, // photos + videos
        filterOption: FilterOptionGroup(
          imageOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
          videoOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
        ),
      );
      
      if (albums.isEmpty) return;
      
      // Get "Recent" album (first one)
      final recentAlbum = albums.first;
      final assets = await recentAlbum.getAssetListRange(start: 0, end: 6);
      
      if (mounted) {
        setState(() {
          _recentPhotos = assets;
        });
      }
    } catch (e) {
      debugPrint('Failed to load recent photos: $e');
    }
  }

  Future<void> _openGalleryAsset(AssetEntity asset) async {
    try {
      final file = await asset.file;
      if (file == null) return;
      
      if (mounted) {
        // Use the same flow as gallery picker - set capturedImage or capturedVideo
        if (asset.type == AssetType.video) {
          await _initVideoPlayer(file);
          setState(() => _capturedVideo = file);
        } else {
          setState(() => _capturedImage = file);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening photo: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _flipCamera() async {
    if (_isSwitchingCamera) return;
    
    // Start fade-out animation
    setState(() => _isSwitchingCamera = true);
    await _cameraSwitchController.forward();
    
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isInitialized = false;
      // Reset zoom when switching cameras (different cameras have different ranges)
      _currentZoom = 1.0;
      _baseZoom = 1.0;
    });
    _controller?.dispose();
    _initCamera();
  }

  /// Flip an image horizontally to remove front camera mirror effect
  Future<File> _flipImageHorizontally(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final original = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(original.width.toDouble(), 0);
    canvas.scale(-1, 1);
    canvas.drawImage(original, Offset.zero, Paint()..filterQuality = FilterQuality.high);

    final picture = recorder.endRecording();
    final flipped = await picture.toImage(original.width, original.height);
    final byteData = await flipped.toByteData(format: ui.ImageByteFormat.png);

    final tempDir = await getTemporaryDirectory();
    final outputFile = File(
      '${tempDir.path}/unmirrored_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await outputFile.writeAsBytes(byteData!.buffer.asUint8List());

    original.dispose();
    flipped.dispose();
    return outputFile;
  }

  void _toggleFlash() {
    setState(() {
      _flashMode = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    });
    // Only set hardware flash for rear camera
    if (!_isFrontCamera) {
      _controller?.setFlashMode(_flashMode);
    }
  }

  void _setZoomLevel(int index) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final targetZoom = _zoomPresets[index];
    // Clamp to available zoom range
    final clampedZoom = targetZoom.clamp(_minZoom, _maxZoom);
    await _controller!.setZoomLevel(clampedZoom);
    setState(() {
      _currentZoom = clampedZoom;
      _baseZoom = clampedZoom;
    });
    _showZoomIndicatorBriefly();
  }
  
  // Pinch-to-zoom handlers
  void _onScaleStart(ScaleStartDetails details) {
    _baseZoom = _currentZoom;
  }
  
  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    final newZoom = (_baseZoom * details.scale).clamp(_minZoom, _maxZoom);
    _controller!.setZoomLevel(newZoom);
    setState(() {
      _currentZoom = newZoom;
      _showZoomIndicator = true;
    });
    _zoomIndicatorTimer?.cancel();
    _zoomIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showZoomIndicator = false);
    });
  }
  
  void _showZoomIndicatorBriefly() {
    setState(() => _showZoomIndicator = true);
    _zoomIndicatorTimer?.cancel();
    _zoomIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showZoomIndicator = false);
    });
  }
  
  // Tap-to-focus handlers
  void _onTapToFocus(TapUpDetails details, Size previewSize) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    // Calculate normalized point (0.0 to 1.0)
    final localPoint = details.localPosition;
    final normalizedX = localPoint.dx / previewSize.width;
    final normalizedY = localPoint.dy / previewSize.height;
    final normalizedPoint = Offset(normalizedX.clamp(0.0, 1.0), normalizedY.clamp(0.0, 1.0));
    
    try {
      await _controller!.setFocusPoint(normalizedPoint);
      await _controller!.setExposurePoint(normalizedPoint);
      
      // Show focus indicator
      setState(() {
        _focusPoint = localPoint;
        _showFocusIndicator = true;
      });
      
      // Animate focus indicator
      _focusAnimationController.reset();
      _focusAnimationController.forward();
      
      // Auto-hide after 800ms
      _focusTimer?.cancel();
      _focusTimer = Timer(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() => _showFocusIndicator = false);
        }
      });
    } catch (e) {
      debugPrint('Focus error: $e');
    }
  }
  
  // Exposure adjustment with vertical swipe
  void _onVerticalDragUpdate(DragUpdateDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_showFocusIndicator) return; // Only adjust if focus was tapped
    
    // Swipe up = increase exposure, swipe down = decrease
    final delta = -details.delta.dy * 0.01;
    final newExposure = (_exposureOffset + delta).clamp(_minExposure, _maxExposure);
    
    try {
      await _controller!.setExposureOffset(newExposure);
      setState(() {
        _exposureOffset = newExposure;
        _showExposureSlider = true;
      });
      
      _exposureTimer?.cancel();
      _exposureTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _showExposureSlider = false);
      });
    } catch (e) {
      debugPrint('Exposure error: $e');
    }
  }
  
  // Get which preset is currently active (nearest lower)
  int _getCurrentPresetIndex() {
    for (int i = _zoomPresets.length - 1; i >= 0; i--) {
      if (_currentZoom >= _zoomPresets[i] - 0.05) return i;
    }
    return 0;
  }

  // _showComingSoon removed - unused

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;
    
    // Haptic feedback — instant
    HapticFeedback.mediumImpact();
    
    // Save preview aspect ratio
    if (_controller!.value.previewSize != null) {
      final ps = _controller!.value.previewSize!;
      _savedPreviewAspect = ps.height / ps.width;
    }
    
    // Freeze preview IMMEDIATELY — don't await, fire and forget for instant response
    _controller!.pausePreview();
    
    // Fire capture animation (non-blocking)
    _captureAnimationController.forward().then((_) {
      _captureAnimationController.reverse();
    });
    
    try {
      // Front flash: show overlay (non-blocking, no await)
      final useFrontFlash = _isFrontCamera && _flashMode != FlashMode.off;
      if (useFrontFlash) {
        setState(() => _screenFlashActive = true);
        _flashAnimationController.reset();
        _flashAnimationController.forward();
      }

      // Take the actual picture (preview already frozen, user doesn't notice delay)
      final xfile = await _controller!.takePicture();

      if (useFrontFlash && mounted) {
        // Let flash animation finish naturally, then dismiss
        _flashAnimationController.addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _screenFlashActive = false);
          }
        });
      }
      if (mounted) {
        File captured = File(xfile.path);
        // Un-mirror front camera photos so the image matches reality
        if (_isFrontCamera) {
          captured = await _flipImageHorizontally(captured);
        }
        setState(() => _capturedImage = captured);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _screenFlashActive = false);
        // Resume preview on failure so camera stays usable
        _controller?.resumePreview();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      // Show bottom sheet to choose between image and video
      final choice = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppTheme.cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.photo, color: Colors.white),
                title: const Text('Photo', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'photo'),
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.white),
                title: const Text('Video', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'video'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );

      if (choice == null) return;

      final picker = ImagePicker();
      if (choice == 'photo') {
        final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (image != null && mounted) {
          setState(() => _capturedImage = File(image.path));
        }
      } else {
        final video = await picker.pickVideo(source: ImageSource.gallery);
        if (video != null && mounted) {
          final videoFile = File(video.path);
          await _initVideoPlayer(videoFile);
          setState(() => _capturedVideo = videoFile);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gallery error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRecording) return;
    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
        if (_recordingDuration.inSeconds >= _maxRecordingSeconds) {
          _stopVideoRecording();
        }
      });
    } catch (e) {
      debugPrint('Start recording error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_isRecording) return;
    _recordingTimer?.cancel();
    try {
      final XFile videoFile = await _controller!.stopVideoRecording();
      final file = File(videoFile.path);
      await _initVideoPlayer(file);
      setState(() {
        _isRecording = false;
        _capturedVideo = file;
      });
    } catch (e) {
      debugPrint('Stop recording error: $e');
      setState(() => _isRecording = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stop recording error: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _initVideoPlayer(File videoFile) async {
    _videoPlayerController?.dispose();
    _videoPlayerController = VideoPlayerController.file(videoFile);
    await _videoPlayerController!.initialize();
    await _videoPlayerController!.setLooping(true);
    await _videoPlayerController!.play();
    _isVideoPlaying = true;
  }

  void _toggleVideoPlayback() {
    if (_videoPlayerController == null) return;
    setState(() {
      if (_isVideoPlaying) {
        _videoPlayerController!.pause();
      } else {
        _videoPlayerController!.play();
      }
      _isVideoPlaying = !_isVideoPlaying;
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _clearCapture() {
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
    setState(() {
      _capturedImage = null;
      _capturedVideo = null;
      // Clear all overlays
      _textOverlays = [];
      _drawingPaths = [];
      _stickers = [];
      _activeOverlayMode = null;
      _currentDrawingPath = null;
      _savedPreviewAspect = 0;
    });
    // Resume camera preview and restore zoom level
    _controller?.resumePreview();
    if (_controller != null && _currentZoom != 1.0) {
      _controller!.setZoomLevel(_currentZoom.clamp(_minZoom, _maxZoom));
    }
  }

  // ── Overlay Helpers ──
  void _activateTextMode() {
    setState(() {
      _editingTextItem = null;
      _activeOverlayMode = 'text';
    });
  }

  void _activateDrawMode() {
    setState(() => _activeOverlayMode = 'draw');
  }

  void _deactivateOverlayMode() {
    setState(() {
      _activeOverlayMode = null;
      _currentDrawingPath = null;
      _editingTextItem = null;
    });
  }

  void _addTextOverlay(TextOverlayItem item) {
    setState(() {
      final existingIndex = _textOverlays.indexWhere((t) => t.id == item.id);
      if (existingIndex >= 0) {
        _textOverlays[existingIndex] = item;
      } else {
        _textOverlays.add(item);
      }
      _activeOverlayMode = null;
      _editingTextItem = null;
    });
  }

  void _updateTextOverlay(TextOverlayItem item) {
    setState(() {
      final index = _textOverlays.indexWhere((t) => t.id == item.id);
      if (index >= 0) {
        _textOverlays[index] = item;
      }
    });
  }

  void _deleteTextOverlay(String id) {
    setState(() {
      _textOverlays.removeWhere((t) => t.id == id);
    });
  }

  void _onDrawingPanStart(Offset position) {
    setState(() {
      _currentDrawingPath = DrawingPath(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        color: _drawingTool == DrawingTool.eraser ? Colors.transparent : _drawingColor,
        strokeWidth: _drawingStrokeWidth,
        points: [position],
        tool: _drawingTool,
      );
    });
  }

  void _onDrawingPanUpdate(Offset position) {
    if (_currentDrawingPath == null) return;
    setState(() {
      _currentDrawingPath = _currentDrawingPath!.copyWith(
        points: [..._currentDrawingPath!.points, position],
      );
    });
  }

  void _onDrawingPanEnd() {
    if (_currentDrawingPath == null) return;
    setState(() {
      _drawingPaths.add(_currentDrawingPath!);
      _currentDrawingPath = null;
    });
  }

  void _undoDrawing() {
    if (_drawingPaths.isEmpty) return;
    setState(() {
      _drawingPaths.removeLast();
    });
  }

  void _showStickerPicker() {
    showStickerPicker(context, (emoji) {
      setState(() {
        _stickers.add(StickerItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          emoji: emoji,
          position: const Offset(0.5, 0.5),
        ));
      });
    });
  }

  void _updateSticker(StickerItem item) {
    setState(() {
      final index = _stickers.indexWhere((s) => s.id == item.id);
      if (index >= 0) {
        _stickers[index] = item;
      }
    });
  }

  void _deleteSticker(String id) {
    setState(() {
      _stickers.removeWhere((s) => s.id == id);
    });
  }

  Size _getPreviewSize() {
    final renderBox = _previewKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size ?? MediaQuery.of(context).size;
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    // If we have a captured video, show video preview
    if (_capturedVideo != null) {
      return _buildVideoPreview();
    }
    // If we have a captured image, show preview overlay
    if (_capturedImage != null) {
      return _buildPreview();
    }
    return _buildCameraView();
  }

  // ── Live Camera View (Snapchat-style full screen) ──
  Widget _buildCameraView() {
    final screenSize = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full-screen camera preview with gestures
          if (_isInitialized && _controller != null)
            GestureDetector(
              onDoubleTap: _isRecording ? null : _flipCamera,
              onScaleStart: _isRecording ? null : _onScaleStart,
              onScaleUpdate: _isRecording ? null : _onScaleUpdate,
              onTapUp: _isRecording ? null : (details) => _onTapToFocus(details, screenSize),
              onVerticalDragUpdate: _isRecording ? null : _onVerticalDragUpdate,
              child: AnimatedBuilder(
                animation: _cameraSwitchAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _isSwitchingCamera ? _cameraSwitchAnimation.value : 1.0,
                    child: _buildFullScreenPreview(),
                  );
                },
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // 2. Focus indicator
          _buildFocusIndicator(),

          // 3. Exposure slider
          _buildExposureIndicator(),

          // 4. Floating zoom indicator (center, above zoom selector)
          Positioned(
            bottom: 230,
            left: 0,
            right: 0,
            child: Center(child: _buildFloatingZoomIndicator()),
          ),

          // 5. Top overlay (avatar + search + add friend + flip)
          _buildTopOverlay(),

          // 6. Right side tools column
          _buildRightToolsColumn(),

          // 7. Zoom selector (above capture button)
          _buildZoomSelector(),

          // 8. Bottom controls (capture + gallery + thumbnails)
          _buildBottomControls(),

          // 9. Filter tabs at very bottom
          _buildFilterTabs(),

          // 10. Recording indicator (if recording)
          if (_isRecording) _buildRecordingIndicator(),

          // 11. Filter strip (when showFilters is active)


          // 12. Front flash overlay (animated)
          if (_screenFlashActive)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _flashAnimation,
                  builder: (context, child) {
                    return Container(
                      color: Colors.white.withValues(alpha: _flashAnimation.value),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Top Overlay (Avatar, Search, Add Friend, Flip) ──
  Widget _buildTopOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left side: Avatar + Search
              Row(
                children: [
                  // User avatar/Bitmoji
                  GestureDetector(
                    onTap: () => context.go('/profile'),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFFC00), Color(0xFFFFD700)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFFC00).withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                        ),
                        padding: const EdgeInsets.all(1.5),
                        child: _authProvider.currentUser?.avatarUrl != null && _authProvider.currentUser!.avatarUrl!.isNotEmpty
                            ? AvatarWidget(
                                avatarUrl: _authProvider.currentUser!.avatarUrl,
                                radius: 16,
                              )
                            : CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.primaryColor,
                                child: Text(
                                  (_authProvider.currentUser?.displayName ?? '?')
                                      .split(' ')
                                      .map((w) => w.isNotEmpty ? w[0] : '')
                                      .take(2)
                                      .join()
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Search icon
                  _buildOverlayButton(
                    icon: Icons.search,
                    onTap: () => context.push('/friends'),
                  ),
                ],
              ),
              // Right side: Add Friend + Flip Camera
              Row(
                children: [
                  // Add friend icon
                  _buildOverlayButton(
                    icon: Icons.person_add_outlined,
                    onTap: () => context.push('/friends'),
                  ),
                  const SizedBox(width: 8),
                  // Camera flip
                  _buildOverlayButton(
                    icon: Icons.flip_camera_ios_rounded,
                    onTap: _isRecording ? null : _flipCamera,
                    disabled: _isRecording,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Right Side Tools Column ──
  Widget _buildRightToolsColumn() {
    return Positioned(
      top: 0,
      right: 12,
      bottom: 0,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 60), // Space for top overlay
            // Flash toggle
            _buildToolButton(
              icon: _flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on,
              isActive: _flashMode != FlashMode.off,
              onTap: _isRecording ? null : _toggleFlash,
            ),

          ],
        ),
      ),
    );
  }

  // ── Zoom Selector Pill (Snapchat-style) ──
  Widget _buildZoomSelector() {
    final currentPreset = _getCurrentPresetIndex();
    
    return Positioned(
      bottom: 180,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_zoomPresets.length, (index) {
              final isSelected = currentPreset == index;
              final preset = _zoomPresets[index];
              final label = preset == 1 ? '1x' : '${preset.toInt()}x';
              
              return GestureDetector(
                onTap: () => _setZoomLevel(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected 
                        ? const Color(0xFFFFFC00).withValues(alpha: 0.9)
                        : Colors.transparent,
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
  
  // ── Floating Zoom Indicator ──
  Widget _buildFloatingZoomIndicator() {
    return AnimatedOpacity(
      opacity: _showZoomIndicator ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '${_currentZoom.toStringAsFixed(1)}x',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
  
  // ── Focus Indicator ──
  Widget _buildFocusIndicator() {
    if (!_showFocusIndicator || _focusPoint == null) return const SizedBox.shrink();
    
    return Positioned(
      left: _focusPoint!.dx - 30,
      top: _focusPoint!.dy - 30,
      child: AnimatedBuilder(
        animation: _focusAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _focusAnimation.value,
            child: AnimatedOpacity(
              opacity: _showFocusIndicator ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFFFFC00),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
  
  // ── Exposure Slider Indicator ──
  Widget _buildExposureIndicator() {
    if (!_showExposureSlider) return const SizedBox.shrink();
    
    return Positioned(
      right: 60,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wb_sunny_outlined, color: Color(0xFFFFFC00), size: 20),
              const SizedBox(height: 8),
              Container(
                width: 4,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Align(
                  alignment: Alignment(
                    0,
                    -(_exposureOffset / (_maxExposure.abs())).clamp(-1.0, 1.0),
                  ),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFC00),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _exposureOffset >= 0 ? '+${_exposureOffset.toStringAsFixed(1)}' : _exposureOffset.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom Controls (Capture, Gallery, Thumbnails) ──
  Widget _buildBottomControls() {
    return Positioned(
      bottom: 85,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Memories/Gallery icon with red dot
          GestureDetector(
            onTap: _isRecording ? null : () => context.push('/memories'),
            child: Stack(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Icon(
                    Icons.photo_library_outlined,
                    color: _isRecording ? Colors.white38 : Colors.white,
                    size: 22,
                  ),
                ),
                // Red notification dot
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Center: Capture button
          _buildSnapchatCaptureButton(),
          const SizedBox(width: 24),
          // Right: Recent photo thumbnails row
          SizedBox(
            width: 160,
            height: 48,
            child: _recentPhotos.isEmpty
                ? ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 3,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () => _pickFromGallery(),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: const Icon(Icons.image, color: Colors.white38, size: 20),
                        ),
                      );
                    },
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentPhotos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final asset = _recentPhotos[index];
                      return GestureDetector(
                        onTap: () => _openGalleryAsset(asset),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: FutureBuilder<Uint8List?>(
                              future: asset.thumbnailDataWithSize(const ThumbnailSize.square(200)),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
                                  return Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                    width: 48,
                                    height: 48,
                                    errorBuilder: (_, _, _) => Container(
                                      color: Colors.grey[800],
                                      child: const Icon(Icons.image, color: Colors.white54, size: 20),
                                    ),
                                  );
                                }
                                return Container(
                                  color: Colors.grey[800],
                                  child: const Center(
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Filter Category Tabs ──
  Widget _buildFilterTabs() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filterTabs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final isSelected = _selectedFilterTab == index;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedFilterTab = index);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.transparent : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            border: isSelected ? Border.all(color: Colors.white, width: 1) : null,
                          ),
                          child: Text(
                            _filterTabs[index],
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  // ── Recording Indicator ──
  Widget _buildRecordingIndicator() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingRedDot(),
                const SizedBox(width: 8),
                Text(
                  _formatDuration(_recordingDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helper: Overlay Button (with shadow for visibility) ──
  Widget _buildOverlayButton({
    required IconData icon,
    VoidCallback? onTap,
    bool disabled = false,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: disabled ? Colors.white38 : Colors.white,
          size: 22,
        ),
      ),
    );
  }

  // ── Helper: Tool Button (Right side column, with shadow) ──
  Widget _buildToolButton({
    required IconData icon,
    VoidCallback? onTap,
    bool isActive = false,
    double size = 36,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: isActive ? const Color(0xFFFFFC00) : Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }

  // ── Snapchat-style Capture Button (76px white ring with animations) ──
  Widget _buildSnapchatCaptureButton() {
    const double outerSize = 76;
    const double strokeWidth = 4;

    return GestureDetector(
      onTap: _isRecording ? null : _takePhoto,
      onLongPressStart: (_) {
        HapticFeedback.mediumImpact();
        _startVideoRecording();
      },
      onLongPressEnd: (_) => _stopVideoRecording(),
      child: AnimatedBuilder(
        animation: _captureScaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _captureScaleAnimation.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _isRecording ? outerSize + 10 : outerSize,
              height: _isRecording ? outerSize + 10 : outerSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring or progress ring when recording
                  if (_isRecording)
                    SizedBox(
                      width: outerSize + 10,
                      height: outerSize + 10,
                      child: CustomPaint(
                        painter: _RecordingProgressPainter(
                          progress: _recordingDuration.inSeconds / _maxRecordingSeconds,
                          strokeWidth: strokeWidth,
                        ),
                      ),
                    )
                  else
                    Container(
                      width: outerSize,
                      height: outerSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: strokeWidth),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  // Inner circle (red square when recording, transparent when not)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: _isRecording ? 32 : 0,
                    height: _isRecording ? 32 : 0,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_isRecording ? 6 : 0),
                      color: _isRecording ? AppTheme.errorColor : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFullScreenPreview() {
    final preview = CameraPreview(_controller!);
    final size = MediaQuery.of(context).size;
    final previewSize = _controller!.value.previewSize!;
    // previewSize is (height x width) in landscape orientation
    final previewAspect = previewSize.height / previewSize.width;
    final screenAspect = size.width / size.height;
    final scale = previewAspect / screenAspect;

    Widget widget = Transform.scale(
      scale: scale < 1 ? 1 / scale : scale,
      child: Center(child: preview),
    );

    // Apply color filter
    final cf = _selectedFilter.colorFilter;
    if (cf != null) {
      widget = ColorFiltered(colorFilter: cf, child: widget);
    }

    return ClipRect(child: widget);
  }

  // ── Preview (after capture) ──
  Widget _buildPreview() {
    // Match the captured photo's display to the live preview framing exactly:
    // 1. Crop the photo to the preview stream's aspect ratio (via AspectRatio + BoxFit.cover)
    // 2. Scale + clip identically to _buildFullScreenPreview()
    Widget imageWidget;
    if (_savedPreviewAspect > 0) {
      final size = MediaQuery.of(context).size;
      final screenAspect = size.width / size.height;
      final s = _savedPreviewAspect / screenAspect;
      final fillScale = s < 1 ? 1 / s : s;
      imageWidget = ClipRect(
        child: Transform.scale(
          scale: fillScale,
          child: Center(
            child: AspectRatio(
              aspectRatio: _savedPreviewAspect,
              child: Image.file(_capturedImage!, fit: BoxFit.cover),
            ),
          ),
        ),
      );
    } else {
      imageWidget = Image.file(_capturedImage!, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }
    final cf = _selectedFilter.colorFilter;
    if (cf != null) {
      imageWidget = ColorFiltered(colorFilter: cf, child: imageWidget);
    }

    // Determine if we're in drawing mode
    final isDrawingMode = _activeOverlayMode == 'draw';
    final isTextMode = _activeOverlayMode == 'text';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main content wrapped with drawing gesture detector if in drawing mode
          if (isDrawingMode)
            DrawingGestureDetector(
              onPanStart: _onDrawingPanStart,
              onPanUpdate: _onDrawingPanUpdate,
              onPanEnd: _onDrawingPanEnd,
              child: _buildPreviewContent(imageWidget),
            )
          else
            _buildPreviewContent(imageWidget),

          // Text input overlay (full screen)
          if (isTextMode)
            TextInputOverlay(
              editingItem: _editingTextItem,
              onDone: _addTextOverlay,
              onCancel: _deactivateOverlayMode,
            ),

          // Drawing HUD (when in draw mode)
          if (isDrawingMode)
            DrawingHUD(
              selectedTool: _drawingTool,
              selectedColor: _drawingColor,
              selectedStrokeWidth: _drawingStrokeWidth,
              hasDrawings: _drawingPaths.isNotEmpty,
              onToolChanged: (t) => setState(() => _drawingTool = t),
              onColorChanged: (c) => setState(() => _drawingColor = c),
              onStrokeWidthChanged: (s) => setState(() => _drawingStrokeWidth = s),
              onUndo: _undoDrawing,
              onDone: _deactivateOverlayMode,
            ),

          // Trash zone
          if (_showTrashZone)
            _buildTrashZone(),

          // Top bar (hidden when in text or draw mode)
          if (!isTextMode && !isDrawingMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _circleButton(icon: Icons.close, color: Colors.white, onTap: _clearCapture),
                      Row(children: [
                        _circleButton(
                          icon: Icons.text_fields, 
                          color: _textOverlays.isNotEmpty ? AppTheme.primaryColor : Colors.white,
                          onTap: _activateTextMode,
                        ),
                        const SizedBox(width: 4),
                        _circleButton(
                          icon: Icons.draw_rounded, 
                          color: _drawingPaths.isNotEmpty ? AppTheme.primaryColor : Colors.white,
                          onTap: _activateDrawMode,
                        ),
                        const SizedBox(width: 4),
                        _circleButton(
                          icon: Icons.emoji_emotions_outlined, 
                          color: _stickers.isNotEmpty ? AppTheme.primaryColor : Colors.white,
                          onTap: _showStickerPicker,
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),

          // Loading overlay
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: const Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Sending...', style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              )),
            ),

          // Bottom bar (hidden when in overlay mode or uploading)
          if (!_isUploading && !isTextMode && !isDrawingMode)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Save to Memories button
                      GestureDetector(
                        onTap: _savePhotoToMemories,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.download_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                      // Story button
                      GestureDetector(
                        onTap: _uploadAsStory,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.auto_stories, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Story', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                      // Send button
                      GestureDetector(
                        onTap: () => _showRecipientPicker(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Send', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the preview content with overlays
  Widget _buildPreviewContent(Widget imageWidget) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          key: _previewKey,
          fit: StackFit.expand,
          children: [
            // Background image
            imageWidget,

            // Drawing paths overlay
            if (_drawingPaths.isNotEmpty || _currentDrawingPath != null)
              DrawingOverlay(
                paths: _drawingPaths,
                currentPath: _currentDrawingPath,
              ),

            // Text overlays
            ..._textOverlays.map((item) => DraggableTextItem(
              item: item,
              containerSize: size,
              onUpdate: _updateTextOverlay,
              onTap: () {
                setState(() {
                  _editingTextItem = item;
                  _activeOverlayMode = 'text';
                });
              },
              onDelete: () => _deleteTextOverlay(item.id),
              onDragStateChanged: (dragging) => setState(() => _showTrashZone = dragging),
            )),

            // Stickers
            ..._stickers.map((item) => DraggableStickerItem(
              item: item,
              containerSize: size,
              onUpdate: _updateSticker,
              onDelete: () => _deleteSticker(item.id),
              onDragStateChanged: (dragging) => setState(() => _showTrashZone = dragging),
            )),
          ],
        );
      },
    );
  }

  // ── Render overlays helper ──
  Future<File> _getImageWithOverlays() async {
    if (_capturedImage == null) {
      throw Exception('No captured image');
    }
    
    // If no overlays, return original
    if (!ImageRenderer.hasOverlays(
      drawingPaths: _drawingPaths,
      textOverlays: _textOverlays,
      stickers: _stickers,
    )) {
      return _capturedImage!;
    }
    
    // Render overlays onto image
    return await ImageRenderer.renderOverlaysToImage(
      originalImage: _capturedImage!,
      previewSize: _getPreviewSize(),
      drawingPaths: _drawingPaths,
      textOverlays: _textOverlays,
      stickers: _stickers,
    );
  }

  // ── Save to Memories helpers ──
  Future<void> _savePhotoToMemories() async {
    if (_capturedImage == null) return;
    setState(() => _isUploading = true);
    try {
      // Render overlays onto image
      final imageToUpload = await _getImageWithOverlays();
      
      final api = ApiService();
      final uploadResponse = await api.uploadMedia(imageToUpload.path);
      final mediaUrl = uploadResponse.data['data']['media']['url'] as String;
      
      final memoryProvider = MemoryProvider();
      final success = await memoryProvider.saveMemory(
        mediaUrl: mediaUrl,
        mediaType: 'IMAGE',
      );
      
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Saved to Memories!' : 'Failed to save'),
            backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _saveVideoToMemories() async {
    if (_capturedVideo == null) return;
    setState(() => _isUploading = true);
    try {
      final api = ApiService();
      final uploadResponse = await api.uploadMedia(_capturedVideo!.path);
      final mediaUrl = uploadResponse.data['data']['media']['url'] as String;
      
      final memoryProvider = MemoryProvider();
      final success = await memoryProvider.saveMemory(
        mediaUrl: mediaUrl,
        mediaType: 'VIDEO',
      );
      
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Saved to Memories!' : 'Failed to save'),
            backgroundColor: success ? AppTheme.successColor : AppTheme.errorColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  // ── Video Preview (after recording) ──
  Widget _buildVideoPreview() {
    // Determine if we're in overlay modes
    final isDrawingMode = _activeOverlayMode == 'draw';
    final isTextMode = _activeOverlayMode == 'text';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video player with overlays
          if (isDrawingMode)
            DrawingGestureDetector(
              onPanStart: _onDrawingPanStart,
              onPanUpdate: _onDrawingPanUpdate,
              onPanEnd: _onDrawingPanEnd,
              child: _buildVideoContent(),
            )
          else
            _buildVideoContent(),

          // Text input overlay (full screen)
          if (isTextMode)
            TextInputOverlay(
              editingItem: _editingTextItem,
              onDone: _addTextOverlay,
              onCancel: _deactivateOverlayMode,
            ),

          // Drawing HUD (when in draw mode)
          if (isDrawingMode)
            DrawingHUD(
              selectedTool: _drawingTool,
              selectedColor: _drawingColor,
              selectedStrokeWidth: _drawingStrokeWidth,
              hasDrawings: _drawingPaths.isNotEmpty,
              onToolChanged: (t) => setState(() => _drawingTool = t),
              onColorChanged: (c) => setState(() => _drawingColor = c),
              onStrokeWidthChanged: (s) => setState(() => _drawingStrokeWidth = s),
              onUndo: _undoDrawing,
              onDone: _deactivateOverlayMode,
            ),

          // Trash zone
          if (_showTrashZone)
            _buildTrashZone(),

          // Play/Pause overlay (hidden when in overlay mode)
          if (_videoPlayerController != null && !_isVideoPlaying && !isTextMode && !isDrawingMode)
            Center(
              child: GestureDetector(
                onTap: _toggleVideoPlayback,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 50),
                ),
              ),
            ),

          // Top bar (hidden when in text or draw mode)
          if (!isTextMode && !isDrawingMode)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _circleButton(icon: Icons.close, color: Colors.white, onTap: _clearCapture),
                      Row(children: [
                        _circleButton(
                          icon: Icons.text_fields, 
                          color: _textOverlays.isNotEmpty ? AppTheme.primaryColor : Colors.white,
                          onTap: _activateTextMode,
                        ),
                        const SizedBox(width: 4),
                        _circleButton(
                          icon: Icons.draw_rounded, 
                          color: _drawingPaths.isNotEmpty ? AppTheme.primaryColor : Colors.white,
                          onTap: _activateDrawMode,
                        ),
                        const SizedBox(width: 4),
                        _circleButton(
                          icon: Icons.emoji_emotions_outlined, 
                          color: _stickers.isNotEmpty ? AppTheme.primaryColor : Colors.white,
                          onTap: _showStickerPicker,
                        ),
                        const SizedBox(width: 4),
                        _circleButton(icon: Icons.volume_up, color: Colors.white,
                            onTap: () {
                              final muted = _videoPlayerController?.value.volume == 0;
                              _videoPlayerController?.setVolume(muted ? 1.0 : 0.0);
                              setState(() {});
                            }),
                      ]),
                    ],
                  ),
                ),
              ),
            ),

          // Loading overlay
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: const Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Sending...', style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              )),
            ),

          // Bottom bar (hidden when in overlay mode or uploading)
          if (!_isUploading && !isTextMode && !isDrawingMode)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Save to Memories button
                      GestureDetector(
                        onTap: _saveVideoToMemories,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.download_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                      // Story button
                      GestureDetector(
                        onTap: _uploadVideoAsStory,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.auto_stories, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Story', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                      // Send button
                      GestureDetector(
                        onTap: () => _showVideoRecipientPicker(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.send_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text('Send', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the video content with overlays
  Widget _buildVideoContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            // Video player
            if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized)
              GestureDetector(
                onTap: _activeOverlayMode == null ? _toggleVideoPlayback : null,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _videoPlayerController!.value.aspectRatio,
                    child: VideoPlayer(_videoPlayerController!),
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),

            // Drawing paths overlay
            if (_drawingPaths.isNotEmpty || _currentDrawingPath != null)
              DrawingOverlay(
                paths: _drawingPaths,
                currentPath: _currentDrawingPath,
              ),

            // Text overlays
            ..._textOverlays.map((item) => DraggableTextItem(
              item: item,
              containerSize: size,
              onUpdate: _updateTextOverlay,
              onTap: () {
                setState(() {
                  _editingTextItem = item;
                  _activeOverlayMode = 'text';
                });
              },
              onDelete: () => _deleteTextOverlay(item.id),
              onDragStateChanged: (dragging) => setState(() => _showTrashZone = dragging),
            )),

            // Stickers
            ..._stickers.map((item) => DraggableStickerItem(
              item: item,
              containerSize: size,
              onUpdate: _updateSticker,
              onDelete: () => _deleteSticker(item.id),
              onDragStateChanged: (dragging) => setState(() => _showTrashZone = dragging),
            )),
          ],
        );
      },
    );
  }

  // ── Upload helpers ──
  Future<void> _uploadAsStory() async {
    if (_capturedImage == null) return;
    setState(() => _isUploading = true);
    try {
      // Render overlays onto image
      final imageToUpload = await _getImageWithOverlays();
      
      final api = ApiService();
      final uploadResponse = await api.uploadMedia(imageToUpload.path);
      final mediaUrl = uploadResponse.data['data']['media']['url'] as String;
      await api.createStory({
        'mediaUrl': mediaUrl,
        'mediaType': 'IMAGE',
        'duration': 5,
      });
      if (mounted) {
        _clearCapture();
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story posted!'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Story failed: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _sendSnapToRecipients(List<String> recipientIds) async {
    if (_capturedImage == null) return;
    setState(() => _isUploading = true);
    try {
      // Render overlays onto image
      final imageToUpload = await _getImageWithOverlays();
      
      final api = ApiService();
      final uploadResponse = await api.uploadMedia(imageToUpload.path);
      final mediaUrl = uploadResponse.data['data']['media']['url'] as String;
      await api.sendSnap(
        recipientIds: recipientIds,
        mediaUrl: mediaUrl,
        mediaType: 'IMAGE',
      );
      if (mounted) {
        _clearCapture();
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snap sent!'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _uploadVideoAsStory() async {
    if (_capturedVideo == null) return;
    setState(() => _isUploading = true);
    try {
      final api = ApiService();
      final uploadResponse = await api.uploadMedia(_capturedVideo!.path);
      final mediaUrl = uploadResponse.data['data']['media']['url'] as String;
      await api.createStory({
        'mediaUrl': mediaUrl,
        'mediaType': 'VIDEO',
        'duration': _videoPlayerController?.value.duration.inSeconds ?? 10,
      });
      if (mounted) {
        _clearCapture();
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Story posted!'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Story failed: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _sendVideoToRecipients(List<String> recipientIds) async {
    if (_capturedVideo == null) return;
    setState(() => _isUploading = true);
    try {
      final api = ApiService();
      final uploadResponse = await api.uploadMedia(_capturedVideo!.path);
      final mediaUrl = uploadResponse.data['data']['media']['url'] as String;
      await api.sendSnap(
        recipientIds: recipientIds,
        mediaUrl: mediaUrl,
        mediaType: 'VIDEO',
      );
      if (mounted) {
        _clearCapture();
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snap sent!'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        final msg = e is AppException ? e.message : ErrorHandler.handle(e).message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $msg'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  void _showVideoRecipientPicker(BuildContext context) {
    final socialProvider = SocialProvider();
    socialProvider.loadFriends();
    final selectedRecipients = <String>{};

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            padding: const EdgeInsets.all(16),
            height: MediaQuery.of(context).size.height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Send To', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    if (selectedRecipients.isNotEmpty)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _sendVideoToRecipients(selectedRecipients.toList());
                        },
                        child: Text('Send (${selectedRecipients.length})',
                            style: const TextStyle(color: Colors.white)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // My Story
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                    child: const Icon(Icons.auto_stories, color: Colors.white, size: 20),
                  ),
                  title: const Text('My Story', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Share to your story', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  onTap: () { Navigator.pop(ctx); _uploadVideoAsStory(); },
                ),
                const Divider(color: Colors.white24),
                const Text('Friends', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: socialProvider,
                    builder: (context, _) {
                      if (socialProvider.friends.isEmpty) {
                        return const Center(
                          child: Text('No friends yet', style: TextStyle(color: AppTheme.textMuted)),
                        );
                      }
                      return ListView.builder(
                        itemCount: socialProvider.friends.length,
                        itemBuilder: (context, index) {
                          final friend = socialProvider.friends[index];
                          final isSelected = selectedRecipients.contains(friend.user.id);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: AvatarWidget(
                              avatarUrl: friend.user.avatarUrl,
                              radius: 22,
                            ),
                            title: Text(friend.user.displayName, style: const TextStyle(color: Colors.white)),
                            trailing: Container(
                              width: 26, height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                                border: Border.all(
                                  color: isSelected ? AppTheme.primaryColor : AppTheme.textMuted, width: 2),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                            onTap: () {
                              setSheetState(() {
                                if (isSelected) {
                                  selectedRecipients.remove(friend.user.id);
                                } else {
                                  selectedRecipients.add(friend.user.id);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRecipientPicker(BuildContext context) {
    final socialProvider = SocialProvider();
    socialProvider.loadFriends();
    final selectedRecipients = <String>{};

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            padding: const EdgeInsets.all(16),
            height: MediaQuery.of(context).size.height * 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Send To', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    if (selectedRecipients.isNotEmpty)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _sendSnapToRecipients(selectedRecipients.toList());
                        },
                        child: Text('Send (${selectedRecipients.length})',
                            style: const TextStyle(color: Colors.white)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // My Story
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(color: AppTheme.primaryColor, shape: BoxShape.circle),
                    child: const Icon(Icons.auto_stories, color: Colors.white, size: 20),
                  ),
                  title: const Text('My Story', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Share to your story', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  onTap: () { Navigator.pop(ctx); _uploadAsStory(); },
                ),
                const Divider(color: Colors.white24),
                const Text('Friends', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListenableBuilder(
                    listenable: socialProvider,
                    builder: (context, _) {
                      if (socialProvider.friends.isEmpty) {
                        return const Center(
                          child: Text('No friends yet', style: TextStyle(color: AppTheme.textMuted)),
                        );
                      }
                      return ListView.builder(
                        itemCount: socialProvider.friends.length,
                        itemBuilder: (context, index) {
                          final friend = socialProvider.friends[index];
                          final isSelected = selectedRecipients.contains(friend.user.id);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: AvatarWidget(
                              avatarUrl: friend.user.avatarUrl,
                              radius: 22,
                            ),
                            title: Text(friend.user.displayName, style: const TextStyle(color: Colors.white)),
                            trailing: Container(
                              width: 26, height: 26,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                                border: Border.all(
                                  color: isSelected ? AppTheme.primaryColor : AppTheme.textMuted, width: 2),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                            onTap: () {
                              setSheetState(() {
                                if (isSelected) {
                                  selectedRecipients.remove(friend.user.id);
                                } else {
                                  selectedRecipients.add(friend.user.id);
                                }
                              });
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Widgets ──
  Widget _buildTrashZone() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: true,
        child: AnimatedOpacity(
          opacity: _showTrashZone ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: 120,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xCCFF0000), Colors.transparent],
              ),
            ),
            alignment: Alignment.bottomCenter,
            padding: const EdgeInsets.only(bottom: 32),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_rounded, color: Colors.white, size: 32),
                SizedBox(height: 4),
                Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black26),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

// ── Recording Progress Ring Painter ──
class _RecordingProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;

  _RecordingProgressPainter({
    required this.progress,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background circle
    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..color = AppTheme.errorColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RecordingProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// ── Pulsing Red Dot ──
class _PulsingRedDot extends StatefulWidget {
  @override
  State<_PulsingRedDot> createState() => _PulsingRedDotState();
}

class _PulsingRedDotState extends State<_PulsingRedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.errorColor.withValues(alpha: _animation.value),
          ),
        );
      },
    );
  }
}
