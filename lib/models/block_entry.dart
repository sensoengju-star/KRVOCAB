import 'package:hive/hive.dart';

/// A single Hangul syllable block the user is drilling, with its (usually
/// auto-filled) Revised Romanization. Hand-written adapter — no build_runner.
class BlockEntry extends HiveObject {
  BlockEntry({
    required this.id,
    required this.block,
    required this.roman,
    required this.dateAdded,
  });

  String id;
  String block;
  String roman;
  DateTime dateAdded;

  Map<String, dynamic> toJson() => {
        'id': id,
        'block': block,
        'roman': roman,
        'dateAdded': dateAdded.toIso8601String(),
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
    );
  }

  @override
  void write(BinaryWriter writer, BlockEntry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.block)
      ..writeByte(2)
      ..write(obj.roman)
      ..writeByte(3)
      ..write(obj.dateAdded);
  }
}
