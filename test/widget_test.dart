import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fechai/features/auth/onboarding_screen.dart';

void main() {
  testWidgets('Onboarding mostra a marca e o CTA inicial', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: OnboardingScreen()),
      ),
    );

    expect(find.text('Fechaí'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
