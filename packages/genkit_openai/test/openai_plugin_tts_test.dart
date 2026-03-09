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
import 'dart:typed_data';

import 'package:genkit/plugin.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:genkit_openai/src/tts.dart' as tts;
import 'package:openai_dart/openai_dart.dart' as sdk;
import 'package:test/test.dart';

void main() {
  group('supportedTtsModels', () {
    test('contains all expected model IDs', () {
      expect(
        supportedTtsModels,
        containsAll(['tts-1', 'tts-1-hd', 'gpt-4o-mini-tts']),
      );
    });
  });

  group('OpenAITtsOptions', () {
    test('default constructor produces empty options', () {
      final opts = OpenAITtsOptions();
      expect(opts.voice, isNull);
      expect(opts.speed, isNull);
      expect(opts.responseFormat, isNull);
      expect(opts.version, isNull);
    });

    test('named constructor round-trips via toJson / fromJson', () {
      final opts = OpenAITtsOptions(
        voice: 'nova',
        speed: 1.5,
        responseFormat: 'wav',
        version: 'tts-1-hd',
      );
      final json = opts.toJson();
      final parsed = OpenAITtsOptions.fromJson(json);

      expect(parsed.voice, 'nova');
      expect(parsed.speed, 1.5);
      expect(parsed.responseFormat, 'wav');
      expect(parsed.version, 'tts-1-hd');
    });

    test('schema exposes voice enum values', () {
      final props =
          OpenAITtsOptions.$schema.jsonSchema()['properties']
              as Map<String, Object?>;
      final voiceProp = props['voice'] as Map<String, Object?>;
      expect(
        voiceProp['enum'],
        containsAll(['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer']),
      );
    });

    test('schema exposes responseFormat enum values', () {
      final props =
          OpenAITtsOptions.$schema.jsonSchema()['properties']
              as Map<String, Object?>;
      final fmtProp = props['responseFormat'] as Map<String, Object?>;
      expect(
        fmtProp['enum'],
        containsAll(['mp3', 'opus', 'aac', 'flac', 'wav', 'pcm']),
      );
    });

    test('schema exposes speed with min/max constraints', () {
      final props =
          OpenAITtsOptions.$schema.jsonSchema()['properties']
              as Map<String, Object?>;
      final speedProp = props['speed'] as Map<String, Object?>;
      expect(speedProp['minimum'], 0.25);
      expect(speedProp['maximum'], 4.0);
    });
  });

  group('parseTtsOptions', () {
    test('parses a populated config map', () {
      final opts = parseTtsOptions({
        'voice': 'shimmer',
        'speed': 0.8,
        'responseFormat': 'opus',
        'version': 'tts-1',
      });
      expect(opts.voice, 'shimmer');
      expect(opts.speed, 0.8);
      expect(opts.responseFormat, 'opus');
      expect(opts.version, 'tts-1');
    });

    test('returns defaults for null config', () {
      final opts = parseTtsOptions(null);
      expect(opts.voice, isNull);
      expect(opts.speed, isNull);
    });
  });

  group('ttsModelInfo', () {
    test('reports media output and no media input', () {
      final info = ttsModelInfo('tts-1');
      expect(info.label, 'tts-1');
      expect(info.supports?['output'], contains('media'));
      expect(info.supports?['media'], isFalse);
      expect(info.supports?['multiturn'], isFalse);
      expect(info.supports?['tools'], isFalse);
    });
  });

  group('ttsModelRef', () {
    test('produces a ref under the openai namespace', () {
      expect(ttsModelRef('tts-1').name, 'openai/tts-1');
    });

    test('customOptions is the OpenAITtsOptions schema', () {
      final ref = ttsModelRef('tts-1');
      expect(ref.customOptions, same(OpenAITtsOptions.$schema));
    });
  });

  group('openAI handle', () {
    test('speech() returns a TTS ModelRef', () {
      final ref = openAI.speech('tts-1');
      expect(ref.name, 'openai/tts-1');
    });

    test('speech() ModelRef uses OpenAITtsOptions schema', () {
      final ref = openAI.speech('tts-1-hd');
      expect(ref.customOptions, same(OpenAITtsOptions.$schema));
    });
  });

  group('parseSpeechVoice', () {
    test('parses all valid OpenAI voices', () {
      for (final voice in [
        'alloy',
        'echo',
        'fable',
        'onyx',
        'nova',
        'shimmer',
      ]) {
        expect(
          tts.parseSpeechVoice(voice).toJson(),
          voice,
          reason: 'failed for voice: $voice',
        );
      }
    });

    test('defaults to alloy for null', () {
      expect(tts.parseSpeechVoice(null), sdk.SpeechVoice.alloy);
    });

    test('defaults to alloy for an unrecognised voice', () {
      expect(tts.parseSpeechVoice('robot-voice'), sdk.SpeechVoice.alloy);
    });
  });

  group('parseSpeechResponseFormat', () {
    test('parses all valid audio formats', () {
      for (final fmt in ['mp3', 'opus', 'aac', 'flac', 'wav', 'pcm']) {
        expect(
          tts.parseSpeechResponseFormat(fmt).toJson(),
          fmt,
          reason: 'failed for format: $fmt',
        );
      }
    });

    test('defaults to mp3 for null', () {
      expect(tts.parseSpeechResponseFormat(null), sdk.SpeechResponseFormat.mp3);
    });

    test('defaults to mp3 for an unrecognised format', () {
      expect(
        tts.parseSpeechResponseFormat('xyz'),
        sdk.SpeechResponseFormat.mp3,
      );
    });
  });

  group('speechToModelResponse', () {
    final fakeAudio = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);

    test('finish reason is stop', () {
      final r = tts.speechToModelResponse(fakeAudio, 'mp3', {});
      expect(r.finishReason, FinishReason.stop);
    });

    test('message has model role with one MediaPart', () {
      final r = tts.speechToModelResponse(fakeAudio, 'mp3', {});
      final msg = r.message!;
      expect(msg.role, Role.model);
      expect(msg.content.length, 1);
      expect(msg.content.first.isMedia, isTrue);
    });

    test('mp3 uses audio/mpeg MIME type', () {
      final r = tts.speechToModelResponse(fakeAudio, 'mp3', {});
      expect(r.message!.media!.contentType, 'audio/mpeg');
      expect(r.message!.media!.url, startsWith('data:audio/mpeg;base64,'));
    });

    test('wav uses audio/wav MIME type', () {
      final r = tts.speechToModelResponse(fakeAudio, 'wav', {});
      expect(r.message!.media!.contentType, 'audio/wav');
    });

    test('opus uses audio/opus MIME type', () {
      final r = tts.speechToModelResponse(fakeAudio, 'opus', {});
      expect(r.message!.media!.contentType, 'audio/opus');
    });

    test('base64 payload round-trips correctly', () {
      final r = tts.speechToModelResponse(fakeAudio, 'mp3', {});
      final url = r.message!.media!.url;
      final decoded = base64Decode(url.substring(url.indexOf(',') + 1));
      expect(decoded, equals(fakeAudio));
    });

    test('unknown format falls back to audio/mpeg', () {
      final r = tts.speechToModelResponse(fakeAudio, 'unknown', {});
      expect(r.message!.media!.contentType, 'audio/mpeg');
    });

    test('raw map is passed through unchanged', () {
      final raw = {'model': 'tts-1', 'responseFormat': 'mp3'};
      final r = tts.speechToModelResponse(fakeAudio, 'mp3', raw);
      expect(r.raw, raw);
    });
  });

  group('audioMimeTypes', () {
    test('covers all TTS response formats', () {
      for (final fmt in ['mp3', 'opus', 'aac', 'flac', 'wav', 'pcm']) {
        expect(
          audioMimeTypes.containsKey(fmt),
          isTrue,
          reason: 'missing entry for $fmt',
        );
      }
    });
  });
}
