import 'package:flutter/material.dart';

class RawJsonTreeWidget extends StatelessWidget {
  final dynamic data;
  final String? label;

  const RawJsonTreeWidget({super.key, required this.data, this.label});

  @override
  Widget build(BuildContext context) {
    return _buildNode(context, label, data, 0);
  }

  Widget _buildNode(BuildContext context, String? key, dynamic value, int depth) {
    if (value is Map<String, dynamic>) {
      return _MapNode(label: key, data: value, depth: depth);
    } else if (value is List) {
      return _ListNode(label: key, data: value, depth: depth);
    } else {
      return _PrimitiveNode(label: key, value: value);
    }
  }
}

// ─── Map Node ──────────────────────────────────────────────────────────────

class _MapNode extends StatefulWidget {
  final String? label;
  final Map<String, dynamic> data;
  final int depth;

  const _MapNode({this.label, required this.data, required this.depth});

  @override
  State<_MapNode> createState() => _MapNodeState();
}

class _MapNodeState extends State<_MapNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final header = Row(
      children: [
        Icon(
          _expanded ? Icons.expand_more : Icons.chevron_right,
          size: 16,
          color: cs.onSurface,
        ),
        if (widget.label != null) ...[
          Text(
            '${widget.label}: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: cs.onSurface,
            ),
          ),
        ],
        Text(
          '{${widget.data.length}}',
          style: TextStyle(
            color: cs.outline,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.only(left: widget.depth * 12.0),
            child: header,
          ),
        ),
        if (_expanded)
          ...widget.data.entries.map((e) {
            return Padding(
              padding: EdgeInsets.only(left: (widget.depth + 1) * 12.0),
              child: RawJsonTreeWidget(data: e.value, label: e.key),
            );
          }),
      ],
    );
  }
}

// ─── List Node ─────────────────────────────────────────────────────────────

class _ListNode extends StatefulWidget {
  final String? label;
  final List data;
  final int depth;

  const _ListNode({this.label, required this.data, required this.depth});

  @override
  State<_ListNode> createState() => _ListNodeState();
}

class _ListNodeState extends State<_ListNode> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.only(left: widget.depth * 12.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: cs.onSurface,
                ),
                if (widget.label != null)
                  Text(
                    '${widget.label}: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: cs.onSurface,
                    ),
                  ),
                Text(
                  '[${widget.data.length}]',
                  style: TextStyle(
                    color: cs.tertiary,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          ...widget.data.asMap().entries.map((e) {
            return Padding(
              padding: EdgeInsets.only(left: (widget.depth + 1) * 12.0),
              child: RawJsonTreeWidget(data: e.value, label: '[${e.key}]'),
            );
          }),
      ],
    );
  }
}

// ─── Primitive Node ────────────────────────────────────────────────────────

class _PrimitiveNode extends StatelessWidget {
  final String? label;
  final dynamic value;

  const _PrimitiveNode({this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 타입별 색상 — colorScheme 기반으로 다크모드 자동 대응
    final Color valueColor;
    if (value is String) {
      valueColor = cs.tertiary;      // 문자열
    } else if (value is num) {
      valueColor = cs.secondary;     // 숫자
    } else if (value is bool) {
      valueColor = cs.primary;       // 불리언
    } else {
      valueColor = cs.onSurface;     // null 등 기타
    }

    final displayValue = value == null ? 'null' : value.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context)
              .style
              .copyWith(fontFamily: 'monospace', fontSize: 12),
          children: [
            if (label != null)
              TextSpan(
                text: '$label: ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            TextSpan(
              text: value is String ? '"$displayValue"' : displayValue,
              style: TextStyle(color: valueColor),
            ),
          ],
        ),
      ),
    );
  }
}
