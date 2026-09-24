part of 'search_tab.dart';

class _StationField extends StatefulWidget {
  const _StationField({
    required this.label,
    required this.hintText,
    required this.controller,
    required this.onTapPicker,
    required this.border,
    required this.fieldStyle,
    required this.labelStyle,
  });

  final String label;
  final String hintText;
  final TextEditingController controller;
  final VoidCallback onTapPicker;
  final OutlineInputBorder border;
  final TextStyle fieldStyle;
  final TextStyle labelStyle;

  @override
  State<_StationField> createState() => _StationFieldState();
}

class _StationFieldState extends State<_StationField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _StationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          readOnly: true,
          onTap: widget.onTapPicker,
          style: widget.fieldStyle,
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: widget.labelStyle,
            floatingLabelStyle: widget.labelStyle,
            hintText: widget.hintText,
            hintStyle: widget.fieldStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
            border: widget.border,
            enabledBorder: widget.border,
            focusedBorder: widget.border.copyWith(
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.border,
    required this.valueStyle,
    required this.labelStyle,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final OutlineInputBorder border;
  final TextStyle valueStyle;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          labelText: label,
          labelStyle: labelStyle,
          floatingLabelStyle: labelStyle,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.4,
            ),
          ),
        ),
        child: Text(value, style: valueStyle),
      ),
    );
  }
}

