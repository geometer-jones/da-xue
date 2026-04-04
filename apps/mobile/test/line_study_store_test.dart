import 'package:daxue_mobile/src/line_study_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('line study entries do not persist translation feedback', () {
    const entry = LineStudyEntry(
      translation: 'Heaven and earth begin in mystery.',
      translationFeedback: 'Keep the cosmological force stronger.',
      response: 'The line opens with a compressed cosmic frame.',
      responseFeedback: 'Push the image contrast further.',
    );

    final json = entry.toJson();

    expect(json['translation'], 'Heaven and earth begin in mystery.');
    expect(json.containsKey('translationFeedback'), isFalse);
    expect(json['responseFeedback'], 'Push the image contrast further.');
  });

  test('line study entries ignore stored translation feedback on load', () {
    final entry = LineStudyEntry.fromJson({
      'translation': 'Heaven and earth begin in mystery.',
      'translationFeedback': 'Legacy saved translation feedback.',
      'response': 'The line opens with a compressed cosmic frame.',
      'responseFeedback': 'Push the image contrast further.',
    });

    expect(entry.translation, 'Heaven and earth begin in mystery.');
    expect(entry.translationFeedback, isEmpty);
    expect(entry.responseFeedback, 'Push the image contrast further.');
  });
}
