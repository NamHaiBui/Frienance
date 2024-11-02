import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:frontend/features/dashboard/components/hero/charts/config/bar_chart_config.dart';
import 'package:frontend/features/dashboard/components/hero/charts/legend_widget.dart';
import 'package:frontend/features/dashboard/provider/time_frame_provider.dart';
import 'package:frontend/features/template/theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef FieldId = String;

class ExpenseBarChart extends ConsumerWidget {
  // final String timeFrame;
  // final String groupByCondition;
  // final String dataSet;
  const ExpenseBarChart({
    super.key,
    // required this.timeFrame,
    // required this.groupByCondition,
    // required this.dataSet,
  });

  final pilateColor = AppColors.contentColorPurple;
  final cyclingColor = AppColors.contentColorCyan;
  final quickWorkoutColor = AppColors.contentColorBlue;

  BarChartGroupData generateGroupData(
    int x,
    Map<FieldId, double> data,
    Map<FieldId, Color> colors,
  ) {
    return BarChartGroupData(
      x: x,
      groupVertically: true,
      barRods: data.entries.map((entry) {
        final fieldId = entry.key;
        final value = entry.value;
        final fromY = data.entries
                .where((element) => element.key.compareTo(fieldId) < 0)
                .map((element) => element.value)
                .fold(
                    0.0, (previousValue, element) => previousValue + element) +
            (BarChartConfig.betweenSpace *
                data.entries.toList().indexOf(entry));
        return BarChartRodData(
          fromY: fromY.toDouble(),
          toY: fromY + value,
          color: colors[fieldId],
          width: 5,
        );
      }).toList(),
    );
  }

  Widget Function(double value, TitleMeta meta) bottomTitlesSelector(
      String groupByCondition) {
    switch (groupByCondition) {
      case "Year":
        return bottomTitlesByYear;
      case "Month":
        return bottomTitlesByMonth;
      case "Week":
        return bottomTitlesByWeek;
      default:
        return bottomTitlesByMonth;
    }
  }

  Widget bottomTitlesByMonth(double value, TitleMeta meta) {
    const style = TextStyle(fontSize: 10);
    String text;
    switch (value.toInt()) {
      case 0:
        text = 'JAN';
        break;
      case 1:
        text = 'FEB';
        break;
      case 2:
        text = 'MAR';
        break;
      case 3:
        text = 'APR';
        break;
      case 4:
        text = 'MAY';
        break;
      case 5:
        text = 'JUN';
        break;
      case 6:
        text = 'JUL';
        break;
      case 7:
        text = 'AUG';
        break;
      case 8:
        text = 'SEP';
        break;
      case 9:
        text = 'OCT';
        break;
      case 10:
        text = 'NOV';
        break;
      case 11:
        text = 'DEC';
        break;
      default:
        text = '';
    }

    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: style),
    );
  }

  Widget bottomTitlesByWeek(double value, TitleMeta meta) {
    const style = TextStyle(fontSize: 10);
    String text;
    switch (value.toInt()) {
      case 0:
        text = 'Mon';
        break;
      case 1:
        text = 'Tue';
        break;
      case 2:
        text = 'Wed';
        break;
      case 3:
        text = 'Thu';
        break;
      case 4:
        text = 'Fri';
        break;
      case 5:
        text = 'Sat';
        break;
      case 6:
        text = 'Sun';
        break;
      default:
        text = '';
    }

    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: style),
    );
  }

  Widget bottomTitlesByYear(double value, TitleMeta meta) {
    const style = TextStyle(fontSize: 10);
    String text;
    switch (value.toInt()) {
      case 0:
        text = '2024';
        break;
      case 1:
        text = '2023';
        break;
      case 2:
        text = '2022';
        break;
      case 3:
        text = '2021';
        break;
      case 4:
        text = '2020';
        break;
      default:
        text = '';
    }

    return SideTitleWidget(
      axisSide: meta.axisSide,
      child: Text(text, style: style),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFrame = ref.watch(timeFrameProvider);
    return Container(
      width: MediaQuery.of(context).size.width * 0.4,
      decoration: BoxDecoration(
          border: Border.all(), borderRadius: BorderRadius.circular(15)),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activity',
            style: TextStyle(
              color: AppColors.contentColorBlue,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          LegendsListWidget(
            legends: [
              Legend('Pilates', pilateColor),
              Legend('Quick workouts', quickWorkoutColor),
              Legend('Cycling', cyclingColor),
            ],
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 2,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceBetween,
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return bottomTitlesSelector(
                          timeFrame,
                        )(value, meta);
                      },
                      reservedSize: 20,
                    ),
                  ),
                ),
                barTouchData: BarTouchData(enabled: false),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: [
                  generateGroupData(0, {
                    'Pilates': 2,
                    'Quick workouts': 3,
                    'Cycling': 2,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(1, {
                    'Pilates': 2,
                    'Quick workouts': 5,
                    'Cycling': 1.7,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(2, {
                    'Pilates': 1.3,
                    'Quick workouts': 3.1,
                    'Cycling': 2.8,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(3, {
                    'Pilates': 3.1,
                    'Quick workouts': 4,
                    'Cycling': 3.1,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(4, {
                    'Pilates': 0.8,
                    'Quick workouts': 3.3,
                    'Cycling': 3.4,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(5, {
                    'Pilates': 2,
                    'Quick workouts': 5.6,
                    'Cycling': 1.8,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(6, {
                    'Pilates': 1.3,
                    'Quick workouts': 3.2,
                    'Cycling': 2,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(7, {
                    'Pilates': 2.3,
                    'Quick workouts': 3.2,
                    'Cycling': 3,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(8, {
                    'Pilates': 2,
                    'Quick workouts': 4.8,
                    'Cycling': 2.5,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(9, {
                    'Pilates': 1.2,
                    'Quick workouts': 3.2,
                    'Cycling': 2.5,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(10, {
                    'Pilates': 1,
                    'Quick workouts': 4.8,
                    'Cycling': 3,
                  }, {
                    'Pilates': pilateColor,
                    'Quick workouts': quickWorkoutColor,
                    'Cycling': cyclingColor,
                  }),
                  generateGroupData(
                    11,
                    {
                      'Pilates': 2,
                      'Quick workouts': 4.4,
                      'Cycling': 2.8,
                    },
                    {
                      'Pilates': pilateColor,
                      'Quick workouts': quickWorkoutColor,
                      'Cycling': cyclingColor,
                    },
                  ),
                ],
                maxY: 15 + (BarChartConfig.betweenSpace * 3),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 3.3,
                      color: pilateColor,
                      strokeWidth: 1,
                      dashArray: [20, 4],
                    ),
                    HorizontalLine(
                      y: 8,
                      color: quickWorkoutColor,
                      strokeWidth: 1,
                      dashArray: [20, 4],
                    ),
                    HorizontalLine(
                      y: 11,
                      color: cyclingColor,
                      strokeWidth: 1,
                      dashArray: [20, 4],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
