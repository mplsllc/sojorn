// Basic Flutter widget test for sojorn

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sojorn/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const sojornApp());

    // Verify app starts (this is a basic smoke test)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
