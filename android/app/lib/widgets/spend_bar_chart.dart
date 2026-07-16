import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../providers/summary.dart';
import 'category_icon_bubble.dart';

/// Bar chart of expense spend per category. The cents→double conversion here
/// is for pixel height only — never for money math.
class SpendBarChart extends StatelessWidget {
  const SpendBarChart({super.key, required this.data});

  final List<SpendByCategory> data;

  @override
  Widget build(BuildContext context) {
    final maxY = data.isEmpty
        ? 1.0
        : data.map((d) => d.totalCents).reduce((a, b) => a > b ? a : b) / 100.0;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxY == 0 ? 1.0 : maxY,
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [BarChartRodData(toY: data[i].totalCents / 100.0)],
              ),
          ],
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= data.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: CategoryIconBubble(data[i].emoji, size: 24),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
