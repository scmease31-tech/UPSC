import 'package:flutter_test/flutter_test.dart';

import 'package:upsc_daily_edge/data/pyq_bank.dart';
import 'package:upsc_daily_edge/models/pyq_question.dart';

/// Guards the PYQ tab's data integrity: a question that renders with a missing
/// option or an out-of-range answer key would silently teach the wrong thing.
void main() {
  final all = PyqBank.all;
  final prelims = all.where((q) => q.type == PyqType.prelims).toList();
  final mains = all.where((q) => q.type == PyqType.mains).toList();

  test('bank is populated across both papers', () {
    expect(prelims.length, greaterThanOrEqualTo(80));
    expect(mains.length, greaterThanOrEqualTo(40));
  });

  test('covers at least ten exam years, newest first', () {
    final years = PyqBank.years;
    expect(years.length, greaterThanOrEqualTo(10));
    expect(years, orderedEquals(List<int>.from(years)..sort((a, b) => b.compareTo(a))));
  });

  test('every question id is unique', () {
    final ids = all.map((q) => q.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('every Prelims question is answerable with a valid key', () {
    for (final q in prelims) {
      expect(q.options.length, 4, reason: 'wrong option count on ${q.id}');
      expect(q.options.every((o) => o.trim().isNotEmpty), isTrue, reason: 'blank option on ${q.id}');
      expect(q.answer, inInclusiveRange(0, 3), reason: 'bad answer index on ${q.id}');
      expect(q.isAnswerable, isTrue, reason: '${q.id} would render as un-attemptable');
      expect(q.explanation.trim().length, greaterThan(40), reason: 'thin explanation on ${q.id}');
    }
  });

  test('every Mains question carries a paper and a model approach', () {
    for (final q in mains) {
      expect(q.paper.trim(), isNotEmpty, reason: 'missing paper on ${q.id}');
      expect(q.marks, greaterThan(0), reason: 'missing marks on ${q.id}');
      expect(q.approach.trim().length, greaterThan(80), reason: 'thin approach on ${q.id}');
      expect(q.options, isEmpty);
    }
  });

  test('every question has a plausible year and a real stem', () {
    for (final q in all) {
      expect(q.year, inInclusiveRange(1990, 2100), reason: 'bad year on ${q.id}');
      // Catches truncated/placeholder entries. Deliberately low enough to allow
      // genuinely terse stems such as "mRNA vaccines work by:".
      expect(q.question.trim().length, greaterThan(18), reason: 'stub question on ${q.id}');
      expect(q.subject.trim(), isNotEmpty);
    }
  });

  test('provenance is always one of the labels the UI knows how to explain', () {
    const known = {'UPSC', 'UPSC Pattern', 'Drishti IAS'};
    for (final q in all) {
      expect(known.contains(q.source), isTrue, reason: 'unknown source "${q.source}" on ${q.id}');
    }
  });

  test('round-trips through the Firestore map shape', () {
    for (final q in all.take(20)) {
      final copy = PyqQuestion.fromMap(q.toMap(), q.id);
      expect(copy.year, q.year);
      expect(copy.type, q.type);
      expect(copy.answer, q.answer);
      expect(copy.options, q.options);
      expect(copy.question, q.question);
    }
  });
}
