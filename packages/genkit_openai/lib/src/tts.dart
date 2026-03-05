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

import 'package:genkit/plugin.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;
import 'package:openai_dart/openai_dart.dart';
// ignore: implementation_imports
import 'package:openai_dart/src/generated/client.dart' as openai_generated;
import 'package:schemantic/schemantic.dart';

import '../genkit_openai.dart';

const Map<String, String> _responseFormatMediaTypes = <String, String>{
  'mp3': 'audio/mpeg',
  'mpeg': 'audio/mpeg',
  'opus': 'audio/opus',
  'aac': 'audio/aac',
  'flac': 'audio/flac',
  'wav': 'audio/wav',
  'pcm': 'audio/L16',
  'pcm16': 'audio/L16',
  'l16': 'audio/L16',
};

final SchemanticType<OpenAIOptions> _ttsOptionsSchema =
    _OpenAIOptionsSchemaType(
      schemaName: 'OpenAIOptionsTts',
      properties: {
        'version': $Schema.string(),
        'audioVoice': $Schema.string(
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
    );

/// Returns custom options schema for speech synthesis models.
SchemanticType<OpenAIOptions> speechSynthesisModelOptionsSchema() =>
    _ttsOptionsSchema;

/// Model info for text-to-speech models.
ModelInfo ttsModelInfo(String model) {
  return ModelInfo(
    label: model,
    supports: {
      'output': ['media'],
      'multiturn': false,
      'tools': false,
      'systemRole': false,
      'media': false,
    },
  );
}

/// Returns true if [modelId] refers to a dedicated speech synthesis model.
bool isSpeechSynthesisModel(String modelId) {
  final id = modelId.toLowerCase();
  return id.contains('tts') &&
      !id.contains('audio') &&
      !id.contains('realtime');
}

Future<ModelResponse> handleSpeechSynthesis(
  OpenAIClient client,
  ModelRequest requestInput, {
  required String modelId,
  required String? baseUrl,
  String? audioVoice,
  String? audioFormat,
}) async {
  final ttsRequest = toSpeechSynthesisRequest(
    modelId,
    requestInput,
    audioVoice: audioVoice,
    audioFormat: audioFormat,
  );
  final responseFormat =
      _nonEmptyString(ttsRequest['response_format']) ?? 'mp3';
  final requestedMimeType = _speechFormatToMimeType(responseFormat);
  final speechEndpoint = _resolveSpeechEndpoint(baseUrl);

  // ignore: invalid_use_of_protected_member
  final response = await client.makeRequest(
    baseUrl: speechEndpoint.baseUrl,
    path: speechEndpoint.path,
    method: openai_generated.HttpMethod.post,
    requestType: 'application/json',
    responseType: requestedMimeType,
    body: ttsRequest,
  );

  final mimeType = _resolveSpeechContentType(
    response.headers['content-type'],
    fallbackFormat: responseFormat,
  );
  final audioData = base64Encode(response.bodyBytes);

  return ModelResponse(
    finishReason: FinishReason.stop,
    message: Message(
      role: Role.model,
      content: [
        MediaPart(
          media: Media(
            url: 'data:$mimeType;base64,$audioData',
            contentType: mimeType,
          ),
          metadata: {
            'audio': {
              'model': modelId,
              'voice': ttsRequest['voice'],
              'format': responseFormat,
            },
          },
        ),
      ],
    ),
    raw: {
      'endpoint': speechEndpoint.path,
      'model': modelId,
      'responseFormat': responseFormat,
      'contentType': mimeType,
    },
  );
}

Map<String, dynamic> toSpeechSynthesisRequest(
  String modelName,
  ModelRequest request, {
  String? audioVoice,
  String? audioFormat,
}) {
  final ttsRequest = <String, dynamic>{
    ...?request.config,
    'model': modelName,
    'input': _extractSpeechInputText(request.messages),
  };

  ttsRequest['voice'] ??= _nonEmptyString(audioVoice) ?? 'alloy';
  final format = _nonEmptyString(audioFormat);
  if (_nonEmptyString(ttsRequest['response_format']) == null &&
      format != null) {
    ttsRequest['response_format'] = format;
  }

  ttsRequest.removeWhere((_, value) => value == null);
  return ttsRequest;
}

String _extractSpeechInputText(List<Message> messages) {
  String? lastNonEmptyText;
  for (final message in messages.reversed) {
    final text = message.text.trim();
    if (text.isEmpty) continue;

    if (message.role == Role.user) {
      return text;
    }

    lastNonEmptyText ??= text;
  }

  if (lastNonEmptyText != null) {
    return lastNonEmptyText;
  }

  throw GenkitException(
    'Speech synthesis models require non-empty text input.',
    status: StatusCodes.INVALID_ARGUMENT,
  );
}

({String baseUrl, String path}) _resolveSpeechEndpoint(String? baseUrl) {
  if (baseUrl == null) {
    return (baseUrl: 'https://api.openai.com', path: '/v1/audio/speech');
  }

  final normalizedPath = Uri.parse(baseUrl).path.toLowerCase();
  final includesVersionPrefix = RegExp(
    r'(^|/)v\d+(/|$)',
  ).hasMatch(normalizedPath);

  return (
    baseUrl: baseUrl,
    path: includesVersionPrefix ? '/audio/speech' : '/v1/audio/speech',
  );
}

String _speechFormatToMimeType(String format) {
  final normalized = format.trim().toLowerCase();
  return _responseFormatMediaTypes[normalized] ?? 'audio/mpeg';
}

String _resolveSpeechContentType(
  String? headerValue, {
  required String fallbackFormat,
}) {
  if (headerValue == null || headerValue.trim().isEmpty) {
    return _speechFormatToMimeType(fallbackFormat);
  }

  final normalized = headerValue.split(';').first.trim().toLowerCase();
  if (normalized.startsWith('audio/')) {
    return normalized;
  }
  if (normalized.contains('/')) {
    return _speechFormatToMimeType(fallbackFormat);
  }
  return _speechFormatToMimeType(normalized);
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

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
