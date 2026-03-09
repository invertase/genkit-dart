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

import 'dart:async';

import 'package:genkit/plugin.dart';

import 'src/chat.dart' as chat_lib;
import 'src/openai_plugin.dart';
import 'src/stt.dart' as stt_lib;

export 'src/chat.dart' show OpenAIChatOptions, OpenAIOptions;
export 'src/converters.dart' show GenkitConverter;
export 'src/stt.dart'
    show
        OpenAISttOptions,
        buildTranscriptionRequest,
        buildTranslationRequest,
        parseSttModelOptions,
        sttModelInfo,
        sttModelOptionsSchema,
        transcriptionModelIds,
        transcriptionToModelResponse,
        whisperModelIds;
export 'src/utils.dart'
    show
        defaultModelInfo,
        getModelType,
        modelInfoFor,
        oSeriesModelInfo,
        supportsTools,
        supportsVision;

/// Custom model definition for registering models from compatible providers
class CustomModelDefinition {
  final String name;
  final ModelInfo? info;

  const CustomModelDefinition({required this.name, this.info});
}

/// Signature used to provide an API key (or bearer token) for requests.
typedef OpenAIApiKeyProvider = FutureOr<String> Function();

/// Public constant handle for OpenAI-compatible plugin
const OpenAICompatPluginHandle openAI = OpenAICompatPluginHandle();

/// Handle class for OpenAI-compatible plugin
class OpenAICompatPluginHandle {
  const OpenAICompatPluginHandle();

  /// Create the plugin instance
  GenkitPlugin call({
    String? apiKey,
    OpenAIApiKeyProvider? apiKeyProvider,
    String? baseUrl,
    List<CustomModelDefinition>? models,
    Map<String, String>? headers,
  }) {
    return OpenAIPlugin(
      apiKey: apiKey,
      apiKeyProvider: apiKeyProvider,
      baseUrl: baseUrl,
      customModels: models ?? const [],
      headers: headers,
    );
  }

  /// Reference to a chat model.
  ModelRef<chat_lib.OpenAIChatOptions> model(String name) {
    return modelRef(
      'openai/$name',
      customOptions: chat_lib.chatModelOptionsSchema(),
    );
  }

  /// Reference to a speech-to-text model.
  ///
  /// Works with both Whisper models (e.g. `'whisper-1'`) and GPT transcription
  /// models (e.g. `'gpt-4o-transcribe'`, `'gpt-4o-mini-transcribe'`).
  ModelRef<stt_lib.OpenAISttOptions> stt(
    String name, {
    stt_lib.OpenAISttOptions? config,
  }) {
    return modelRef(
      'openai/$name',
      customOptions: stt_lib.sttModelOptionsSchema(),
      config: config,
    );
  }
}
