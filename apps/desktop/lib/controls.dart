import 'package:fluent_ui/fluent_ui.dart';

import 'l10n/app_localizations.dart';

/// A setting: its name, one line of help, then its control. A section's
/// only setting leaves the name to the section title.
class Field extends StatelessWidget {
  const Field({super.key, this.label, this.help, required this.child});

  final String? label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final typography = FluentTheme.of(context).typography;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label case final label?)
            Text(label, style: typography.bodyStrong),
          if (help case final help?)
            Padding(
              padding: EdgeInsets.only(top: label == null ? 0 : 2),
              child: Text(
                help,
                style: typography.caption?.copyWith(
                  color: FluentTheme.of(context)
                      .resources
                      .textFillColorSecondary,
                ),
              ),
            ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// A group of [Field]s under a heading, drawn as a card; spacing between
/// sections is left to their parent.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: FluentTheme.of(context).typography.subtitle),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

/// One choice of a [Picker] or a [ChoiceBox].
typedef Choice<T> = ({T value, String title, String? detail});

/// A drop-down limited to [choices], with each one's meaning below it.
class ChoiceBox<T> extends StatelessWidget {
  const ChoiceBox({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final T value;
  final List<Choice<T>> choices;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final detail = choices.where((c) => c.value == value).firstOrNull?.detail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ComboBox<T>(
          value: value,
          items: [
            for (final choice in choices)
              ComboBoxItem(value: choice.value, child: Text(choice.title)),
          ],
          onChanged: onChanged == null
              ? null
              : (picked) => onChanged!(picked as T),
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              detail,
              style: FluentTheme.of(context).typography.caption,
            ),
          ),
      ],
    );
  }
}

/// An ordered list shown as badges that reorder by dragging.
///
/// With a [pool], the values left out are shown below; dragging one up or
/// clicking it adds it, and dragging a badge down to the pool removes it.
class BadgeFlow<T extends Object> extends StatelessWidget {
  const BadgeFlow({
    super.key,
    required this.values,
    required this.label,
    required this.onChanged,
    this.tooltip,
    this.pool,
    this.numbered = false,
    this.trailing,
    this.empty,
  });

  final List<T> values;
  final String Function(T value) label;
  final String? Function(T value)? tooltip;

  /// Null disables every interaction.
  final ValueChanged<List<T>>? onChanged;
  final List<T>? pool;
  final bool numbered;

  /// Shown after the badges, usually the button that adds one.
  final Widget? trailing;

  /// Shown instead of the badges when [values] is empty.
  final String? empty;

