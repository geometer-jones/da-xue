const Map<String, String> _bookDisplayTitles = {
  'chengyu-catalog': '成語目錄',
  'da-xue': '大學',
  'daodejing': '道德經',
  'lunyu': '論語',
  'mengzi': '孟子',
  'qian-zi-wen': '千字文',
  'san-zi-jing': '三字經',
  'sanguo-yanyi': '三國演義',
  'sunzi-bingfa': '孫子兵法',
  'zhong-yong': '中庸',
};

const Map<String, String> _bookTitleTranslations = {
  'chengyu-catalog': 'Chengyu Catalog',
  'da-xue': 'The Great Learning',
  'daodejing': 'Dao De Jing',
  'lunyu': 'The Analects',
  'mengzi': 'Mencius',
  'qian-zi-wen': 'The Thousand Character Classic',
  'san-zi-jing': 'Three Character Classic',
  'sanguo-yanyi': 'Romance of the Three Kingdoms',
  'sunzi-bingfa': 'The Art of War',
  'zhong-yong': 'The Doctrine of the Mean',
};

const Map<String, String> _daXueChapterTranslations = {
  '大學之道': 'The Way of Great Learning',
  '知止而后有定': 'Knowing Where to Stop, Then Becoming Settled',
  '物有本末': 'Things Have Roots and Branches',
  '古之欲明明德於天下者':
      'Those of Old Who Wished to Illuminate Luminous Virtue Throughout the World',
  '物格而后知至': 'When Things Are Investigated, Knowledge Reaches Fulfillment',
  '自天子以至於庶人': 'From the Son of Heaven Down to the Common People',
  '其本亂而末治者否矣':
      'If the Root Is Disordered, the Branches Cannot Be Well Governed',
};

const Map<String, String> _lunyuChapterTranslations = {
  '學而第一': 'Learning',
  '為政第二': 'Governing',
  '八佾第三': 'Eight Rows of Dancers',
  '里仁第四': 'Living with Humaneness',
  '公冶長第五': 'Gongye Chang',
  '雍也第六': 'Yong Ye',
  '述而第七': 'Transmission',
  '泰伯第八': 'Taibo',
  '子罕第九': 'The Master Rarely Spoke',
  '鄉黨第十': 'Among the Villagers',
  '先進第十一': 'Advanced Students',
  '顏淵第十二': 'Yan Yuan',
  '子路第十三': 'Zilu',
  '憲問第十四': 'Xian Asked',
  '衛靈公第十五': 'Duke Ling of Wei',
  '季氏第十六': 'The Ji Clan',
  '陽貨第十七': 'Yang Huo',
  '微子第十八': 'Viscount of Wei',
  '子張第十九': 'Zizhang',
  '堯曰第二十': 'Yao Said',
};

const Map<String, String> _zhongYongChapterTranslations = {
  '天命之謂性': 'Heaven is Nature',
  '君子中庸': 'The Gentleman Follows the Mean',
  '中庸其至矣乎': 'The Mean Reaches Its Fulfillment',
  '道之不行也': 'When the Way Does Not Flow',
  '道其不行矣夫': 'When the Way Does Not Prevail',
  '舜其大知也與': 'Was Shun Truly So Wise',
  '人皆曰『予知': 'All Say “I Know”',
  '回之為人也': 'This Is What It Is to Be Human',
  '天下國家可均也': 'A Country Can Be Made Equal',
  '子路問強': 'Zilu Asked About Strength',
  '素隱行怪': 'The Mysterious and Hidden Is Strange',
  '君子之道費而隱': 'The Noble Way Is Costly and Hidden',
  '道不遠人': 'The Way Is Not Far From People',
  '君子素其位而行': 'The Gentleman Stays in His Place and Acts',
  '君子之道': 'The Noble Way',
  '鬼神之為德': 'The Virtue of Spirits and Gods',
  '舜其大孝也與': 'Was Shun the Most Filial of Men',
  '無憂者其惟文王乎': 'Who Else Could Be Without Worry but King Wen',
  '武王': 'King Wu',
  '哀公問政': 'Duke Ai Asked About Government',
  '自誠明': 'Sincerity Makes Things Clear',
  '唯天下至誠': 'Only Perfect Sincerity is Under Heaven',
  '其次致曲': 'Then Comes Distortion',
  '至誠之道': 'The Way of Perfect Sincerity',
  '誠者自成也': 'Sincerity Makes One Complete',
  '故至誠無息': 'Therefore Perfect Sincerity Never Ceases',
  '大哉聖人之道': 'Great Is the Way of the Sage',
  '愚而好自用': 'The Fool Loves to Rely on Himself',
  '王天下有三重焉': 'Ruling the World Has Three Layers',
  '仲尼祖述堯舜': 'Zhongni Expounds Yao and Shun',
  '唯天下至聖': 'Only the Supreme Sage is Under Heaven',
  '衣錦尚絅': 'Fine Brocade and Flashy Garb Are Praised',
};

