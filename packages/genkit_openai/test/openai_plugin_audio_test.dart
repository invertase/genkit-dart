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
import 'package:genkit_openai/genkit_openai.dart';
import 'package:openai_dart/openai_dart.dart'
    show
        ChatCompletionAssistantMessage,
        ChatCompletionAssistantMessageAudio,
        ChatCompletionAudioFormat,
        ChatCompletionMessage,
        ChatCompletionModality;
import 'package:test/test.dart';

void main() {
  group('OpenAIOptions (audio)', () {
    test('parses audio response options', () {
      final options = OpenAIOptions.$schema.parse({
        'responseModalities': ['audio'],
        'audioVoice': 'alloy',
        'audioFormat': 'mp3',
      });

      expect(options.responseModalities, ['audio']);
      expect(options.audioVoice, 'alloy');
      expect(options.audioFormat, 'mp3');
    });
  });

  group('resolveOpenAIModalities (audio)', () {
    test('returns null when not configured', () {
      expect(
        resolveOpenAIModalities(modelType: 'audio', configured: null),
        isNull,
      );
    });

    test('keeps configured audio-only modality', () {
      expect(
        resolveOpenAIModalities(modelType: 'chat', configured: ['audio']),
        [ChatCompletionModality.audio],
      );
    });
  });

  group('GenkitConverter.fromOpenAIAssistantMessage (audio)', () {
    test('converts audio payload to media part', () {
      final msg =
          ChatCompletionMessage.assistant(
                audio: ChatCompletionAssistantMessageAudio(
                  id: 'audio_123',
                  expiresAt: 1730000000,
                  data: 'QUJD',
                  transcript: 'hello',
                ),
              )
              as ChatCompletionAssistantMessage;

      final result = GenkitConverter.fromOpenAIAssistantMessage(
        msg,
        audioFormat: ChatCompletionAudioFormat.mp3,
      );

      expect(result.content.length, 1);
      final firstPart = result.content.first;
      expect(firstPart.isMedia, true);
      final media = firstPart.media!;
      final audioMetadata =
          firstPart.metadata?['audio'] as Map<String, dynamic>?;
      expect(media.contentType, 'audio/mpeg');
      expect(media.url, 'data:audio/mpeg;base64,QUJD');
      expect(audioMetadata?['transcript'], 'hello');
    });
  });

  group('Model Info Helpers (audio)', () {
    test('audioModelInfo sets correct supports', () {
      final info = audioModelInfo('gpt-4o-audio-preview');
      expect(info.supports?['multiturn'], true);
      expect(info.supports?['tools'], true);
      expect(info.supports?['systemRole'], true);
      expect(info.supports?['media'], true);
    });
  });

  group('getModelType (audio)', () {
    test('classifies audio and stt models', () {
      expect(getModelType('gpt-4o-audio-preview'), 'audio');
      expect(getModelType('whisper-1'), 'stt');
    });
  });

  group('Plugin Handle (audio)', () {
    test('audio model reference includes audio custom options', () {
      final schema = openAI
          .model('gpt-4o-audio-preview')
          .customOptions!
          .jsonSchema();
      final properties = schema['properties'] as Map<String, dynamic>;

      expect(properties.containsKey('responseModalities'), true);
      expect(properties.containsKey('audioVoice'), true);
      expect(properties.containsKey('audioFormat'), true);
    });
  });
}
