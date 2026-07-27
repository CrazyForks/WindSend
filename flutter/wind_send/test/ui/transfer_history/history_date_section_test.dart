import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/ui/transfer_history/history_date_section.dart';

const double _itemExtent = 200.0;
const int _itemsPerSection = 2;
const double _sectionExtent =
    SliverHistoryDateSection.headerExtent + _itemExtent * _itemsPerSection;

void main() {
  testWidgets('a pinned date header leaves with its history section', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    const titles = ['July 27', 'July 26', 'July 25'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: CustomScrollView(
              controller: controller,
              slivers: [
                for (final title in titles) _buildSection(title),
                const SliverToBoxAdapter(child: SizedBox(height: 600)),
              ],
            ),
          ),
        ),
      ),
    );

    final viewport = tester.getRect(find.byType(CustomScrollView));

    controller.jumpTo(_sectionExtent + 40);
    await tester.pump();
    expect(_headersIntersecting(tester, titles, viewport), equals({'July 26'}));

    controller.jumpTo(_sectionExtent * 2 + 40);
    await tester.pump();
    expect(_headersIntersecting(tester, titles, viewport), equals({'July 25'}));
  });
}

SliverHistoryDateSection _buildSection(String title) {
  return SliverHistoryDateSection(
    title: title,
    headerBackgroundColor: Colors.white,
    headerForegroundColor: Colors.black,
    itemDelegate: SliverChildBuilderDelegate(
      (_, index) => SizedBox(height: _itemExtent, child: Text('item $index')),
      childCount: _itemsPerSection,
    ),
  );
}

Set<String> _headersIntersecting(
  WidgetTester tester,
  List<String> titles,
  Rect viewport,
) {
  return {
    for (final title in titles)
      if (_renderedTextRects(tester, title).any(viewport.overlaps)) title,
  };
}

Iterable<Rect> _renderedTextRects(WidgetTester tester, String text) sync* {
  final elements = find.text(text, skipOffstage: false).evaluate();
  for (final element in elements) {
    final renderObject = element.renderObject;
    if (renderObject is RenderBox && renderObject.hasSize) {
      yield renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
  }
}