  List<T> _moved(T value, int index) {
    final from = values.indexOf(value);
    final list = [...values]..remove(value);
    final at = from >= 0 && from < index ? index - 1 : index;
    return list..insert(at.clamp(0, list.length), value);
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    final theme = FluentTheme.of(context);
    final pool = this.pool?.where((v) => !values.contains(v)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (values.isEmpty && empty != null)
              Text(empty!, style: theme.typography.caption),
            for (final (index, value) in values.indexed)
              _Slot<T>(
                onDrop: onChanged == null
                    ? null
                    : (dropped) => onChanged(_moved(dropped, index)),
                child: _Draggable<T>(
                  value: value,
                  enabled: onChanged != null,
                  badge: _Badge(
                    label: numbered
                        ? '${index + 1}  ${label(value)}'
                        : label(value),
                    tooltip: tooltip?.call(value),
                    filled: true,
                    onRemove: onChanged == null
                        ? null
                        : () => onChanged([...values]..remove(value)),
                  ),
                ),
              ),
            _Slot<T>(
              onDrop: onChanged == null
                  ? null
                  : (dropped) => onChanged(_moved(dropped, values.length)),
              child: trailing ?? const SizedBox(width: 24, height: 30),
            ),
          ],
        ),
        if (pool != null) ...[
          const SizedBox(height: 8),
          DragTarget<T>(
            onWillAcceptWithDetails: (details) =>
                onChanged != null && values.contains(details.data),
            onAcceptWithDetails: (details) =>
                onChanged?.call([...values]..remove(details.data)),
            builder: (context, candidates, _) => Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: candidates.isEmpty
                      ? theme.resources.dividerStrokeColorDefault
                      : theme.accentColor,
                ),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    pool.isEmpty
                        ? AppLocalizations.of(context).dropToLeaveOut
                        : AppLocalizations.of(context).notUsed,
                    style: theme.typography.caption,
                  ),
                  for (final value in pool)
                    _Draggable<T>(
                      value: value,
                      enabled: onChanged != null,
                      badge: _Badge(
                        label: label(value),
                        tooltip: tooltip?.call(value),
                        filled: false,
                        onPressed: onChanged == null
                            ? null
                            : () => onChanged([...values, value]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Accepts a dragged badge and marks where it would land.
class _Slot<T extends Object> extends StatelessWidget {
  const _Slot({required this.onDrop, required this.child});

  final ValueChanged<T>? onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) => DragTarget<T>(
    onWillAcceptWithDetails: (_) => onDrop != null,
    onAcceptWithDetails: (details) => onDrop?.call(details.data),
    builder: (context, candidates, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: candidates.isEmpty ? 0 : 3,
          height: 28,
          margin: EdgeInsets.only(right: candidates.isEmpty ? 0 : 4),
          decoration: BoxDecoration(
            color: FluentTheme.of(context).accentColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Flexible(child: child),
      ],
    ),
  );
}

class _Draggable<T extends Object> extends StatelessWidget {
  const _Draggable({
    required this.value,
    required this.badge,
    required this.enabled,
  });

  final T value;
  final Widget badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return badge;
    final style = DefaultTextStyle.of(context).style;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<T>(
        data: value,
        feedback: DefaultTextStyle(
          style: style,
          child: FluentTheme(data: FluentTheme.of(context), child: badge),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: badge),
        child: badge,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.filled,
    this.tooltip,
    this.onRemove,
    this.onPressed,
  });

  final String label;
  final String? tooltip;
  final bool filled;
  final VoidCallback? onRemove;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final foreground = filled
        ? theme.resources.textOnAccentFillColorPrimary
        : theme.resources.textFillColorPrimary;
    final badge = Container(
      height: 30,
      padding: EdgeInsets.only(left: 10, right: onRemove == null ? 10 : 2),
      decoration: BoxDecoration(
        color: filled
            ? theme.accentColor.defaultBrushFor(theme.brightness)
            : theme.resources.controlFillColorDefault,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: foreground),
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: Icon(FluentIcons.chrome_close, size: 9, color: foreground),
              onPressed: onRemove,
            ),
        ],
      ),
    );
    final interactive = onPressed == null
        ? badge
        : GestureDetector(onTap: onPressed, child: badge);
    return tooltip == null
        ? interactive
        : Tooltip(message: tooltip!, child: interactive);
  }
}

/// A button that opens a filterable list of [choices]; [custom] also
/// accepts what was typed when nothing matches it exactly.
class Picker extends StatefulWidget {
  const Picker({
    super.key,
    required this.label,
    required this.onPicked,
    this.choices = const [],
    this.load,
    this.custom = false,
  });

  final String label;
  final List<Choice<String>> choices;

  /// Reads the choices when the list opens, replacing [choices].
  final Future<List<Choice<String>>> Function()? load;
  final ValueChanged<String>? onPicked;
  final bool custom;

  @override
  State<Picker> createState() => _PickerState();
}

class _PickerState extends State<Picker> {
  final _flyout = FlyoutController();

