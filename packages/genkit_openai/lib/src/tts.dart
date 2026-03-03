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

import 'package:genkit/plugin.dart';
import 'package:openai_dart/openai_dart.dart';
// ignore: implementation_imports
import 'package:openai_dart/src/generated/client.dart' as openai_generated;

/// Model info for text-to-speech models.
ModelInfo ttsModelInfo(String model) {
  return ModelInfo(
    label: model,
    supports: {
      'multiturn': false,
      'tools': false,
      'systemRole': false,
      'media': false,
    },
  );
}

/// Returns true if [modelId] refers to a dedicated speech synthesis model.
bool isSpeechSynthesisModel(String modelId) {
  final id = modelId.toLowerCase();
  return id.contains('tts') &&
      !id.contains('audio') &&
      !id.contains('realtime');
}

Future<ModelResponse> handleSpeechSynthesis(
  OpenAIClient client,
  ModelRequest requestInput, {
  required String modelId,
  required String? baseUrl,
  String? audioVoice,
  String? audioFormat,
}) async {
  final textInput = _extractSpeechInputText(requestInput.messages);
  final voice = audioVoice ?? 'alloy';
  final format = (audioFormat ?? 'mp3').toLowerCase();
  final responseFormat = _speechFormatToApiValue(format);
  final requestedMimeType = _speechFormatToMimeType(format);
  final speechEndpoint = _resolveSpeechEndpoint(baseUrl);

  // ignore: invalid_use_of_protected_member
  final response = await client.makeRequest(
    baseUrl: speechEndpoint.baseUrl,
    path: speechEndpoint.path,
    method: openai_generated.HttpMethod.post,
    requestType: 'application/json',
    responseType: requestedMimeType,
    body: {
      'model': modelId,
      'input': textInput,
      'voice': voice,
      'response_format': responseFormat,
    },
  );

  final mimeType = _resolveSpeechContentType(
    response.headers['content-type'],
    fallbackFormat: format,
  );
  final audioData = base64Encode(response.bodyBytes);

  return ModelResponse(
    finishReason: FinishReason.stop,
    message: Message(
      role: Role.model,
      content: [
        MediaPart(
          media: Media(
            url: 'data:$mimeType;base64,$audioData',
            contentType: mimeType,
          ),
          metadata: {
            'audio': {
              'model': modelId,
              'voice': voice,
              'format': responseFormat,
            },
          },
        ),
      ],
    ),
    raw: {
      'endpoint': speechEndpoint.path,
      'model': modelId,
      'contentType': mimeType,
    },
  );
}

String _extractSpeechInputText(List<Message> messages) {
  String? lastNonEmptyText;
  for (final message in messages.reversed) {
    final text = message.text.trim();
    if (text.isEmpty) continue;

    if (message.role == Role.user) {
      return text;
    }

    lastNonEmptyText ??= text;
  }

  if (lastNonEmptyText != null) {
    return lastNonEmptyText;
  }

  throw GenkitException(
    'Speech synthesis models require non-empty text input.',
    status: StatusCodes.INVALID_ARGUMENT,
  );
}

({String baseUrl, String path}) _resolveSpeechEndpoint(String? baseUrl) {
  if (baseUrl == null) {
    return (baseUrl: 'https://api.openai.com', path: '/v1/audio/speech');
  }

  final normalizedPath = Uri.parse(baseUrl).path.toLowerCase();
  final includesVersionPrefix = RegExp(
    r'(^|/)v\d+(/|$)',
  ).hasMatch(normalizedPath);

  return (
    baseUrl: baseUrl,
    path: includesVersionPrefix ? '/audio/speech' : '/v1/audio/speech',
  );
}

String _speechFormatToApiValue(String format) {
  return switch (format) {
    'wav' || 'mp3' || 'flac' || 'opus' => format,
    'pcm16' || 'pcm' => 'pcm',
    _ => throw GenkitException(
      'Unsupported audio format "$format".',
      status: StatusCodes.INVALID_ARGUMENT,
    ),
  };
}

String _speechFormatToMimeType(String format) {
  return switch (format) {
    'wav' => 'audio/wav',
    'mp3' || 'mpeg' => 'audio/mpeg',
    'flac' => 'audio/flac',
    'opus' => 'audio/opus',
    'pcm16' || 'pcm' => 'audio/pcm',
    _ => throw GenkitException(
      'Unsupported audio format "$format".',
      status: StatusCodes.INVALID_ARGUMENT,
    ),
  };
}

String _resolveSpeechContentType(
  String? headerValue, {
  required String fallbackFormat,
}) {
  if (headerValue == null || headerValue.trim().isEmpty) {
    return _speechFormatToMimeType(fallbackFormat);
  }

  final normalized = headerValue.split(';').first.trim().toLowerCase();
  if (normalized.startsWith('audio/')) {
    return normalized;
  }
  if (normalized.contains('/')) {
    return _speechFormatToMimeType(fallbackFormat);
  }

  try {
    return _speechFormatToMimeType(normalized);
  } on GenkitException {
    return _speechFormatToMimeType(fallbackFormat);
  }
}
