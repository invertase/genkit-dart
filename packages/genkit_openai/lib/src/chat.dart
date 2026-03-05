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

import 'package:json_schema_builder/json_schema_builder.dart' as jsb;
import 'package:schemantic/schemantic.dart';

import '../genkit_openai.dart';

final SchemanticType<OpenAIOptions> _chatOptionsSchema =
    _OpenAIOptionsSchemaType(
      schemaName: 'OpenAIOptionsNoAudio',
      properties: {
        'version': $Schema.string(),
        'temperature': $Schema.number(minimum: 0.0, maximum: 2.0),
        'topP': $Schema.number(minimum: 0.0, maximum: 1.0),
        'maxTokens': $Schema.integer(),
        'stop': $Schema.list(items: $Schema.string()),
        'presencePenalty': $Schema.number(minimum: -2.0, maximum: 2.0),
        'frequencyPenalty': $Schema.number(minimum: -2.0, maximum: 2.0),
        'seed': $Schema.integer(),
        'user': $Schema.string(),
        'jsonMode': $Schema.boolean(),
        'visualDetailLevel': $Schema.string(
          enumValues: ['auto', 'low', 'high'],
        ),
      },
    );

/// Returns custom options schema for standard chat models.
SchemanticType<OpenAIOptions> chatModelOptionsSchema() => _chatOptionsSchema;

final class _OpenAIOptionsSchemaType extends SchemanticType<OpenAIOptions> {
  final String schemaName;
  final Map<String, jsb.Schema> properties;

  const _OpenAIOptionsSchemaType({
    required this.schemaName,
    required this.properties,
  });

  @override
  OpenAIOptions parse(Object? json) => OpenAIOptions.$schema.parse(json);

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: schemaName,
    definition: $Schema.object(properties: properties, required: []).value,
    dependencies: const [],
  );
}
