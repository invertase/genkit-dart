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

part of 'stt.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

base class OpenAISttOptions {
  factory OpenAISttOptions.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  OpenAISttOptions._(this._json);

  OpenAISttOptions({
    String? version,
    double? temperature,
    String? language,
    String? responseFormat,
    List<String>? timestampGranularities,
    bool? translate,
  }) {
    _json = {
      'version': ?version,
      'temperature': ?temperature,
      'language': ?language,
      'responseFormat': ?responseFormat,
      'timestampGranularities': ?timestampGranularities,
      'translate': ?translate,
    };
  }

  late final Map<String, dynamic> _json;

  static const SchemanticType<OpenAISttOptions> $schema =
      _OpenAISttOptionsTypeFactory();

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

  String? get language {
    return _json['language'] as String?;
  }

  set language(String? value) {
    if (value == null) {
      _json.remove('language');
    } else {
      _json['language'] = value;
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

  List<String>? get timestampGranularities {
    return (_json['timestampGranularities'] as List?)?.cast<String>();
  }

  set timestampGranularities(List<String>? value) {
    if (value == null) {
      _json.remove('timestampGranularities');
    } else {
      _json['timestampGranularities'] = value;
    }
  }

  bool? get translate {
    return _json['translate'] as bool?;
  }

  set translate(bool? value) {
    if (value == null) {
      _json.remove('translate');
    } else {
      _json['translate'] = value;
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

base class _OpenAISttOptionsTypeFactory
    extends SchemanticType<OpenAISttOptions> {
  const _OpenAISttOptionsTypeFactory();

  @override
  OpenAISttOptions parse(Object? json) {
    return OpenAISttOptions._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'OpenAISttOptions',
    definition: $Schema
        .object(
          properties: {
            'version': $Schema.string(),
            'temperature': $Schema.number(minimum: 0.0, maximum: 1.0),
            'language': $Schema.string(),
            'responseFormat': $Schema.string(
              enumValues: ['json', 'text', 'srt', 'verbose_json', 'vtt'],
            ),
            'timestampGranularities': $Schema.list(items: $Schema.string()),
            'translate': $Schema.boolean(),
          },
          required: [],
        )
        .value,
    dependencies: [],
  );
}
