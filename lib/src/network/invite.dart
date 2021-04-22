import 'dart:async';
import 'dart:convert';

import 'package:free_chat/src/config.dart';
import 'package:free_chat/src/fcp/fcp.dart';
import 'package:free_chat/src/model.dart';
import 'package:free_chat/src/model/initial_invite_response.dart';
import 'package:free_chat/src/network/database_handler.dart';
import 'package:free_chat/src/network/networking.dart';
import 'package:free_chat/src/utils/logger.dart';


class Invite {

  static final Logger _logger = Logger(Invite().toString());

  static final Invite _invite = Invite._internal();

  final Networking _networking = Networking();

  final DatabaseHandler _databaseHandler = DatabaseHandler();

  factory Invite() {
    return _invite;
  }

  ChatClient _client;

  Invite._internal();

  void setClient(ChatClient client) {
    this._client = client;
  }

  Future<InitialInvite> createInitialInvitation(String identifier) async {

    var _sskKey = await _networking.getKeys();

    String _unique = Uuid().v4();

    String _requestUri = _sskKey.getAsUskRequestUri() + "chat/0";

    String _insertUri = _sskKey.getAsUskInsertUri() + "chat/0";

    String _listeningUri = "KSK@" + _unique  + "-handshake-";

    String _name = Config.clientName;

    String _encrypt = Uuid().v4();

    String _sharedId = Uuid().v4();

    InitialInvite initialInvite = new InitialInvite(_requestUri, _listeningUri, _name, _encrypt, _insertUri, _sharedId);

    Chat chat = Chat(_insertUri, "", _encrypt, [], _name, _sharedId);

    _logger.i("Created Initial invite: ${initialInvite.toString()}");

    _logger.i("Created Initial chat: $chat");

    _networking.sendMessage(_insertUri, chat.toString(), identifier);

    return initialInvite;
  }

  Future<bool> handleInvitation(InitialInvite initialInvite, String identifierHandshake, String identifierInsert, String identifierRequest) async {
    var _sskKey = await _networking.getKeys();

    var _insertUri = _sskKey.getAsUskInsertUri() + "chat/0/";

    var _requestUri = _sskKey.getAsUskRequestUri() + "chat/0/";

    String _unique = Uuid().v4();

    _logger.i("InitialInvite12 => $initialInvite");

    Chat chat = Chat(_insertUri, initialInvite.getRequestUri(), initialInvite.encryptKey, [], initialInvite.getName(), initialInvite.sharedId);

    InitialInviteResponse initialInviteResponse = InitialInviteResponse(_requestUri, Config.clientName);

    List req = [];

    for(int i = 3; i < 20; i++) {
      _networking.sendMessage(
          "${initialInvite.getHandshakeUri()}$i", initialInviteResponse.toString(),
          "$identifierHandshake-$i ", prioClass: 3);
    }


    try {
      await Future.wait(
        [
          _networking.sendMessage(_insertUri, chat.toString(), identifierInsert),
          _networking.sendMessage("${initialInvite.getHandshakeUri()}0", initialInviteResponse.toString(),"$identifierHandshake-0"),
          _networking.sendMessage("${initialInvite.getHandshakeUri()}1", initialInviteResponse.toString(),"$identifierHandshake-1"),
          _networking.sendMessage("${initialInvite.getHandshakeUri()}2", initialInviteResponse.toString(),"$identifierHandshake-2"),
        ]
      );

    }
    catch(e) {
      _logger.e("Upload failed");
      return false;
    }
    FcpMessage fcpChat;
    try {
     fcpChat = await _networking.getMessage(initialInvite.getRequestUri(), identifierRequest);

    }
    catch(e) {
      _logger.e(e.toString());
      return false;
    }
    _logger.i(fcpChat.toString());


    FcpSubscribeUSK fcpSubscribeUSK = FcpSubscribeUSK(initialInvite.getRequestUri(), Uuid().v4());

    _networking.fcpConnection.sendFcpMessage(fcpSubscribeUSK);

    ChatDTO dto = ChatDTO.fromChat(chat);

    _logger.i("dto => $dto");

    await _databaseHandler.upsertChat(dto);
    return true;
  }

  Future<bool> inviteAccepted(InitialInvite initialInvite) async {
    FcpMessage handshakeMessage;
    FcpMessage fcpChat;

    try {
      for(var i = 0; i < 20; i++) {
        handshakeMessage = await _networking.getMessage("${initialInvite.getHandshakeUri()}$i", Uuid().v4());
        if(handshakeMessage != null) break;
        await Future.delayed(Duration(seconds: 20), () => _logger.i("Trying again"));
      }
      fcpChat = await _networking.getMessage(initialInvite.getRequestUri(), Uuid().v4());
    }
    catch(e) {
      _logger.e(e.toString());
      return false;
    }

    _logger.i(fcpChat.toString());

    _logger.i("HandshakeMessage: ${handshakeMessage.toString()}");

    String cleanedData = handshakeMessage.data.split("}")[0] + "}";

    InitialInviteResponse response = InitialInviteResponse.fromJson(jsonDecode(cleanedData));

    ChatDTO chatDTO = ChatDTO();
    chatDTO.insertUri = initialInvite.insertUri;
    chatDTO.encryptKey = initialInvite.encryptKey;
    chatDTO.requestUri = response.requestUri;
    chatDTO.name = response.name;
    chatDTO.sharedId = initialInvite.sharedId;

    _logger.i(chatDTO.toMap().toString());


    FcpSubscribeUSK fcpSubscribeUSK = FcpSubscribeUSK(response.requestUri, Uuid().v4());

    _networking.fcpConnection.sendFcpMessage(fcpSubscribeUSK);

    await _databaseHandler.upsertChat(chatDTO);

    return true;

  }
}
