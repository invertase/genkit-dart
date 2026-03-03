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
import 'package:genkit_vertex_auth/genkit_vertex_auth.dart';
import 'package:openai_dart/openai_dart.dart' hide Model;
import 'package:schemantic/schemantic.dart';

import '../genkit_openai.dart';
import 'aggregation.dart';
import 'audio.dart';
import 'options.dart';
import 'tts.dart';

/// Returns true when the output config indicates JSON-structured output
/// (format is 'json' or contentType is 'application/json').
bool isJsonStructuredOutput(String? format, String? contentType) {
  return format == 'json' || contentType == 'application/json';
}

/// Builds an OpenAI [ResponseFormat] from a Genkit output schema.
/// Flattens `$ref`/`$defs` since OpenAI requires `type` at the top level.
/// Returns null if [schema] is null.
ResponseFormat? buildOpenAIResponseFormat(Map<String, dynamic>? schema) {
  if (schema == null) return null;
  final flattened = schema.flatten();
  return ResponseFormat.jsonSchema(
    jsonSchema: JsonSchemaObject(
      name: 'output',
      schema: {...flattened, 'additionalProperties': false},
      strict: true,
    ),
  );
}

/// Core plugin implementation
class OpenAIPlugin extends GenkitPlugin {
  @override
  String get name => 'openai';

  final String? apiKey;
  final String? baseUrl;
  final OpenAIVertexConfig? vertex;
  final List<CustomModelDefinition> customModels;
  final Map<String, String>? headers;

  OpenAIPlugin({
    this.apiKey,
    this.baseUrl,
    this.vertex,
    this.customModels = const [],
    this.headers,
  }) {
    if (apiKey != null && vertex != null) {
      throw GenkitException(
        'Provide either apiKey or vertex configuration, not both.',
        status: StatusCodes.INVALID_ARGUMENT,
      );
    }
    if (baseUrl != null && vertex != null) {
      throw GenkitException(
        'Provide either baseUrl or vertex configuration, not both.',
        status: StatusCodes.INVALID_ARGUMENT,
      );
    }
    vertex?.validate();
  }

  @override
  Future<List<Action>> init() async {
    final actions = <Action>[];

    // Fetch and register models from OpenAI API only for default OpenAI host.
    if (baseUrl == null && vertex == null) {
      try {
        final availableModelIds = await _fetchAvailableModels();

        for (final modelId in availableModelIds) {
          final modelType = getModelType(modelId);

          if (modelType != 'chat' &&
              modelType != 'audio' &&
              modelType != 'tts' &&
              modelType != 'unknown') {
            continue;
          }

          final info = _getModelInfo(modelId);
          actions.add(_createModel(modelId, info));
        }
      } catch (e) {
        throw GenkitException(
          'Error fetching available models from OpenAI: $e',
          underlyingException: e,
        );
      }
    }

    // Register custom models
    for (final model in customModels) {
      actions.add(_createModel(model.name, model.info));
    }

    return actions;
  }

  /// Fetch available model IDs from OpenAI API
  Future<List<String>> _fetchAvailableModels() async {
    final resolvedConfig = await _resolveClientConfig();

    final client = OpenAIClient(
      apiKey: resolvedConfig.apiKey,
      baseUrl: resolvedConfig.baseUrl,
      headers: resolvedConfig.headers,
    );

    try {
      final response = await client.listModels();
      final modelIds = <String>[];

      // Collect all model IDs
      for (final model in response.data) {
        modelIds.add(model.id);
      }

      return modelIds;
    } finally {
      client.endSession();
    }
  }

  /// Get appropriate ModelInfo for a given model ID
  ModelInfo _getModelInfo(String modelId) {
    final id = modelId.toLowerCase();
    final modelType = getModelType(modelId);

    if (modelType == 'audio') {
      return audioModelInfo(modelId);
    }

    if (modelType == 'tts') {
      return ttsModelInfo(modelId);
    }
    // O-series reasoning models (o1, o2, o3, o4, etc.) have different capabilities
    // Matches: o1, o1-preview, o2, o3-mini, o4-mini-2025-01-01, etc.
    final oSeriesPattern = RegExp(r'^o\d+(?:-|$)');
    if (oSeriesPattern.hasMatch(id)) {
      return oSeriesModelInfo(modelId);
    }

    return defaultModelInfo(modelId);
  }

  Future<_ResolvedClientConfig> _resolveClientConfig() async {
    final vertexConfig = vertex;
    if (vertexConfig != null) {
      final token = (await vertexConfig.resolveAccessToken()).trim();
      return _ResolvedClientConfig(
        apiKey: token,
        baseUrl: vertexConfig.resolveBaseUrl(),
        headers: {
          ...?headers,
          'x-goog-api-client': googleApiClientHeaderValue(),
        },
      );
    }

    final configuredApiKey = apiKey;
    if (configuredApiKey == null || configuredApiKey.trim().isEmpty) {
      throw GenkitException(
        'API key is required. Provide it via the plugin constructor.',
        status: StatusCodes.INVALID_ARGUMENT,
      );
    }

    return _ResolvedClientConfig(
      apiKey: configuredApiKey.trim(),
      baseUrl: baseUrl,
      headers: headers,
    );
  }

  @override
  Future<List<ActionMetadata<dynamic, dynamic, dynamic, dynamic>>>
  list() async {
    try {
      final modelIds = await _fetchAvailableModels();
      for (final modelId in modelIds) {
        final modelType = getModelType(modelId);
        if (modelType != 'chat' && modelType != 'unknown') {
          continue;
        }
      }

      // Filter to only chat models and generate their metadata
      final modelMetadataList = modelIds
          .where(
            (modelId) =>
                getModelType(modelId) == 'chat' ||
                getModelType(modelId) == 'audio' ||
                getModelType(modelId) == 'tts' ||
                getModelType(modelId) == 'unknown',
          )
          .map((modelId) {
            final modelInfo = _getModelInfo(modelId);

            return modelMetadata(
              'openai/$modelId',
              modelInfo: modelInfo,
              customOptions: optionsSchemaForModel(modelId),
            );
          })
          .toList();
      return modelMetadataList;
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
      return _createModel(name, null);
    }
    return null;
  }

