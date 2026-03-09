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

/// TTS (text-to-speech) support.
///
/// Speech synthesis is performed via [sdk.OpenAIClient.audio.speech.create].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:genkit/plugin.dart';
import 'package:openai_dart/openai_dart.dart' as sdk;
import 'package:schemantic/schemantic.dart';

part 'tts.g.dart';

/// Options for OpenAI TTS models (`tts-1`, `tts-1-hd`, `gpt-4o-mini-tts`).
///
/// Note: [speed] is ignored by `gpt-4o-mini-tts`, which does not support it.
@Schema()
abstract class $OpenAITtsOptions {
  /// Model version override (e.g. `tts-1-hd`).
  String? get version;

  /// Voice to use for speech synthesis.
  @StringField(
    enumValues: ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'],
  )
  String? get voice;

  /// Speaking speed multiplier (0.25 – 4.0). Not supported by gpt-4o-mini-tts.
  @DoubleField(minimum: 0.25, maximum: 4.0)
  double? get speed;

  /// Audio encoding format for the response.
  @StringField(enumValues: ['mp3', 'opus', 'aac', 'flac', 'wav', 'pcm'])
  String? get responseFormat;
}

/// Maps OpenAI TTS response format strings to their MIME types.
const Map<String, String> audioMimeTypes = {
  'mp3': 'audio/mpeg',
  'opus': 'audio/opus',
  'aac': 'audio/aac',
  'flac': 'audio/flac',
  'wav': 'audio/wav',
  'pcm': 'audio/L16',
};

/// TTS model IDs supported by the plugin.
const List<String> supportedTtsModels = [
  'tts-1',
  'tts-1-hd',
  'gpt-4o-mini-tts',
];

/// Returns a [ModelInfo] for a TTS (speech output) model.
ModelInfo ttsModelInfo(String label) => ModelInfo(
  label: label,
  supports: {
    'media': false,
    'output': ['media'],
    'multiturn': false,
    'systemRole': false,
    'tools': false,
  },
);

/// Returns the [SchemanticType] for TTS model options.
SchemanticType<OpenAITtsOptions> ttsOptionsSchema() => OpenAITtsOptions.$schema;

/// Parses TTS model options from an action config map.
OpenAITtsOptions parseTtsOptions(Map<String, dynamic>? config) {
  return config != null
      ? OpenAITtsOptions.$schema.parse(config)
      : OpenAITtsOptions();
}

/// Returns a [ModelRef] for the named TTS model under the `openai` namespace.
ModelRef<OpenAITtsOptions> ttsModelRef(String name) =>
    modelRef<OpenAITtsOptions>(
      'openai/$name',
      customOptions: OpenAITtsOptions.$schema,
    );

/// Converts TTS audio [audioBytes] to a [ModelResponse] with a base64 data-URI
/// media part whose MIME type is derived from [responseFormat].
ModelResponse speechToModelResponse(
  Uint8List audioBytes,
  String responseFormat,
  Map<String, dynamic> raw,
) {
  final mimeType = audioMimeTypes[responseFormat] ?? audioMimeTypes['mp3']!;
  return ModelResponse(
    finishReason: FinishReason.stop,
    message: Message(
      role: Role.model,
      content: [
        MediaPart(
          media: Media(
            contentType: mimeType,
            url: 'data:$mimeType;base64,${base64Encode(audioBytes)}',
          ),
        ),
      ],
    ),
    raw: raw,
  );
}

/// Parses [voice] into a [sdk.SpeechVoice], defaulting to `alloy` on failure.
sdk.SpeechVoice parseSpeechVoice(String? voice) {
  if (voice == null) return sdk.SpeechVoice.alloy;
  try {
    return sdk.SpeechVoice.fromJson(voice);
  } catch (_) {
    return sdk.SpeechVoice.alloy;
  }
}

/// Parses [format] into a [sdk.SpeechResponseFormat], defaulting to `mp3`.
sdk.SpeechResponseFormat parseSpeechResponseFormat(String? format) {
  if (format == null) return sdk.SpeechResponseFormat.mp3;
  try {
    return sdk.SpeechResponseFormat.fromJson(format);
  } catch (_) {
    return sdk.SpeechResponseFormat.mp3;
  }
}
