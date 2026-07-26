import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/config/category_style.dart';
import 'package:upsc_daily_edge/widgets/article_thumbnail.dart';
import 'package:upsc_daily_edge/widgets/rich_article_content.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ArticleThumbnail', () {
    testWidgets('renders generated cover art when the article has no image', (tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 300,
          height: 150,
          child: ArticleThumbnail(
            imageUrl: '',
            title: 'Assam Floods and Flood Management in India',
            category: 'Geography',
          ),
        ),
      ));

      // The subject label is drawn on the generated cover, so an article with
      // no artwork still reads as designed rather than broken.
      expect(find.text('GEOGRAPHY'), findsOneWidget);
      expect(find.byIcon(Icons.terrain_rounded), findsOneWidget);
    });

    testWidgets('compact sizes drop the label but keep the glyph', (tester) async {
      await tester.pumpWidget(_host(
        const SizedBox(
          width: 86,
          height: 86,
          child: ArticleThumbnail(imageUrl: '', title: 'Green Bonds', category: 'Economy'),
        ),
      ));

      expect(find.text('ECONOMY'), findsNothing);
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    });
  });

  group('RichArticleContent', () {
    testWidgets('renders headings and bullets without printing their markers', (tester) async {
      const body = '## Why in News?\n\n'
          'India\'s WPI inflation surged to around 10%.\n\n'
          '## Summary\n\n'
          '• Cost-push factors dominate.\n'
          '◦ Crude oil prices rose sharply.';

      await tester.pumpWidget(_host(
        const SingleChildScrollView(child: RichArticleContent(content: body)),
      ));

      expect(find.text('Why in News?'), findsOneWidget);
      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Cost-push factors dominate.'), findsOneWidget);
      expect(find.text('Crude oil prices rose sharply.'), findsOneWidget);

      // The raw markers must never reach the reader.
      expect(find.textContaining('##'), findsNothing);
      expect(find.textContaining('•'), findsNothing);
    });

    testWidgets('unmarked legacy text still renders as prose', (tester) async {
      await tester.pumpWidget(_host(
        const RichArticleContent(content: 'A plain paragraph saved by an older scrape.'),
      ));

      expect(find.text('A plain paragraph saved by an older scrape.'), findsOneWidget);
    });

    testWidgets('empty content renders nothing', (tester) async {
      await tester.pumpWidget(_host(const RichArticleContent(content: '   ')));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('CategoryStyle', () {
    test('maps raw scraper tags onto canonical subjects', () {
      expect(CategoryStyle.of('Government Policies & Interventions').label, 'Governance');
      expect(CategoryStyle.of('biotechnology').label, 'Science & Technology');
      expect(CategoryStyle.of('Disaster Management').label, 'Geography');
      expect(CategoryStyle.of('Issues Related to Minorities').label, 'Social Issues');
      expect(CategoryStyle.of('Monetary Policy').label, 'Economy');
    });

    test('falls back to Current Affairs for unknown tags', () {
      expect(CategoryStyle.of('Some Unmapped Tag').label, 'Current Affairs');
      expect(CategoryStyle.of('').label, 'Current Affairs');
    });

    test('fromTags skips GS paper tags', () {
      expect(CategoryStyle.fromTags(['GS Paper - 2', 'Polity']).label, 'Polity');
    });
  });
}
