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
import 'dart:typed_data';

import 'package:genkit/plugin.dart';
import 'package:openai_dart/openai_dart.dart' as sdk;
import 'package:schemantic/schemantic.dart';

import 'converters.dart';
import 'utils.dart';

part 'audio.g.dart';

/// Options for OpenAI audio chat models (e.g. `gpt-4o-audio-preview`).
///
/// These models accept text input and return both text and audio output.
/// The output always includes `modalities: ['text', 'audio']` — there is no
/// need to configure modalities explicitly.
@Schema()
abstract class $OpenAIAudioOptions {
  /// Model version override (e.g. `gpt-4o-audio-preview-2024-12-17`).
  String? get version;

  /// Sampling temperature (0.0 – 2.0).
  @DoubleField(minimum: 0.0, maximum: 2.0)
  double? get temperature;

  /// Nucleus sampling (0.0 – 1.0).
  @DoubleField(minimum: 0.0, maximum: 1.0)
  double? get topP;

  /// Maximum tokens to generate.
  int? get maxTokens;

  /// Seed for deterministic sampling.
  int? get seed;

  /// User identifier for abuse detection.
  String? get user;

  /// Voice for the audio output.
  @StringField(
    enumValues: [
      'alloy',
      'ash',
      'ballad',
      'coral',
      'echo',
      'fable',
      'nova',
      'onyx',
      'sage',
      'shimmer',
      'verse',
    ],
  )
  String? get voice;

  /// Audio encoding format for the output.
  @StringField(enumValues: ['wav', 'mp3', 'flac', 'opus', 'pcm16'])
  String? get audioFormat;
}

typedef AudioOptions = OpenAIAudioOptions;

/// Returns `true` when [name] is an audio chat model.
///
/// Audio chat models produce both text and audio output via the chat
/// completions API. They are identified by having `audio` in their model ID,
/// which distinguishes them from TTS (`tts-*`), transcription (`whisper-*`),
/// and realtime (`*-realtime-*`) models.
bool isAudioModel(String name) => name.toLowerCase().contains('audio');

ModelInfo audioModelInfo(String label) => ModelInfo(
  label: label,
  supports: {
    'media': false,
    'multiturn': true,
    'systemRole': true,
    'tools': false,
  },
);

/// Returns the [SchemanticType] for [OpenAIAudioOptions].
SchemanticType<OpenAIAudioOptions> audioOptionsSchema() =>
    OpenAIAudioOptions.$schema;

/// Parses audio model options from an action config map.
OpenAIAudioOptions parseAudioOptions(Map<String, dynamic>? config) {
  return config != null
      ? OpenAIAudioOptions.$schema.parse(config)
      : OpenAIAudioOptions();
}

const Map<String, String> _chatAudioMediaTypes = {
  'mp3': 'audio/mpeg',
  'wav': 'audio/wav',
  'flac': 'audio/flac',
  'opus': 'audio/opus',
  'pcm16': 'audio/L16',
};

sdk.ChatAudioConfig buildChatAudioConfig(OpenAIAudioOptions options) {
  return sdk.ChatAudioConfig(
    voice: sdk.ChatAudioVoice.fromJson(options.voice ?? 'alloy'),
    format: sdk.ChatAudioFormat.fromJson(options.audioFormat ?? 'mp3'),
  );
}

/// Makes a raw HTTP request to the chat completions endpoint so the full
/// JSON body (including `message.audio`) is accessible before being parsed
/// into a typed object (the openai_dart SDK drops the audio field).
Future<ModelResponse> handleChatAudioNonStreaming(
  sdk.ChatCompletionCreateRequest request,
  OpenAIClientConfig resolved,
) async {
  final baseUrl = resolved.baseUrl ?? 'https://api.openai.com/v1';
  final url = Uri.parse('$baseUrl/chat/completions');
  final httpClient = HttpClient();

  try {
    final httpRequest = await httpClient.postUrl(url);
    httpRequest.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    httpRequest.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${resolved.apiKey}',
    );
    if (resolved.headers != null) {
      for (final entry in resolved.headers!.entries) {
        httpRequest.headers.set(entry.key, entry.value);
      }
    }
    httpRequest.write(jsonEncode(request.toJson()));

    final response = await httpRequest.close();
    final bytes = await _collectBytes(response);
    final bodyText = utf8.decode(bytes, allowMalformed: true);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GenkitException(
        'OpenAI chat audio API error ($bodyText)',
        status: StatusCodes.fromHttpStatus(response.statusCode),
        details: bodyText,
      );
    }

    final rawJson = jsonDecode(bodyText) as Map<String, dynamic>;
    return buildChatAudioResponse(rawJson, request);
  } finally {
    httpClient.close(force: false);
  }
}

