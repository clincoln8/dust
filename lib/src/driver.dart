// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:dust/src/execution_path.dart';
import 'package:dust/src/failure_library.dart';
import 'package:dust/src/input_result.dart';
import 'package:dust/src/mutator.dart';
import 'package:dust/src/mutators.dart';
import 'package:dust/src/pool.dart';
import 'package:dust/src/seed.dart';
import 'package:dust/src/seed_candidate.dart';
import 'package:dust/src/seed_library.dart';
import 'package:dust/src/simplify/simplifier.dart';
import 'package:dust/src/simplify/superset_paths_constraint.dart';
import 'package:dust/src/vm_controller.dart';
import 'package:dust/src/vm_result.dart';
import 'package:dust/src/weighted_random_choice.dart';
import 'package:meta/meta.dart';

/// Drives the main fuzz testing loop.
///
/// Meant to be platform-agnostic, but otherwise do the bulk of the wiring of
/// the fuzz tester workflow.
class Driver {
  final SeedLibrary _seeds;
  final FailureLibrary _failures;
  final Random _random;
  final List<VmController> _runners;
  final WeightedOptions<WeightedMutator> _mutators;
  final int _batchSize;
  final bool _simplify;

  final _successStreamCtrl = StreamController<void>.broadcast();
  final _newSeedStreamCtrl = StreamController<Seed>.broadcast();
  final _seedCandidateProcessedStreamCtrl =
      StreamController<SeedCandidate>.broadcast();
  final _uniqueFailStreamCtrl = StreamController<InputResult>.broadcast();
  final _duplicateFailStreamCtrl = StreamController<InputResult>.broadcast();

  final bool _computeEdgeCoverage;

  /// Construct a Driver to run fuzz testing.
  Driver(this._seeds, this._failures, this._batchSize, this._runners,
      this._mutators, this._random, this._computeEdgeCoverage,
      {@required bool simplify})
      : _simplify = simplify;

  /// Notifications for all non-unique fuzz [InputResult] cases.
  Stream<InputResult> get onDuplicateFail => _duplicateFailStreamCtrl.stream;

  /// Notifications for when new [Seed]s are discovered.
  Stream<Seed> get onNewSeed => _newSeedStreamCtrl.stream;

  /// Notifications for when [SeedCandidate]s are processed.
  Stream<SeedCandidate> get onSeedCandidateProcessed =>
      _seedCandidateProcessedStreamCtrl.stream;

  /// Notifications for when cases pass without error.
  Stream<void> get onSuccess => _successStreamCtrl.stream;

  /// Notifications fo new and unique fuzz [InputResult] cases.
  Stream<InputResult> get onUniqueFail => _uniqueFailStreamCtrl.stream;

  /// Begin running the [Driver]
  Future<void> run(List<SeedCandidate> inputs, {int count = -1}) async {
    // run initial seed candidates
    await Pool<VmController, SeedCandidate>(_runners, _preseed,
            handleError: _handleError)
        .consume(Queue.from(inputs.reversed));

    final pool =
        Pool<VmController, Seed>(_runners, _runCase, handleError: _handleError);

    var i = 0;
    while (count == -1 || i < count) {
      int nextBatchSize;
      if (count != -1 && i + _batchSize > count) {
        nextBatchSize = count - i;
      } else {
        nextBatchSize = _batchSize;
      }
      final batch = _seeds.getBatch(nextBatchSize, _random);
      i += nextBatchSize;

      await pool.consume(Queue.from(batch));
    }
  }

  Future<bool> _handleError<T>(VmController controller, T job, T error,
      [StackTrace stackTrace]) async {
    // TODO(mfairhurst): report this some other way.
    print('error with $error: $error $stackTrace');
    if (controller.isConnected) {
      await controller.dispose();
    }
    await controller.prestart();
    // Don't re-add item. It is randomly generated, and we've printed it. So
    // it is safer to drop. Otherwise, if we weren't careful, a single bad
    // item could deadlock the queue.
    return false;
  }

  Future<Seed> _potentialSeed(InputResult original, VmController runner) async {
    if (!_simplify) {
      return _seeds.report(original.input, original.result);
    }
    final result = original.result;
    final uniquePaths = _seeds.uniquePaths(result);
    if (uniquePaths.isNotEmpty) {
      final simplifier = Simplifier(
          original, runner, [SupersetPathsConstraint(uniquePaths.toSet())]);
      final simplified = await simplifier.simplify();
      return _seeds.report(simplified.input, simplified.result);
    }
    return null;
  }

  Future<void> _preseed(VmController runner, SeedCandidate seed) async {
    final results = <VmResult>[];
    final res = await runner.run(seed.input);
    results.add(res);
    if (_computeEdgeCoverage) {
      results.add(VmResult(res.timeElapsed, [ExecutionPath(res.paths)]));
    }

    for (final result in results) {
      final newSeed = seed.inCorpus
          ? _seeds.report(seed.input, result)
          : await _potentialSeed(InputResult(seed.input, result), runner);
      var broadcastSeed = seed;
      if (newSeed != null) {
        if (newSeed.input != seed.input) {
          broadcastSeed = SeedCandidate.forText(newSeed.input);
        }
        broadcastSeed.accepted = true;
      } else {
        broadcastSeed.accepted = false;
      }

      _seedCandidateProcessedStreamCtrl.add(broadcastSeed);
    }
  }

  Future<void> _runCase(VmController runner, Seed seed) async {
    final input = await mutate(seed.input, _random, _mutators);

    final res = await runner.run(input);

    final inputResult = InputResult(input, res);

    if (!res.succeeded) {
      final previousFailure = _failures.report(inputResult);
      if (previousFailure == null) {
        _uniqueFailStreamCtrl.add(inputResult);
      } else {
        _duplicateFailStreamCtrl.add(inputResult);
      }
    } else {
      _successStreamCtrl.add(null);
    }

    final results = [inputResult];
    if (_computeEdgeCoverage) {
      results.add(InputResult(
          input, VmResult(res.timeElapsed, [ExecutionPath(res.paths)])));
    }

    for (final inResult in results) {
      final newSeed = await _potentialSeed(inResult, runner);
      // Edge case: new seed may no longer be new.
      if (newSeed != null) {
        _newSeedStreamCtrl.add(newSeed);
      }
    }
  }
}
