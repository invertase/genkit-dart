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

part of 'transcriptions.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

class OpenAITranscriptionOptions {
  factory OpenAITranscriptionOptions.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  OpenAITranscriptionOptions._(this._json);

  OpenAITranscriptionOptions({double? temperature, String? responseFormat}) {
    _json = {'temperature': ?temperature, 'responseFormat': ?responseFormat};
  }

  late final Map<String, dynamic> _json;

  static const SchemanticType<OpenAITranscriptionOptions> $schema =
      _OpenAITranscriptionOptionsTypeFactory();

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

class _OpenAITranscriptionOptionsTypeFactory
    extends SchemanticType<OpenAITranscriptionOptions> {
  const _OpenAITranscriptionOptionsTypeFactory();

  @override
  OpenAITranscriptionOptions parse(Object? json) {
    return OpenAITranscriptionOptions._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'OpenAITranscriptionOptions',
    definition: $Schema
        .object(
          properties: {
            'temperature': $Schema.number(minimum: 0.0, maximum: 1.0),
            'responseFormat': $Schema.string(
              enumValues: ['json', 'text', 'srt', 'verbose_json', 'vtt'],
            ),
          },
          required: [],
        )
        .value,
    dependencies: [],
  );
}
