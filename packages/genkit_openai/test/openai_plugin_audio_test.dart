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

import 'package:genkit_openai/genkit_openai.dart';
import 'package:test/test.dart';

void main() {
  group('isAudioModel', () {
    test('recognises known audio chat models', () {
      expect(isAudioModel('gpt-4o-audio-preview'), isTrue);
      expect(isAudioModel('gpt-4o-audio-preview-2024-12-17'), isTrue);
      expect(isAudioModel('gpt-4o-audio-preview-2024-10-01'), isTrue);
    });

    test('returns false for non-audio models', () {
      expect(isAudioModel('gpt-4o'), isFalse);
      expect(isAudioModel('gpt-4o-mini'), isFalse);
      expect(isAudioModel('o3'), isFalse);
    });
  });

  group('OpenAIAudioOptions', () {
    test('creates with all fields null by default', () {
      final opts = OpenAIAudioOptions();
      expect(opts.version, isNull);
      expect(opts.temperature, isNull);
      expect(opts.topP, isNull);
      expect(opts.maxTokens, isNull);
      expect(opts.seed, isNull);
      expect(opts.user, isNull);
      expect(opts.voice, isNull);
      expect(opts.audioFormat, isNull);
    });

    test('parses voice and audioFormat', () {
      final opts = OpenAIAudioOptions.$schema.parse({
        'voice': 'nova',
        'audioFormat': 'wav',
      });
      expect(opts.voice, 'nova');
      expect(opts.audioFormat, 'wav');
    });

    test('parses standard chat fields', () {
      final opts = OpenAIAudioOptions.$schema.parse({
        'temperature': 0.7,
        'maxTokens': 256,
        'seed': 42,
      });
      expect(opts.temperature, 0.7);
      expect(opts.maxTokens, 256);
      expect(opts.seed, 42);
    });

    test('parses version override', () {
      final opts = OpenAIAudioOptions.$schema.parse({
        'version': 'gpt-4o-audio-preview-2024-12-17',
      });
      expect(opts.version, 'gpt-4o-audio-preview-2024-12-17');
    });
  });

  group('AudioOptions typedef', () {
    test('AudioOptions is an alias for OpenAIAudioOptions', () {
      final opts = AudioOptions();
      expect(opts, isA<OpenAIAudioOptions>());
    });
  });

  group('OpenAICompatPluginHandle.audioModel', () {
    test('returns ref with prefixed name', () {
      final ref = openAI.audioModel('gpt-4o-audio-preview');
      expect(ref.name, 'openai/gpt-4o-audio-preview');
    });

    test('ref carries OpenAIAudioOptions schema', () {
      final ref = openAI.audioModel('gpt-4o-audio-preview');
      expect(ref.customOptions, isNotNull);
    });
  });

  group('getModelType for audio models', () {
    test('gpt-4o-audio-preview is classified as audio', () {
      expect(getModelType('gpt-4o-audio-preview'), 'audio');
    });

    test('gpt-4o is classified as chat (not audio)', () {
      expect(getModelType('gpt-4o'), 'chat');
    });
  });

  group('Plugin', () {
    test('creates plugin instance', () {
      final plugin = openAI(apiKey: 'test-key');
      expect(plugin, isNotNull);
    });
  });
}
