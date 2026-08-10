import 'package:flutter/material.dart';

class AnalyticsTabConfig {
  final String tabId;
  final String tabTitle;
  final String tabSubtitle;
  final List<AnalyticsMetricDefinition> metrics;

  const AnalyticsTabConfig({
    required this.tabId,
    required this.tabTitle,
    required this.tabSubtitle,
    required this.metrics,
  });
}

class AnalyticsMetricDefinition {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final bool isCurrency;
  final bool isTrend;

  const AnalyticsMetricDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.isCurrency = false,
    this.isTrend = false,
  });
}

class AnalyticsMetric {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final double value;
  final String displayValue;
  final bool isCurrency;
  final bool isTrend;

  const AnalyticsMetric({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.value,
    required this.displayValue,
    required this.isCurrency,
    required this.isTrend,
  });
}
