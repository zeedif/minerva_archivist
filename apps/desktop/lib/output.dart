import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:minerva_core/minerva_core.dart';

import 'l10n/app_localizations.dart';
import 'run_controller.dart';
import 'settings.dart';

/// Where the output panel sits.
enum Dock { left, bottom, right, floating }

/// The output panel's place and size, remembered across launches.
final class OutputLayout extends ChangeNotifier {
  OutputLayout({this.settings});

  final AppSettings? settings;
  Dock dock = Dock.right;
  bool visible = true;

  /// Width when docked to a side.
  double side = 440;

  /// Height when docked at the bottom.
  double bottom = 280;

  /// Bounds when floating, relative to the area the panel lives in.
  Rect floating = const Rect.fromLTWH(120, 80, 640, 380);

  Future<void> restore() async {
    if (await settings?.value('output') case final Map<String, Object?> v) {
      dock = Dock.values.asNameMap()[v['dock']] ?? dock;
      visible = v['visible'] as bool? ?? visible;
      side = (v['side'] as num?)?.toDouble() ?? side;
      bottom = (v['bottom'] as num?)?.toDouble() ?? bottom;
      if (v['floating'] case [
        final num l,
        final num t,
        final num w,
        final num h,
      ]) {
        floating = Rect.fromLTWH(
          l.toDouble(),
          t.toDouble(),
          w.toDouble(),
          h.toDouble(),
        );
      }
    }
  }

  /// Applies [change], redraws and, unless [transient], stores the result.
  void update(void Function() change, {bool transient = false}) {
    change();
    notifyListeners();
    if (!transient) save();
  }

  void save() => settings?.setValue('output', {
    'dock': dock.name,
    'visible': visible,
    'side': side,
    'bottom': bottom,
    'floating': [floating.left, floating.top, floating.width, floating.height],
  });
}

/// Lays out [content] with the output panel docked beside it, below it or
/// floating over it. Dragging the panel's title bar undocks it; dropping it
/// on an edge docks it there.
class OutputHost extends StatefulWidget {
  const OutputHost({
    super.key,
    required this.layout,
    required this.controller,
    required this.content,
  });

  final OutputLayout layout;
  final RunController controller;
  final Widget content;

  @override
  State<OutputHost> createState() => _OutputHostState();
}

class _OutputHostState extends State<OutputHost> {
  static const _zone = 56.0;

  bool _dragging = false;
  Dock? _target;
  Offset _grab = Offset.zero;
  Size _size = Size.zero;

  OutputLayout get _layout => widget.layout;

  Rect _bounds(Size size) {
    final l = _layout;
    final side = l.side.clamp(260.0, size.width * 0.75);
    final bottom = l.bottom.clamp(140.0, size.height * 0.85);
    return switch (l.dock) {
      Dock.left => Rect.fromLTWH(0, 0, side, size.height),
      Dock.right => Rect.fromLTWH(size.width - side, 0, side, size.height),
      Dock.bottom => Rect.fromLTWH(0, size.height - bottom, size.width, bottom),
      Dock.floating => _clamp(l.floating, size),
    };
  }

  static Rect _clamp(Rect rect, Size size) {
    final width = rect.width.clamp(280.0, size.width);
    final height = rect.height.clamp(160.0, size.height);
    return Rect.fromLTWH(
      rect.left.clamp(0.0, size.width - width),
      rect.top.clamp(0.0, size.height - height),
      width,
      height,
    );
  }

  Dock? _zoneAt(Offset point) {
    if (point.dx < _zone) return Dock.left;
    if (point.dx > _size.width - _zone) return Dock.right;
    if (point.dy > _size.height - _zone) return Dock.bottom;
    return null;
  }

  Offset _local(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global);

