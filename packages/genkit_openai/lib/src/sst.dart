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
import 'dart:io';

import 'package:genkit/plugin.dart';

import 'utils.dart';

typedef _MultipartField = ({String name, String value});

const _transcriptionResponseFormats = <String>{
  'json',
  'text',
  'srt',
  'verbose_json',
  'vtt',
  'diarized_json',
};
const _transcriptionIncludeValues = <String>{'logprobs'};

/// Handles speech-to-text (SST) requests for transcription models.
Future<ModelResponse> handleSpeechToText({
  required ModelRequest request,
  required String modelName,
  required String apiKey,
  required String? baseUrl,
  required Map<String, String>? headers,
  required double? temperature,
  required String? configuredResponseFormat,
  required bool? configuredTranslate,
  required Map<String, dynamic>? rawConfig,
  required ({
    bool streamingRequested,
    void Function(ModelResponseChunk) sendChunk,
    Map<String, dynamic>? context,
    Stream<ModelRequest>? inputStream,
    void init,
  })
  ctx,
}) async {
  if (ctx.streamingRequested) {
    throw GenkitException(
      'Streaming is not currently supported for transcription models.',
    );
  }

  final media = _extractAudioMedia(request.messages);
  if (media == null) {
    throw GenkitException(
      'Transcription requires at least one audio MediaPart in request messages.',
    );
  }

  final audioPayload = _decodeAudioDataUrl(media);
  final useTranslationEndpoint = _shouldUseTranslationEndpoint(
    modelName: modelName,
    configuredTranslate: configuredTranslate,
    rawConfig: rawConfig,
  );
  final transcriptionUri = buildOpenAIUri(
    useTranslationEndpoint ? '/audio/translations' : '/audio/transcriptions',
    baseUrl,
  );
  final httpClient = HttpClient();

  try {
    final httpRequest = await httpClient.postUrl(transcriptionUri);
    httpRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    httpRequest.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (headers != null) {
      for (final header in headers.entries) {
        httpRequest.headers.set(header.key, header.value);
      }
    }

    final boundary = 'genkit-${DateTime.now().microsecondsSinceEpoch}';
    httpRequest.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );

    final bodyBytes = <int>[];
    final fields = _buildTranscriptionFields(
      request: request,
      modelName: modelName,
      temperature: temperature,
      configuredResponseFormat: configuredResponseFormat,
      rawConfig: rawConfig,
      useTranslationEndpoint: useTranslationEndpoint,
    );
    for (final field in fields) {
      appendMultipartField(bodyBytes, boundary, field.name, field.value);
    }

    appendMultipartFile(
      bodyBytes,
      boundary,
      fieldName: 'file',
      filename: audioPayload.filename,
      contentType: audioPayload.contentType,
      bytes: audioPayload.bytes,
    );

    bodyBytes.addAll(utf8.encode('--$boundary--\r\n'));
    httpRequest.add(bodyBytes);

    final response = await httpRequest.close();
    final responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GenkitException(
        'OpenAI API error: ${useTranslationEndpoint ? 'translation' : 'transcription'} request failed with status ${response.statusCode}.',
        status: StatusCodes.fromHttpStatus(response.statusCode),
        details: responseBody,
      );
    }

    final contentType = response.headers.contentType?.mimeType.toLowerCase();
    if (contentType != null && contentType.contains('application/json')) {
      final parsedBody = jsonDecode(responseBody);
      final raw = parsedBody is Map<String, dynamic>
          ? parsedBody
          : <String, dynamic>{'response': parsedBody};
      final transcript = _extractTranscriptionText(raw);

      if (transcript == null || transcript.trim().isEmpty) {
        throw GenkitException(
          '${useTranslationEndpoint ? 'Translation' : 'Transcription'} response did not contain text.',
          details: responseBody,
        );
      }

      return ModelResponse(
        finishReason: FinishReason.stop,
        message: Message(
          role: Role.model,
          content: [TextPart(text: transcript.trim())],
        ),
        raw: raw,
      );
    }

    final transcript = responseBody.trim();
    if (transcript.isEmpty) {
      throw GenkitException(
        '${useTranslationEndpoint ? 'Translation' : 'Transcription'} response did not contain text.',
        details: responseBody,
      );
    }
    return ModelResponse(
      finishReason: FinishReason.stop,
      message: Message(
        role: Role.model,
        content: [TextPart(text: transcript.trim())],
      ),
    );
  } on GenkitException {
    rethrow;
  } on FormatException catch (e, stackTrace) {
    throw GenkitException(
      'Invalid transcription response format: $e',
      underlyingException: e,
      stackTrace: stackTrace,
    );
  } catch (e, stackTrace) {
    throw GenkitException(
      'OpenAI transcription error: $e',
      details: e.toString(),
      underlyingException: e,
      stackTrace: stackTrace,
    );
  } finally {
    httpClient.close(force: true);
  }
}

