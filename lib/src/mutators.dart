// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:dust/src/mutator.dart';
import 'package:dust/src/seed_library.dart';

/// The default mutators to fuzz seeds in search of new cases.
// const defaultMutators = [
//   DefaultMutator(addChar),
//   DefaultMutator(flipChar),
//   DefaultMutator(removeChar)
// ];

String _randomChar(Random random, List<String> customCharSet) {
  if (customCharSet.isEmpty) {
    return String.fromCharCode(random.nextInt(128 - 31) + 31);
  }
  return customCharSet[random.nextInt(customCharSet.length)];
}

int _randomPos(String s, Random random, [bool inclusive = false]) {
  if (s.isEmpty || (!inclusive && s.length == 1)) {
    return 0;
  }
  return random.nextInt(s.length + (inclusive ? 1 : 0));
}

/// Add a single random char to a random position in the [input] string.
String addChar(String input, Random random, List<String> customCharSet) {
  final newchar = _randomChar(random, customCharSet);
  final charpos = _randomPos(input, random, true);
  return input.replaceRange(charpos, charpos, newchar);
}

/// Change a single random char to a new random char in the [input] string.
String flipChar(String input, Random random, List<String> customCharSet) {
  if (input.isEmpty) {
    return addChar(input, random, customCharSet);
  }

  final newchar = _randomChar(random, customCharSet);
  final charpos = _randomPos(input, random);
  return input.replaceRange(charpos, charpos + 1, newchar);
}

/// Remove a single random char in the [input] string.
String removeChar(String input, Random random, List<String> customCharSet) {
  if (input.isEmpty) {
    return addChar(input, random, customCharSet);
  }
  final charpos = _randomPos(input, random);
  return input.replaceRange(charpos, charpos + 1, '');
}

/// From a [SeedLibrary], get a mutator to merge two seeds by taking half of
/// a seed and putting it in the input.
DefaultMutator getCrossoverMutator(
        SeedLibrary seedLibrary, List<String> customCharSet) =>
    DefaultMutator((input, random, charSet) {
      if (input.isEmpty) {
        return addChar(input, random, charSet);
      }
      // TODO: Getting 1 seed is not very efficient. Pre-fetch this?
      final batch = seedLibrary.getBatch(1, random);
      if (batch.isEmpty) {
        return addChar(input, random, charSet);
      }
      final other = batch.single.input;
      if (other.isEmpty) {
        return addChar(input, random, charSet);
      }
      final leftOffset =
          input.length < 2 ? input.length : _randomPos(input, random) + 1;
      final rightOffset = other.length < 2 ? 0 : _randomPos(other, random);

      return input.substring(0, leftOffset) +
          other.substring(rightOffset, other.length);
    }, customCharSet);

/// From a [SeedLibrary], get a mutator to merge two seeds by splicing a segment
/// of a second seed into the input.
DefaultMutator getSpliceMutator(
        SeedLibrary seedLibrary, List<String> customCharSet) =>
    DefaultMutator((input, random, charSet) {
      if (input.isEmpty) {
        return addChar(input, random, charSet);
      }
      // TODO: Getting 1 seed is not very efficient. Pre-fetch this?
      final batch = seedLibrary.getBatch(1, random);
      if (batch.isEmpty) {
        return addChar(input, random, charSet);
      }
      final other = batch.single.input;
      if (other.isEmpty) {
        return addChar(input, random, charSet);
      }
      final replaceOffset = _randomPos(input, random, true);
      // don't replace all of input if we replace from offset 0.
      final replaceCap = replaceOffset == 0 ? input.length : input.length + 1;
      final replaceLength = replaceOffset == input.length
          ? 0
          : random.nextInt(replaceCap - replaceOffset);
      final spliceOffset = _randomPos(other, random);
      final spliceLength = spliceOffset + 1 == other.length
          ? 1
          : random.nextInt(other.length - spliceOffset) + 1;

      return input.replaceRange(replaceOffset, replaceOffset + replaceLength,
          other.substring(spliceOffset, spliceOffset + spliceLength));
    }, customCharSet);

/// A default mutator with a default weight.
class DefaultMutator implements WeightedMutator {
  @override
  final Mutator mutatorFn;

  @override
  final List<String> customCharSet;

  /// Construct a default mutator from a default function.
  const DefaultMutator(this.mutatorFn, this.customCharSet);

  @override
  double get weight => 1;
}