  void _startMove(DragStartDetails details) {
    final point = _local(details.globalPosition);
    final l = _layout;
    if (l.dock != Dock.floating) {
      final rect = Rect.fromLTWH(
        point.dx - 120,
        point.dy - 16,
        l.floating.width,
        l.floating.height,
      );
      l.update(() {
        l.floating = _clamp(rect, _size);
        l.dock = Dock.floating;
      }, transient: true);
    }
    _grab = point - l.floating.topLeft;
    setState(() => _dragging = true);
  }

  void _move(DragUpdateDetails details) {
    final point = _local(details.globalPosition);
    final l = _layout;
    l.update(() {
      l.floating = _clamp((point - _grab) & l.floating.size, _size);
    }, transient: true);
    setState(() => _target = _zoneAt(point));
  }

  void _endMove(DragEndDetails _) {
    final target = _target;
    setState(() {
      _dragging = false;
      _target = null;
    });
    _layout.update(() {
      if (target != null) _layout.dock = target;
    });
  }

  void _resize(Offset delta) {
    final l = _layout;
    l.update(() {
      switch (l.dock) {
        case Dock.left:
          l.side = (l.side + delta.dx).clamp(260.0, _size.width * 0.75);
        case Dock.right:
          l.side = (l.side - delta.dx).clamp(260.0, _size.width * 0.75);
        case Dock.bottom:
          l.bottom = (l.bottom - delta.dy).clamp(140.0, _size.height * 0.85);
        case Dock.floating:
          l.floating = _clamp(
            l.floating.topLeft &
                Size(l.floating.width + delta.dx, l.floating.height + delta.dy),
            _size,
          );
      }
    }, transient: true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _layout,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final l = _layout;
        final shown = l.visible;
        final rect = _bounds(_size);
        final inset = !shown
            ? EdgeInsets.zero
            : switch (l.dock) {
                Dock.left => EdgeInsets.only(left: rect.width),
                Dock.right => EdgeInsets.only(right: rect.width),
                Dock.bottom => EdgeInsets.only(bottom: rect.height),
                Dock.floating => EdgeInsets.zero,
              };
        return Stack(
          children: [
            Positioned.fill(
              child: Padding(padding: inset, child: widget.content),
            ),
            if (shown)
              Positioned.fromRect(
                rect: rect,
                child: _Panel(
                  layout: l,
                  controller: widget.controller,
                  onMoveStart: _startMove,
                  onMove: _move,
                  onMoveEnd: _endMove,
                  onResize: _resize,
                  onResizeEnd: l.save,
                ),
              ),
            if (_dragging)
              for (final dock in const [Dock.left, Dock.right, Dock.bottom])
                _DropZone(dock: dock, size: _size, active: _target == dock),
          ],
        );
      },
    ),
  );
}

/// The edge that docks the panel when it is dropped there.
class _DropZone extends StatelessWidget {
  const _DropZone({
    required this.dock,
    required this.size,
    required this.active,
  });

