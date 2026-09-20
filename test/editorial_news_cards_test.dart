import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/models/article.dart';
import 'package:upsc_daily_edge/widgets/editorial_news_cards.dart';

Article _article({String title = 'India’s new climate policy and what UPSC aspirants should know'}) => Article(
      id: 'editorial-1',
      title: title,
      summary: 'A concise exam-focused summary covering the policy context, implementation challenge, and syllabus relevance.',
      content: List.filled(440, 'policy').join(' '),
      keyPoints: const ['First point', 'Second point'],
      examRelevance: 'Both',
      categoryTags: const ['Environment'],
      imageUrl: '',
      publishedDate: DateTime(2026, 9, 19),
      newspaper: 'Drishti IAS',
      upscPaper: 'GS-III',
    );

Future<void> _pump(WidgetTester tester, Widget child, {double width = 360}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      routes: {
        '/article-detail': (_) => const Scaffold(body: Text('Article detail')),
      },
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('editorial lead story fits a narrow phone', (tester) async {
    await _pump(tester, EditorialLeadStory(article: _article()), width: 320);

    expect(find.text('Top story'), findsOneWidget);
    expect(find.text('GS-III'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial compact card survives a long headline', (tester) async {
    await _pump(
      tester,
      EditorialStoryCard(article: _article(title: 'A very long UPSC current affairs headline ' * 8)),
      width: 300,
    );

    expect(find.text('DRISHTI IAS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editorial cards open article details', (tester) async {
    await _pump(tester, EditorialStoryCard(article: _article()));

    await tester.tap(find.byType(EditorialStoryCard));
    await tester.pumpAndSettle();

    expect(find.text('Article detail'), findsOneWidget);
  });

  test('reading time is calculated from article content', () {
    expect(editorialReadMinutes(_article()), 2);
  });
}
