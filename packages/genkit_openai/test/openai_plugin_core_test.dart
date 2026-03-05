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
import 'package:test/test.dart';

void main() {
  group('OpenAIOptions', () {
    test('parses temperature', () {
      final options = OpenAIOptions.$schema.parse({'temperature': 0.7});
      expect(options.temperature, 0.7);
    });

    test('parses maxTokens', () {
      final options = OpenAIOptions.$schema.parse({'maxTokens': 100});
      expect(options.maxTokens, 100);
    });

    test('parses jsonMode', () {
      final options = OpenAIOptions.$schema.parse({'jsonMode': true});
      expect(options.jsonMode, true);
    });

    test('parses stop sequences', () {
      final options = OpenAIOptions.$schema.parse({
        'stop': ['stop1', 'stop2'],
      });
      expect(options.stop, ['stop1', 'stop2']);
    });

    test('creates default options', () {
      final options = OpenAIOptions();
      expect(options.temperature, isNull);
      expect(options.maxTokens, isNull);
    });
  });

  group('OpenAIVertexConfig', () {
    test('builds ADC helper config', () {
      final config = OpenAIVertexConfig.adc(projectId: 'my-project');

      expect(config.projectId, 'my-project');
      expect(config.location, 'global');
      expect(config.endpointId, 'openapi');
      expect(config.accessToken, isNull);
      expect(config.accessTokenProvider, isNotNull);
    });

    test('builds service account helper config', () {
      final config = OpenAIVertexConfig.serviceAccount(
        credentialsJson: {
          'type': 'service_account',
          'project_id': 'my-project',
          'client_email': 'svc@project.iam.gserviceaccount.com',
          'client_id': '1234567890',
          'private_key':
              '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n',
        },
      );

      expect(config.projectId, isNull);
      expect(config.resolveProjectId(), 'my-project');
      expect(config.location, 'global');
      expect(config.endpointId, 'openapi');
      expect(config.accessToken, isNull);
      expect(config.accessTokenProvider, isNotNull);
    });

    test('prefers explicit projectId over service account project_id', () {
      final config = OpenAIVertexConfig.serviceAccount(
        projectId: 'my-explicit-project',
        credentialsJson: {
          'type': 'service_account',
          'project_id': 'my-inferred-project',
          'client_email': 'svc@project.iam.gserviceaccount.com',
          'client_id': '1234567890',
          'private_key':
              '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n',
        },
      );

      expect(config.resolveProjectId(), 'my-explicit-project');
    });

    test('resolves global base URL', () {
      final config = OpenAIVertexConfig(
        projectId: 'my-project',
        accessToken: 'ya29.token',
      );

      expect(
        config.resolveBaseUrl(),
        'https://aiplatform.googleapis.com/v1/projects/my-project/locations/global/endpoints/openapi',
      );
    });

    test('resolves regional base URL', () {
      final config = OpenAIVertexConfig(
        projectId: 'my-project',
        location: 'us-east5',
        endpointId: 'openapi',
        accessToken: 'ya29.token',
      );

      expect(
        config.resolveBaseUrl(),
        'https://us-east5-aiplatform.googleapis.com/v1/projects/my-project/locations/us-east5/endpoints/openapi',
      );
    });

    test('resolves access token from provider', () async {
      final config = OpenAIVertexConfig(
        projectId: 'my-project',
        accessTokenProvider: () async => 'ya29.from-provider',
      );

      expect(await config.resolveAccessToken(), 'ya29.from-provider');
    });

    test('rejects invalid config with both token sources', () {
      expect(
        () => OpenAIVertexConfig(
          projectId: 'my-project',
          accessToken: 'ya29.token',
          accessTokenProvider: () async => 'ya29.provider',
        ).validate(),
        throwsA(
          isA<GenkitException>()
              .having((e) => e.status, 'status', StatusCodes.INVALID_ARGUMENT)
              .having(
                (e) => e.message,
                'message',
                'Provide either accessToken or accessTokenProvider, not both.',
              ),
        ),
      );
    });

    test('rejects invalid location', () {
      expect(
        () => OpenAIVertexConfig(
          projectId: 'my-project',
          location: 'evil.com/path?',
          accessToken: 'ya29.token',
        ).validate(),
        throwsA(
          isA<GenkitException>()
              .having((e) => e.status, 'status', StatusCodes.INVALID_ARGUMENT)
              .having(
                (e) => e.message,
                'message',
                'Vertex OpenAI location may only contain letters, numbers, and hyphens.',
              ),
        ),
      );
    });

    test('rejects empty projectId', () {
      expect(
        () => OpenAIVertexConfig(
          projectId: '   ',
          accessToken: 'ya29.token',
        ).validate(),
        throwsA(
          isA<GenkitException>()
              .having((e) => e.status, 'status', StatusCodes.INVALID_ARGUMENT)
              .having(
                (e) => e.message,
                'message',
                'Vertex OpenAI requires a non-empty projectId.',
              ),
        ),
      );
    });

    test('rejects empty endpointId', () {
      expect(
        () => OpenAIVertexConfig(
          projectId: 'my-project',
          endpointId: '   ',
          accessToken: 'ya29.token',
        ).validate(),
        throwsA(
          isA<GenkitException>()
              .having((e) => e.status, 'status', StatusCodes.INVALID_ARGUMENT)
              .having(
                (e) => e.message,
                'message',
                'Vertex OpenAI requires a non-empty endpointId.',
              ),
        ),
      );
    });

    test('rejects invalid endpointId', () {
      expect(
        () => OpenAIVertexConfig(
          projectId: 'my-project',
          endpointId: 'openapi/path',
          accessToken: 'ya29.token',
        ).validate(),
        throwsA(
          isA<GenkitException>()
              .having((e) => e.status, 'status', StatusCodes.INVALID_ARGUMENT)
              .having(
                (e) => e.message,
                'message',
                'Vertex OpenAI endpointId may only contain letters, numbers, underscores, and hyphens.',
              ),
        ),
      );
    });
  });

  group('Plugin Handle', () {
    test('creates plugin instance', () {
      final plugin = openAI(apiKey: 'test-key');
      expect(plugin, isNotNull);
    });

    test('rejects conflicting apiKey + vertex configuration', () {
      expect(
        () => openAI(
          apiKey: 'openai-key',
          vertex: OpenAIVertexConfig(
            projectId: 'my-project',
            accessToken: 'ya29.token',
          ),
        ),
        throwsA(
          isA<GenkitException>()
              .having((e) => e.status, 'status', StatusCodes.INVALID_ARGUMENT)
              .having(
                (e) => e.message,
                'message',
                'Provide either apiKey or vertex configuration, not both.',
              ),
        ),
      );
    });

    test('rejects conflicting baseUrl + vertex configuration', () {
      expect(
        () => openAI(
          baseUrl: 'https://example.com/openai/v1',
          vertex: OpenAIVertexConfig(
            projectId: 'my-project',
            accessToken: 'ya29.token',
          ),
        ),
        throwsA(
          isA<GenkitException>()
              .having((e) => e.status, 'status', StatusCodes.INVALID_ARGUMENT)
              .having(
                (e) => e.message,
                'message',
                'Provide either baseUrl or vertex configuration, not both.',
              ),
        ),
      );
    });

    test('creates model reference', () {
      final ref = openAI.model('gpt-4o');
      expect(ref.name, 'openai/gpt-4o');
    });
  });

  group('CustomModelDefinition', () {
    test('creates with name and info', () {
      final def = CustomModelDefinition(
        name: 'custom-model',
        info: ModelInfo(label: 'Custom Model', supports: {'multiturn': true}),
      );
      expect(def.name, 'custom-model');
      expect(def.info?.label, 'Custom Model');
    });
  });
}
