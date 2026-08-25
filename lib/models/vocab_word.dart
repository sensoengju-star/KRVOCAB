import 'package:hive/hive.dart';

/// VocabWord persisted in Hive.
/// Hand-written adapter — no build_runner needed.
class VocabWord extends HiveObject {
  VocabWord({
    required this.id,
    required this.hangul,
    required this.romanization,
    required this.englishMeaning,
    required this.partOfSpeech,
    required this.dateAdded,
    this.correctCount = 0,
    this.incorrectCount = 0,
    this.politeForm = '',
    WordStatus? status,
    bool? isLearned,
  })  : status = status ??
            (isLearned == true ? WordStatus.learned : WordStatus.learning);

  /// Tri-state status: learning / learned / reinforcement.
  /// Replaces the legacy boolean `isLearned`. We keep an `isLearned` getter
  /// so existing call-sites don't break.
  WordStatus status;

  String id;
  String hangul;
  String romanization;
  String englishMeaning;
  String partOfSpeech;
  DateTime dateAdded;
  int correctCount;
  int incorrectCount;

  /// Standard present-tense polite form (해요체), e.g. 가다 → 가요, 먹다 → 먹어요.
  /// Empty for words where it doesn't apply (most nouns).
  String politeForm;

  /// Backward-compat boolean. True iff status == learned.
  bool get isLearned => status == WordStatus.learned;
  set isLearned(bool v) =>
      status = v ? WordStatus.learned : WordStatus.learning;

  VocabWord copyWith({
    String? hangul,
    String? romanization,
    String? englishMeaning,
    String? partOfSpeech,
    int? correctCount,
    int? incorrectCount,
    String? politeForm,
    bool? isLearned,
    WordStatus? status,
  }) {
    return VocabWord(
      id: id,
      hangul: hangul ?? this.hangul,
      romanization: romanization ?? this.romanization,
      englishMeaning: englishMeaning ?? this.englishMeaning,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      dateAdded: dateAdded,
      correctCount: correctCount ?? this.correctCount,
      incorrectCount: incorrectCount ?? this.incorrectCount,
      politeForm: politeForm ?? this.politeForm,
      status: status ??
          (isLearned == null
              ? this.status
              : (isLearned ? WordStatus.learned : WordStatus.learning)),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hangul': hangul,
        'romanization': romanization,
        'englishMeaning': englishMeaning,
        'partOfSpeech': partOfSpeech,
        'dateAdded': dateAdded.toIso8601String(),
        'correctCount': correctCount,
        'incorrectCount': incorrectCount,
        'politeForm': politeForm,
        'isLearned': isLearned,
        'status': status.name,
      };
}

/// Lifecycle of a vocabulary word. Two live states — a word is either being
/// learned or being reinforced.
enum WordStatus {
  /// Default — included in the review deck.
  learning,

  /// RETIRED. The app used to have a third "learned" resting state with its
  /// own tab. Kept so the Hive adapter can still read records written by
  /// older builds; a one-time migration folds these into [learning], and
  /// every code path treats a stray `learned` as learning.
  learned,

  /// The user keeps this word in rotation for refreshers. Appears in the
  /// review deck when "Include reinforced words" is on, and feeds the
  /// Stories tab.
  reinforcement,
}

class VocabWordAdapter extends TypeAdapter<VocabWord> {
  @override
  final int typeId = 1;

  @override
  VocabWord read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };
    // Field 8 = legacy isLearned (bool). Field 9 = status (String enum name).
    // Older records have only 8; derive status from it.
    WordStatus status;
    final statusName = fields[9] as String?;
    if (statusName != null) {
      status = WordStatus.values.firstWhere(
        (s) => s.name == statusName,
        orElse: () => WordStatus.learning,
      );
    } else {
      final legacy = (fields[8] as bool?) ?? false;
      status = legacy ? WordStatus.learned : WordStatus.learning;
    }
    return VocabWord(
      id: fields[0] as String,
      hangul: fields[1] as String,
      romanization: fields[2] as String,
      englishMeaning: fields[3] as String,
      partOfSpeech: fields[4] as String,
      dateAdded: fields[5] as DateTime,
      correctCount: (fields[6] as int?) ?? 0,
      incorrectCount: (fields[7] as int?) ?? 0,
      // Field 10 = politeForm (added later; older records won't have it).
      politeForm: (fields[10] as String?) ?? '',
      status: status,
    );
  }

  @override
  void write(BinaryWriter writer, VocabWord obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.hangul)
      ..writeByte(2)
      ..write(obj.romanization)
      ..writeByte(3)
      ..write(obj.englishMeaning)
      ..writeByte(4)
      ..write(obj.partOfSpeech)
      ..writeByte(5)
      ..write(obj.dateAdded)
      ..writeByte(6)
      ..write(obj.correctCount)
      ..writeByte(7)
      ..write(obj.incorrectCount)
      // Keep the legacy bool field for forward/backward compat in case the
      // file is read by an older adapter.
      ..writeByte(8)
      ..write(obj.isLearned)
      ..writeByte(9)
      ..write(obj.status.name)
      ..writeByte(10)
      ..write(obj.politeForm);
  }
}

class PartsOfSpeech {
  static const noun = 'noun';
  static const verb = 'verb';
  static const descriptiveVerb = 'descriptive_verb';
  static const adverb = 'adverb';
  static const particle = 'particle';
  static const expression = 'expression';

  static const all = [noun, verb, descriptiveVerb, adverb, particle, expression];

  static String label(String code) {
    switch (code) {
      case noun:
        return 'noun';
      case verb:
        return 'verb';
      case descriptiveVerb:
        return 'descriptive verb';
      case adverb:
        return 'adverb';
      case particle:
        return 'particle';
      case expression:
        return 'expression';
      default:
        return code;
    }
  }

  /// Korean name for the part of speech — used where the UI itself is
  /// written in Korean (the add/edit sheet).
  static String koreanLabel(String code) {
    switch (code) {
      case noun:
        return '명사';
      case verb:
        return '동사';
      case descriptiveVerb:
        return '형용사';
      case adverb:
        return '부사';
      case particle:
        return '조사';
      case expression:
        return '표현';
      default:
        return code;
    }
  }
}