  Model _createModel(String modelName, ModelInfo? info) {
    final modelInfo = info ?? _getModelInfo(modelName);

    return Model(
      name: 'openai/$modelName',
      customOptions: optionsSchemaForModel(modelName),
      metadata: {'model': modelInfo.toJson()},
      fn: (req, ctx) async {
        final requestInput = req!;
        final options = requestInput.config != null
            ? OpenAIOptions.$schema.parse(requestInput.config!)
            : OpenAIOptions();

        final resolvedConfig = await _resolveClientConfig();
        final client = OpenAIClient(
          apiKey: resolvedConfig.apiKey,
          baseUrl: resolvedConfig.baseUrl,
          headers: resolvedConfig.headers,
        );

        try {
          final supports = modelInfo.supports;
          final supportsTools = supports?['tools'] == true;
          final resolvedModelId = options.version ?? modelName;
          if (getModelType(resolvedModelId) == 'tts') {
            return await handleSpeechSynthesis(
              client,
              requestInput,
              modelId: resolvedModelId,
              baseUrl: baseUrl,
              audioVoice: options.audioVoice,
              audioFormat: options.audioFormat,
            );
          }

          final modelType = getModelType(resolvedModelId);
          final modalities = resolveOpenAIModalities(
            modelType: modelType,
            configured: options.responseModalities,
          );

          final audioOptions = resolveOpenAIAudioOptions(
            modalities,
            voice: options.audioVoice,
            format: options.audioFormat,
          );

          final isJsonMode = isJsonStructuredOutput(
            requestInput.output?.format,
            requestInput.output?.contentType,
          );
          final responseFormat = buildOpenAIResponseFormat(
            requestInput.output?.schema,
          );
          final request = CreateChatCompletionRequest(
            model: ChatCompletionModel.modelId(resolvedModelId),
            messages: GenkitConverter.toOpenAIMessages(
              requestInput.messages,
              options.visualDetailLevel,
            ),
            tools: supportsTools
                ? requestInput.tools?.map(GenkitConverter.toOpenAITool).toList()
                : null,
            modalities: modalities,
            audio: audioOptions,
            temperature: options.temperature,
            topP: options.topP,
            maxTokens: options.maxTokens,
            stop: options.stop != null
                ? ChatCompletionStop.listString(options.stop!)
                : null,
            presencePenalty: options.presencePenalty,
            frequencyPenalty: options.frequencyPenalty,
            seed: options.seed,
            user: options.user,
            responseFormat: isJsonMode ? responseFormat : null,
          );
          if (ctx.streamingRequested) {
            return await _handleStreaming(
              client,
              request,
              request.audio?.format,
              ctx,
            );
          } else {
            return await _handleNonStreaming(
              client,
              request,
              request.audio?.format,
            );
          }
        } catch (e, stackTrace) {
          if (e is GenkitException) {
            rethrow;
          }

          StatusCodes? status;
          String? details;

          if (e is OpenAIClientException) {
            status = e.code != null
                ? StatusCodes.fromHttpStatus(e.code!)
                : null;
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
          client.endSession();
        }
      },
    );
  }

  /// Handle streaming response
  Future<ModelResponse> _handleStreaming(
    OpenAIClient client,
    CreateChatCompletionRequest request,
    ChatCompletionAudioFormat? audioFormat,
    ({
      bool streamingRequested,
      void Function(ModelResponseChunk) sendChunk,
      Map<String, dynamic>? context,
      Stream<ModelRequest>? inputStream,
      void init,
    })
    ctx,
  ) async {
    final stream = client.createChatCompletionStream(request: request);
    final chunks = <CreateChatCompletionStreamResponse>[];

    try {
      await for (final chunk in stream) {
        chunks.add(chunk);

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

        if (delta.audio?.transcript != null &&
            delta.audio!.transcript!.isNotEmpty) {
          ctx.sendChunk(
            ModelResponseChunk(
              index: 0,
              content: [TextPart(text: delta.audio!.transcript!)],
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

    final response = aggregateStreamResponses(chunks);
    final choice = response.choices.first;
    final message = GenkitConverter.fromOpenAIAssistantMessage(
      choice.message,
      audioFormat: audioFormat,
    );

    return ModelResponse(
      finishReason: GenkitConverter.mapFinishReason(choice.finishReason?.name),
      message: message,
      raw: response.toJson(),
    );
  }

  /// Handle non-streaming response
  Future<ModelResponse> _handleNonStreaming(
    OpenAIClient client,
    CreateChatCompletionRequest request,
    ChatCompletionAudioFormat? audioFormat,
  ) async {
    final response = await client.createChatCompletion(request: request);

    if (response.choices.isEmpty) {
      throw GenkitException('Model returned no choices.');
    }

    final choice = response.choices.first;
    final message = GenkitConverter.fromOpenAIAssistantMessage(
      choice.message,
      audioFormat: audioFormat,
    );

    return ModelResponse(
      finishReason: GenkitConverter.mapFinishReason(choice.finishReason?.name),
      message: message,
      raw: response.toJson(),
    );
  }
}

final class _ResolvedClientConfig {
  final String apiKey;
  final String? baseUrl;
  final Map<String, String>? headers;

  const _ResolvedClientConfig({
    required this.apiKey,
    required this.baseUrl,
    required this.headers,
  });
}
