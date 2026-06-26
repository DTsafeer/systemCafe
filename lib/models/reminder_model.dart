import 'dart:convert';
import 'package:flutter/material.dart';

class Reminder {
  final String id;
  final String title;
  final String body;
  final TimeOfDay time;
  final List<int> days; // 1-7 (Mon-Sun)
  final bool isEnabled;

  Reminder({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.days,
    this.isEnabled = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'hour': time.hour,
      'minute': time.minute,
      'days': days,
      'isEnabled': isEnabled,
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      id: map['id'],
      title: map['title'],
      body: map['body'],
      time: TimeOfDay(hour: map['hour'], minute: map['minute']),
      days: List<int>.from(map['days']),
      isEnabled: map['isEnabled'] ?? true,
    );
  }

  String toJson() => json.encode(toMap());
  factory Reminder.fromJson(String source) => Reminder.fromMap(json.decode(source));
}
