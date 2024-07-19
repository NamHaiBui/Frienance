import 'package:flutter/material.dart';


IconData getCategoryIcon(String category) {
  switch (category) {
    case 'food':
      return Icons.lunch_dining;
    case 'travel':
      return Icons.flight_takeoff;
    case 'leisure':
      return Icons.movie;
    case 'work':
      return Icons.work;
    default:
      return Icons.new_releases;
  }
}
