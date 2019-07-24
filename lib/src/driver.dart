// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:dust/src/controller.dart';
import 'package:dust/src/failure.dart';
import 'package:dust/src/failure_library.dart';
import 'package:dust/src/mutators.dart';
import 'package:dust/src/pool.dart';
import 'package:dust/src/seed.dart';
import 'package:dust/src/seed_library.dart';

class Driver {
  final SeedLibrary _seeds;
  final FailureLibrary _failures;
  final Random _random;
  final List<Controller> _runners;
  final int _batchSize;

  final _successStreamCtrl = StreamController<void>();
  final _newSeedStreamCtrl = StreamController<Seed>();
  final _uniqueFailStreamCtrl = StreamController<Failure>();
  final _duplicateFailStreamCtrl = StreamController<Failure>();

  Driver(this._seeds, this._failures, this._batchSize, this._runners,
      this._random);

  Stream<Failure> get onDuplicateFail => _duplicateFailStreamCtrl.stream;
  Stream<Seed> get onNewSeed => _newSeedStreamCtrl.stream;
  Stream<void> get onSuccess => _successStreamCtrl.stream;
  Stream<Failure> get onUniqueFail => _uniqueFailStreamCtrl.stream;

  Future<void> run(List<String> seeds) async {
    // run initial seeds
    await Pool<Controller, String>(_runners, _preseed)
        .consume(Queue.from(seeds));

    final pool = Pool<Controller, Seed>(_runners, _runCase);

    while (true) {
      final batch = _seeds.getBatch(_batchSize, _random);

      await pool.consume(Queue.from(batch));
    }
  }

  Future<void> _preseed(Controller runner, String seed) async {
    final result = await runner.run(seed);
    _seeds.report(seed, result);
  }

  Future<void> _runCase(Controller runner, Seed seed) async {
    final input = mutate(seed.input, _random);
    final result = await runner.run(input);
    if (!result.succeeded) {
      final failure = Failure(input, result);
      final previousFailure = _failures.report(failure);
      if (previousFailure == null) {
        _uniqueFailStreamCtrl.add(failure);
      } else {
        _duplicateFailStreamCtrl.add(failure);
      }
    }

    _successStreamCtrl.add(null);
    final newSeed = _seeds.report(input, result);
    if (newSeed != null) {
      _newSeedStreamCtrl.add(newSeed);
    }
  }
}
