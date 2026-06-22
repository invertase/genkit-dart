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
import 'package:genkit_ollama/genkit_ollama.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Builds a [MockClient] that records requests and replies with [chatBody] for
/// `/api/chat` and [embedBody] for `/api/embed`.
MockClient _mockClient({
  Map<String, dynamic>? chatBody,
  Map<String, dynamic>? embedBody,
  List<http.Request>? captured,
}) {
  return MockClient((request) async {
    captured?.add(request);
    final path = request.url.path;
    if (path.endsWith('/api/chat')) {
      return http.Response(
        jsonEncode(chatBody ?? const {}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/api/embed')) {
      return http.Response(
        jsonEncode(embedBody ?? const {}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('not found: $path', 404);
  });
}

OllamaPlugin _plugin(http.Client client) =>
    ollama(httpClient: client) as OllamaPlugin;

void main() {
  group('model generate (non-streaming)', () {
    test('returns the assistant message', () async {
      final plugin = _plugin(
        _mockClient(
          chatBody: {
            'model': 'llama3.2',
            'message': {'role': 'assistant', 'content': 'Hello there!'},
            'done': true,
            'done_reason': 'stop',
          },
        ),
      );
      final model = plugin.resolve('model', 'llama3.2')!;

      final result = await model.call(
        ModelRequest(
          messages: [
            Message(
              role: Role.user,
              content: [TextPart(text: 'hi')],
            ),
          ],
        ),
      );

      final response = result as ModelResponse;
      expect(response.message!.text, 'Hello there!');
      expect(response.finishReason, FinishReason.stop);
    });

    test('sends options, stop list, and format on the request', () async {
      final captured = <http.Request>[];
      final plugin = _plugin(
        _mockClient(
          captured: captured,
          chatBody: {
            'message': {'role': 'assistant', 'content': 'ok'},
            'done': true,
            'done_reason': 'stop',
          },
        ),
      );
      final model = plugin.resolve('model', 'llama3.2')!;

      await model.call(
        ModelRequest(
          messages: [
            Message(
              role: Role.user,
              content: [TextPart(text: 'hi')],
            ),
          ],
          config: {
            'temperature': 0.5,
            'numCtx': 4096,
            'stop': ['END', 'STOP'],
          },
          output: OutputConfig(format: 'json'),
        ),
      );

      final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
      final options = body['options'] as Map<String, dynamic>;
      expect(options['temperature'], 0.5);
      expect(options['num_ctx'], 4096);
      // Stop sequences are a real list, not a joined string.
      expect(options['stop'], ['END', 'STOP']);
      expect(body['format'], 'json');
    });

    test('maps tool calls in the response', () async {
      final plugin = _plugin(
        _mockClient(
          chatBody: {
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'function': {
                    'name': 'getWeather',
                    'arguments': {'city': 'NY'},
                  },
                },
              ],
            },
            'done': true,
            'done_reason': 'stop',
          },
        ),
      );
      final model = plugin.resolve('model', 'llama3.2')!;

      final result =
          await model.call(
                ModelRequest(
                  messages: [
                    Message(
                      role: Role.user,
                      content: [TextPart(text: 'hi')],
                    ),
                  ],
                ),
              )
              as ModelResponse;

      final part = result.message!.content.single;
      expect(part.isToolRequest, isTrue);
      expect(part.toolRequest!.name, 'getWeather');
    });
  });

  group('embedder', () {
    test('returns embedding vectors', () async {
      final plugin = _plugin(
        _mockClient(
          embedBody: {
            'model': 'nomic-embed-text',
            'embeddings': [
              [0.1, 0.2, 0.3],
            ],
          },
        ),
      );
      final embedder = plugin.resolve('embedder', 'nomic-embed-text')!;

      final result =
          await embedder.call(
                EmbedRequest(
                  input: [
                    DocumentData(content: [TextPart(text: 'hello')]),
                  ],
                ),
              )
              as EmbedResponse;

      expect(result.embeddings.single.embedding, [0.1, 0.2, 0.3]);
    });
  });
}
