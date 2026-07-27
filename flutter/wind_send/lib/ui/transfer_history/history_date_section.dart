import 'package:flutter/material.dart';

/// A transfer-history date section whose pinned header is bounded by its items.
final class SliverHistoryDateSection extends StatelessWidget {
  const SliverHistoryDateSection({
    super.key,
    required this.title,
    required this.headerBackgroundColor,
    required this.headerForegroundColor,
    required this.itemDelegate,
  });

  static const double headerExtent = 40.0;

  final String title;
  final Color headerBackgroundColor;
  final Color headerForegroundColor;
  final SliverChildDelegate itemDelegate;

  @override
  Widget build(BuildContext context) {
    // A persistent header cannot infer where the list after it ends. Giving the
    // header and its items one sliver boundary prevents completed date headers
    // from remaining pinned while later sections scroll into view.
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HistoryDateHeaderDelegate(
            title: title,
            backgroundColor: headerBackgroundColor,
            foregroundColor: headerForegroundColor,
          ),
        ),
        SliverList(delegate: itemDelegate),
      ],
    );
  }
}

final class _HistoryDateHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _HistoryDateHeaderDelegate({
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String title;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  double get minExtent => SliverHistoryDateSection.headerExtent;

  @override
  double get maxExtent => SliverHistoryDateSection.headerExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: SliverHistoryDateSection.headerExtent,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: foregroundColor,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HistoryDateHeaderDelegate oldDelegate) {
    return title != oldDelegate.title ||
        backgroundColor != oldDelegate.backgroundColor ||
        foregroundColor != oldDelegate.foregroundColor;
  }
}
