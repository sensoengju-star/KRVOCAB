import 'package:hive/hive.dart';

/// A single Hangul syllable block the user is drilling, with its (usually
/// auto-filled) Revised Romanization. Hand-written adapter — no build_runner.
class BlockEntry extends HiveObject {
  BlockEntry({
    required this.id,
    required this.block,
    required this.roman,
    required this.dateAdded,
    this.definition = '',
  });

  String id;
  String block;
  String roman;
  DateTime dateAdded;

  /// What the block means, in the learner's own words — typically its
  /// Sino-Korean sense (학 → study, learning) or the family of words it
  /// anchors. Empty for a block that is only being learned for its sound.
  String definition;

  BlockEntry copyWith({String? block, String? roman, String? definition}) =>
      BlockEntry(
        id: id,
        block: block ?? this.block,
        roman: roman ?? this.roman,
        dateAdded: dateAdded,
        definition: definition ?? this.definition,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'block': block,
        'roman': roman,
        'dateAdded': dateAdded.toIso8601String(),
        'definition': definition,
      };
}

class BlockEntryAdapter extends TypeAdapter<BlockEntry> {
  @override
  final int typeId = 2;

  @override
  BlockEntry read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return BlockEntry(
      id: fields[0] as String,
      block: fields[1] as String,
      roman: fields[2] as String,
      dateAdded: fields[3] as DateTime,
      // Index 4 arrived after blocks already existed on disk. Records written
      // before it simply lack the key, and read back as having no definition —
      // which is exactly what they had. No migration step, nothing to break.
      definition: (fields[4] as String?) ?? '',
    );
  }

  @override
  void write(BinaryWriter writer, BlockEntry obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.block)
      ..writeByte(2)
      ..write(obj.roman)
      ..writeByte(3)
      ..write(obj.dateAdded)
      ..writeByte(4)
      ..write(obj.definition);
  }
}
