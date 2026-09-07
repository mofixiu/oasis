import 'package:flutter/material.dart';

/// A list whose rows arrive and leave rather than appearing and vanishing.
///
/// Every list in this app changes under the reader: an application is
/// approved and leaves the pending pile, a booking request is declined, a
/// notification is read and drops out of the unread filter. Rebuilt from a
/// plain `Column`, all of those are a jump: the row is simply not there on
/// the next frame and everything below it snaps up by its height. With
/// optimistic updates that jump now happens *instantly* on tap, which makes
/// it more noticeable, not less.
///
/// This diffs by key on each rebuild and animates the difference: removals
/// collapse and fade, insertions expand and rise. Callers keep passing a
/// plain list and a builder, so no screen has to hold an `AnimatedListState`
/// or remember to call `insertItem` itself, which is the part of `AnimatedList`
/// that nobody gets right twice.
class LandaAnimatedList<T> extends StatefulWidget {
  final List<T> items;

  /// Identity, not equality. Two rows are "the same row" when this matches,
  /// so an application whose status changed animates in place instead of
  /// being removed and re-inserted.
  final Object Function(T item) keyOf;

  final Widget Function(BuildContext context, T item, int index) itemBuilder;

  /// Vertical gap between rows, applied as bottom padding so it collapses
  /// with the row it belongs to.
  final double spacing;

  final Duration duration;

  const LandaAnimatedList({
    super.key,
    required this.items,
    required this.keyOf,
    required this.itemBuilder,
    this.spacing = 0,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  State<LandaAnimatedList<T>> createState() => _LandaAnimatedListState<T>();
}

class _LandaAnimatedListState<T> extends State<LandaAnimatedList<T>> {
  /// What is currently on screen, which is not the same as `widget.items`
  /// while a removal is still animating out.
  late List<T> _rendered = List<T>.from(widget.items);

  /// Rows that have been dropped from `items` but are still collapsing.
  /// Rendered from this snapshot, because the caller's list no longer has
  /// them and the builder needs something to build.
  final Map<Object, T> _leaving = {};

  /// Keys currently animating in or out, so a row is not re-animated by an
  /// unrelated rebuild halfway through its own transition.
  final Set<Object> _entering = {};

  @override
  void didUpdateWidget(covariant LandaAnimatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final nextKeys = widget.items.map(widget.keyOf).toSet();
    final renderedKeys = _rendered.map(widget.keyOf).toSet();

    final removed = renderedKeys.difference(nextKeys);
    final added = nextKeys.difference(renderedKeys);
    if (removed.isEmpty && added.isEmpty) {
      // Same rows, new contents: an approved application, a read
      // notification. Take the new objects so the rows redraw, and animate
      // nothing: the list did not change shape.
      setState(() => _rendered = List<T>.from(widget.items));
      return;
    }

    for (final item in _rendered) {
      final key = widget.keyOf(item);
      if (removed.contains(key)) _leaving[key] = item;
    }

    setState(() {
      _rendered = List<T>.from(widget.items);
      _entering.addAll(added);
    });

    // Held for the length of the collapse, then dropped. A row that is gone
    // from the data and finished animating has no business being rebuilt.
    if (removed.isNotEmpty) {
      Future.delayed(widget.duration, () {
        if (!mounted) return;
        setState(() => _leaving.removeWhere((key, _) => removed.contains(key)));
      });
    }
    if (added.isNotEmpty) {
      Future.delayed(widget.duration, () {
        if (!mounted) return;
        _entering.removeAll(added);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Leaving rows keep their old positions so the list collapses from where
    // the row actually was, rather than from the bottom.
    final rows = <_Row<T>>[
      for (final (index, item) in _rendered.indexed)
        _Row(key: widget.keyOf(item), item: item, index: index, leaving: false),
    ];
    for (final entry in _leaving.entries) {
      if (rows.any((row) => row.key == entry.key)) continue;
      rows.add(
        _Row(
          key: entry.key,
          item: entry.value,
          index: rows.length,
          leaving: true,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          _AnimatedRow(
            key: ValueKey(row.key),
            duration: widget.duration,
            // A row that was already on screen when this list was first built
            // must not play an entrance: otherwise every scroll back to a
            // loaded screen replays the whole list.
            entering: _entering.contains(row.key),
            leaving: row.leaving,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.spacing),
              child: widget.itemBuilder(context, row.item, row.index),
            ),
          ),
      ],
    );
  }
}

/// One row's identity and state during a diff.
class _Row<T> {
  final Object key;
  final T item;
  final int index;
  final bool leaving;

  const _Row({
    required this.key,
    required this.item,
    required this.index,
    required this.leaving,
  });
}

/// The collapse-and-fade applied to a single row.
///
/// `AnimatedSize` rather than a slide, because the rows below have to close
/// the gap smoothly: sliding one row out and leaving a hole is the same jump
/// with an animation on top of it.
class _AnimatedRow extends StatefulWidget {
  final Widget child;
  final bool entering;
  final bool leaving;
  final Duration duration;

  const _AnimatedRow({
    super.key,
    required this.child,
    required this.entering,
    required this.leaving,
    required this.duration,
  });

  @override
  State<_AnimatedRow> createState() => _AnimatedRowState();
}

class _AnimatedRowState extends State<_AnimatedRow> {
  late bool _open = !widget.entering;

  @override
  void initState() {
    super.initState();
    if (widget.entering) {
      // One frame closed, then open: an `AnimatedSize` that is built at its
      // final height has nothing to animate from.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _open = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving && _open) {
      setState(() => _open = false);
    } else if (!widget.leaving && !_open && !widget.entering) {
      setState(() => _open = true);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: widget.duration,
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: AnimatedOpacity(
      opacity: _open ? 1 : 0,
      duration: widget.duration,
      curve: Curves.easeOut,
      // Clipped and height-factored rather than removed from the tree: the
      // row keeps its full layout, so nothing inside it reflows on the way
      // out, while the box around it reports a height of zero for
      // `AnimatedSize` to travel to.
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _open ? 1.0 : 0.0,
          child: widget.child,
        ),
      ),
    ),
  );
}