Media? _extractAudioMedia(List<Message> messages) {
  for (final message in messages.reversed) {
    for (final part in message.content.reversed) {
      final media = part.media;
      if (media == null) continue;

      final contentType = media.contentType?.toLowerCase();
      final normalizedUrl = media.url.toLowerCase();
      final isTranscriptionDataUrl =
          normalizedUrl.startsWith('data:audio/') ||
          normalizedUrl.startsWith('data:video/') ||
          normalizedUrl.startsWith('data:application/ogg;');
      final isTranscriptionContentType =
          contentType != null &&
          (contentType.startsWith('audio/') ||
              contentType == 'video/mp4' ||
              contentType == 'video/webm' ||
              contentType == 'application/ogg');
      if (isTranscriptionDataUrl || isTranscriptionContentType) {
        return media;
      }
    }
  }
  return null;
}

({List<int> bytes, String contentType, String filename}) _decodeAudioDataUrl(
  Media media,
) {
  final url = media.url.trim();
  final match = RegExp(
    r'^data:((?:audio|video)\/[^;]+|application\/ogg);base64,',
    caseSensitive: false,
  ).firstMatch(url);

  if (match == null) {
    throw GenkitException(
      'Audio media must be provided as a base64 data URL for transcription models.',
    );
  }

  final contentType = match.group(1)!.toLowerCase();
  final encodedAudio = url.substring(match.end);
  final bytes = base64Decode(encodedAudio);
  final filename = switch (contentType) {
    'audio/flac' || 'audio/x-flac' => 'audio.flac',
    'audio/mp4' || 'video/mp4' => 'audio.mp4',
    'audio/mpeg' => 'audio.mpeg',
    'audio/mpga' || 'audio/x-mpga' => 'audio.mpga',
    'audio/m4a' || 'audio/x-m4a' => 'audio.m4a',
    'audio/ogg' || 'application/ogg' => 'audio.ogg',
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'audio.wav',
    'audio/mp3' || 'audio/x-mp3' => 'audio.mp3',
    'audio/webm' || 'video/webm' => 'audio.webm',
    _ => 'audio.bin',
  };

  return (bytes: bytes, contentType: contentType, filename: filename);
}

