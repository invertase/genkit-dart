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

import 'package:genkit/plugin.dart';
import 'package:openai_dart/openai_dart.dart' as sdk;

import '../genkit_openai.dart';
import 'chat.dart' as chat_lib;
import 'tts.dart' as tts_lib;
import 'utils.dart';

/// Core plugin implementation
class OpenAIPlugin extends GenkitPlugin {
  @override
  String get name => 'openai';

  final String? apiKey;
  final OpenAIApiKeyProvider? apiKeyProvider;
  final String? baseUrl;
  final List<CustomModelDefinition> customModels;
  final Map<String, String>? headers;

  OpenAIPlugin({
    this.apiKey,
    this.apiKeyProvider,
    this.baseUrl,
    this.customModels = const [],
    this.headers,
  }) {
    if (apiKey != null && apiKeyProvider != null) {
      throw GenkitException(
        'Provide either apiKey or apiKeyProvider, not both.',
        status: StatusCodes.INVALID_ARGUMENT,
      );
    }
  }

  @override
  Future<List<Action>> init() async {
    final actions = <Action>[];

    // Fetch and register models from OpenAI API only for the default host.
    if (baseUrl == null) {
      try {
        final availableModelIds = await _fetchAvailableModels();

        for (final modelId in availableModelIds) {
          final modelType = getModelType(modelId);

          if (modelType == 'chat' || modelType == 'unknown') {
            actions.add(_createModel(modelId, modelInfoFor(modelId)));
          } else if (modelType == 'audio' &&
              tts_lib.supportedTtsModels.contains(modelId)) {
            actions.add(_createTtsModel(modelId));
          }
        }
      } catch (e) {
        throw GenkitException(
          'Error fetching available models from OpenAI: $e',
          underlyingException: e,
        );
      }
    }

    // Register custom models.
    for (final model in customModels) {
      actions.add(_createModel(model.name, model.info));
    }

    return actions;
  }

  /// Fetch available model IDs from OpenAI API.
  Future<List<String>> _fetchAvailableModels() async {
    final resolvedConfig = await _resolveClientConfig();
    final client = buildOpenAIClient(resolvedConfig);
    try {
      final response = await client.models.list();
      return response.data.map((m) => m.id).toList();
    } finally {
      client.close();
    }
  }

  Future<OpenAIClientConfig> _resolveClientConfig() async {
    final configuredApiKey = await _resolveApiKey();
    if (configuredApiKey == null || configuredApiKey.trim().isEmpty) {
      throw GenkitException(
        'API key is required. Provide it via apiKey or apiKeyProvider in the plugin constructor.',
        status: StatusCodes.INVALID_ARGUMENT,
      );
    }

    return OpenAIClientConfig(
      apiKey: configuredApiKey.trim(),
      baseUrl: baseUrl,
      headers: headers,
    );
  }

  Future<String?> _resolveApiKey() async {
    final configuredApiKeyProvider = apiKeyProvider;
    if (configuredApiKeyProvider != null) {
      return await configuredApiKeyProvider();
    }
    return apiKey;
  }

