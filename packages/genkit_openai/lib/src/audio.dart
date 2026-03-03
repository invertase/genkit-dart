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
import 'package:openai_dart/openai_dart.dart';

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

/// Resolves and normalizes OpenAI chat completion modalities.
///
/// OpenAI currently accepts only:
/// - `['text']`
/// - `['text', 'audio']`
///
/// If audio is requested, this function always includes `text`.
List<ChatCompletionModality>? resolveOpenAIModalities({
  required String modelType,
  required List<String>? configured,
}) {
  final requested = configured ?? (modelType == 'audio' ? ['audio'] : null);
  if (requested == null || requested.isEmpty) {
    return null;
  }

  final parsed = <ChatCompletionModality>{};
  for (final modality in requested) {
    parsed.add(_parseOpenAIModality(modality));
  }

  if (parsed.contains(ChatCompletionModality.audio)) {
    return [ChatCompletionModality.text, ChatCompletionModality.audio];
  }

  return [ChatCompletionModality.text];
}

/// Builds audio options for chat completions when audio modality is enabled.
ChatCompletionAudioOptions? resolveOpenAIAudioOptions(
  List<ChatCompletionModality>? modalities, {
  String? voice,
  String? format,
}) {
  if (modalities == null ||
      !modalities.contains(ChatCompletionModality.audio)) {
    return null;
  }

  return ChatCompletionAudioOptions(
    voice: ChatCompletionAudioVoice.values.byName(voice ?? 'alloy'),
    format: ChatCompletionAudioFormat.values.byName(format ?? 'mp3'),
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