  final Dock dock;
  final Size size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = FluentTheme.of(context).accentColor;
    final preview = switch (dock) {
      Dock.left => Rect.fromLTWH(0, 0, size.width / 3, size.height),
      Dock.right => Rect.fromLTWH(
        size.width * 2 / 3,
        0,
        size.width / 3,
        size.height,
      ),
      _ => Rect.fromLTWH(0, size.height * 2 / 3, size.width, size.height / 3),
    };
    final strip = switch (dock) {
      Dock.left => Rect.fromLTWH(0, 0, 6, size.height),
      Dock.right => Rect.fromLTWH(size.width - 6, 0, 6, size.height),
      _ => Rect.fromLTWH(0, size.height - 6, size.width, 6),
    };
    return Positioned.fromRect(
      rect: active ? preview : strip,
      child: IgnorePointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: active ? 0.18 : 0.5),
            border: active ? Border.all(color: accent, width: 2) : null,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.layout,
    required this.controller,
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
    required this.onResize,
    required this.onResizeEnd,
  });

  final OutputLayout layout;
  final RunController controller;
  final GestureDragStartCallback onMoveStart;
  final GestureDragUpdateCallback onMove;
  final GestureDragEndCallback onMoveEnd;
  final ValueChanged<Offset> onResize;
  final VoidCallback onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final floating = layout.dock == Dock.floating;
    final palette = _Palette(context);
    final divider = BorderSide(color: palette.divider);
    final panel = Container(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: floating ? BorderRadius.circular(8) : null,
        border: switch (layout.dock) {
          Dock.left => Border(right: divider),
          Dock.right => Border(left: divider),
          Dock.bottom => Border(top: divider),
          Dock.floating => Border.all(color: palette.stroke),
        },
        boxShadow: floating ? kElevationToShadow[8] : null,
      ),
      clipBehavior: floating ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleBar(
            layout: layout,
            controller: controller,
            onMoveStart: onMoveStart,
            onMove: onMove,
            onMoveEnd: onMoveEnd,
          ),
          Expanded(child: OutputLog(controller)),
        ],
      ),
    );
    final handle = switch (layout.dock) {
      Dock.left => (Alignment.centerRight, SystemMouseCursors.resizeColumn),
      Dock.right => (Alignment.centerLeft, SystemMouseCursors.resizeColumn),
      Dock.bottom => (Alignment.topCenter, SystemMouseCursors.resizeRow),
      Dock.floating => (
        Alignment.bottomRight,
        SystemMouseCursors.resizeDownRight,
      ),
    };
    final (alignment, cursor) = handle;
    final horizontal = layout.dock == Dock.left || layout.dock == Dock.right;
    return Stack(
      children: [
        Positioned.fill(child: panel),
        Align(
          alignment: alignment,
          child: MouseRegion(
            cursor: cursor,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (details) => onResize(details.delta),
              onPanEnd: (_) => onResizeEnd(),
              child: SizedBox(
                width: horizontal ? 8 : (floating ? 16 : double.infinity),
                height: horizontal ? double.infinity : (floating ? 16 : 8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.layout,
    required this.controller,
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
  });

  final OutputLayout layout;
  final RunController controller;
  final GestureDragStartCallback onMoveStart;
  final GestureDragUpdateCallback onMove;
  final GestureDragEndCallback onMoveEnd;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);
    final l = AppLocalizations.of(context);
    Widget button(String tip, Widget icon, VoidCallback? onPressed) => Tooltip(
      message: tip,
      child: IconButton(icon: icon, onPressed: onPressed),
    );
    Widget dockButton(Dock dock, String tip) => button(
      tip,
      _DockGlyph(dock, selected: layout.dock == dock),
      () => layout.update(() => layout.dock = dock),
    );
    return Container(
      height: 36,
      color: palette.bar,
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: onMoveStart,
                onPanUpdate: onMove,
                onPanEnd: onMoveEnd,
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.command_prompt,
                      size: 13,
                      color: palette.dim,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.output,
                      style: TextStyle(color: palette.text, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          button(
            l.copyAll,
            Icon(FluentIcons.copy, size: 13, color: palette.dim),
            () => Clipboard.setData(
              ClipboardData(text: outputLines(controller, l).join('\n')),
            ),
          ),
          dockButton(Dock.left, l.dockLeft),
          dockButton(Dock.bottom, l.dockBottom),
          dockButton(Dock.right, l.dockRight),
          dockButton(Dock.floating, l.float),
          button(
            l.hidePanel,
            Icon(FluentIcons.chrome_close, size: 11, color: palette.dim),
            () => layout.update(() => layout.visible = false),
          ),
        ],
      ),
    );
  }
}

/// A window outline with the panel's place filled in.
class _DockGlyph extends StatelessWidget {
  const _DockGlyph(this.dock, {required this.selected});

