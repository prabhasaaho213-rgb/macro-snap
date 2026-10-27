import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/app_nav.dart';
import '../core/theme.dart';
import '../services/currency_service.dart';
import '../services/scan_gate.dart';
import '../services/meal_store.dart';
import '../services/subscription_service.dart';
import '../widgets/animations.dart';
import '../widgets/gradient_button.dart';
import '../widgets/pro_badge.dart';
import 'barcode_scan_screen.dart';
import 'recent_foods_screen.dart';
import 'settings_screen.dart';
import 'result_screen.dart';
import 'subscription_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _initialized = false;
  bool _cameraError = false;

  /// Torch state for the round button at the bottom left of the viewfinder.
  /// Tracked here, not read back from the controller, because some devices
  /// accept `setFlashMode` and then report `off` anyway.
  bool _torchOn = false;

  /// True when camera access is permanently blocked ("Don't ask again") — in
  /// that state request() never re-shows the dialog, so the user must be
  /// sent to the system Settings screen instead.
  bool _cameraPermanentlyDenied = false;
  int _scansLeft = 3;
  String? _capturedImagePath;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadScans();
    // Defer the camera permission request until AFTER the first frame. When
    // requested from initState (mid widget-mount), Android can suppress the
    // system "Allow camera?" dialog — the tab opened with no prompt and no
    // camera. Post-frame the prompt reliably appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
    // Refresh scan count when data changes (e.g. after subscribing)
    MealStore.instance.changeNotifier.addListener(_onDataChanged);
    // The camera is paused while another tab is on screen instead of the tab
    // being torn down, so coming back resumes the preview instantly instead of
    // re-opening the camera (which showed black for a second or two).
    scanTabVisible.addListener(_onScanVisibilityChanged);
  }

  void _onScanVisibilityChanged() {
    final controller = _controller;
    final hasCamera = controller != null && controller.value.isInitialized;
    if (!scanTabVisible.value) {
      if (hasCamera) controller.pausePreview();
      // Leaving the tab drops the torch: coming back to a camera that is
      // silently lighting the room reads as a bug, not as a saved setting.
      if (_torchOn) _setTorch(false);
      return;
    }
    // The tab now stays mounted, so re-read the allowance on return — it used
    // to refresh only because the whole screen was rebuilt each visit.
    _loadScans();
    if (hasCamera) controller.resumePreview();
  }

  void _onDataChanged() {
    _loadScans();
  }

  /// Round secondary camera button (flash, recent foods) beside the shutter.
  Widget _roundCameraButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? MacroSnapTheme.neonGreen.withValues(alpha: 0.9)
              : Colors.white.withValues(alpha: 0.15),
          border: Border.all(
            color: active
                ? MacroSnapTheme.neonGreen
                : Colors.white.withValues(alpha: 0.22),
          ),
        ),
        child: Icon(
          icon,
          color: active ? Colors.black : Colors.white.withValues(alpha: 0.85),
          size: 22,
        ),
      ),
    );
  }

  /// One pill inside the capture-mode switcher. The selected mode carries the
  /// label; the others are icon-only so the row stays short enough for a
  /// 320 dp phone.
  Widget _switcherSegment({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: selected ? 14 : 10,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: selected ? Colors.black.withValues(alpha: 0.55) : null,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : Colors.white60,
            ),
            if (selected) ...[
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// AI Camera · barcode · gallery — every way into a scan, in one pill.
  /// Barcode and gallery used to live in unrelated corners of the app (the
  /// barcode only on a Home quick action, the gallery button at the bottom of
  /// the viewfinder).
  Widget _captureModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _switcherSegment(
            icon: Icons.photo_camera_rounded,
            label: 'AI Camera',
            selected: true,
            onTap: _capture,
          ),
          _switcherSegment(
            icon: Icons.qr_code_scanner_rounded,
            label: 'Barcode',
            selected: false,
            onTap: _openBarcode,
          ),
          _switcherSegment(
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
            selected: false,
            onTap: _pickFromGallery,
          ),
        ],
      ),
    );
  }

  /// Flips the torch on or off. Best-effort: a device that refuses
  /// `setFlashMode` keeps the button in its previous state rather than
  /// claiming a light that is not on.
  Future<void> _setTorch(bool on) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _torchOn = on);
    } catch (e) {
      debugPrint('Torch unavailable: $e');
    }
  }

  void _toggleTorch() {
    HapticFeedback.selectionClick();
    _setTorch(!_torchOn);
  }

  /// Hands the user to the barcode scanner and re-reads the allowance on the
  /// way back, since a barcode log can also change what is left today.
  Future<void> _openBarcode() async {
    HapticFeedback.lightImpact();
    await Navigator.push(context, habitFlowRoute(const BarcodeScanScreen()));
    if (mounted) _loadScans();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    MealStore.instance.changeNotifier.removeListener(_onDataChanged);
    scanTabVisible.removeListener(_onScanVisibilityChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      _controller?.resumePreview();
    } else if (state == AppLifecycleState.paused) {
      _controller?.pausePreview();
    }
  }

  Future<void> _loadScans() async {
    // Ask the server for the authoritative count first (best-effort) so the
    // badge shows today's real allowance, not a stale local estimate.
    await ScanGate.refreshFromServer();
    final remaining = await ScanGate.getScansRemaining();
    if (mounted) setState(() => _scansLeft = remaining);
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      // request() will NEVER re-show the dialog from this state — the only
      // way out is the system Settings screen.
      setState(() {
        _cameraError = true;
        _cameraPermanentlyDenied = true;
      });
      return;
    }
    if (status.isDenied || status.isRestricted) {
      setState(() {
        _cameraError = true;
        _cameraPermanentlyDenied = false;
      });
      return;
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = true);
        return;
      }
      final controller = CameraController(
        _cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (mounted) {
        setState(() {
          _controller = controller;
          _initialized = true;
          _cameraError = false;
          _cameraPermanentlyDenied = false;
        });
        // The tab may have been left while the camera was still opening.
        if (!scanTabVisible.value) controller.pausePreview();
      } else {
        // Screen went away mid-initialize — don't leak the camera.
        await controller.dispose();
      }
    } catch (e) {
      if (mounted) setState(() => _cameraError = true);
    }
  }

  /// Re-request camera permission and re-initialize the preview. Used by the
  /// "Grant Camera Access" button on the camera-unavailable screen so a user
  /// who dismissed the first prompt (or denied it) can try again in-app.
  Future<void> _retryCamera() async {
    setState(() {
      _cameraError = false;
      _initialized = false;
      _cameraPermanentlyDenied = false;
    });
    await _initCamera();
  }

  /// Opens the system Settings so a permanently-blocked camera can be
  /// re-enabled manually (request() never re-prompts from that state).
  Future<void> _openCameraSettings() async {
    await openAppSettings();
    // Re-check after the user returns from Settings.
    if (mounted) {
      setState(() {
        _cameraError = false;
        _initialized = false;
        _cameraPermanentlyDenied = false;
      });
      await _initCamera();
    }
  }

  void _navigateToResult(String path) {
    if (!mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => ResultScreen(imagePath: path),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  void _showPreview(String path) {
    setState(() => _capturedImagePath = path);
    // Auto-navigate after a brief preview so Hero can animate
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _capturedImagePath = null);
        _navigateToResult(path);
      }
    });
  }

  Future<void> _capture() async {
    HapticFeedback.lightImpact();
    if (!await ScanGate.canScan()) {
      if (mounted) _showLimitDialog();
      return;
    }
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      HapticFeedback.mediumImpact();
      final xfile = await _controller!.takePicture();
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/food_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await xfile.saveTo(tempFile.path);
      // Scan is only counted AFTER successful AI analysis (in ResultScreen),
      // so failed analyses don't consume the free limit.
      if (mounted) {
        _showPreview(tempFile.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: MacroSnapTheme.neonPink,
          ),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (!await ScanGate.canScan()) {
      if (mounted) _showLimitDialog();
      return;
    }
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    // Higher resolution feeds the AI more detail for accurate recognition
    // (512px was too small for fine details like desserts and packaged food).
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 82,
    );
    if (image != null && mounted) {
      final bytes = await image.readAsBytes();
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/food_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(bytes);
      // Scan is only counted AFTER successful AI analysis (in ResultScreen),
      // so failed analyses don't consume the free limit.
      if (mounted) {
        _showPreview(tempFile.path);
      }
    }
  }

  void _showLimitDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? MacroSnapTheme.cardDark
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MacroSnapTheme.neonOrange.withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  color: MacroSnapTheme.neonOrange,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Free scans used up today',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const ProBadge(),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'You get ${ScanGate.freeLimitPerDay} free AI scans per day.\nCome back tomorrow or go Pro for unlimited scans.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: MacroSnapTheme.textSecondary(context),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              GradientButton(
                label: SubscriptionService.instance.introEligible
                    ? 'Go Pro · ${CurrencyService.instance.introLabel} first month, then ${CurrencyService.instance.monthlyLabel}/mo'
                    : 'Go Pro · ${CurrencyService.instance.monthlyLabel}/mo',
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen(),
                    ),
                  );
                },
                height: 48,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Maybe later',
                  style: TextStyle(
                    fontSize: 14,
                    color: MacroSnapTheme.textTertiary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canUse = _scansLeft > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_cameraError) {
      return Scaffold(
        backgroundColor: isDark
            ? MacroSnapTheme.surfaceDark
            : MacroSnapTheme.surfaceLight,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 24,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam_off_rounded,
                  color: MacroSnapTheme.textTertiary(context),
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Camera unavailable',
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.6)
                        : const Color(0xFF475569),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Allow camera access to scan your meals.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MacroSnapTheme.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                if (_cameraPermanentlyDenied)
                  FilledButton.icon(
                    onPressed: _openCameraSettings,
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Open Settings'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MacroSnapTheme.neonPink,
                      foregroundColor: Colors.black,
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _retryCamera,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Grant Camera Access'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MacroSnapTheme.neonGreen,
                      foregroundColor: Colors.black,
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_rounded),
                  label: const Text('Choose from Gallery'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return Scaffold(
        backgroundColor: isDark
            ? MacroSnapTheme.surfaceDark
            : MacroSnapTheme.surfaceLight,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: MacroSnapTheme.neonGreen),
              const SizedBox(height: 16),
              Text(
                'Starting camera...',
                style: TextStyle(color: MacroSnapTheme.textSecondary(context)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: MacroSnapTheme.surfaceDark,
      body: Stack(
        children: [
          // Live camera preview — OverflowBox allows camera to exceed
          // screen bounds to maintain native aspect ratio, ClipRect crops overflow
          if (_controller != null && _controller!.value.isInitialized)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenAspect =
                      constraints.maxWidth / constraints.maxHeight;
                  final cameraAspect = _controller!.value.aspectRatio;
                  return ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.center,
                      maxHeight: screenAspect > cameraAspect
                          ? constraints.maxWidth / cameraAspect
                          : constraints.maxHeight,
                      maxWidth: screenAspect > cameraAspect
                          ? constraints.maxWidth
                          : constraints.maxHeight * cameraAspect,
                      child: CameraPreview(_controller!),
                    ),
                  );
                },
              ),
            ),

          // ─── Captured Image Preview (Hero source) ─────────
          if (_capturedImagePath != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _previewTimer?.cancel();
                  if (mounted) {
                    final path = _capturedImagePath!;
                    setState(() => _capturedImagePath = null);
                    _navigateToResult(path);
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'food_image_$_capturedImagePath',
                      child: Image.file(
                        File(_capturedImagePath!),
                        fit: BoxFit.cover,
                        // Keep the preview area dark if the temp file vanished
                        // between capture and paint.
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: MacroSnapTheme.surfaceDark),
                      ),
                    ),
                    // Dark overlay + hint text
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.6),
                            Colors.transparent,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 40,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  color: MacroSnapTheme.neonGreen,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Analyzing your meal...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap anywhere to continue',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ─── Camera overlays (hidden during preview) ───────
          if (_capturedImagePath == null) ...[
            // Dark gradient overlay at bottom for button visibility
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 200,
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
              ),
            ),

            // Top bar: close / allowance / settings, with the capture-mode
            // switcher directly beneath it.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (canUse
                                          ? MacroSnapTheme.neonGreen
                                          : MacroSnapTheme.neonPink)
                                      .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    (canUse
                                            ? MacroSnapTheme.neonGreen
                                            : MacroSnapTheme.neonPink)
                                        .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flash_on_rounded,
                                  size: 14,
                                  color: canUse
                                      ? MacroSnapTheme.neonGreen
                                      : MacroSnapTheme.neonPink,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _scansLeft >= 99
                                      ? 'Unlimited'
                                      : '$_scansLeft left',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: canUse
                                        ? MacroSnapTheme.greenText(context)
                                        : MacroSnapTheme.neonPink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Settings button
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              habitFlowRoute(const SettingsScreen()),
                            ),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.settings_rounded,
                                color: Colors.white60,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _captureModeSwitcher(),
                    ],
                  ),
                ),
              ),
            ),

            // Small hint above the action bar: how many free scans are left
            // today (unlimited/Pro users see nothing).
            if (_scansLeft < 99)
              Positioned(
                left: 0,
                right: 0,
                bottom: 118,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _scansLeft == 0
                          ? 'No free scans left today'
                          : '$_scansLeft of ${ScanGate.freeLimitPerDay} scans left today',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _scansLeft == 0
                            ? MacroSnapTheme.neonPink
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

            // Bottom action bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Flash / torch toggle
                      _roundCameraButton(
                        icon: _torchOn
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        active: _torchOn,
                        onTap: _toggleTorch,
                      ),
                      // Capture button
                      GestureDetector(
                        onTap: _capture,
                        child: Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 3,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                              child: const Icon(
                                Icons.photo_camera_rounded,
                                color: Colors.black87,
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Recent foods — the gallery button moved into the top
                      // switcher, so this slot carries the other half of the
                      // scan flow: what was logged before.
                      _roundCameraButton(
                        icon: Icons.history_rounded,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RecentFoodsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ], // end if _capturedImagePath == null
        ],
      ),
    );
  }
}
