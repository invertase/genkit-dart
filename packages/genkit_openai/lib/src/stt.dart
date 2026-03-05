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
import 'dart:typed_data';

import 'package:genkit/plugin.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:json_schema_builder/json_schema_builder.dart' as jsb;
import 'package:openai_dart/openai_dart.dart';
import 'package:schemantic/schemantic.dart';

import '../genkit_openai.dart';

final SchemanticType<OpenAIOptions> _sttOptionsSchema =
    _OpenAIOptionsSchemaType(
      schemaName: 'OpenAIOptionsStt',
      properties: {
        'version': $Schema.string(),
        'temperature': $Schema.number(minimum: 0.0, maximum: 1.0),
        'language': $Schema.string(),
        'prompt': $Schema.string(),
        'response_format': $Schema.string(
          enumValues: ['json', 'text', 'srt', 'verbose_json', 'vtt'],
        ),
        'include': $Schema.list(items: $Schema.string()),
        'timestamp_granularities': $Schema.list(items: $Schema.string()),
        'translate': $Schema.boolean(),
        'task': $Schema.string(enumValues: ['transcribe', 'translate']),
      },
    );

/// Returns custom options schema for speech-to-text models.
SchemanticType<OpenAIOptions> speechToTextModelOptionsSchema() =>
    _sttOptionsSchema;

/// Model info for speech-to-text models.
ModelInfo speechToTextModelInfo(String model) {
  return ModelInfo(
    label: model,
    supports: {
      'output': ['text', 'json'],
      'multiturn': false,
      'tools': false,
      'systemRole': false,
      'media': true,
    },
  );
}

/// Returns true if [modelId] refers to a dedicated speech-to-text model.
bool isSpeechToTextModel(String modelId) {
  final id = modelId.toLowerCase();
  return id.contains('transcribe') || id.contains('whisper');
}

final class SpeechToTextInputFile {
  final Uint8List bytes;
  final String filename;
  final String contentType;

  const SpeechToTextInputFile({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });
}

final class SpeechToTextPreparedRequest {
  final bool translation;
  final SpeechToTextInputFile file;
  final Map<String, dynamic> fields;

  const SpeechToTextPreparedRequest({
    required this.translation,
    required this.file,
    required this.fields,
  });
}

Future<ModelResponse> handleSpeechToText(
  OpenAIClient client,
  ModelRequest requestInput, {
  required String modelId,
  required String? baseUrl,
}) async {
  final prepared = toSpeechToTextRequest(modelId, requestInput);
  final endpoint = _resolveSpeechToTextEndpoint(
    baseUrl,
    translation: prepared.translation,
  );
  final uri = Uri.parse('${endpoint.baseUrl}${endpoint.path}');

  final request = http.MultipartRequest('POST', uri);
  if (client.apiKey.trim().isNotEmpty) {
    request.headers['authorization'] = 'Bearer ${client.apiKey.trim()}';
  }
  final inheritedHeaders = Map<String, String>.from(client.headers);
  inheritedHeaders.removeWhere(
    (name, _) => name.toLowerCase() == 'content-type',
  );
  request.headers.addAll(inheritedHeaders);
  request.files.add(
    http.MultipartFile.fromBytes(
      'file',
      prepared.file.bytes,
      filename: prepared.file.filename,
      contentType: MediaType.parse(prepared.file.contentType),
    ),
  );
  _appendSpeechToTextFields(request, prepared.fields);

  final streamedResponse = await client.client.send(request);
  final response = await http.Response.fromStream(streamedResponse);
  if ((response.statusCode ~/ 100) != 2) {
    throw GenkitException(
      'Speech-to-text request failed with status ${response.statusCode}.',
      status: StatusCodes.fromHttpStatus(response.statusCode),
      details: utf8.decode(response.bodyBytes),
    );
  }

  final responseFormat = _resolveSpeechToTextResponseFormat(
    prepared.fields,
    fallback: prepared.translation ? 'text' : 'json',
  );
  final payload = _parseSpeechToTextPayload(response.bodyBytes, responseFormat);
  final transcriptText = _extractTranscriptText(payload);

  return ModelResponse(
    finishReason: FinishReason.stop,
    message: Message(
      role: Role.model,
      content: [TextPart(text: transcriptText)],
    ),
    raw: {
      'endpoint': endpoint.path,
      'model': modelId,
      'translation': prepared.translation,
      'responseFormat': responseFormat,
      'response': payload,
    },
  );
}

