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

import 'package:schemantic/schemantic.dart';

import '../genkit_openai.dart';

const _audioOptionFields = {'responseModalities', 'audioVoice', 'audioFormat'};
const _responseModalitiesField = {'responseModalities'};

final SchemanticType<OpenAIOptions> _noAudioOptionsSchema =
    _FilteredOpenAIOptionsType(
      hiddenFields: _audioOptionFields,
      schemaNameSuffix: 'NoAudio',
    );

final SchemanticType<OpenAIOptions> _noResponseModalitiesSchema =
    _FilteredOpenAIOptionsType(
      hiddenFields: _responseModalitiesField,
      schemaNameSuffix: 'NoResponseModalities',
    );

/// Returns a config schema tailored to the target model type.
SchemanticType<OpenAIOptions> optionsSchemaForModel(String modelId) {
  return switch (getModelType(modelId)) {
    'audio' => OpenAIOptions.$schema,
    'tts' => _noResponseModalitiesSchema,
    _ => _noAudioOptionsSchema,
  };
}

final class _FilteredOpenAIOptionsType extends SchemanticType<OpenAIOptions> {
  final Set<String> hiddenFields;
  final String schemaNameSuffix;

  const _FilteredOpenAIOptionsType({
    required this.hiddenFields,
    required this.schemaNameSuffix,
  });

  @override
  OpenAIOptions parse(Object? json) => OpenAIOptions.$schema.parse(json);

  @override
  JsonSchemaMetadata? get schemaMetadata {
    final base = OpenAIOptions.$schema.schemaMetadata;
    if (base == null) {
      return null;
    }

    final definition = _deepClone(base.definition) as Map<String, Object?>;
    final properties = definition['properties'];
    if (properties is Map) {
      for (final key in hiddenFields) {
        properties.remove(key);
      }
    }

    final required = definition['required'];
    if (required is List) {
      required.removeWhere(hiddenFields.contains);
    }

    final baseName = base.name ?? 'OpenAIOptions';
    return JsonSchemaMetadata(
      name: '$baseName$schemaNameSuffix',
      definition: definition,
      dependencies: base.dependencies,
    );
  }
}

Object? _deepClone(Object? value) {
  if (value is Map) {
    final cloned = <String, Object?>{};
    for (final entry in value.entries) {
      cloned[entry.key as String] = _deepClone(entry.value);
    }
    return cloned;
  }

  if (value is List) {
    return value.map(_deepClone).toList();
  }

  return value;
}