const Map<String, String> _mengziChapterTranslations = {
  '梁惠王章句上': 'King Hui of Liang, Part 1',
  '梁惠王章句下': 'King Hui of Liang, Part 2',
  '公孫丑章句上': 'Gongsun Chou, Part 1',
  '公孫丑章句下': 'Gongsun Chou, Part 2',
  '滕文公章句上': 'Duke Wen of Teng, Part 1',
  '滕文公章句下': 'Duke Wen of Teng, Part 2',
  '離婁章句上': 'Li Lou, Part 1',
  '離婁章句下': 'Li Lou, Part 2',
  '萬章章句上': 'Wan Zhang, Part 1',
  '萬章章句下': 'Wan Zhang, Part 2',
  '告子章句上': 'Gaozi, Part 1',
  '告子章句下': 'Gaozi, Part 2',
  '盡心章句上': 'Exerting the Heart, Part 1',
  '盡心章句下': 'Exerting the Heart, Part 2',
};

const Map<String, String> _sunziChapterTranslations = {
  '始計': 'Initial Calculations',
  '作戰': 'Waging War',
  '謀攻': 'Planning Offensives',
  '軍形': 'Military Dispositions',
  '兵勢': 'Strategic Power',
  '虛實': 'Emptiness and Fullness',
  '軍爭': 'Maneuvering Armies',
  '九變': 'Nine Variations',
  '行軍': 'Marching the Army',
  '地形': 'Terrain',
  '九地': 'Nine Grounds',
  '火攻': 'Attack by Fire',
  '用間': 'Using Spies',
};

const Map<String, String> _chengyuChapterTranslations = {
  '入门常用·学习与积累': 'Beginner Essentials: Study and Accumulation',
  '入门常用·思考与判断': 'Beginner Essentials: Thought and Judgment',
  '入门常用·行动与方法': 'Beginner Essentials: Action and Method',
  '入门常用·人际与协作': 'Beginner Essentials: Relationships and Collaboration',
  '入门常用·品格与表达': 'Beginner Essentials: Character and Expression',
  '典故起步·高频故事成语': 'Story Foundations: High-Frequency Story Idioms',
  '常用拓展·高透明度 I': 'Common Expansion: High Transparency I',
  '常用拓展·高透明度 II': 'Common Expansion: High Transparency II',
  '常用拓展·高透明度 III': 'Common Expansion: High Transparency III',
  '常用拓展·高透明度 IV': 'Common Expansion: High Transparency IV',
  '常用拓展·高透明度 V': 'Common Expansion: High Transparency V',
  '书面拓展·中高透明度 I': 'Literary Expansion: Medium-High Transparency I',
  '书面拓展·中高透明度 II': 'Literary Expansion: Medium-High Transparency II',
  '书面拓展·中高透明度 III': 'Literary Expansion: Medium-High Transparency III',
  '书面拓展·中高透明度 IV': 'Literary Expansion: Medium-High Transparency IV',
  '书面拓展·中高透明度 V': 'Literary Expansion: Medium-High Transparency V',
  '典故进阶·中透明度 I': 'Story Progression: Medium Transparency I',
  '典故进阶·中透明度 II': 'Story Progression: Medium Transparency II',
  '文言进阶·较高难度 I': 'Classical Chinese Progression: Higher Difficulty I',
  '文言进阶·较高难度 II': 'Classical Chinese Progression: Higher Difficulty II',
};

final RegExp _numberedChapterPattern = RegExp(r'^第([0-9一二三四五六七八九十百零〇]+)章$');
final RegExp _commentaryChapterPattern = RegExp(r'^右第([0-9一二三四五六七八九十百零〇]+)章$');
final RegExp _sanguoChapterPattern = RegExp(r'^第([0-9一二三四五六七八九十百零〇]+)回');
final RegExp _daodejingSummaryBreakPattern = RegExp(r'[，；。？！：、]');

