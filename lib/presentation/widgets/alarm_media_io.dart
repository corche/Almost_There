import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../domain/entities/destination.dart';

Widget buildAlarmMedia(Destination destination) {
  final path = destination.mediaPath;
  if (path == null || path.isEmpty) return const SizedBox.shrink();
  return switch (destination.background) {
    AlarmBackground.gradient => const SizedBox.shrink(),
    AlarmBackground.image => Image.file(
      File(path),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    ),
    AlarmBackground.video => _VideoBackground(path: path),
  };
}

class _VideoBackground extends StatefulWidget {
  const _VideoBackground({required this.path});
  final String path;

  @override
  State<_VideoBackground> createState() => _VideoBackgroundState();
}

class _VideoBackgroundState extends State<_VideoBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_VideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _controller?.dispose();
      _ready = false;
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_ready) _updatePlayback();
  }

  Future<void> _load() async {
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || _controller != controller) return;
      // Background video never competes with the separately routed alarm audio.
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted || _controller != controller) return;
      setState(() => _ready = true);
      await _updatePlayback();
    } catch (_) {
      // Unsupported codecs, missing files, and unavailable desktop plugins all
      // leave the gradient beneath this widget visible.
      if (mounted && _controller == controller) {
        setState(() => _ready = false);
      }
    }
  }

  Future<void> _updatePlayback() async {
    try {
      if (_reduceMotion) {
        await _controller?.pause();
      } else {
        await _controller?.play();
      }
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) return const SizedBox.shrink();
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