  final Dock dock;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? FluentTheme.of(context).accentColor
        : _Palette(context).dim;
    return SizedBox(
      width: 16,
      height: 13,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.2),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Align(
          alignment: switch (dock) {
            Dock.left => Alignment.centerLeft,
            Dock.right => Alignment.centerRight,
            Dock.bottom => Alignment.bottomCenter,
            Dock.floating => Alignment.center,
          },
          child: FractionallySizedBox(
            widthFactor: switch (dock) {
              Dock.left || Dock.right => 0.4,
              Dock.bottom => 1,
              Dock.floating => 0.55,
            },
            heightFactor: switch (dock) {
              Dock.bottom => 0.45,
              Dock.floating => 0.55,
              _ => 1,
            },
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

/// The panel's colors, taken from the Fluent theme so it matches the window
/// in light and dark mode.
final class _Palette {
  _Palette(BuildContext context) : this._(FluentTheme.of(context));

  _Palette._(FluentThemeData theme)
    : background = theme.resources.solidBackgroundFillColorSecondary,
      bar = theme.resources.solidBackgroundFillColorTertiary,
      text = theme.resources.textFillColorPrimary,
      dim = theme.resources.textFillColorSecondary,
      heading = theme.accentColor.defaultBrushFor(theme.brightness),
      error = theme.resources.systemFillColorCritical,
      divider = theme.resources.dividerStrokeColorDefault,
      stroke = theme.resources.cardStrokeColorDefault;

  final Color background;
  final Color bar;
  final Color text;
  final Color dim;
  final Color heading;
  final Color error;
  final Color divider;
  final Color stroke;

  Color? tone(_Tone? tone) => switch (tone) {
    null => null,
    _Tone.dim => dim,
    _Tone.heading => heading,
    _Tone.error => error,
  };

  TextStyle get mono => TextStyle(
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: const [
      'Consolas',
      'Menlo',
      'DejaVu Sans Mono',
      'Liberation Mono',
      'monospace',
    ],
    fontSize: 12.5,
    height: 1.4,
    color: text,
  );
}

/// How a report line is drawn; null is plain text.
enum _Tone { dim, heading, error }

/// What the last preview or run reported, as plain text lines.
List<String> outputLines(RunController controller, AppLocalizations l) => [
  for (final (line, _) in _styledLines(controller, l)) line,
];

/// Each line with how it is drawn: null for plain text.
List<(String, _Tone?)> _styledLines(
  RunController controller,
  AppLocalizations l,
) {
  final dry = controller.applied ? '' : l.logPreview;
  return [
    if (controller.sync case (:final downloaded, :final errors))
      (
        '${l.logSync(downloaded)}${errors == 0 ? '' : l.logSyncErrors(errors)}',
        _Tone.dim,
      ),
    for (final platform in controller.platforms) ...[
      ('', null),
      ('== ${platform.name ?? l.logRun}', _Tone.heading),
      if (platform.selection case final selection?) ...[
        (
          '${l.logSelected(selection.stats.selected, selection.stats.total)}'
              '${selection.stats.reasons.isEmpty ? "" : "  (${selection.stats.reasons.join(', ')})"}',
          null,
        ),
        for (final entry in selection.unmatchedWishlist)
          (l.logWishlistUnmatched(entry), null),
      ],
      if (platform.audit case final audit?)
        (
          l.logAudit(
            audit.present.length,
            audit.results.length,
            audit.missing.length,
            audit.unknownFiles.length,
          ),
          null,
        ),
      if (platform.download case final download?) ...[
        (
          '${l.logToDownload(download.plan.selected.length, _size(download.plan.totalBytes))}'
              '${download.seeders == null ? "" : l.logSeeders(download.seeders!)}$dry',
          null,
        ),
        for (final name in download.plan.unmatched)
          (l.logNotDistributed(name), null),
        for (final name in download.held) (l.logHeld(name), null),
      ],
      if (platform.transfer case final transfer?
          when platform.fetched == null) ...[
        (
          l.logTransfer(
            transfer.files.where((f) => f.isComplete).length,
            transfer.files.length,
            _size(transfer.done),
            _size(transfer.total),
            _size(transfer.bytesPerSecond),
            transfer.seeds,
            transfer.peers,
          ),
          _Tone.dim,
        ),
        for (final file in [...transfer.files]..sort(_byActivity))
          (
            '${_bar(file.fraction)} '
                '${(file.fraction * 100).toStringAsFixed(1).padLeft(5)}%  '
                '${_size(file.total).padLeft(9)}  ${file.name}',
            null,
          ),
      ],
      if (platform.fetched case final fetched?)
        (l.logDownloaded(fetched), null),
      if (platform.organized case final actions?)
        ('${l.logOrganize(actions.summary)}$dry', null),
      if (platform.playlists case final count?)
        ('${l.logPlaylists(count)}$dry', null),
      if (platform.pruned case final pruned?)
        ('${l.logPruned(pruned.moved.length, trashFolderName)}$dry', null),
      for (final failure in platform.failures) (failure, _Tone.error),
    ],
  ];
}

/// Active transfers first, then waiting, then finished.
int _byActivity(FileTransfer a, FileTransfer b) => _rank(a).compareTo(_rank(b));

int _rank(FileTransfer file) => switch (file) {
  FileTransfer(isComplete: true) => 2,
  FileTransfer(done: 0) => 1,
  _ => 0,
};

String _bar(double fraction) {
  final filled = (fraction * 20).round().clamp(0, 20);
  return '[${'#' * filled}${'.' * (20 - filled)}]';
}

String _size(int bytes) => switch (bytes) {
  >= 1 << 30 => '${(bytes / (1 << 30)).toStringAsFixed(2)} GB',
  >= 1 << 20 => '${(bytes / (1 << 20)).toStringAsFixed(1)} MB',
  _ => '${(bytes / 1024).toStringAsFixed(0)} KB',
};

/// The report as read-only text that can be selected and copied; it keeps
/// the newest lines in view while scrolled to the end.
class OutputLog extends StatefulWidget {
  const OutputLog(this.controller, {super.key});

  final RunController controller;

  @override
  State<OutputLog> createState() => _OutputLogState();
}

class _OutputLogState extends State<OutputLog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final l = AppLocalizations.of(context);
    final lines = _styledLines(c, l);
    final following = !_scroll.hasClients || _scroll.position.extentAfter < 24;
    if (following) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    final palette = _Palette(context);
    final spans = lines.isEmpty
        ? [
            TextSpan(
              text: c.running ? l.logStarting : l.logIdle,
              style: TextStyle(color: palette.dim),
            ),
          ]
        : [
            for (final (index, (line, tone)) in lines.indexed)
              TextSpan(
                text: index == lines.length - 1 ? line : '$line\n',
                style: tone == null
                    ? null
                    : TextStyle(color: palette.tone(tone)),
              ),
          ];
    return SelectionArea(
      contextMenuBuilder: (context, state) => _ContextMenu(
        anchor: state.contextMenuAnchors.primaryAnchor,
        items: state.contextMenuButtonItems,
      ),
      child: Scrollbar(
        controller: _scroll,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: Text.rich(TextSpan(children: spans), style: palette.mono),
            ),
          ),
        ),
      ),
    );
  }
}

/// Copy and Select all, drawn as a Fluent menu at [anchor].
class _ContextMenu extends StatelessWidget {
  const _ContextMenu({required this.anchor, required this.items});

  final Offset anchor;
  final List<ContextMenuButtonItem> items;

  static String _label(AppLocalizations l, ContextMenuButtonItem item) =>
      item.label ??
      switch (item.type) {
        ContextMenuButtonType.copy => l.menuCopy,
        ContextMenuButtonType.selectAll => l.menuSelectAll,
        ContextMenuButtonType.cut => l.menuCut,
        ContextMenuButtonType.paste => l.menuPaste,
        ContextMenuButtonType.delete => l.delete,
        _ => item.type.name,
      };

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        left: anchor.dx,
        top: anchor.dy,
        child: FlyoutContent(
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 240),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items)
                ListTile(
                  title: Text(_label(AppLocalizations.of(context), item)),
                  onPressed: item.onPressed,
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