String displayBookTitle({required String bookId, required String title}) {
  final mappedTitle = _bookDisplayTitles[bookId];
  if (mappedTitle != null && mappedTitle.trim().isNotEmpty) {
    return mappedTitle;
  }

  return title.trim();
}

String? translatedBookTitle({required String bookId, required String title}) {
  final translation = _bookTitleTranslations[bookId];
  if (translation == null) {
    return null;
  }

  final trimmedTranslation = translation.trim();
  if (trimmedTranslation.isEmpty) {
    return null;
  }

  final visibleTitle = displayBookTitle(bookId: bookId, title: title).trim();
  if (trimmedTranslation == visibleTitle) {
    return null;
  }

  return trimmedTranslation;
}

String displayChapterTitle({
  required String bookId,
  required String title,
  String? summary,
}) {
  final trimmedTitle = title.trim();
  final trimmedSummary = summary?.trim() ?? '';

  if (bookId == 'chengyu-catalog') {
    return _stripTitleCategory(trimmedTitle, '·');
  }

  if (bookId == 'daodejing' &&
      trimmedSummary.isNotEmpty &&
      _matchNumber(trimmedTitle, _numberedChapterPattern) != null) {
    final conciseSummary = trimmedSummary
        .split(_daodejingSummaryBreakPattern)
        .first
        .trim();
    if (conciseSummary.isNotEmpty) {
      return conciseSummary;
    }

    return trimmedSummary;
  }

  return trimmedTitle;
}

String? translatedChapterTitle({
  required String bookId,
  required String title,
}) {
  final trimmedTitle = title.trim();
  if (trimmedTitle.isEmpty) {
    return null;
  }

  switch (bookId) {
    case 'chengyu-catalog':
      final translation = _chengyuChapterTranslations[trimmedTitle];
      if (translation == null) {
        return null;
      }

      return _stripTitleCategory(translation, ':');
    case 'da-xue':
      return _daXueChapterTranslations[trimmedTitle];
    case 'lunyu':
      return _lunyuChapterTranslations[trimmedTitle];
    case 'mengzi':
      return _mengziChapterTranslations[trimmedTitle];
    case 'sunzi-bingfa':
      return _sunziChapterTranslations[trimmedTitle];
    case 'zhong-yong':
      return _zhongYongChapterTranslations[trimmedTitle];
  }

  if (trimmedTitle == '全篇') {
    return 'Complete Text';
  }

  final commentaryChapterNumber = _matchNumber(
    trimmedTitle,
    _commentaryChapterPattern,
  );
  if (commentaryChapterNumber != null) {
    return 'Chapter $commentaryChapterNumber';
  }

  final numberedChapter = _matchNumber(trimmedTitle, _numberedChapterPattern);
  if (numberedChapter != null) {
    return 'Chapter $numberedChapter';
  }

  final sanguoChapterNumber = _matchNumber(trimmedTitle, _sanguoChapterPattern);
  if (sanguoChapterNumber != null) {
    return 'Chapter $sanguoChapterNumber';
  }

  return null;
}

String _stripTitleCategory(String value, String separator) {
  final trimmedValue = value.trim();
  if (trimmedValue.isEmpty) {
    return trimmedValue;
  }

  final separatorIndex = trimmedValue.indexOf(separator);
  if (separatorIndex == -1) {
    return trimmedValue;
  }

  final strippedValue = trimmedValue.substring(separatorIndex + 1).trim();
  if (strippedValue.isEmpty) {
    return trimmedValue;
  }

  return strippedValue;
}

int? _matchNumber(String title, RegExp pattern) {
  final match = pattern.firstMatch(title);
  if (match == null) {
    return null;
  }

  return _parseChapterNumber(match.group(1) ?? '');
}

int? _parseChapterNumber(String rawValue) {
  final trimmedValue = rawValue.trim();
  if (trimmedValue.isEmpty) {
    return null;
  }

  return int.tryParse(trimmedValue) ?? _parseChineseNumber(trimmedValue);
}

int? _parseChineseNumber(String rawValue) {
  const digitValues = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  const unitValues = {'十': 10, '百': 100};

  var total = 0;
  var currentDigit = 0;
  for (final rune in rawValue.runes) {
    final character = String.fromCharCode(rune);
    if (digitValues.containsKey(character)) {
      currentDigit = digitValues[character]!;
      continue;
    }

    final unit = unitValues[character];
    if (unit == null) {
      return null;
    }

    total += (currentDigit == 0 ? 1 : currentDigit) * unit;
    currentDigit = 0;
  }

  return total + currentDigit;
}
