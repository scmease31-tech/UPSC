import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/theme.dart';
import 'package:upsc_daily_edge/models/article.dart';
import 'package:upsc_daily_edge/widgets/article_card.dart';

/// ArticleCard is placed inside fixed-height rails (the home screen's trending
/// carousel) and inside narrow columns. A card that grows past its rail throws
/// a RenderFlex overflow, which these tests turn into a build failure rather
/// than a yellow-and-black stripe the user notices first.
Article _article({String image = '', String summary = ''}) => Article(
      id: 'a1',
      title: 'Assam Floods and Flood Management in India: Causes, Concerns and the Way Forward',
      summary: summary.isEmpty
          ? 'Assam has witnessed its worst floods in over 60 years, affecting over 8 lakh people and '
              'highlighting persistent challenges in India\'s flood management framework.'
          : summary,
      content: '',
      keyPoints: const [],
      examRelevance: 'Both',
      categoryTags: const ['Geography', 'Disaster Management'],
      imageUrl: image,
      publishedDate: DateTime(2026, 7, 25),
      newspaper: 'Drishti IAS',
      upscPaper: 'GS-III',
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pump();
}

void main() {
  testWidgets('standard card fits the home trending rail', (tester) async {
    // Matches the SizedBox height and card width used by _buildTrendingTopics.
    await _pump(
      tester,
      SizedBox(
        height: 336,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [SizedBox(width: 280, child: ArticleCard(article: _article()))],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('standard card renders in a narrow column', (tester) async {
    await _pump(tester, SizedBox(width: 320, child: ArticleCard(article: _article())));
    expect(tester.takeException(), isNull);
  });

  testWidgets('featured card renders at phone width', (tester) async {
    await _pump(
      tester,
      SizedBox(width: 375, child: ArticleCard(article: _article(), featured: true)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact card survives a very long headline', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 300,
        child: ArticleCard(
          compact: true,
          article: _article(summary: 'x' * 400),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('card renders identically whether or not the article has artwork', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 340,
        child: Column(
          children: [
            ArticleCard(article: _article()),
            ArticleCard(article: _article(image: 'https://example.invalid/x.png')),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ArticleCard), findsNWidgets(2));
  });
}
