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
import 'package:schemantic/schemantic.dart';

part 'transcriptions.g.dart';

typedef Schema = $Schema;

@Schematic()
abstract class $OpenAITranscriptionOptions {
  /// Transcription temperature (0.0 - 1.0)
  @DoubleField(minimum: 0.0, maximum: 1.0)
  double? get temperature;

  /// Transcription response format.
  ///
  /// `diarized_json` is accepted as a compatibility alias and sent to the
  /// OpenAI API as `verbose_json`.
  @StringField(
    enumValues: ['json', 'text', 'srt', 'verbose_json', 'vtt', 'diarized_json'],
  )
  String? get responseFormat;

  /// Whisper-only flag to use the translation endpoint.
  bool? get translate;
}

/// Model info for transcription models (Whisper and GPT transcribe models).
ModelInfo transcriptionModelInfo(String model) {
  return ModelInfo(
    label: model,
    supports: {
      'multiturn': false,
      'tools': false,
      'systemRole': false,
      'media': true,
      'output': ['text', 'json'],
    },
  );
}

/// Check if a model is a transcription model (Whisper/GPT transcribe).
bool isTranscriptionModel(String model) {
  final id = model.toLowerCase();
  return id.contains('whisper') || id.contains('transcribe');
}
