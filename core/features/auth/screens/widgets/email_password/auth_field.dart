import 'dart:math';

import 'package:flutter/material.dart';

class AuthTextField extends StatefulWidget {
  // width and height
  final double width;
  final double height;

  /// A focus node that might be used to control the focus of the input.
  final FocusNode? focusNode;

  /// Whether the input should have a focus when rendered.
  final bool? autofocus;
  final String fieldName;
  final String hintText;
  final bool obscure;
  final double padding;
  final TextEditingController controller;
  final void Function(String value) onSubmitted;
  final String? Function(String? value) validator;
  const AuthTextField(
      {super.key,
      this.obscure = false,
      required this.controller,
      required this.fieldName,
      required this.hintText,
      this.focusNode,
      this.autofocus,
      required this.onSubmitted,
      required this.validator,
      required this.padding,
      required this.width,
      required this.height});

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool viewPass = false;
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: Text(
            widget.fieldName,
            style: textTheme.bodyMedium!.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: min(16, widget.width / 36)),
          ),
        ),
        TextFormField(
          controller: widget.controller,
          autofocus: widget.autofocus ?? false,
          focusNode: widget.focusNode,
          obscureText: widget.obscure && !viewPass,
          style: textTheme.bodyMedium!.copyWith(
            fontSize: min(14, widget.width / 36),
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: textTheme.bodyMedium!.copyWith(
                color: const Color(0xFFB9B9B9),
                fontSize: min(14, widget.width / 36),
                fontWeight: FontWeight.normal),
            contentPadding: EdgeInsets.all(min(12, widget.width / 36)),
            enabledBorder: OutlineInputBorder(
                borderSide:
                    BorderSide(width: 1, color: colorScheme.surfaceTint),
                borderRadius: BorderRadius.circular(4)),
            focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(width: 1, color: colorScheme.primary),
                borderRadius: BorderRadius.circular(4)),
            suffixIcon: widget.obscure
                ? IconButton(
                    onPressed: () {
                      setState(() {
                        viewPass = !viewPass;
                      });
                    },
                    icon: Icon(!viewPass
                        ? Icons.remove_red_eye_outlined
                        : Icons.remove_red_eye),
                  )
                : null,
          ),
          onFieldSubmitted: widget.onSubmitted,
          validator: widget.validator,
        ),
      ],
    );
  }
}
