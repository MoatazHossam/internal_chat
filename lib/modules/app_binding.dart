import 'package:get/get.dart';

import '../repositories/authentication_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/file_repository.dart';
import '../repositories/mock_repositories.dart';
import '../services/contracts.dart';
import '../services/mock_services.dart';
import '../services/token_storage_service.dart';

class AppBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<TokenStorageService>(
      PlatformTokenStorageService(),
      permanent: true,
    );

    Get.put<LocalChatStorageService>(
      MemoryLocalChatStorageService(),
      permanent: true,
    );

    Get.put<OutboxService>(
      MemoryOutboxService(),
      permanent: true,
    );

    Get.put<ConnectivityService>(
      MockConnectivityService(),
      permanent: true,
    );

    Get.put<RealtimeService>(
      MockRealtimeService(),
      permanent: true,
    );

    Get.put<AuthenticationRepository>(
      MockAuthenticationRepository(Get.find<TokenStorageService>()),
      permanent: true,
    );

    Get.put<ChatRepository>(
      MockChatRepository(
        outbox: Get.find<OutboxService>(),
        connectivity: Get.find<ConnectivityService>(),
        realtime: Get.find<RealtimeService>(),
      ),
      permanent: true,
    );

    Get.put<FileRepository>(
      MockFileRepository(),
      permanent: true,
    );
  }
}
