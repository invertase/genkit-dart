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

import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_openai/genkit_openai.dart';

/// Defines a flow using the defaults
Flow<String, Media, void, void> defineDefaultTextToSpeechFlow(Genkit ai) {
  return ai.defineFlow(
    name: 'defaultTextToSpeech',
    inputSchema: .string(
      defaultValue: 'Genkit Dart supports OpenAI text to speech.',
    ),
    outputSchema: Media.$schema,
    fn: (prompt, _) async {
      final response = await ai.generate(
        model: openAI.speech('gpt-4o-mini-tts'),
        prompt: prompt,
        config: OpenAITtsOptions(),
      );

      final media = response.media;
      if (media == null) throw StateError('Model returned no audio media.');
      return media;
    },
  );
}

/// Demonstrates the [OpenAITtsOptions] fields on the `tts-1-hd` model.
Flow<String, Media, void, void> defineCustomTextToSpeechFlow(Genkit ai) {
  return ai.defineFlow(
    name: 'customTextToSpeech',
    inputSchema: .string(
      defaultValue: 'Genkit Dart supports high-quality speech synthesis.',
    ),
    outputSchema: Media.$schema,
    fn: (prompt, _) async {
      final response = await ai.generate(
        model: openAI.speech('tts-1-hd'),
        prompt: prompt,
        config: OpenAITtsOptions(
          voice: 'nova',
          speed: 1.25,
          responseFormat: 'wav',
        ),
      );

      final media = response.media;
      if (media == null) throw StateError('Model returned no audio media.');
      return media;
    },
  );
}

/// Shows supported voices on the `tts-1` model by defining one flow per voice.
List<Flow<String, Media, void, void>> defineVoiceShowcaseFlows(Genkit ai) {
  const voices = ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'];

  return [
    for (final voice in voices)
      ai.defineFlow(
        name: 'tts_$voice',
        inputSchema: .string(defaultValue: 'Hello, I am the $voice voice.'),
        outputSchema: Media.$schema,
        fn: (prompt, _) async {
          final response = await ai.generate(
            model: openAI.speech('tts-1'),
            prompt: prompt,
            config: OpenAITtsOptions(voice: voice, responseFormat: 'mp3'),
          );

          final media = response.media;
          if (media == null) throw StateError('Model returned no audio media.');
          return media;
        },
      ),
  ];
}

/// Shows supported `responseFormat` values on the `tts-1` model.
List<Flow<String, Media, void, void>> defineFormatShowcaseFlows(Genkit ai) {
  const formats = ['mp3', 'opus', 'aac', 'flac', 'wav', 'pcm'];

  return [
    for (final format in formats)
      ai.defineFlow(
        name: 'tts_format_$format',
        inputSchema: .string(
          defaultValue: 'This sample is encoded as $format.',
        ),
        outputSchema: Media.$schema,
        fn: (prompt, _) async {
          final response = await ai.generate(
            model: openAI.speech('tts-1'),
            prompt: prompt,
            config: OpenAITtsOptions(voice: 'alloy', responseFormat: format),
          );

          final media = response.media;
          if (media == null) throw StateError('Model returned no audio media.');
          return media;
        },
      ),
  ];
}

void main() {
  final ai = Genkit(
    plugins: [openAI(apiKey: Platform.environment['OPENAI_API_KEY'])],
  );

  defineDefaultTextToSpeechFlow(ai);
  defineCustomTextToSpeechFlow(ai);
  defineVoiceShowcaseFlows(ai);
  defineFormatShowcaseFlows(ai);
}
