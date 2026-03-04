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

import 'package:genkit/plugin.dart';

import 'utils.dart';

/// Handles speech-to-text (SST) requests for transcription models.
Future<ModelResponse> handleSpeechToText({
  required ModelRequest request,
  required String modelName,
  required String apiKey,
  required String? baseUrl,
  required Map<String, String>? headers,
  required double? temperature,
  required String? configuredResponseFormat,
  required ({
    bool streamingRequested,
    void Function(ModelResponseChunk) sendChunk,
    Map<String, dynamic>? context,
    Stream<ModelRequest>? inputStream,
    void init,
  })
  ctx,
}) async {
  if (ctx.streamingRequested) {
    throw GenkitException(
      'Streaming is not currently supported for transcription models.',
    );
  }

  final media = _extractAudioMedia(request.messages);
  if (media == null) {
    throw GenkitException(
      'Transcription requires at least one audio MediaPart in request messages.',
    );
  }

  final audioPayload = _decodeAudioDataUrl(media);
  final transcriptionUri = buildOpenAIUri('/audio/transcriptions', baseUrl);
  final httpClient = HttpClient();

  try {
    final httpRequest = await httpClient.postUrl(transcriptionUri);
    httpRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    httpRequest.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (headers != null) {
      for (final header in headers.entries) {
        httpRequest.headers.set(header.key, header.value);
      }
    }

    final boundary = 'genkit-${DateTime.now().microsecondsSinceEpoch}';
    httpRequest.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );

    final bodyBytes = <int>[];
    appendMultipartField(bodyBytes, boundary, 'model', modelName);

    final prompt = _extractTranscriptionPrompt(request.messages);
    if (prompt != null && prompt.isNotEmpty) {
      appendMultipartField(bodyBytes, boundary, 'prompt', prompt);
    }

    final responseFormat = _resolveTranscriptionResponseFormat(
      configuredResponseFormat,
      request.output?.format,
      request.output?.contentType,
    );
    if (responseFormat != null) {
      appendMultipartField(
        bodyBytes,
        boundary,
        'response_format',
        responseFormat,
      );
    }

    if (temperature != null) {
      appendMultipartField(
        bodyBytes,
        boundary,
        'temperature',
        temperature.toString(),
      );
    }

    appendMultipartFile(
      bodyBytes,
      boundary,
      fieldName: 'file',
      filename: audioPayload.filename,
      contentType: audioPayload.contentType,
      bytes: audioPayload.bytes,
    );

    bodyBytes.addAll(utf8.encode('--$boundary--\r\n'));
    httpRequest.add(bodyBytes);

    final response = await httpRequest.close();
    final responseBody = await utf8.decoder.bind(response).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GenkitException(
        'OpenAI API error: transcription request failed with status ${response.statusCode}.',
        status: StatusCodes.fromHttpStatus(response.statusCode),
        details: responseBody,
      );
    }

    final parsedBody = jsonDecode(responseBody);
    final raw = parsedBody is Map<String, dynamic>
        ? parsedBody
        : <String, dynamic>{'response': parsedBody};
    final transcript = _extractTranscriptionText(raw);

    if (transcript == null || transcript.trim().isEmpty) {
      throw GenkitException(
        'Transcription response did not contain text.',
        details: responseBody,
      );
    }

    return ModelResponse(
      finishReason: FinishReason.stop,
      message: Message(
        role: Role.model,
        content: [TextPart(text: transcript.trim())],
      ),
      raw: raw,
    );
  } on GenkitException {
    rethrow;
  } on FormatException catch (e, stackTrace) {
    throw GenkitException(
      'Invalid transcription response format: $e',
      underlyingException: e,
      stackTrace: stackTrace,
    );
  } catch (e, stackTrace) {
    throw GenkitException(
      'OpenAI transcription error: $e',
      details: e.toString(),
      underlyingException: e,
      stackTrace: stackTrace,
    );
  } finally {
    httpClient.close(force: true);
  }
}

Media? _extractAudioMedia(List<Message> messages) {
  for (final message in messages.reversed) {
    for (final part in message.content.reversed) {
      final media = part.media;
      if (media == null) continue;

      final contentType = media.contentType?.toLowerCase();
      final normalizedUrl = media.url.toLowerCase();
      final isTranscriptionDataUrl =
          normalizedUrl.startsWith('data:audio/') ||
          normalizedUrl.startsWith('data:video/') ||
          normalizedUrl.startsWith('data:application/ogg;');
      final isTranscriptionContentType =
          contentType != null &&
          (contentType.startsWith('audio/') ||
              contentType == 'video/mp4' ||
              contentType == 'video/webm' ||
              contentType == 'application/ogg');
      if (isTranscriptionDataUrl || isTranscriptionContentType) {
        return media;
      }
    }
  }
  return null;
}

({List<int> bytes, String contentType, String filename}) _decodeAudioDataUrl(
  Media media,
) {
  final url = media.url.trim();
  final match = RegExp(
    r'^data:((?:audio|video)\/[^;]+|application\/ogg);base64,',
    caseSensitive: false,
  ).firstMatch(url);

  if (match == null) {
    throw GenkitException(
      'Audio media must be provided as a base64 data URL for transcription models.',
    );
  }

  final contentType = match.group(1)!.toLowerCase();
  final encodedAudio = url.substring(match.end);
  final bytes = base64Decode(encodedAudio);
  final filename = switch (contentType) {
    'audio/flac' || 'audio/x-flac' => 'audio.flac',
    'audio/mp4' || 'video/mp4' => 'audio.mp4',
    'audio/mpeg' => 'audio.mpeg',
    'audio/mpga' || 'audio/x-mpga' => 'audio.mpga',
    'audio/m4a' || 'audio/x-m4a' => 'audio.m4a',
    'audio/ogg' || 'application/ogg' => 'audio.ogg',
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'audio.wav',
    'audio/mp3' || 'audio/x-mp3' => 'audio.mp3',
    'audio/webm' || 'video/webm' => 'audio.webm',
    _ => 'audio.bin',
  };

  return (bytes: bytes, contentType: contentType, filename: filename);
}

String? _extractTranscriptionPrompt(List<Message> messages) {
  for (final message in messages.reversed) {
    if (message.role != Role.user) continue;

    final prompt = message.text.trim();
    if (prompt.isNotEmpty) return prompt;
  }
  return null;
}

String? _resolveTranscriptionResponseFormat(
  String? configuredResponseFormat,
  String? format,
  String? contentType,
) {
  final normalizedConfigured = normalizeOptionalString(
    configuredResponseFormat,
  )?.toLowerCase();
  if (normalizedConfigured != null) {
    const allowed = {'json', 'text', 'srt', 'verbose_json', 'vtt'};
    if (allowed.contains(normalizedConfigured)) {
      return normalizedConfigured;
    }
  }

  final normalizedFormat = normalizeOptionalString(format)?.toLowerCase();
  if (normalizedFormat != null) {
    const allowed = {'json', 'text', 'srt', 'verbose_json', 'vtt'};
    if (allowed.contains(normalizedFormat)) {
      return normalizedFormat;
    }
  }

  if (contentType == 'application/json') {
    return 'json';
  }
  return null;
}

String? _extractTranscriptionText(Map<String, dynamic> responseBody) {
  final text = responseBody['text'];
  if (text is String && text.trim().isNotEmpty) {
    return text;
  }

  final transcript = responseBody['transcript'];
  if (transcript is String && transcript.trim().isNotEmpty) {
    return transcript;
  }

  return null;
}
