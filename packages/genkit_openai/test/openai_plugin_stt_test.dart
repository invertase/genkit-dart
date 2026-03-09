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

import 'dart:convert';

import 'package:genkit/genkit.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:openai_dart/openai_dart.dart' as sdk;
import 'package:test/test.dart';

void main() {
  group('OpenAISttOptions', () {
    test('creates default options with all nulls', () {
      final opts = OpenAISttOptions();
      expect(opts.version, isNull);
      expect(opts.temperature, isNull);
      expect(opts.language, isNull);
      expect(opts.responseFormat, isNull);
      expect(opts.timestampGranularities, isNull);
      expect(opts.translate, isNull);
    });

    test('parses temperature from config', () {
      final opts = parseSttModelOptions({'temperature': 0.5});
      expect(opts.temperature, 0.5);
    });

    test('parses language from config', () {
      final opts = parseSttModelOptions({'language': 'fr'});
      expect(opts.language, 'fr');
    });

    test('parses responseFormat from config', () {
      final opts = parseSttModelOptions({'responseFormat': 'verbose_json'});
      expect(opts.responseFormat, 'verbose_json');
    });

    test('parses timestampGranularities from config', () {
      final opts = parseSttModelOptions({
        'timestampGranularities': ['word', 'segment'],
      });
      expect(opts.timestampGranularities, ['word', 'segment']);
    });

    test('parses translate flag from config', () {
      final opts = parseSttModelOptions({'translate': true});
      expect(opts.translate, isTrue);
    });

    test('returns default options for null config', () {
      final opts = parseSttModelOptions(null);
      expect(opts.temperature, isNull);
      expect(opts.translate, isNull);
    });
  });

  group('buildTranscriptionRequest', () {
    test('builds request from model request with media part', () {
      final wavBytes = _fakeAudioBase64('audio/wav');
      final request = ModelRequest(
        messages: [
          Message(
            role: Role.user,
            content: [
              MediaPart(
                media: Media(
                  url: 'data:audio/wav;base64,$wavBytes',
                  contentType: 'audio/wav',
                ),
              ),
            ],
          ),
        ],
      );
      final opts = OpenAISttOptions(temperature: 0.3, language: 'en');

      final transcriptionReq = buildTranscriptionRequest(
        modelId: 'whisper-1',
        request: request,
        options: opts,
      );

      expect(transcriptionReq.model, 'whisper-1');
      expect(transcriptionReq.filename, 'input.wav');
      expect(transcriptionReq.temperature, 0.3);
      expect(transcriptionReq.language, 'en');
      expect(transcriptionReq.file, isNotEmpty);
    });

    test('uses version override when provided', () {
      final request = _minimalAudioRequest();
      final opts = OpenAISttOptions(version: 'whisper-1');

      final req = buildTranscriptionRequest(
        modelId: 'whisper-1',
        request: request,
        options: opts,
      );

      expect(req.model, 'whisper-1');
    });

    test('includes prompt text from message', () {
      final mp3Bytes = _fakeAudioBase64('audio/mpeg');
      final request = ModelRequest(
        messages: [
          Message(
            role: Role.user,
            content: [
              TextPart(text: 'please transcribe carefully'),
              MediaPart(
                media: Media(
                  url: 'data:audio/mpeg;base64,$mp3Bytes',
                  contentType: 'audio/mpeg',
                ),
              ),
            ],
          ),
        ],
      );

      final req = buildTranscriptionRequest(
        modelId: 'whisper-1',
        request: request,
        options: OpenAISttOptions(),
      );

      expect(req.prompt, 'please transcribe carefully');
    });

    test('maps responseFormat to SDK enum', () {
      final request = _minimalAudioRequest();
      final opts = OpenAISttOptions(responseFormat: 'srt');

      final req = buildTranscriptionRequest(
        modelId: 'whisper-1',
        request: request,
        options: opts,
      );

      expect(req.responseFormat, sdk.TranscriptionResponseFormat.srt);
    });

    test('includes timestamp granularities', () {
      final request = _minimalAudioRequest();
      final opts = OpenAISttOptions(
        responseFormat: 'verbose_json',
        timestampGranularities: ['word'],
      );

      final req = buildTranscriptionRequest(
        modelId: 'whisper-1',
        request: request,
        options: opts,
      );

      expect(
        req.timestampGranularities,
        contains(sdk.TimestampGranularity.word),
      );
    });

    test('throws when no media part found', () {
      final request = ModelRequest(
        messages: [
          Message(
            role: Role.user,
            content: [TextPart(text: 'hello')],
          ),
        ],
      );

      expect(
        () => buildTranscriptionRequest(
          modelId: 'whisper-1',
          request: request,
          options: OpenAISttOptions(),
        ),
        throwsA(isA<GenkitException>()),
      );
    });
  });

  group('buildTranslationRequest', () {
    test('builds translation request with correct model', () {
      final request = _minimalAudioRequest();
      final opts = OpenAISttOptions(temperature: 0.2);

      final req = buildTranslationRequest(
        modelId: 'whisper-1',
        request: request,
        options: opts,
      );

      expect(req.model, 'whisper-1');
      expect(req.temperature, 0.2);
      expect(req.file, isNotEmpty);
    });
  });

  group('transcriptionToModelResponse', () {
    test('creates ModelResponse with transcribed text', () {
      final response = transcriptionToModelResponse('Hello world');

      expect(response.finishReason, FinishReason.stop);
      expect(response.message?.role, Role.model);
      expect(response.message?.text, 'Hello world');
    });

    test('includes raw map in response', () {
      final raw = {'text': 'Hi', 'language': 'en'};
      final response = transcriptionToModelResponse('Hi', raw: raw);

      expect(response.raw, raw);
    });
  });

  group('sttModelInfo', () {
    test('reports correct capabilities', () {
      expect(sttModelInfo.supports?['media'], isTrue);
      expect(sttModelInfo.supports?['multiturn'], isFalse);
      expect(sttModelInfo.supports?['tools'], isFalse);
      expect(sttModelInfo.supports?['systemRole'], isFalse);
    });
  });

  group('OpenAICompatPluginHandle.stt', () {
    test('creates ref for a Whisper model', () {
      final ref = openAI.stt('whisper-1');
      expect(ref.name, 'openai/whisper-1');
    });

    test('creates ref for a GPT transcription model', () {
      final ref = openAI.stt('gpt-4o-transcribe');
      expect(ref.name, 'openai/gpt-4o-transcribe');
    });

    test('carries config', () {
      final config = OpenAISttOptions(language: 'de');
      final ref = openAI.stt('whisper-1', config: config);
      expect(ref.config?.language, 'de');
    });
  });

  group('STT model ID constants', () {
    test('whisperModelIds contains whisper-1', () {
      expect(whisperModelIds, contains('whisper-1'));
    });

    test('transcriptionModelIds contains gpt-4o-transcribe', () {
      expect(transcriptionModelIds, contains('gpt-4o-transcribe'));
      expect(transcriptionModelIds, contains('gpt-4o-mini-transcribe'));
    });
  });
}

ModelRequest _minimalAudioRequest() {
  final bytes = _fakeAudioBase64('audio/wav');
  return ModelRequest(
    messages: [
      Message(
        role: Role.user,
        content: [
          MediaPart(
            media: Media(
              url: 'data:audio/wav;base64,$bytes',
              contentType: 'audio/wav',
            ),
          ),
        ],
      ),
    ],
  );
}

/// Returns a base64-encoded stub audio payload for the given [contentType].
String _fakeAudioBase64(String contentType) {
  final stub = utf8.encode('fake-audio-data');
  return base64Encode(stub);
}
