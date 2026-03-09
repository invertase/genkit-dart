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

part of 'tts.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

base class OpenAITtsOptions {
  factory OpenAITtsOptions.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  OpenAITtsOptions._(this._json);

  OpenAITtsOptions({
    String? version,
    String? voice,
    double? speed,
    String? responseFormat,
  }) {
    _json = {
      'version': ?version,
      'voice': ?voice,
      'speed': ?speed,
      'responseFormat': ?responseFormat,
    };
  }

  late final Map<String, dynamic> _json;

  static const SchemanticType<OpenAITtsOptions> $schema =
      _OpenAITtsOptionsTypeFactory();

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

  double? get speed {
    return (_json['speed'] as num?)?.toDouble();
  }

  set speed(double? value) {
    if (value == null) {
      _json.remove('speed');
    } else {
      _json['speed'] = value;
    }
  }

  String? get responseFormat {
    return _json['responseFormat'] as String?;
  }

  set responseFormat(String? value) {
    if (value == null) {
      _json.remove('responseFormat');
    } else {
      _json['responseFormat'] = value;
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

base class _OpenAITtsOptionsTypeFactory
    extends SchemanticType<OpenAITtsOptions> {
  const _OpenAITtsOptionsTypeFactory();

  @override
  OpenAITtsOptions parse(Object? json) {
    return OpenAITtsOptions._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'OpenAITtsOptions',
    definition: $Schema
        .object(
          properties: {
            'version': $Schema.string(),
            'voice': $Schema.string(
              enumValues: ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'],
            ),
            'speed': $Schema.number(minimum: 0.25, maximum: 4.0),
            'responseFormat': $Schema.string(
              enumValues: ['mp3', 'opus', 'aac', 'flac', 'wav', 'pcm'],
            ),
          },
          required: [],
        )
        .value,
    dependencies: [],
  );
}
