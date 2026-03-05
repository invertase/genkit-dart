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

import 'package:genkit/genkit.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;
import 'package:openai_dart/openai_dart.dart';
import 'package:schemantic/schemantic.dart';

import '../genkit_openai.dart';

final SchemanticType<OpenAIOptions> _audioOptionsSchema =
    _OpenAIOptionsSchemaType(
      schemaName: 'OpenAIOptionsAudio',
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
        'responseModalities': $Schema.list(items: $Schema.string()),
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

/// Returns custom options schema for chat-audio models.
SchemanticType<OpenAIOptions> audioModelOptionsSchema() => _audioOptionsSchema;

/// Model info for audio generation models.
ModelInfo audioModelInfo(String model) {
  return ModelInfo(
    label: model,
    supports: {
      'multiturn': true,
      'tools': true,
      'systemRole': true,
      'media': true,
    },
  );
}

/// Returns true when [modelId] refers to an audio-preview chat model.
bool isAudioPreviewModel(String modelId) {
  return modelId.toLowerCase().contains('audio-preview');
}

/// Returns true if any user message includes audio media input.
bool containsInputAudio(List<Message> messages) {
  for (final message in messages) {
    if (message.role != Role.user) continue;
    for (final part in message.content) {
      final media = part.media;
      if (media == null) continue;

      final contentType = media.contentType;
      if (contentType != null &&
          contentType.toLowerCase().startsWith('audio/')) {
        return true;
      }

      final parsedDataUrl = _extractDataFromBase64Url(media.url);
      final parsedContentType = parsedDataUrl?['contentType'];
      if (parsedContentType != null &&
          parsedContentType.toLowerCase().startsWith('audio/')) {
        return true;
      }
    }
  }
  return false;
}

/// Resolves OpenAI chat completion modalities from user-provided values.
List<ChatCompletionModality>? resolveOpenAIModalities({
  required String modelType,
  required List<String>? configured,
  String? modelId,
  bool hasInputAudio = false,
}) {
  if (configured == null || configured.isEmpty) {
    return null;
  }

  return configured.map(_parseOpenAIModality).toList();
}

/// Builds audio options for chat completions when audio modality is enabled.
ChatCompletionAudioOptions? resolveOpenAIAudioOptions(
  List<ChatCompletionModality>? modalities, {
  String? voice,
  String? format,
  Map<String, dynamic>? rawConfig,
  String defaultFormat = 'wav',
}) {
  if (modalities == null ||
      !modalities.contains(ChatCompletionModality.audio)) {
    return null;
  }

  final resolvedVoice = _nonEmptyString(voice) ?? 'alloy';
  final resolvedFormat = _nonEmptyString(format) ?? defaultFormat;

  return ChatCompletionAudioOptions(
    voice: _parseOpenAIAudioVoice(resolvedVoice),
    format: _parseOpenAIAudioFormat(resolvedFormat),
  );
}

ChatCompletionModality _parseOpenAIModality(String modality) {
  return switch (modality.toLowerCase()) {
    'text' => ChatCompletionModality.text,
    'audio' => ChatCompletionModality.audio,
    _ => throw GenkitException(
      'Unsupported response modality "$modality". OpenAI chat completions support only "text" and "audio".',
      status: StatusCodes.INVALID_ARGUMENT,
    ),
  };
}

ChatCompletionAudioVoice _parseOpenAIAudioVoice(String voice) {
  final normalized = voice.trim().toLowerCase();
  for (final value in ChatCompletionAudioVoice.values) {
    if (value.name == normalized) {
      return value;
    }
  }
  throw GenkitException(
    'Unsupported audio voice "$voice".',
    status: StatusCodes.INVALID_ARGUMENT,
  );
}

ChatCompletionAudioFormat _parseOpenAIAudioFormat(String format) {
  final normalized = format.trim().toLowerCase();
  for (final audioFormat in ChatCompletionAudioFormat.values) {
    if (audioFormat.name == normalized) {
      return audioFormat;
    }
  }
  throw GenkitException(
    'Unsupported audio format "$format".',
    status: StatusCodes.INVALID_ARGUMENT,
  );
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, String>? _extractDataFromBase64Url(String url) {
  final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(url);
  if (match == null) return null;
  return <String, String>{
    'contentType': match.group(1)!,
    'data': match.group(2)!,
  };
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