SpeechToTextPreparedRequest toSpeechToTextRequest(
  String modelName,
  ModelRequest request,
) {
  final fields = <String, dynamic>{...?request.config};
  final translation = _resolveTranslationMode(fields);
  final file = _extractSpeechToTextInputAudio(request.messages);

  fields['model'] = modelName;
  fields['prompt'] ??= _extractSpeechPrompt(request.messages);

  final normalizedResponseFormat =
      _nonEmptyString(fields['response_format']) ??
      _nonEmptyString(fields['responseFormat']);
  if (normalizedResponseFormat != null) {
    fields['response_format'] = normalizedResponseFormat;
  } else {
    fields['response_format'] = translation ? 'text' : 'json';
  }

  fields.remove('responseFormat');
  fields.remove('translate');
  final task = _nonEmptyString(fields['task'])?.toLowerCase();
  if (task == 'translate' || task == 'transcribe') {
    fields.remove('task');
  }

  fields.removeWhere((_, value) => value == null);

  return SpeechToTextPreparedRequest(
    translation: translation,
    file: file,
    fields: fields,
  );
}

void _appendSpeechToTextFields(
  http.MultipartRequest request,
  Map<String, dynamic> fields,
) {
  for (final entry in fields.entries) {
    _appendSpeechToTextFieldValue(request, entry.key, entry.value);
  }
}

void _appendSpeechToTextFieldValue(
  http.MultipartRequest request,
  String key,
  Object? value,
) {
  if (value == null) return;

  if (value is Iterable) {
    final repeatedKey = key.endsWith('[]') ? key : '$key[]';
    for (final item in value) {
      _appendSpeechToTextFieldValue(request, repeatedKey, item);
    }
    return;
  }

  final encodedValue = switch (value) {
    Map() || List() => jsonEncode(value),
    _ => value.toString(),
  };

  request.files.add(http.MultipartFile.fromString(key, encodedValue));
}

String _resolveSpeechToTextResponseFormat(
  Map<String, dynamic> fields, {
  required String fallback,
}) {
  final explicit =
      _nonEmptyString(fields['response_format']) ??
      _nonEmptyString(fields['responseFormat']);
  return explicit?.toLowerCase() ?? fallback.toLowerCase();
}

Object? _parseSpeechToTextPayload(Uint8List bodyBytes, String responseFormat) {
  switch (responseFormat) {
    case 'json':
    case 'verbose_json':
      return jsonDecode(utf8.decode(bodyBytes));
    default:
      return utf8.decode(bodyBytes);
  }
}

String _extractTranscriptText(Object? payload) {
  if (payload is String) {
    return payload;
  }

  if (payload is Map<String, dynamic>) {
    final text = payload['text'];
    if (text is String && text.trim().isNotEmpty) {
      return text;
    }
    final transcript = payload['transcript'];
    if (transcript is String && transcript.trim().isNotEmpty) {
      return transcript;
    }
  }

  return jsonEncode(payload);
}

bool _resolveTranslationMode(Map<String, dynamic> fields) {
  final translate = fields['translate'];
  if (translate is bool) {
    return translate;
  }
  if (translate is String) {
    final normalized = translate.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }

  final task = _nonEmptyString(fields['task'])?.toLowerCase();
  return task == 'translate';
}

