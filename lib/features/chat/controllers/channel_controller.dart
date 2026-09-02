import 'package:get/get.dart';
import '../../../core/models/channel.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../features/auth/controllers/auth_controller.dart';

class ChannelController extends GetxController {
  final _api    = Get.find<ApiService>();
  final _socket = Get.find<SocketService>();

  final _all      = <Channel>[].obs;
  final isLoading = true.obs;

  List<Channel> get rooms => _all.where((c) => !c.isDirect).toList();
  List<Channel> get dms   => _all.where((c) => c.isDirect).toList();

  @override
  void onInit() {
    super.onInit();
    loadChannels();
    _socket.connect();
  }

  /// Sends a hospitality request message to the office boy (خالد).
  Future<bool> sendHospitalityRequest(String order) async {
    final auth = Get.find<AuthController>();
    final result = await _api.post(
      '/channels/dm_ob/messages',
      {'text': '🫖 طلب ضيافة من ${auth.currentUser.value?.name ?? ''}: $order'},
      (_) {},
    );
    return result is ApiSuccess;
  }

  Future<void> loadChannels() async {
    isLoading.value = true;
    final result = await _api.get(
      '/channels',
      (j) => (j['channels'] as List)
          .map((c) => Channel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
    if (result is ApiSuccess<List<Channel>>) {
      _all.assignAll(result.data);
    }
    isLoading.value = false;
  }
}