List<_MultipartField> _buildTranscriptionFields({
  required ModelRequest request,
  required String modelName,
  required double? temperature,
  required String? configuredResponseFormat,
  required Map<String, dynamic>? rawConfig,
  required bool useTranslationEndpoint,
}) {
  final config = Map<String, dynamic>.from(rawConfig ?? const {});
  final fields = <_MultipartField>[];
  _appendField(fields, 'model', modelName);

  final explicitPrompt = _takeOptionalString(config, ['prompt']);
  final prompt =
      explicitPrompt ?? _extractTranscriptionPrompt(request.messages);
  if (prompt != null && prompt.isNotEmpty) {
    _appendField(fields, 'prompt', prompt);
  }

  final rawCustomResponseFormat = _takeRawValue(config, ['response_format']);
  final camelResponseFormat = _takeRawValue(config, ['responseFormat']);
  final language = _takeOptionalString(config, ['language']);
  final chunkingStrategy = _takeRawValue(config, [
    'chunking_strategy',
    'chunkingStrategy',
  ]);
  final include = _takeStringList(config, ['include[]', 'include']);
  final timestampGranularities = _takeStringList(config, [
    'timestamp_granularities[]',
    'timestamp_granularities',
    'timestampGranularities',
  ]);
  final knownSpeakerNames = _takeStringList(config, [
    'known_speaker_names[]',
    'known_speaker_names',
    'knownSpeakerNames',
  ]);
  final knownSpeakerReferences = _takeStringList(config, [
    'known_speaker_references[]',
    'known_speaker_references',
    'knownSpeakerReferences',
  ]);
  final streamValue = _takeRawValue(config, ['stream']);
  config.remove('temperature');
  config.remove('version');
  config.remove('maxOutputTokens');
  config.remove('stopSequences');
  config.remove('topK');
  config.remove('topP');
  config.remove('maxTokens');
  config.remove('stop');
  config.remove('presencePenalty');
  config.remove('frequencyPenalty');
  config.remove('seed');
  config.remove('user');
  config.remove('jsonMode');
  config.remove('visualDetailLevel');
  config.remove('translate');

  if (temperature != null) {
    _appendField(fields, 'temperature', temperature.toString());
  }

  final responseFormat = _resolveTranscriptionResponseFormat(
    configuredResponseFormat: configuredResponseFormat,
    rawConfigResponseFormat: rawCustomResponseFormat is String
        ? rawCustomResponseFormat
        : null,
    camelConfigResponseFormat: camelResponseFormat is String
        ? camelResponseFormat
        : null,
    outputFormat: request.output?.format,
    outputContentType: request.output?.contentType,
  );
  _appendField(fields, 'response_format', responseFormat);

  if (responseFormat == 'diarized_json' && timestampGranularities.isNotEmpty) {
    throw GenkitException(
      'timestamp_granularities is not compatible with response_format diarized_json.',
    );
  }

  if (timestampGranularities.isNotEmpty && responseFormat != 'verbose_json') {
    throw GenkitException(
      'timestamp_granularities requires response_format verbose_json.',
    );
  }

  if (include.isNotEmpty && responseFormat != 'json') {
    throw GenkitException('include requires response_format json.');
  }
  for (final includeValue in include) {
    if (!_transcriptionIncludeValues.contains(includeValue)) {
      throw GenkitException('Unsupported include value: $includeValue');
    }
  }

  if (language != null) {
    _appendField(fields, 'language', language);
  }

  if (chunkingStrategy != null) {
    _appendField(
      fields,
      'chunking_strategy',
      chunkingStrategy is Map || chunkingStrategy is List
          ? jsonEncode(chunkingStrategy)
          : chunkingStrategy.toString(),
    );
  }

  _appendRepeatedFields(fields, 'include[]', include);
  _appendRepeatedFields(
    fields,
    'timestamp_granularities[]',
    timestampGranularities,
  );
  _appendRepeatedFields(fields, 'known_speaker_names[]', knownSpeakerNames);
  _appendRepeatedFields(
    fields,
    'known_speaker_references[]',
    knownSpeakerReferences,
  );

  for (final entry in config.entries) {
    _appendConfigValue(fields, entry.key, entry.value);
  }

  final stream = _parseBool(streamValue);
  if (stream == true) {
    throw GenkitException(
      'Transcription parameter stream=true is not supported by this plugin.',
    );
  }
  if (!useTranslationEndpoint) {
    _appendField(fields, 'stream', 'false');
  }
  return fields;
}

String? _extractTranscriptionPrompt(List<Message> messages) {
  if (messages.isEmpty) return null;

  final firstMessagePrompt = messages.first.text.trim();
  if (firstMessagePrompt.isNotEmpty) {
    return firstMessagePrompt;
  }

  for (final message in messages.reversed) {
    if (message.role != Role.user) continue;

    final prompt = message.text.trim();
    if (prompt.isNotEmpty) return prompt;
  }
  return null;
}