  @override
  void dispose() {
    _flyout.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final choices = await widget.load?.call() ?? widget.choices;
    if (!mounted) return;
    await _flyout.showFlyout<void>(
      placementMode: FlyoutPlacementMode.bottomLeft,
      builder: (context) => _PickerFlyout(
        choices: choices,
        custom: widget.custom,
        onPicked: (value) {
          Navigator.of(context).pop();
          widget.onPicked?.call(value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FlyoutTarget(
    controller: _flyout,
    child: Button(
      onPressed: widget.onPicked == null ? null : _open,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.add, size: 11),
          const SizedBox(width: 6),
          Text(widget.label),
        ],
      ),
    ),
  );
}

class _PickerFlyout extends StatefulWidget {
  const _PickerFlyout({
    required this.choices,
    required this.custom,
    required this.onPicked,
  });

  final List<Choice<String>> choices;
  final bool custom;
  final ValueChanged<String> onPicked;

  @override
  State<_PickerFlyout> createState() => _PickerFlyoutState();
}

class _PickerFlyoutState extends State<_PickerFlyout> {
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final query = filter.trim().toLowerCase();
    final matches = [
      for (final choice in widget.choices)
        if (choice.title.toLowerCase().contains(query) ||
            choice.value.toLowerCase().contains(query) ||
            (choice.detail?.toLowerCase().contains(query) ?? false))
          choice,
    ];
    final typed = filter.trim();
    final offerTyped =
        widget.custom &&
        typed.isNotEmpty &&
        !widget.choices.any((c) => c.value.toLowerCase() == query);
    return FlyoutContent(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
      child: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextBox(
              autofocus: true,
              placeholder: widget.custom
                  ? AppLocalizations.of(context).filterOrType
                  : AppLocalizations.of(context).filter,
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(FluentIcons.search, size: 12),
              ),
              onChanged: (text) => setState(() => filter = text),
              onSubmitted: (_) {
                if (offerTyped) {
                  widget.onPicked(typed);
                } else if (matches.isNotEmpty) {
                  widget.onPicked(matches.first.value);
                }
              },
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (offerTyped)
                    ListTile(
                      leading: const Icon(FluentIcons.add, size: 12),
                      title: Text(AppLocalizations.of(context).useTyped(typed)),
                      onPressed: () => widget.onPicked(typed),
                    ),
                  for (final choice in matches)
                    ListTile(
                      title: Text(choice.title),
                      subtitle: choice.detail == null
                          ? null
                          : Text(choice.detail!),
                      onPressed: () => widget.onPicked(choice.value),
                    ),
                  if (matches.isEmpty && !offerTyped)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(AppLocalizations.of(context).nothingMatches),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A text box that shows [value] whenever it changes from outside.
class SyncedTextBox extends StatefulWidget {
  const SyncedTextBox({
    super.key,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.enabled = true,
    this.onSubmitted,
    this.suffix,
    this.focusNode,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? placeholder;
  final bool enabled;
  final Widget? suffix;
  final FocusNode? focusNode;

  @override
  State<SyncedTextBox> createState() => _SyncedTextBoxState();
}

class _SyncedTextBoxState extends State<SyncedTextBox> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(SyncedTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _text.text) {
      _text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextBox(
    controller: _text,
    focusNode: widget.focusNode,
    enabled: widget.enabled,
    placeholder: widget.placeholder,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    suffix: widget.suffix,
  );
}

/// A path that can be typed or chosen with [browse]; empty means none.
class PathBox extends StatelessWidget {
  const PathBox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.browse,
    this.placeholder,
  });

  final String? value;

  /// Null disables the box.
  final ValueChanged<String?>? onChanged;
  final Future<String?> Function() browse;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final onChanged = this.onChanged;
    return Row(
      children: [
        Expanded(
          child: SyncedTextBox(
            value: value ?? '',
            enabled: onChanged != null,
            placeholder: placeholder,
            onChanged: (text) =>
                onChanged?.call(text.trim().isEmpty ? null : text.trim()),
            suffix: value == null || onChanged == null
                ? null
                : IconButton(
                    icon: const Icon(FluentIcons.chrome_close, size: 9),
                    onPressed: () => onChanged(null),
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: AppLocalizations.of(context).browse,
          child: Button(
            onPressed: onChanged == null
                ? null
                : () async {
                    if (await browse() case final picked?) onChanged(picked);
                  },
            child: const Icon(FluentIcons.open_folder_horizontal, size: 14),
          ),
        ),
      ],
    );
  }
}

/// A vertical scroll view that keeps a fixed [gutter] on its right for the
/// scrollbar, centred in it, so the content never changes width when the bar
/// shows or hides.
class GutterScrollView extends StatefulWidget {
  const GutterScrollView({super.key, required this.child, this.gutter = 16});

  final Widget child;
  final double gutter;

  @override
  State<GutterScrollView> createState() => _GutterScrollViewState();
}

class _GutterScrollViewState extends State<GutterScrollView> {
  /// The widest a Fluent scrollbar track gets, while hovered.
  static const _track = 12.0;

  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outside = (widget.gutter - _track) / 2;
    return Padding(
      padding: EdgeInsets.only(right: outside),
      child: Scrollbar(
        controller: _scroll,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.only(right: widget.gutter - outside),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