ModelResponse buildChatAudioResponse(
  Map<String, dynamic> rawJson,
  sdk.ChatCompletionCreateRequest request,
) {
  final choices = rawJson['choices'] as List?;
  if (choices == null || choices.isEmpty) {
    throw GenkitException('Model returned no choices.');
  }

  final firstChoice = choices.first as Map<String, dynamic>;
  final finishReason = firstChoice['finish_reason'] as String?;
  final messageJson = firstChoice['message'] as Map<String, dynamic>?;

  // Build the text/tool parts via the existing converter.
  final chatCompletion = sdk.ChatCompletion.fromJson(rawJson);
  final message = GenkitConverter.fromOpenAIAssistantMessage(
    chatCompletion.choices.first.message,
  );

  // Extract audio data that the SDK drops from the parsed AssistantMessage.
  final audioJson = messageJson?['audio'] as Map<String, dynamic>?;
  final audioBase64 = audioJson?['data'] as String?;

  final List<Part> content;
  if (audioBase64 != null && audioBase64.isNotEmpty) {
    final format = request.audio?.format.toJson() ?? 'mp3';
    final mediaType = _chatAudioMediaTypes[format] ?? 'audio/mpeg';
    final dataUri = 'data:$mediaType;base64,$audioBase64';
    content = [
      ...message.content,
      MediaPart(
        media: Media(contentType: mediaType, url: dataUri),
      ),
    ];
  } else {
    content = message.content;
  }

  return ModelResponse(
    finishReason: GenkitConverter.mapFinishReason(finishReason),
    message: Message(role: message.role, content: content),
    raw: rawJson,
  );
}

Future<List<int>> _collectBytes(HttpClientResponse response) async {
  final builder = BytesBuilder();
  await for (final chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// Creates an audio chat model (e.g. `gpt-4o-audio-preview`).
///
/// [resolveClientConfig] is a callback that resolves the OpenAI client
/// configuration at request time, typically provided by the plugin.
Model<OpenAIAudioOptions> createAudioChatModel(
  String modelName,
  ModelInfo? info,
  Future<OpenAIClientConfig> Function() resolveClientConfig,
) {
  final modelInfo = info ?? audioModelInfo(modelName);

  return Model<OpenAIAudioOptions>(
    name: 'openai/$modelName',
    customOptions: audioOptionsSchema(),
    metadata: {'model': modelInfo.toJson()},
    fn: (req, ctx) async {
      final modelRequest = req!;
      final options = parseAudioOptions(modelRequest.config);

      final resolvedConfig = await resolveClientConfig();
      final client = buildOpenAIClient(resolvedConfig);

      try {
        final request = sdk.ChatCompletionCreateRequest(
          model: options.version ?? modelName,
          messages: GenkitConverter.toOpenAIMessages(
            modelRequest.messages,
            null,
          ),
          temperature: options.temperature,
          topP: options.topP,
          maxCompletionTokens: options.maxTokens,
          seed: options.seed,
          user: options.user,
          modalities: [sdk.ChatModality.text, sdk.ChatModality.audio],
          audio: buildChatAudioConfig(options),
        );

        return await handleChatAudioNonStreaming(request, resolvedConfig);
      } catch (e, stackTrace) {
        rethrowAsGenkitException(e, stackTrace, 'audio');
      } finally {
        client.close();
      }
    },
  );
}
