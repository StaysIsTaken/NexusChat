// Basis-Smoke-Test für NexusChat.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexuschat/main.dart';

void main() {
  testWidgets('App startet ohne Fehler', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(NexusChatApp(prefs: prefs));
    await tester.pump();

    // App rendert (MaterialApp vorhanden)
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
