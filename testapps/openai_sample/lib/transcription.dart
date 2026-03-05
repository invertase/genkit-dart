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
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_openai/genkit_openai.dart';

/// Defines a flow that performs basic speech-to-text on a data URL.
///
/// This is the simplest transcription path: provide `data:audio/...;base64,...`
/// and get plain text back.
Flow<String, String, void, void> defineWhisperTranscriptionFlow(
  Genkit ai, {
  String model = 'whisper-1',
}) {
  return ai.defineFlow(
    name: 'whisperTranscribeDataUrl',
    inputSchema: .string(
      defaultValue: 'data:audio/wav;base64,<base64-audio-bytes>',
    ),
    outputSchema: .string(),
    fn: (audioDataUrl, _) => _generateTranscriptFromDataUrl(
      ai: ai,
      model: model,
      audioDataUrl: audioDataUrl,
      prompt: 'Transcribe this audio. Return only the transcript text.',
    ),
  );
}

/// Defines a flow that demonstrates `response_format=json` with logprobs.
Flow<String, Map<String, dynamic>, void, void> defineWhisperJsonLogprobsFlow(
  Genkit ai, {
  String model = 'gpt-4o-transcribe',
}) {
  return ai.defineFlow(
    name: 'whisperTranscribeJsonLogprobs',
    inputSchema: .string(
      defaultValue: 'data:audio/wav;base64,<base64-audio-bytes>',
    ),
    outputSchema: .map(.string(), .dynamicSchema()),
    fn: (audioDataUrl, _) => _generateTranscriptionJsonFromDataUrl(
      ai: ai,
      model: model,
      audioDataUrl: audioDataUrl,
      prompt: 'Transcribe this audio. Return transcript text.',
      config: <String, dynamic>{
        'response_format': 'json',
        'include': ['logprobs'],
      },
    ),
  );
}

/// Defines a flow that requests word and segment timestamps.
Flow<String, Map<String, dynamic>, void, void>
defineWhisperVerboseTimestampFlow(Genkit ai, {String model = 'whisper-1'}) {
  return ai.defineFlow(
    name: 'whisperTranscribeVerboseTimestamps',
    inputSchema: .string(
      defaultValue: 'data:audio/wav;base64,<base64-audio-bytes>',
    ),
    outputSchema: .map(.string(), .dynamicSchema()),
    fn: (audioDataUrl, _) => _generateTranscriptionJsonFromDataUrl(
      ai: ai,
      model: model,
      audioDataUrl: audioDataUrl,
      prompt: 'Transcribe this audio. Return transcript text.',
      config: <String, dynamic>{
        'response_format': 'verbose_json',
        'timestampGranularities': ['word', 'segment'],
      },
    ),
  );
}

/// Defines a flow that demonstrates diarized output with speaker hints.
Flow<String, Map<String, dynamic>, void, void> defineWhisperDiarizedFlow(
  Genkit ai, {
  String model = 'gpt-4o-transcribe-diarize',
}) {
  return ai.defineFlow(
    name: 'whisperTranscribeDiarized',
    inputSchema: .string(
      defaultValue: 'data:audio/wav;base64,<base64-audio-bytes>',
    ),
    outputSchema: .map(.string(), .dynamicSchema()),
    fn: (audioDataUrl, _) => _generateTranscriptionJsonFromDataUrl(
      ai: ai,
      model: model,
      audioDataUrl: audioDataUrl,
      prompt: 'Transcribe this audio and use diarization if available.',
      config: <String, dynamic>{
        'response_format': 'json',
        'knownSpeakerNames': ['Speaker A', 'Speaker B'],
      },
    ),
  );
}

/// Defines a flow that translates source speech into English.
///
/// The plugin-level `translate` option routes the request to
/// `/audio/translations`.
Flow<String, String, void, void> defineWhisperTranslationFlow(
  Genkit ai, {
  String model = 'whisper-1',
}) {
  return ai.defineFlow(
    name: 'whisperTranslateToEnglish',
    inputSchema: .string(
      defaultValue: 'data:audio/wav;base64,<base64-audio-bytes>',
    ),
    outputSchema: .string(),
    fn: (audioDataUrl, _) => _generateTranscriptFromDataUrl(
      ai: ai,
      model: model,
      audioDataUrl: audioDataUrl,
      prompt: 'Translate this audio into English.',
      config: OpenAITranscriptionOptions(translate: true),
    ),
  );
}

