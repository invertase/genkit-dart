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

import 'package:genkit/plugin.dart';

import 'src/models.dart' show CustomModelDefinition, OpenAIOptions;
import 'src/openai_plugin.dart';
import 'src/transcriptions.dart' show OpenAITranscriptionOptions;

export 'src/converters.dart' show GenkitConverter;
export 'src/models.dart'
    show
        CustomModelDefinition,
        OpenAIOptions,
        defaultModelInfo,
        oSeriesModelInfo,
        supportsTools,
        supportsVision;
export 'src/transcriptions.dart'
    show
        OpenAITranscriptionOptions,
        isTranscriptionModel,
        transcriptionModelInfo;

/// Public constant handle for OpenAI-compatible plugin
const OpenAICompatPluginHandle openAI = OpenAICompatPluginHandle();

/// Handle class for OpenAI-compatible plugin
class OpenAICompatPluginHandle {
  const OpenAICompatPluginHandle();

  /// Create the plugin instance
  GenkitPlugin call({
    String? apiKey,
    String? baseUrl,
    List<CustomModelDefinition>? models,
    Map<String, String>? headers,
  }) {
    return OpenAIPlugin(
      apiKey: apiKey,
      baseUrl: baseUrl,
      customModels: models ?? const [],
      headers: headers,
    );
  }

  /// Reference to a model
  ModelRef<OpenAIOptions> model(String name) {
    return modelRef('openai/$name', customOptions: OpenAIOptions.$schema);
  }

  /// Reference to a transcription model with transcription-specific options
  ModelRef<OpenAITranscriptionOptions> transcribe(String name) {
    return modelRef(
      'openai/$name',
      customOptions: OpenAITranscriptionOptions.$schema,
    );
  }
}