String _resolveTranscriptionResponseFormat({
  required String? configuredResponseFormat,
  required String? rawConfigResponseFormat,
  required String? camelConfigResponseFormat,
  required String? outputFormat,
  required String? outputContentType,
}) {
  final normalizedOutputFormat = normalizeOptionalString(
    outputFormat,
  )?.toLowerCase();
  if (normalizedOutputFormat == 'media') {
    throw GenkitException('Output format media is not supported.');
  }

  final customResponseFormat =
      normalizeOptionalString(configuredResponseFormat)?.toLowerCase() ??
      normalizeOptionalString(camelConfigResponseFormat)?.toLowerCase() ??
      normalizeOptionalString(rawConfigResponseFormat)?.toLowerCase();

  if (normalizedOutputFormat != null &&
      customResponseFormat != null &&
      normalizedOutputFormat == 'json' &&
      customResponseFormat != 'json' &&
      customResponseFormat != 'verbose_json') {
    throw GenkitException(
      'Custom response format $customResponseFormat is not compatible with output format $normalizedOutputFormat',
    );
  }

  if (customResponseFormat != null) {
    if (!_transcriptionResponseFormats.contains(customResponseFormat)) {
      throw GenkitException(
        'Unsupported transcription response format: $customResponseFormat',
      );
    }
    return customResponseFormat;
  }

  if (normalizedOutputFormat != null) {
    if (!_transcriptionResponseFormats.contains(normalizedOutputFormat)) {
      throw GenkitException(
        'Unsupported transcription output format: $normalizedOutputFormat',
      );
    }
    return normalizedOutputFormat;
  }

  if (outputContentType == 'application/json') {
    return 'json';
  }

  return 'text';
}

bool _shouldUseTranslationEndpoint({
  required String modelName,
  required bool? configuredTranslate,
  required Map<String, dynamic>? rawConfig,
}) {
  if (!_isWhisperModelName(modelName)) {
    return false;
  }

  if (configuredTranslate == true) {
    return true;
  }

  final rawTranslate = rawConfig?['translate'];
  if (rawTranslate is bool) {
    return rawTranslate;
  }
  if (rawTranslate is String) {
    return rawTranslate.toLowerCase() == 'true';
  }
  return false;
}

bool _isWhisperModelName(String modelName) {
  return modelName.toLowerCase().contains('whisper');
}

void _appendField(List<_MultipartField> fields, String name, String value) {
  fields.add((name: name, value: value));
}

void _appendRepeatedFields(
  List<_MultipartField> fields,
  String name,
  List<String> values,
) {
  for (final value in values) {
    _appendField(fields, name, value);
  }
}

Object? _takeRawValue(Map<String, dynamic> config, List<String> keys) {
  for (final key in keys) {
    if (config.containsKey(key)) {
      return config.remove(key);
    }
  }
  return null;
}

String? _takeOptionalString(Map<String, dynamic> config, List<String> keys) {
  return _normalizeStringValue(_takeRawValue(config, keys));
}

List<String> _takeStringList(Map<String, dynamic> config, List<String> keys) {
  final value = _takeRawValue(config, keys);
  if (value == null) return const [];

  if (value is Iterable) {
    return value
        .map(_normalizeStringValue)
        .whereType<String>()
        .toList(growable: false);
  }

  final normalized = _normalizeStringValue(value);
  if (normalized == null) return const [];
  return [normalized];
}

String? _normalizeStringValue(Object? value) {
  if (value == null) return null;
  final trimmed = value.toString().trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

void _appendConfigValue(
  List<_MultipartField> fields,
  String key,
  Object? value,
) {
  if (value == null) return;
  if (value is Iterable) {
    for (final item in value) {
      if (item == null) continue;
      _appendField(fields, key, item.toString());
    }
    return;
  }
  if (value is Map) {
    _appendField(fields, key, jsonEncode(value));
    return;
  }
  _appendField(fields, key, value.toString());
}

bool? _parseBool(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return null;
}

String? _extractTranscriptionText(Map<String, dynamic> responseBody) {
  final text = responseBody['text'];
  if (text is String && text.trim().isNotEmpty) {
    return text;
  }

  final transcript = responseBody['transcript'];
  if (transcript is String && transcript.trim().isNotEmpty) {
    return transcript;
  }

  final response = responseBody['response'];
  if (response is String && response.trim().isNotEmpty) {
    return response;
  }

  return null;
}
