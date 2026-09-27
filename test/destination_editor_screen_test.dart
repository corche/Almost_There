import 'package:almost_there/core/theme/app_theme.dart';
import 'package:almost_there/domain/entities/destination.dart';
import 'package:almost_there/presentation/screens/destination_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _destination = Destination(
  id: 'editor-test',
  name: '서울역',
  address: '서울특별시',
  latitude: 37.5547,
  longitude: 126.9707,
);

Future<void> _openEditor(
  WidgetTester tester, {
  ValueChanged<Destination?>? onResult,
  Future<void> Function(Destination)? onSave,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<Destination>(
                  MaterialPageRoute(
                    builder: (_) => DestinationEditorScreen(
                      destination: _destination,
                      onSave: onSave,
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('목적지 열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('목적지 열기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('back protects edits and discard returns no destination', (
    tester,
  ) async {
    var returned = false;
    Destination? result;
    await _openEditor(
      tester,
      onResult: (value) {
        returned = true;
        result = value;
      },
    );
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, '우리 집');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('입력한 내용이 저장되지 않습니다. 나가시겠습니까?'), findsOneWidget);
    expect(returned, isFalse);
    await tester.tap(find.text('저장 안함'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(result, isNull);
    expect(find.text('목적지 열기'), findsOneWidget);
  }, variant: TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets(
    'save returns the edited destination and preserves other options',
    (tester) async {
      Destination? result;
      await _openEditor(tester, onResult: (value) => result = value);
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).first, '  퇴근길 서울역  ');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(result?.id, _destination.id);
      expect(result?.name, '퇴근길 서울역');
      expect(result?.radius, _destination.radius);
      expect(result?.latitude, _destination.latitude);
      expect(result?.alarmType, AlarmType.sound);
      expect(find.byType(AlertDialog), findsNothing);
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );

  testWidgets('empty alias is rejected and narrow layout remains usable', (
    tester,
  ) async {
    await _openEditor(tester);
    tester.view.physicalSize = const Size(320, 844);
    await tester.pump();
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.enterText(find.byType(TextFormField).first, '   ');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.byType(DestinationEditorScreen), findsOneWidget);
    expect(find.text('목적지 이름을 입력해 주세요.'), findsWidgets);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1400));
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets(
    'persistence failure retains input and allows a successful retry',
    (tester) async {
      var attempts = 0;
      Destination? saved;
      await _openEditor(
        tester,
        onSave: (value) async {
          attempts++;
          if (attempts == 1) throw StateError('Storage unavailable');
          saved = value;
        },
      );
      await tester.ensureVisible(find.byType(TextFormField).first);
      await tester.enterText(find.byType(TextFormField).first, '입력이 남아 있어요');
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(find.byType(DestinationEditorScreen), findsOneWidget);
      expect(find.text('입력이 남아 있어요'), findsOneWidget);
      expect(
        find.text('저장하지 못했어요. 입력한 내용은 그대로 있으니 다시 시도해 주세요.'),
        findsOneWidget,
      );
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(saved?.name, '입력이 남아 있어요');
      expect(find.text('목적지 열기'), findsOneWidget);
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );
}
