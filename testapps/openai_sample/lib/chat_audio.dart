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

Media _requireMedia(GenerateResponseHelper<dynamic> response) {
  final media = response.media;
  if (media == null) throw StateError('Model returned no audio media.');
  return media;
}

/// Baseline: alloy voice, mp3 output — the simplest possible audio generation.
Flow<String, Media, void, void> defineChatAudioFlow(Genkit ai) {
  return ai.defineFlow(
    name: 'chatAudio',
    inputSchema: .string(
      defaultValue: 'Say hello from Genkit Dart using chat audio model.',
    ),
    outputSchema: Media.$schema,
    fn: (prompt, _) async {
      final response = await ai.generate(
        model: openAI.audioModel('gpt-4o-audio-preview'),
        prompt: prompt,
        config: OpenAIAudioOptions(voice: 'alloy', audioFormat: 'mp3'),
      );
      return _requireMedia(response);
    },
  );
}

/// Creative: high [temperature] + wide [topP] for expressive, varied output.
///
/// Demonstrates the sampling controls. The ballad voice suits storytelling well.
Flow<String, Media, void, void> defineChatAudioCreativeFlow(Genkit ai) {
  return ai.defineFlow(
    name: 'chatAudioCreative',
    inputSchema: .string(
      defaultValue:
          'Tell me a whimsical story about a robot learning to dance.',
    ),
    outputSchema: Media.$schema,
    fn: (prompt, _) async {
      final response = await ai.generate(
        model: openAI.audioModel('gpt-4o-audio-preview'),
        prompt: prompt,
        config: OpenAIAudioOptions(
          voice: 'ballad',
          audioFormat: 'wav',
          temperature: 1.4,
          topP: 0.95,
          maxTokens: 512,
        ),
      );
      return _requireMedia(response);
    },
  );
}

/// Multi-turn: passes prior conversation [messages] alongside the new prompt.
///
/// Also demonstrates [version] pinning (to prevent rolling-update drift) and
/// a fixed [seed] with low [temperature] for reproducible follow-up responses.
Flow<String, Media, void, void> defineChatAudioMultiTurnFlow(Genkit ai) {
  return ai.defineFlow(
    name: 'chatAudioMultiTurn',
    inputSchema: .string(
      defaultValue: 'And what is the most famous landmark there?',
    ),
    outputSchema: Media.$schema,
    fn: (followUp, _) async {
      final response = await ai.generate(
        model: openAI.audioModel('gpt-4o-audio-preview'),
        messages: [
          Message(
            role: Role.user,
            content: [TextPart(text: 'What is the capital of France?')],
          ),
          Message(
            role: Role.model,
            content: [TextPart(text: 'The capital of France is Paris.')],
          ),
        ],
        prompt: followUp,
        config: OpenAIAudioOptions(
          version: 'gpt-4o-audio-preview-2024-12-17',
          voice: 'nova',
          audioFormat: 'mp3',
          temperature: 0.2,
          seed: 42,
        ),
      );
      return _requireMedia(response);
    },
  );
}

void main() {
  final ai = Genkit(
    plugins: [openAI(apiKey: Platform.environment['OPENAI_API_KEY'])],
  );

  defineChatAudioFlow(ai);
  defineChatAudioCreativeFlow(ai);
  defineChatAudioMultiTurnFlow(ai);
}
