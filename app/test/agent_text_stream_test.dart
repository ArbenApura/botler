// A STREAMING ANSWER IS READ AS MARKDOWN AT MOST ONCE EVERY 250 MS, AND IN FULL THE MOMENT IT IS COMPLETE.

// -- DEP-MODULES -- //
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// -- MODULES -- //
import 'package:botler/features/chat/agent_text.dart';

// -- FUNCTIONS -- //

Widget _host(String text, {required bool streaming}) => MaterialApp(
  home: Scaffold(body: AgentText(text, streaming: streaming)),
);

void main() {
  testWidgets('a long stream is read far less often than it ticks', (
    tester,
  ) async {
    AgentText.renders = 0;
    var text = '';
    // 100 ticks of 40 ms: four seconds of streaming
    for (var i = 0; i < 100; i++) {
      text += 'word$i ';
      await tester.pumpWidget(_host(text, streaming: true));
      await tester.pump(const Duration(milliseconds: 40));
    }
    // About one read per 250 ms (16 for four seconds), never one per tick
    expect(AgentText.renders, lessThan(25));
    expect(AgentText.renders, greaterThan(5));
    // The complete answer is read in full at once
    final before = AgentText.renders;
    await tester.pumpWidget(_host('$text end', streaming: false));
    expect(AgentText.renders, before + 1);
    expect(find.textContaining('end', findRichText: true), findsOneWidget);
  });
}
