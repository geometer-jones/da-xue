import 'package:daxue_mobile/src/title_translations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'translatedBookTitle keeps the mapped English subtitle when source title is already English',
    () {
      expect(
        displayBookTitle(bookId: 'daodejing', title: 'Dao De Jing'),
        '道德經',
      );
      expect(
        translatedBookTitle(bookId: 'daodejing', title: 'Dao De Jing'),
        'Dao De Jing',
      );
      expect(
        displayBookTitle(bookId: 'sunzi-bingfa', title: 'The Art of War'),
        '孫子兵法',
      );
      expect(
        translatedBookTitle(bookId: 'sunzi-bingfa', title: 'The Art of War'),
        'The Art of War',
      );
      expect(
        displayBookTitle(
          bookId: 'san-zi-jing',
          title: 'Three Character Classic',
        ),
        '三字經',
      );
      expect(
        translatedBookTitle(
          bookId: 'san-zi-jing',
          title: 'Three Character Classic',
        ),
        'Three Character Classic',
      );
    },
  );

  test('translatedBookTitle still maps Chinese source titles to English', () {
    expect(
      translatedBookTitle(bookId: 'daodejing', title: '道德經'),
      'Dao De Jing',
    );
    expect(
      translatedBookTitle(bookId: 'sunzi-bingfa', title: '孫子兵法'),
      'The Art of War',
    );
    expect(
      translatedBookTitle(bookId: 'san-zi-jing', title: '三字經'),
      'Three Character Classic',
    );
  });

  test(
    'displayChapterTitle uses Daodejing incipits instead of bare numbers',
    () {
      expect(
        displayChapterTitle(
          bookId: 'daodejing',
          title: '第1章',
          summary: '道可道，非常道',
        ),
        '道可道',
      );
      expect(
        translatedChapterTitle(bookId: 'daodejing', title: '第1章'),
        'Chapter 1',
      );
    },
  );

  test(
    'displayChapterTitle shortens long Daodejing incipits to the first clause',
    () {
      expect(
        displayChapterTitle(
          bookId: 'daodejing',
          title: '第66章',
          summary: '江海所以能為百谷王者，以其善下之，故能為百谷王',
        ),
        '江海所以能為百谷王者',
      );
    },
  );

  test(
    'displayChapterTitle omits chengyu chapter categories from rendered titles',
    () {
      expect(
        displayChapterTitle(
          bookId: 'chengyu-catalog',
          title: '入门常用·学习与积累',
          summary: '持之以恒',
        ),
        '学习与积累',
      );
      expect(
        translatedChapterTitle(bookId: 'chengyu-catalog', title: '入门常用·学习与积累'),
        'Study and Accumulation',
      );
    },
  );

  test(
    'displayChapterTitle keeps non-Daodejing and non-summary titles intact',
    () {
      expect(
        displayChapterTitle(bookId: 'lunyu', title: '學而第一', summary: '學而時習之'),
        '學而第一',
      );
      expect(
        displayChapterTitle(bookId: 'daodejing', title: '第2章', summary: ''),
        '第2章',
      );
    },
  );

  test('translatedChapterTitle provides English for Zhong Yong chapter titles', () {
    expect(
      translatedChapterTitle(bookId: 'zhong-yong', title: '天命之謂性'),
      'Heaven is Nature',
    );
    expect(
      translatedChapterTitle(bookId: 'zhong-yong', title: '王天下有三重焉'),
      'Ruling the World Has Three Layers',
    );
    expect(
      translatedChapterTitle(bookId: 'zhong-yong', title: '人皆曰『予知'),
      'All Say “I Know”',
    );
  });
}
