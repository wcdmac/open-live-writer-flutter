import 'package:flutter/material.dart';

/// Grouping container for a set of [RadioListTile]s.
///
/// Holds the shared `groupValue` and `onChanged` for the group and exposes
/// them to descendant tiles through [RadioGroup.of], so each tile only needs
/// to declare its own `value`/`title`/`subtitle` instead of repeating the
/// group wiring. Exactly one tile is selected at a time, matching the
/// standard `Radio` group semantics.
///
/// Children are built by [builder] with a [BuildContext] that sits *below*
/// the group's [InheritedWidget], so a [RadioListTile] inside it can read the
/// shared handlers via `RadioGroup.of<T>(context)`.
///
/// Usage:
/// ```dart
/// RadioGroup<MyType>(
///   groupValue: _selected,
///   onChanged: (v) { if (v != null) setState(() => _selected = v); },
///   builder: (context) => Column(children: [
///     RadioListTile<MyType>(
///       value: MyType.a,
///       groupValue: RadioGroup.of<MyType>(context).groupValue,
///       onChanged: RadioGroup.of<MyType>(context).onChanged,
///       title: Text('A'),
///     ),
///   ]),
/// )
/// ```
class RadioGroup<T> extends StatelessWidget {
  const RadioGroup({
    super.key,
    required this.groupValue,
    required this.onChanged,
    required this.builder,
  });

  final T? groupValue;
  final ValueChanged<T?>? onChanged;

  /// Builds the group's tiles. The supplied [BuildContext] is a descendant of
  /// the group's [InheritedWidget], so tiles may call [RadioGroup.of].
  final Widget Function(BuildContext context) builder;

  /// Reads the enclosing [RadioGroup<T>] from [context].
  ///
  /// Pass the result's [groupValue] / [onChanged] into a descendant
  /// [RadioListTile]; the tile then re-renders automatically whenever the
  /// group's selection changes.
  static _RadioGroupScope<T> of<T>(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_RadioGroupScope<T>>();
    assert(
      scope != null,
      'RadioGroup.of<$T> called outside of a RadioGroup<$T> ancestor',
    );
    return scope!;
  }

  @override
  Widget build(BuildContext context) => _RadioGroupScope<T>(
        groupValue: groupValue,
        onChanged: onChanged,
        child: Builder(builder: builder),
      );
}

class _RadioGroupScope<T> extends InheritedWidget {
  const _RadioGroupScope({
    required this.groupValue,
    required this.onChanged,
    required super.child,
  });

  final T? groupValue;
  final ValueChanged<T?>? onChanged;

  @override
  bool updateShouldNotify(_RadioGroupScope<T> old) =>
      groupValue != old.groupValue || onChanged != old.onChanged;
}
