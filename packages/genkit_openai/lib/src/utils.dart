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

import 'dart:convert';

import 'package:openai_dart/openai_dart.dart';
import 'package:schemantic/schemantic.dart';

/// Returns true when the output config indicates JSON-structured output
/// (format is 'json' or contentType is 'application/json').
bool isJsonStructuredOutput(String? format, String? contentType) {
  return format == 'json' || contentType == 'application/json';
}

/// Builds an OpenAI [ResponseFormat] from a Genkit output schema.
/// Flattens `$ref`/`$defs` since OpenAI requires `type` at the top level.
/// Returns null if [schema] is null.
ResponseFormat? buildOpenAIResponseFormat(Map<String, dynamic>? schema) {
  if (schema == null) return null;
  final flattened = schema.flatten();
  return ResponseFormat.jsonSchema(
    jsonSchema: JsonSchemaObject(
      name: 'output',
      schema: {...flattened, 'additionalProperties': false},
      strict: true,
    ),
  );
}

Uri buildOpenAIUri(String path, String? baseUrl) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';

  if (baseUrl == null || baseUrl.isEmpty) {
    return Uri.parse('https://api.openai.com/v1$normalizedPath');
  }

  final parsedBaseUri = Uri.parse(baseUrl);
  final trimmedBasePath = parsedBaseUri.path.endsWith('/')
      ? parsedBaseUri.path.substring(0, parsedBaseUri.path.length - 1)
      : parsedBaseUri.path;

  return parsedBaseUri.replace(path: '$trimmedBasePath$normalizedPath');
}

String? normalizeOptionalString(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

void appendMultipartField(
  List<int> bodyBytes,
  String boundary,
  String name,
  String value,
) {
  bodyBytes.addAll(utf8.encode('--$boundary\r\n'));
  bodyBytes.addAll(
    utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'),
  );
  bodyBytes.addAll(utf8.encode(value));
  bodyBytes.addAll(utf8.encode('\r\n'));
}

void appendMultipartFile(
  List<int> bodyBytes,
  String boundary, {
  required String fieldName,
  required String filename,
  required String contentType,
  required List<int> bytes,
}) {
  bodyBytes.addAll(utf8.encode('--$boundary\r\n'));
  bodyBytes.addAll(
    utf8.encode(
      'Content-Disposition: form-data; name="$fieldName"; filename="$filename"\r\n',
    ),
  );
  bodyBytes.addAll(utf8.encode('Content-Type: $contentType\r\n\r\n'));
  bodyBytes.addAll(bytes);
  bodyBytes.addAll(utf8.encode('\r\n'));
}
