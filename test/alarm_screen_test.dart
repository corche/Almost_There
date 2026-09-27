import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:almost_there/domain/entities/destination.dart';
import 'package:almost_there/presentation/screens/alarm_screen.dart';
import 'package:almost_there/presentation/widgets/alarm_dismiss_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destination = Destination(
  id: 'seoul',
  name: '서울역',
  latitude: 37.5547,
  longitude: 126.9706,
);

Widget _slider(Future<void> Function() onDismiss) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        child: AlarmDismissSlider(onDismiss: onDismiss),
      ),
    ),
  ),
);

void main() {
  testWidgets('incomplete dismissal snaps back without stopping the alarm', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(_slider(() async => calls++));
    final thumb = find.byKey(const Key('alarm-dismiss-thumb'));
    final original = tester.getTopLeft(thumb);

    // The thumb has 244px of travel; 84% must not dismiss.
    await tester.drag(thumb, const Offset(244 * .84, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(calls, 0);
    expect(tester.getTopLeft(thumb).dx, closeTo(original.dx, .1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a full slide dismisses once while cleanup is pending', (
    tester,
  ) async {
    var calls = 0;
    final cleanup = Completer<void>();
    await tester.pumpWidget(
      _slider(() {
        calls++;
        return cleanup.future;
      }),
    );
    final thumb = find.byKey(const Key('alarm-dismiss-thumb'));
    // Just beyond the 85% threshold is sufficient; reaching the end is optional.
    await tester.drag(thumb, const Offset(244 * .86, 0));
    await tester.pump();
    await tester.drag(thumb, const Offset(-200, 0));
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    cleanup.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen readers can explicitly dismiss without a gesture', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    await tester.pumpWidget(_slider(() async => calls++));
    final node = tester.getSemantics(find.bySemanticsLabel('알람 종료'));
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pump();

    expect(calls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('failed dismissal allows retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _slider(() async {
        calls++;
        if (calls == 1) throw StateError('stop failed');
      }),
    );
    final thumb = find.byKey(const Key('alarm-dismiss-thumb'));
    await tester.drag(thumb, const Offset(400, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.drag(thumb, const Offset(400, 0));
    await tester.pump();

    expect(calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final preview in [false, true]) {
    testWidgets(
      preview
          ? 'preview back stops audio through the same dismissal callback'
          : 'actual alarm blocks back until deliberate dismissal',
      (tester) async {
        var calls = 0;
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('목적지 목록')),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (context) => AlarmScreen(
              destination: _destination,
              preview: preview,
              onDismiss: () async {
                calls++;
                navigator.currentState!.pop();
              },
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));

        expect(calls, preview ? 1 : 0);
        expect(find.text('서울역'), preview ? findsNothing : findsOneWidget);
        if (!preview) {
          await tester.drag(
            find.byKey(const Key('alarm-dismiss-thumb')),
            const Offset(500, 0),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(calls, 1);
          expect(find.text('목적지 목록'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('320px and enlarged text can scroll to the dismiss control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: AlarmScreen(
          destination: _destination.copyWith(name: '서울역 공항철도 환승센터'),
          preview: true,
          onDismiss: () async {},
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('alarm-dismiss-track')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('alarm-dismiss-thumb')).hitTestable(),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
