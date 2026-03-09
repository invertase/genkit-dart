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
import 'package:openai_dart/openai_dart.dart' as sdk;
import 'package:schemantic/schemantic.dart';

part 'stt.g.dart';

/// Model info for Whisper and transcription models.
final ModelInfo sttModelInfo = ModelInfo(
  label: 'OpenAI STT',
  supports: {
    'media': true,
    'output': ['text', 'json'],
    'multiturn': false,
    'systemRole': false,
    'tools': false,
  },
);

/// Known whisper models.
const List<String> whisperModelIds = ['whisper-1'];

/// Known GPT transcription models.
const List<String> transcriptionModelIds = [
  'gpt-4o-transcribe',
  'gpt-4o-mini-transcribe',
];

/// Options for OpenAI speech-to-text (transcription / Whisper) models.
@Schema()
abstract class $OpenAISttOptions {
  /// Model version override (e.g. 'whisper-1').
  String? get version;

  /// Sampling temperature (0.0 – 1.0).
  @DoubleField(minimum: 0.0, maximum: 1.0)
  double? get temperature;

  /// BCP-47 language code of the audio (e.g. 'en', 'fr').
  ///
  /// When provided, transcription accuracy improves.
  String? get language;

  /// Output format for the transcription result.
  ///
  /// One of: 'json', 'text', 'srt', 'verbose_json', 'vtt'.
  @StringField(enumValues: ['json', 'text', 'srt', 'verbose_json', 'vtt'])
  String? get responseFormat;

  /// Timestamp granularities to include (requires 'verbose_json' format).
  ///
  /// Each value must be one of: 'word', 'segment'.
  List<String>? get timestampGranularities;

  /// When true, translates audio to English instead of transcribing in-language.
  ///
  /// Only supported by Whisper models; ignored for gpt-4o-transcribe variants.
  bool? get translate;
}

/// Returns the [SchemanticType] for [OpenAISttOptions].
SchemanticType<OpenAISttOptions> sttModelOptionsSchema() =>
    OpenAISttOptions.$schema;

/// Parses STT model options from action config.
OpenAISttOptions parseSttModelOptions(Map<String, dynamic>? config) {
  return config != null
      ? OpenAISttOptions.$schema.parse(config)
      : OpenAISttOptions();
}

/// Builds an SDK [sdk.TranscriptionRequest] from a Genkit [ModelRequest].
sdk.TranscriptionRequest buildTranscriptionRequest({
  required String modelId,
  required ModelRequest request,
  required OpenAISttOptions options,
}) {
  final audioFile = _extractAudioFile(request);
  final granularities = _parseGranularities(options.timestampGranularities);
  final format = _parseTranscriptionFormat(options.responseFormat);
  return sdk.TranscriptionRequest(
    file: audioFile.bytes,
    filename: audioFile.filename,
    model: options.version ?? modelId,
    language: options.language,
    prompt: _extractPromptText(request),
    responseFormat: format,
    temperature: options.temperature,
    timestampGranularities: granularities.isNotEmpty ? granularities : null,
  );
}

/// Builds an SDK [sdk.TranslationRequest] from a Genkit [ModelRequest].
///
/// Used when `translate: true` is set on a Whisper model.
sdk.TranslationRequest buildTranslationRequest({
  required String modelId,
  required ModelRequest request,
  required OpenAISttOptions options,
}) {
  final audioFile = _extractAudioFile(request);
  final format = _parseTranscriptionFormat(options.responseFormat);
  return sdk.TranslationRequest(
    file: audioFile.bytes,
    filename: audioFile.filename,
    model: options.version ?? modelId,
    prompt: _extractPromptText(request),
    responseFormat: format,
    temperature: options.temperature,
  );
}

/// Converts a transcription/translation text result to a [ModelResponse].
ModelResponse transcriptionToModelResponse(
  String text, {
  Map<String, dynamic>? raw,
}) {
  return ModelResponse(
    finishReason: FinishReason.stop,
    message: Message(
      role: Role.model,
      content: [TextPart(text: text)],
    ),
    raw: raw ?? {'text': text},
  );
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

class _AudioFile {
  const _AudioFile({required this.bytes, required this.filename});
  final Uint8List bytes;
  final String filename;
}

_AudioFile _extractAudioFile(ModelRequest request) {
  if (request.messages.isEmpty) {
    throw GenkitException(
      'STT request must contain at least one message with a media part.',
      status: StatusCodes.INVALID_ARGUMENT,
    );
  }

  for (final message in request.messages) {
    for (final part in message.content) {
      if (part.isMedia) {
        final media = part.media;
        if (media != null) {
          return _mediaToFile(media);
        }
      }
    }
  }

  throw GenkitException(
    'No audio media part found in the request messages.',
    status: StatusCodes.INVALID_ARGUMENT,
  );
}

_AudioFile _mediaToFile(Media media) {
  final contentType = media.contentType ?? _contentTypeFromDataUrl(media.url);
  if (contentType == null || contentType.isEmpty) {
    throw GenkitException(
      'Media part is missing a content type.',
      status: StatusCodes.INVALID_ARGUMENT,
    );
  }
  final ext = _extensionFromContentType(contentType);
  final bytes = _bytesFromDataUrl(media.url);
  return _AudioFile(filename: 'input.$ext', bytes: Uint8List.fromList(bytes));
}

String? _contentTypeFromDataUrl(String url) {
  if (!url.startsWith('data:')) return null;
  final semi = url.indexOf(';');
  if (semi <= 'data:'.length) return null;
  return url.substring('data:'.length, semi);
}

List<int> _bytesFromDataUrl(String dataUrl) {
  final marker = dataUrl.indexOf(',');
  final body = marker >= 0 ? dataUrl.substring(marker + 1) : dataUrl;
  return base64Decode(body);
}

String _extensionFromContentType(String contentType) {
  return switch (contentType) {
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/mp4' => 'mp4',
    'audio/ogg' => 'ogg',
    'audio/wav' || 'audio/x-wav' => 'wav',
    'audio/webm' => 'webm',
    'audio/flac' => 'flac',
    'audio/m4a' || 'audio/x-m4a' => 'm4a',
    _ => 'mp3',
  };
}

String? _extractPromptText(ModelRequest request) {
  for (final message in request.messages) {
    for (final part in message.content) {
      final text = part.text;
      if (text != null && text.isNotEmpty) return text;
    }
  }
  return null;
}

sdk.TranscriptionResponseFormat? _parseTranscriptionFormat(String? value) {
  if (value == null) return null;
  try {
    return sdk.TranscriptionResponseFormat.fromJson(value);
  } catch (_) {
    return null;
  }
}

List<sdk.TimestampGranularity> _parseGranularities(List<String>? values) {
  if (values == null || values.isEmpty) return const [];
  final result = <sdk.TimestampGranularity>[];
  for (final v in values) {
    try {
      result.add(sdk.TimestampGranularity.fromJson(v));
    } catch (_) {
      // Skip unknown values.
    }
  }
  return result;
}