/// Defines a flow that transcribes a local audio file path.
Flow<String, String, void, void> defineWhisperAudioFileTranscriptionFlow(
  Genkit ai, {
  String model = 'whisper-1',
}) {
  return ai.defineFlow(
    name: 'whisperTranscribeAudioFile',
    inputSchema: .string(defaultValue: './sample.wav'),
    outputSchema: .string(),
    fn: (audioPath, _) async {
      final dataUrl = await _readFileAsDataUrl(audioPath);
      return _generateTranscriptFromDataUrl(
        ai: ai,
        model: model,
        audioDataUrl: dataUrl,
        prompt: 'Transcribe this audio. Return only the transcript text.',
      );
    },
  );
}

void main() {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    throw StateError('OPENAI_API_KEY is required.');
  }

  final ai = Genkit(plugins: [openAI(apiKey: apiKey)]);
  defineWhisperTranscriptionFlow(ai);
  defineWhisperJsonLogprobsFlow(ai);
  defineWhisperVerboseTimestampFlow(ai);
  defineWhisperDiarizedFlow(ai);
  defineWhisperTranslationFlow(ai);
  defineWhisperAudioFileTranscriptionFlow(ai);
}

Future<String> _generateTranscriptFromDataUrl({
  required Genkit ai,
  required String model,
  required String audioDataUrl,
  required String prompt,
  Object? config,
}) async {
  final response = await _requestTranscriptionFromDataUrl(
    ai: ai,
    model: model,
    audioDataUrl: audioDataUrl,
    prompt: prompt,
    config: config,
  );

  final text = response.text.trim();
  if (text.isEmpty) {
    throw StateError('Model returned empty transcription.');
  }
  return text;
}

Future<Map<String, dynamic>> _generateTranscriptionJsonFromDataUrl({
  required Genkit ai,
  required String model,
  required String audioDataUrl,
  required String prompt,
  Object? config,
}) async {
  final response = await _requestTranscriptionFromDataUrl(
    ai: ai,
    model: model,
    audioDataUrl: audioDataUrl,
    prompt: prompt,
    config: config,
  );

  final raw = response.raw;
  if (raw != null) {
    return raw;
  }

  throw StateError(
    'Model returned non-JSON transcription payload for a JSON flow.',
  );
}

Future<GenerateResponseHelper> _requestTranscriptionFromDataUrl({
  required Genkit ai,
  required String model,
  required String audioDataUrl,
  required String prompt,
  Object? config,
}) async {
  final contentType = _extractAudioMimeTypeFromDataUrl(audioDataUrl);
  if (contentType == null) {
    throw ArgumentError(
      'Input must be a base64 media data URL (data:audio/...;base64,... or data:video/...;base64,...).',
    );
  }

  return ai.generate(
    model: openAI.transcribe(model),
    messages: [
      Message(
        role: Role.user,
        content: [
          TextPart(text: prompt),
          MediaPart(
            media: Media(url: audioDataUrl, contentType: contentType),
          ),
        ],
      ),
    ],
    config: config,
  );
}

Future<String> _readFileAsDataUrl(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw ArgumentError('File not found: $path');
  }

  final bytes = await file.readAsBytes();
  final mimeType = _mediaMimeTypeFromPath(path);
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

String? _extractAudioMimeTypeFromDataUrl(String url) {
  final match = RegExp(
    r'^data:((?:audio|video)\/[^;]+);base64,',
    caseSensitive: false,
  ).firstMatch(url);
  return match?.group(1);
}

String _mediaMimeTypeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.flac')) return 'audio/flac';
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.mp4')) return 'video/mp4';
  if (lower.endsWith('.mpeg')) return 'video/mpeg';
  if (lower.endsWith('.mpga')) return 'audio/mpga';
  if (lower.endsWith('.m4a')) return 'audio/m4a';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.webm')) return 'audio/webm';

  throw ArgumentError(
    'Unsupported media file extension for "$path". Supported extensions: .flac, .mp3, .mp4, .mpeg, .mpga, .m4a, .ogg, .wav, .webm.',
  );
}
