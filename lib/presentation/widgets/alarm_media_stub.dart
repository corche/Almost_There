import 'package:flutter/widgets.dart';

import '../../domain/entities/destination.dart';

/// Persisted device file paths are unavailable in the browser. The caller's
/// animated gradient remains visible when media cannot be opened.
Widget buildAlarmMedia(Destination destination) => const SizedBox.shrink();