String? _extractSpeechPrompt(List<Message> messages) {
  for (final message in messages.reversed) {
    if (message.role != Role.user) continue;
    final textParts = message.content
        .where((part) => part.isText)
        .map((part) => part.text!.trim())
        .where((text) => text.isNotEmpty)
        .toList();
    if (textParts.isEmpty) continue;
    return textParts.join('\n');
  }
  return null;
}

SpeechToTextInputFile _extractSpeechToTextInputAudio(List<Message> messages) {
  for (final message in messages.reversed) {
    if (message.role != Role.user) continue;
    for (final part in message.content) {
      final media = part.media;
      if (media == null) continue;
      final parsedDataUrl = _extractDataFromBase64Url(media.url);
      final contentType =
          _nonEmptyString(media.contentType)?.toLowerCase() ??
          parsedDataUrl?['contentType']?.toLowerCase();
      if (contentType == null || !contentType.startsWith('audio/')) {
        continue;
      }

      return _decodeAudioMedia(media, parsedDataUrl: parsedDataUrl);
    }
  }

  throw GenkitException(
    'Speech-to-text models require an audio media data URL in a user message.',
    status: StatusCodes.INVALID_ARGUMENT,
  );
}

SpeechToTextInputFile _decodeAudioMedia(
  Media media, {
  Map<String, String>? parsedDataUrl,
}) {
  parsedDataUrl ??= _extractDataFromBase64Url(media.url);
  if (parsedDataUrl == null) {
    throw GenkitException(
      'Speech-to-text currently supports only audio data URLs '
      '(data:audio/...;base64,...).',
      status: StatusCodes.INVALID_ARGUMENT,
    );
  }

  final parsedContentType = parsedDataUrl['contentType']!;
  final contentType = _nonEmptyString(media.contentType) ?? parsedContentType;
  final normalizedContentType = contentType.toLowerCase();
  if (!normalizedContentType.startsWith('audio/')) {
    throw GenkitException(
      'Speech-to-text input must be audio media, got "$contentType".',
      status: StatusCodes.INVALID_ARGUMENT,
    );
  }

  final rawData = parsedDataUrl['data']!;
  late final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Decode(rawData));
  } catch (e, stackTrace) {
    throw GenkitException(
      'Invalid base64 audio data URL.',
      status: StatusCodes.INVALID_ARGUMENT,
      underlyingException: e,
      stackTrace: stackTrace,
    );
  }

  return SpeechToTextInputFile(
    bytes: bytes,
    filename: 'input.${_audioExtensionForContentType(normalizedContentType)}',
    contentType: normalizedContentType,
  );
}

Map<String, String>? _extractDataFromBase64Url(String url) {
  final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(url);
  if (match == null) return null;
  return <String, String>{
    'contentType': match.group(1)!,
    'data': match.group(2)!,
  };
}

String _audioExtensionForContentType(String contentType) {
  return switch (contentType) {
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/flac' => 'flac',
    'audio/opus' => 'opus',
    'audio/ogg' => 'ogg',
    'audio/webm' => 'webm',
    'audio/mp4' => 'mp4',
    'audio/m4a' => 'm4a',
    _ => contentType.split('/').last,
  };
}

({String baseUrl, String path}) _resolveSpeechToTextEndpoint(
  String? baseUrl, {
  required bool translation,
}) {
  final endpointPath = translation
      ? '/audio/translations'
      : '/audio/transcriptions';

  if (baseUrl == null) {
    return (baseUrl: 'https://api.openai.com', path: '/v1$endpointPath');
  }

  final normalizedPath = Uri.parse(baseUrl).path.toLowerCase();
  final includesVersionPrefix = RegExp(
    r'(^|/)v\d+(/|$)',
  ).hasMatch(normalizedPath);

  return (
    baseUrl: baseUrl,
    path: includesVersionPrefix ? endpointPath : '/v1$endpointPath',
  );
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
