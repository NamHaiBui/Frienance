import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. Time Pack Provider (StateNotifierProvider)
enum TimePack { week, month, year }

final timePackProvider = StateNotifierProvider<TimePackNotifier, TimePack>((ref) {
  return TimePackNotifier();
});

class TimePackNotifier extends StateNotifier<TimePack> {
  TimePackNotifier() : super(TimePack.week); // Initial value

  void setTimePack(TimePack pack) {
    state = pack;
  }
}

// 2. Date Range Provider (StateNotifierProvider)
class DateRange {
  final DateTime start;
  final DateTime end;

  DateRange({required this.start, required this.end});
}

final dateRangeProvider = StateNotifierProvider<DateRangeNotifier, DateRange>((ref) {
  return DateRangeNotifier();
});

class DateRangeNotifier extends StateNotifier<DateRange> {
  DateRangeNotifier()
      : super(DateRange(
          start: DateTime.now().subtract(const Duration(days: 7)),
          end: DateTime.now(),
        )); // Initial date range (last 7 days)

  void setDateRange(DateTime start, DateTime end) {
    state = DateRange(start: start, end: end);
  }
}
