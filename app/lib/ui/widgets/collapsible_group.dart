import 'package:flutter/material.dart';

import '../../theme.dart';

/// A collapsible admin group for the sidebar — a `Sym.label` header with a
/// chevron, matching the exact expand/collapse pattern used by the host
/// controls panel. Collapsed by default; keeps its own open/closed state.
///
/// [trailing] renders a tiny status glance on the right of the header even
/// while collapsed (e.g. a teal dot + a hosting code), so critical state is
/// never hidden entirely behind a fold.
class CollapsibleGroup extends StatefulWidget {
  final String title;

  /// A small status summary pinned to the header, visible collapsed or not.
  final Widget? trailing;

  /// The section content, revealed when the group is open.
  final Widget child;

  /// Start expanded instead of collapsed. Admin groups default to collapsed.
  final bool initiallyOpen;

  const CollapsibleGroup({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.initiallyOpen = false,
  });

  @override
  State<CollapsibleGroup> createState() => _CollapsibleGroupState();
}

class _CollapsibleGroupState extends State<CollapsibleGroup> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(child: Text(widget.title, style: Sym.label())),
                if (widget.trailing != null) ...[
                  widget.trailing!,
                  const SizedBox(width: 8),
                ],
                Icon(_open ? Icons.expand_less : Icons.expand_more,
                    size: 15, color: Sym.inkFaint),
              ],
            ),
          ),
        ),
        if (_open) widget.child,
      ],
    );
  }
}
