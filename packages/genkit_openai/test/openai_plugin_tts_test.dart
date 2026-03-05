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
  group('isSpeechSynthesisModel', () {
    test('returns true for non-chat TTS models', () {
      expect(isSpeechSynthesisModel('gpt-4o-mini-tts'), true);
      expect(isSpeechSynthesisModel('tts-1'), true);
    });

    test('returns false for chat and chat-audio models', () {
      expect(isSpeechSynthesisModel('gpt-4o'), false);
      expect(isSpeechSynthesisModel('gpt-4o-audio-preview'), false);
    });
  });

  group('Model Info Helpers (tts)', () {
    test('ttsModelInfo sets correct supports', () {
      final info = ttsModelInfo('gpt-4o-mini-tts');
      expect(info.supports?['multiturn'], false);
      expect(info.supports?['tools'], false);
      expect(info.supports?['systemRole'], false);
      expect(info.supports?['media'], false);
    });
  });

  group('getModelType (tts)', () {
    test('classifies tts models', () {
      expect(getModelType('gpt-4o-mini-tts'), 'tts');
    });
  });

  group('Plugin Handle (tts)', () {
    test('tts model reference includes voice/format but hides modalities', () {
      final schema = openAI
          .model('gpt-4o-mini-tts')
          .customOptions!
          .jsonSchema();
      final properties = schema['properties'] as Map<String, dynamic>;

      expect(properties.containsKey('responseModalities'), false);
      expect(properties.containsKey('audioVoice'), true);
      expect(properties.containsKey('audioFormat'), true);
    });
  });
}
