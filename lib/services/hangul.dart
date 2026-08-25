/// Per-syllable Hangul → Revised Romanization.
///
/// Romanizes each Hangul syllable BLOCK in isolation (no cross-syllable
/// liaison/assimilation), which is exactly what we want when training
/// recognition of single blocks: 작 → "jak", 한 → "han", 글 → "geul".
class Hangul {
  Hangul._();

  static const int _base = 0xAC00; // '가'
  static const int _last = 0xD7A3; // '힣'

  // 19 initials (choseong), Revised Romanization at syllable onset.
  static const List<String> _initials = [
    'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss',
    '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h',
  ];

  // 21 medials (jungseong).
  static const List<String> _medials = [
    'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae',
    'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i',
  ];

  // 28 finals (jongseong); index 0 = no final. Romanized by their final
  // (pronounced) value per Revised Romanization. Order (Unicode jongseong):
  //  ''  ㄱ ㄲ ㄳ ㄴ ㄵ ㄶ ㄷ ㄹ ㄺ ㄻ ㄼ ㄽ ㄾ ㄿ ㅀ ㅁ ㅂ ㅄ ㅅ ㅆ ㅇ ㅈ ㅊ ㅋ ㅌ ㅍ ㅎ
  static const List<String> _finals = [
    '', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'k', 'm', 'l', 'l', 'l',
    'p', 'l', 'm', 'p', 'p', 't', 't', 'ng', 't', 't', 'k', 't', 'p', 't',
  ];

  /// True if [c] (a single character) is a composed Hangul syllable block.
  static bool isSyllable(String c) {
    if (c.isEmpty) return false;
    final code = c.runes.first;
    return code >= _base && code <= _last;
  }

  /// Romanize an entire string syllable-by-syllable (no cross-syllable
  /// liaison). Non-Hangul characters are passed through unchanged.
  static String romanize(String text) {
    final buf = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(isSyllable(ch) ? romanizeSyllable(ch) : ch);
    }
    return buf.toString();
  }

  /// Revised Romanization of a single syllable block. Returns '' if [c] is
  /// not a Hangul syllable.
  static String romanizeSyllable(String c) {
    if (!isSyllable(c)) return '';
    final s = c.runes.first - _base;
    final initial = s ~/ (21 * 28);
    final medial = (s % (21 * 28)) ~/ 28;
    final fin = s % 28;
    return '${_initials[initial]}${_medials[medial]}${_finals[fin]}';
  }
}
