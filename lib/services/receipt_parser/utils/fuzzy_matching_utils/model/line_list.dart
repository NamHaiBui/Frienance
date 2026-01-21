import 'package:flutter/material.dart';

class LineNode {
  LineNode(this.text, this.rect);

  final String text;
  final Rect rect;
  LineNode? next;
}
