// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:analyzer/file_system/file_system.dart' show ResourceProvider;
// ignore: implementation_imports
import 'package:analyzer/src/clients/build_resolvers/build_resolvers.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/byte_store.dart'
    show MemoryCachingByteStore;
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/file_byte_store.dart'
    show EvictingFileByteStore;
import 'package:package_config/package_config.dart' show PackageConfig;
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'analysis_driver_filesystem.dart';
import 'analysis_driver_model.dart';

/// Builds an [AnalysisDriverForPackageBuild] backed by a summary SDK.
///
/// Any code must be resolvable through [analysisDriverModel].
AnalysisDriverForPackageBuild analysisDriver(
  AnalysisDriverModel analysisDriverModel,
  AnalysisOptions analysisOptions,
  String sdkSummaryPath,
  PackageConfig packageConfig,
) {
  return createAnalysisDriver(
    analysisOptions: analysisOptions,
    packages: _buildAnalyzerPackages(
      packageConfig,
      analysisDriverModel.filesystem,
    ),
    resourceProvider: analysisDriverModel.filesystem,
    fileContentCache: analysisDriverModel.filesystem,
    sdkSummaryBytes: File(sdkSummaryPath).readAsBytesSync(),
    uriResolvers: [analysisDriverModel.filesystem],
    byteStore: _persistentByteStore(),
  );
}

/// The directory named by this environment variable holds the analyzer's
/// parsed and linked summaries across builds.
const _analyzerCacheEnvironmentVariable = 'BUILD_RUNNER_ANALYZER_CACHE';

/// A byte store that keeps analyzer results on disk, or `null` to keep the
/// analyzer's default in-memory store.
///
/// Without it every build_runner process parses and links the SDK, every
/// dependency and every workspace package from scratch. Entries are keyed by
/// content and API signatures, and the analyzer only sees the virtual asset
/// paths from [AnalysisDriverFilesystem], so one directory can safely be
/// shared by several checkouts and by concurrent processes.
ByteStore? _persistentByteStore() {
  final path = Platform.environment[_analyzerCacheEnvironmentVariable];
  if (path == null || path.isEmpty) return null;
  Directory(path).createSync(recursive: true);
  return MemoryCachingByteStore(
    EvictingFileByteStore(path, 4 * 1024 * 1024 * 1024),
    512 * 1024 * 1024,
  );
}

Packages _buildAnalyzerPackages(
  PackageConfig packageConfig,
  ResourceProvider resourceProvider,
) => Packages({
  for (final package in packageConfig.packages)
    package.name: Package(
      name: package.name,
      languageVersion: package.languageVersion == null
          ? sdkLanguageVersion
          : Version(
              package.languageVersion!.major,
              package.languageVersion!.minor,
              0,
            ),
      // Analyzer does not see the original file paths at all, we need to
      // make them match the paths that we give it, so we use the
      // `assetPath` function to create those.
      rootFolder: resourceProvider.getFolder(
        p.url.normalize(
          AnalysisDriverFilesystem.assetPathFor(
            package: package.name,
            path: '',
          ),
        ),
      ),
      libFolder: resourceProvider.getFolder(
        p.url.normalize(
          AnalysisDriverFilesystem.assetPathFor(
            package: package.name,
            path: 'lib',
          ),
        ),
      ),
    ),
});

/// The language version of the current sdk parsed from the [Platform.version].
final sdkLanguageVersion = () {
  final sdkVersion = Version.parse(Platform.version.split(' ').first);
  return Version(sdkVersion.major, sdkVersion.minor, 0);
}();