  @override
  Future<List<ActionMetadata<dynamic, dynamic, dynamic, dynamic>>>
  list() async {
    try {
      final modelIds = await _fetchAvailableModels();
      final metadata =
          <ActionMetadata<dynamic, dynamic, dynamic, dynamic>>[];

      for (final modelId in modelIds) {
        final modelType = getModelType(modelId);

        if (modelType == 'chat' || modelType == 'unknown') {
          metadata.add(
            modelMetadata(
              'openai/$modelId',
              modelInfo: modelInfoFor(modelId),
              customOptions: chat_lib.chatModelOptionsSchema(),
            ),
          );
        }
      }

      // Include known TTS models when using the default OpenAI endpoint.
      if (baseUrl == null) {
        for (final modelId in tts_lib.supportedTtsModels) {
          metadata.add(
            modelMetadata(
              'openai/$modelId',
              modelInfo: tts_lib.ttsModelInfo(modelId),
              customOptions: tts_lib.ttsOptionsSchema(),
            ),
          );
        }
      }

      return metadata;
    } catch (e, stackTrace) {
      throw GenkitException(
        'Error listing models from OpenAI: $e',
        underlyingException: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Action? resolve(String actionType, String name) {
    if (actionType == 'model') {
      if (tts_lib.supportedTtsModels.contains(name)) {
        return _createTtsModel(name);
      }
      return _createModel(name, null);
    }
    return null;
  }

  /// Creates a [Model] action that calls the OpenAI TTS endpoint.
  Model _createTtsModel(String modelName) {
    return Model(
      name: 'openai/$modelName',
      customOptions: tts_lib.ttsOptionsSchema(),
      metadata: {'model': tts_lib.ttsModelInfo(modelName).toJson()},
      fn: (req, ctx) async {
        final request = req!;
        final options = tts_lib.parseTtsOptions(request.config);
        final responseFormat = options.responseFormat ?? 'mp3';
        final modelVersion = options.version ?? modelName;

        if (request.messages.isEmpty) {
          throw GenkitException(
            'TTS requires a text input message.',
            status: StatusCodes.INVALID_ARGUMENT,
          );
        }
        final inputText = request.messages.first.text;
        if (inputText.isEmpty) {
          throw GenkitException(
            'TTS requires non-empty text input.',
            status: StatusCodes.INVALID_ARGUMENT,
          );
        }

        final resolvedConfig = await _resolveClientConfig();
        final client = buildOpenAIClient(resolvedConfig);
        try {
          final audioBytes = await client.audio.speech.create(
            sdk.SpeechRequest(
              model: modelVersion,
              input: inputText,
              voice: tts_lib.parseSpeechVoice(options.voice),
              responseFormat: tts_lib.parseSpeechResponseFormat(responseFormat),
              speed: options.speed,
            ),
          );
          return tts_lib.speechToModelResponse(
            audioBytes,
            responseFormat,
            {'model': modelVersion, 'responseFormat': responseFormat},
          );
        } catch (e, stackTrace) {
          rethrowAsGenkitException(e, stackTrace, 'TTS');
        } finally {
          client.close();
        }
      },
    );
  }

  // ─── Chat model factory ────────────────────────────────────────────────────────

  Model _createModel(String modelName, ModelInfo? info) {
    final modelInfo = info ?? modelInfoFor(modelName);

    return Model(
      name: 'openai/$modelName',
      customOptions: chat_lib.chatModelOptionsSchema(),
      metadata: {'model': modelInfo.toJson()},
      fn: (req, ctx) async {
        final modelRequest = req!;
        final options = chat_lib.parseChatModelOptions(modelRequest.config);

        final resolvedConfig = await _resolveClientConfig();
        final client = buildOpenAIClient(resolvedConfig);

        try {
          final supports = modelInfo.supports;
          final supportsTools = supports?['tools'] == true;

          final isJsonMode = chat_lib.isJsonStructuredOutput(
            modelRequest.output?.format,
            modelRequest.output?.contentType,
          );
          final responseFormat = chat_lib.buildOpenAIResponseFormat(
            modelRequest.output?.schema,
          );
          final request = sdk.ChatCompletionCreateRequest(
            model: options.version ?? modelName,
            messages: GenkitConverter.toOpenAIMessages(
              modelRequest.messages,
              options.visualDetailLevel,
            ),
            tools: supportsTools
                ? modelRequest.tools
                      ?.map(GenkitConverter.toOpenAITool)
                      .toList()
                : null,
            temperature: options.temperature,
            topP: options.topP,
            maxCompletionTokens: options.maxTokens,
            stop: options.stop,
            presencePenalty: options.presencePenalty,
            frequencyPenalty: options.frequencyPenalty,
            seed: options.seed,
            user: options.user,
            responseFormat: isJsonMode ? responseFormat : null,
          );
          if (ctx.streamingRequested) {
            return await _handleStreaming(client, request, ctx);
          } else {
            return await _handleNonStreaming(client, request);
          }
        } catch (e, stackTrace) {
          if (e is GenkitException) {
            rethrow;
          }

          StatusCodes? status;
          String? details;

          if (e is sdk.ApiException) {
            status = StatusCodes.fromHttpStatus(e.statusCode);
            details = e.body?.toString();
          }

          throw GenkitException(
            'OpenAI API error: $e',
            status: status,
            details: details ?? e.toString(),
            underlyingException: e,
            stackTrace: stackTrace,
          );
        } finally {
          client.close();
        }
      },
    );
  }

  // ─── Streaming helpers ─────────────────────────────────────────────────────────

  /// Handle streaming response
  Future<ModelResponse> _handleStreaming(
    sdk.OpenAIClient client,
    sdk.ChatCompletionCreateRequest request,
    ({
      bool streamingRequested,
      void Function(ModelResponseChunk) sendChunk,
      Map<String, dynamic>? context,
      Stream<ModelRequest>? inputStream,
      void init,
    })
    ctx,
  ) async {
    final stream = client.chat.completions.createStream(request);
    final accumulator = sdk.ChatStreamAccumulator();

    try {
      await for (final chunk in stream) {
        accumulator.add(chunk);

        final choice = (chunk.choices != null && chunk.choices!.isNotEmpty)
            ? chunk.choices!.first
            : null;
        final delta = choice?.delta;
        if (delta == null) continue;

        if (delta.content != null) {
          ctx.sendChunk(
            ModelResponseChunk(
              index: 0,
              content: [TextPart(text: delta.content!)],
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      if (e is GenkitException) rethrow;
      throw GenkitException(
        'Error in streaming: $e',
        underlyingException: e,
        stackTrace: stackTrace,
      );
    }

    final response = accumulator.toChatCompletion();
    final choice = response.choices.first;
    final message = GenkitConverter.fromOpenAIAssistantMessage(choice.message);

    return ModelResponse(
      finishReason: GenkitConverter.mapFinishReason(choice.finishReason?.name),
      message: message,
      raw: response.toJson(),
    );
  }

  /// Handle non-streaming response
  Future<ModelResponse> _handleNonStreaming(
    sdk.OpenAIClient client,
    sdk.ChatCompletionCreateRequest request,
  ) async {
    final response = await client.chat.completions.create(request);

    if (response.choices.isEmpty) {
      throw GenkitException('Model returned no choices.');
    }

    final choice = response.choices.first;
    final message = GenkitConverter.fromOpenAIAssistantMessage(choice.message);

    return ModelResponse(
      finishReason: GenkitConverter.mapFinishReason(choice.finishReason?.name),
      message: message,
      raw: response.toJson(),
    );
  }

}
