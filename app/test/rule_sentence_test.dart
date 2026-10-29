// THE PAYDAY RULE SENTENCE: THE SERVER PUTS THE NAME IN FRONT OF IT, THE SCREEN DRAWS THE NAME ON ITS OWN LINE

import 'package:flutter_test/flutter_test.dart';

import 'package:botler/core/json.dart';

void main() {
  test('drops the name the server put in front of the sentence', () {
    final rule = <String, Object?>{
      'label': 'Emergency fund',
      'summary':
          'Emergency fund: Put 20% of your pay into Savings, from 2026-10-28.',
    };
    expect(
      ruleSentence(rule),
      'Put 20% of your pay into Savings, from 2026-10-28.',
    );
  });

  test('keeps the sentence when there is no name', () {
    final rule = <String, Object?>{
      'label': null,
      'summary': 'Put the rest into Savings.',
    };
    expect(ruleSentence(rule), 'Put the rest into Savings.');
  });

  test('drops the bill it saves for, which has its own row', () {
    final rule = <String, Object?>{
      'label': 'Parents',
      'fundsBillName': 'Parents allowance',
      'summary': 'Parents: Put ₱3,500.00 into RCBC, from 2026-11-02. It saves for Parents allowance.',
    };
    expect(ruleSentence(rule), 'Put ₱3,500.00 into RCBC, from 2026-11-02.');
  });
}
