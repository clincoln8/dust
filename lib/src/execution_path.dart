import 'package:collection/collection.dart';
import 'package:dust/src/path.dart';
import 'package:quiver/core.dart' as q;

/// Represents a code path that was or wasn't executed by the VM.
///
/// The VM provides both a special canonicalized URI string, and also a unique
/// integer identifier based on the code offset of the code path. This class
/// should be constructed with the integer ID unchanged, but the script URI
/// made shorter & more human readable.
class ExecutionPath extends Path {
  List<Path> path;

  ExecutionPath(List<Path> paths) : super('edge coverage path', -1) {
    this.path = paths.map((item) => item).toList();
  }

  List<List<Path>> get paths => [path];

  @override
  int get hashCode => q.hashObjects(path
      .map((branch) => [branch.scriptUri.hashCode, branch.locationId.hashCode])
      .toList()
      .expand((i) => i)
      .toList());

  @override
  bool operator ==(Object other) =>
      other is ExecutionPath &&
      DeepCollectionEquality().equals(path, other.path);

  @override
  String toString() => 'pathlen: $path.length\npath: $path';
}
