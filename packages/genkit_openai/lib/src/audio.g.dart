// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'audio.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

base class OpenAIAudioOptions {
  factory OpenAIAudioOptions.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  OpenAIAudioOptions._(this._json);

  OpenAIAudioOptions({
    String? version,
    double? temperature,
    double? topP,
    int? maxTokens,
    int? seed,
    String? user,
    String? voice,
    String? audioFormat,
  }) {
    _json = {
      'version': ?version,
      'temperature': ?temperature,
      'topP': ?topP,
      'maxTokens': ?maxTokens,
      'seed': ?seed,
      'user': ?user,
      'voice': ?voice,
      'audioFormat': ?audioFormat,
    };
  }

  late final Map<String, dynamic> _json;

  static const SchemanticType<OpenAIAudioOptions> $schema =
      _OpenAIAudioOptionsTypeFactory();

  String? get version {
    return _json['version'] as String?;
  }

  set version(String? value) {
    if (value == null) {
      _json.remove('version');
    } else {
      _json['version'] = value;
    }
  }

  double? get temperature {
    return (_json['temperature'] as num?)?.toDouble();
  }

  set temperature(double? value) {
    if (value == null) {
      _json.remove('temperature');
    } else {
      _json['temperature'] = value;
    }
  }

  double? get topP {
    return (_json['topP'] as num?)?.toDouble();
  }

  set topP(double? value) {
    if (value == null) {
      _json.remove('topP');
    } else {
      _json['topP'] = value;
    }
  }

  int? get maxTokens {
    return _json['maxTokens'] as int?;
  }

  set maxTokens(int? value) {
    if (value == null) {
      _json.remove('maxTokens');
    } else {
      _json['maxTokens'] = value;
    }
  }

  int? get seed {
    return _json['seed'] as int?;
  }

  set seed(int? value) {
    if (value == null) {
      _json.remove('seed');
    } else {
      _json['seed'] = value;
    }
  }

  String? get user {
    return _json['user'] as String?;
  }

  set user(String? value) {
    if (value == null) {
      _json.remove('user');
    } else {
      _json['user'] = value;
    }
  }

  String? get voice {
    return _json['voice'] as String?;
  }

  set voice(String? value) {
    if (value == null) {
      _json.remove('voice');
    } else {
      _json['voice'] = value;
    }
  }

  String? get audioFormat {
    return _json['audioFormat'] as String?;
  }

  set audioFormat(String? value) {
    if (value == null) {
      _json.remove('audioFormat');
    } else {
      _json['audioFormat'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _OpenAIAudioOptionsTypeFactory
    extends SchemanticType<OpenAIAudioOptions> {
  const _OpenAIAudioOptionsTypeFactory();

  @override
  OpenAIAudioOptions parse(Object? json) {
    return OpenAIAudioOptions._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'OpenAIAudioOptions',
    definition: $Schema
        .object(
          properties: {
            'version': $Schema.string(),
            'temperature': $Schema.number(minimum: 0.0, maximum: 2.0),
            'topP': $Schema.number(minimum: 0.0, maximum: 1.0),
            'maxTokens': $Schema.integer(),
            'seed': $Schema.integer(),
            'user': $Schema.string(),
            'voice': $Schema.string(
              enumValues: [
                'alloy',
                'ash',
                'ballad',
                'coral',
                'echo',
                'fable',
                'nova',
                'onyx',
                'sage',
                'shimmer',
                'verse',
              ],
            ),
            'audioFormat': $Schema.string(
              enumValues: ['wav', 'mp3', 'flac', 'opus', 'pcm16'],
            ),
          },
          required: [],
        )
        .value,
    dependencies: [],
  );
}
