-module(fly_mod_offline_push).

-behavior(gen_server).

-behaviour(gen_mod).

-define(TIMEOUT_MPNS_ON_ERROR, 2000).

-define(TIMEOUT, 10000).

-define(BASEURL, "https://fcm.googleapis.com/fcm/send").

-define(PROCNAME, fly_mod_offline_push).
-define(EJABBERD_DEBUG, true).

%% gen_mod callbacks
-export([send_offline_message/1, groupcreationfunction/9, queryexecfunction/5, queryfunction/6, groupcreationfunction/10, has_more_resources/2, send_bulk_group_push/7, send_own_offline_message/3, start/2, start_link/2, depends/2,
  stop/1]).

-export([code_change/3, handle_call/3, handle_cast/2, handle_info/2, init/1, mod_opt_type/1, terminate/2, mod_options/1]).

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").

-include_lib("amqp_client/include/amqp_client.hrl").


-record(state,

{host = <<"">>, rabbitmq_host = <<"">>, rabbitmq_exchange = <<"">>, rabbitmq_username = <<"">>, rabbitmq_password = <<"">>, rabbitmq_connection = <<"">>}).


%%%===================================================================
%%% API
%%%===================================================================

start_link(Host, Opts) ->
  Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
  gen_server:start_link({local, Proc}, ?MODULE,
    [Host, Opts], []).

start(Host, Opts) ->
  inets:start(),
  crypto:start(),
  ssl:start(),
  case ets:info(rabbit_mq_connection, size) of
    undefined ->
  ets:new(rabbit_mq_connection,[set, public, named_table ,{write_concurrency, false}, {read_concurrency, true}]);
  _ ->
  ok
  end,
  [_Node, _] = binary:split(atom_to_binary(node(),utf8), <<"@">>),
  Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
  ejabberd_hooks:add(offline_message_hook, Host, ?MODULE,
    send_offline_message, 40),
  ChildSpec = {Proc, {?MODULE, start_link, [Host, Opts]},
    transient, 1000, worker, [?MODULE]},
  supervisor:start_child(ejabberd_backend_sup, ChildSpec).

stop(Host) ->
  Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
  ejabberd_hooks:delete(offline_message_hook, Host,
    ?MODULE, send_offline_message, 40),
  catch gen_server:call(Proc, stop),
  supervisor:terminate_child(ejabberd_backend_sup, Proc),
  supervisor:delete_child(ejabberd_backend_sup, Proc),
  ok.

%%====================================================================
%% gen_server callbacks
%%====================================================================
init([Host, _Opts]) ->
  case create_rabbit_mq_create_connection(Host) of
    [Channel,RabbitMQExchange] ->
      [[RabbitMQConnectionPid]] = ets:match(rabbit_mq_connection, {pid, '$1'}),
      ?INFO_MSG("RabbitMQConnectionPid: ~p",[RabbitMQConnectionPid]),
      {ok,
        #state{host = Host, rabbitmq_connection = Channel, rabbitmq_exchange = RabbitMQExchange}};
    _ERROR ->
      ?ERROR_MSG("RabbitMQ Server Connection failed: ~p",[_ERROR])
  end.

%%=========================================================================
%% Function: terminate(Reason, State) -> void()
%% Description: This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any necessary
%% cleaning up. When it returns, the gen_server terminates with Reason.
%% The return value is ignored.
%%=========================================================================
terminate(_Reason, State) ->
  Host = State#state.host,
  ejabberd_hooks:delete(offline_message_hook, Host,
    ?MODULE, send_offline_message, 1),
  gen_iq_handler:remove_iq_handler(ejabberd_sm, Host,
    ?NS_FLEX_OFFLINE),
  ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%===============================================================================
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%==============================================================================
handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

%%====================================================================================
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%=========================================================================
handle_cast({pushnotification, <<"chat">>,
  {Sender, Recipient, ChatType, SubEl, Packet}},
    State) ->
      case catch fly_mod_utils:check_chatmuted(Recipient#jid.server, Recipient#jid.luser,
      Sender#jid.luser)
    of
      {selected, _, []} ->
        Call = true;
      {selected, _, [[_T]]} ->
      if ChatType =:= <<"mediacall">> ->
        Call = true;
        true ->
          Call = false,
        ?INFO_MSG("push muted ~p", [Recipient#jid.luser]),
        ok
      end
      end,
      if Call =:= true ->
        case ChatType of
          <<"meeting_reminder">> ->
            ?INFO_MSG("handle_cast meeting_reminder push to=~ts stanza_id=~ts",
                      [jid:to_string(Recipient), fxml:get_attr_s(<<"id">>, Packet#xmlel.attrs)]);
          _ ->
            ok
        end,
        case catch send_push_notifications(Sender, Recipient, ChatType, SubEl, Packet, State) of
          {ok, _Result} -> ok;
          {error, Error} ->
            ?INFO_MSG("push error ~p", [Error]), ok;
          _Exception ->
            ?INFO_MSG("push status ~p", [_Exception]), ok
        end;
      true ->
        ?INFO_MSG("push muted ~p", [Recipient#jid.luser]),
        ok
        end,
  {noreply, State};
handle_cast({pushnotification, <<"normal">>, {Sender, Recipient, ChatType, SubEl, Packet}}, State) ->
	case catch fly_mod_utils:check_chatmuted(Recipient#jid.server, Recipient#jid.luser, Sender#jid.luser) of
		{selected, _, []} ->
			Call = true;
		{selected, _, [[_T]]} ->
			if ChatType =:= <<"mediacall">> ->
				   Call = true;
			   true ->
				   Call = false,
				   ?INFO_MSG("push muted ~p", [Recipient#jid.luser]),
				   ok
			end
	end,
	if Call =:= true ->
		   case catch send_push_notifications(Sender, Recipient, ChatType, SubEl, Packet, State) of
			   {ok, _Result} -> ok;
			   {error, Error} ->
				   ?INFO_MSG("push error ~p", [Error]), ok;
			   _Exception ->
				   ?INFO_MSG("push status ~p", [_Exception]), ok
		   end;
	   true ->
		   ?INFO_MSG("push muted ~p", [Recipient#jid.luser]),
		   ok
	end,
  {noreply, State};
handle_cast({queryexecution, <<"clear_all">>,
  {From, Last_Msg_Id, Delete_Type, XMLBody}},
    State) ->

  clear_all_query(From, Last_Msg_Id, Delete_Type, XMLBody, State),

  {noreply, State};
handle_cast({queryexecution, <<"call_log">>,
  {From, Chat_Type, Delete_Type, XMLBody}},
    State) ->
  clear_call_log(From, Chat_Type, Delete_Type, XMLBody, State),
  {noreply, State};
handle_cast({groupcreationexecutions, <<"group_creation">>,
  {From, Participants, Channel, GroupJID, SubEl, IQ, MessageId1,CustomAttributes}},State) ->
  group_create_query(From, Participants, Channel, GroupJID, SubEl, IQ, MessageId1,CustomAttributes, State),

  {noreply, State};
handle_cast({own_pushnotification, <<"chat">>,
  {Sender, Recipient, ChatType, SubEl, Packet}},
    State) ->

  case catch send_own_push_notifications(Sender, Recipient,
    ChatType, SubEl, Packet, State)
  of
    {ok, _Result} -> ok;
    {error, _Error} ->
      ok;
    _Exception ->
      ok
  end,
  {noreply, State};
handle_cast({own_group_pushnotification, <<"normal">>,
  {FromUser, ToUser, ChatType, SubEl, Packet, GroupName}},
    State) ->
  case catch send_own_group_push_notifications(FromUser,
    ToUser, ChatType, SubEl, Packet,
    GroupName, State)
  of
    {ok, _Result} -> ok;
    {error, _Error} ->
      ok;
    _Exception ->
      ok
  end,
  {noreply, State};
handle_cast({send_bulk_group_push_notification, <<"normal">>,
  {FromUser, Server, MessageContent, Members, Node, Stanza, Type}},
    State) ->
  case catch send_bulk_group_push_notification( FromUser, Server, MessageContent, Members, Node, Stanza,Type,
    State)
  of
    {ok, _Result} -> ok;
    {error, _Error} ->
      ok;
    _Exception ->
      ok
  end,
  {noreply, State};
handle_cast(_Data, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

push(Proc, Type, Sender, Recipient, ChatType, SubEl,
    Packet) ->
  gen_server:cast(Proc,
    {pushnotification, Type,
      {Sender, Recipient, ChatType, SubEl, Packet}}).

ownpush(Proc, Type, Sender, Recipient, ChatType, SubEl,
    Packet) ->
  gen_server:cast(Proc,
    {own_pushnotification, Type,
      {Sender, Recipient, ChatType, SubEl, Packet}}).

owngroup_push(Proc, Type, Sender, Recipient, ChatType,
    SubEl, Packet, GroupName) ->
  gen_server:cast(Proc,
    {own_group_pushnotification, Type,
      {Sender, Recipient, ChatType, SubEl, Packet,
        GroupName}}).

send_bulk_group_push(From, Server,MessageContent, Members, Node, Stanza, Type) ->
  Proc = gen_mod:get_module_proc(Server,
    ?PROCNAME),
  gen_server:cast(Proc,
    {send_bulk_group_push_notification, <<"normal">>,
      {From, Server, MessageContent, Members, Node, Stanza, Type}}).

queryfunction(Proc, Type, From, Chat_Type, Delete_Type, XMLBody) ->

  gen_server:cast(Proc,
    {queryexecution, Type,
      { From, Chat_Type, Delete_Type,XMLBody}}).

groupcreationfunction(Proc, Type, From, Participants, Channel, GroupJID, SubEl, IQ, MessageId1,CustomAttributes) ->
  gen_server:cast(Proc,
    {groupcreationexecutions, Type,
      {From, Participants, Channel, GroupJID, SubEl, IQ, MessageId1,CustomAttributes}}).

%% Hook lisenter to for offline message hook
%%
%% @param record Sender
%% @param record Recipient
%% @param record Packet
%% @return atom
%%send_offline_message(#message{from = Sender,to = Recipient,type = ChatType} = Pac) ->
send_offline_message(({Action, #message{from = Sender, to = Recipient, type = ChatType, id = MsgId} = Pkt} = Acc)) ->
  Packet = xmpp:encode(Pkt),
  SubEl = fxml:get_subtag_cdata(Packet, <<"body">>),
  Server = gen_mod:get_module_proc(Recipient#jid.lserver,?PROCNAME),
  PushSource = case Action of
    #jid{} -> <<"offline_message_hook">>;
    _ when is_binary(Action) -> <<"direct_call">>;
    _ -> <<"unknown">>
  end,
  MeetingInfo =
    case fxml:get_subtag_with_xmlns(Packet, <<"meeting">>, <<"urn:xmpp:receipts">>) of
      false ->
        <<"none">>;
      #xmlel{attrs = MAttrs} ->
        fxml:get_attr_s(<<"status">>, MAttrs)
    end,
  ?INFO_MSG("send_offline_message source=~ts from=~ts to=~ts msg_id=~ts chat_type=~p meeting_status=~ts action=~p",
            [PushSource, jid:to_string(Sender), jid:to_string(Recipient), MsgId, ChatType, MeetingInfo, Action]),
  if ChatType == chat ->
    case SubEl of
      <<"">> ->
        Call = fxml:get_subtag_with_xmlns(Packet, <<"call">>,
          <<"urn:xmpp:call">>),
        if Call =:= false -> ok;
          true ->
            {value, CallStatus} = fxml:get_tag_attr(<<"call_status">>, Call),
            if CallStatus =:= <<"CALLING">> ->
              push(Server, <<"chat">>, Sender, Recipient,
                <<"call">>, SubEl, Packet);
              CallStatus =:= <<"ENDED">> ->
                push(Server, <<"chat">>, Sender, Recipient,
                  <<"call">>, SubEl, Packet);
              CallStatus =:= <<"RECONNECT">> ->
                push(Server, <<"chat">>, Sender, Recipient,
                  <<"call">>, SubEl, Packet);
              true -> ok
            end
        end,
        ReCall = fxml:get_subtag_with_xmlns(Packet, <<"recall">>,
          <<"urn:xmpp:receipts">>),
        if ReCall =:= false -> ok;
          true ->
            push(Server, <<"chat">>, Sender, Recipient,
              <<"recall">>, SubEl, Packet)
        end,
        Seen = fxml:get_subtag_with_xmlns(Packet, <<"seen">>,
          <<"urn:xmpp:receipts">>),
        if Seen =:= false -> ok;
          true ->
            push(Server, <<"chat">>, Sender, Recipient,
              <<"seen">>, SubEl, Packet)
        end,
        Reaction = fxml:get_subtag_with_xmlns(Packet, <<"reaction">>,
        <<"urn:xmpp:receipts">>),
        if Reaction =:= false ->
            ok;
          true ->
            push(Server, <<"chat">>, Sender, Recipient, <<"reaction">>, SubEl, Packet)
        end,
        Poll = fxml:get_subtag_with_xmlns(Packet, <<"poll">>,
          <<"urn:xmpp:receipts">>),
        if Poll =:= false -> ok;
          true ->
            push(Server, <<"chat">>, Sender, Recipient,
              <<"poll">>, SubEl, Packet)
        end,
        Ptt = fxml:get_subtag_with_xmlns(Packet, <<"ptt">>,
          <<"urn:xmpp:receipts">>),
        if Ptt =:= false ->
          ok;
          true ->
            push(Server, <<"chat">>, Sender, Recipient,
              <<"ptt">>, SubEl, Packet)
        end,
        AdminBlock = fxml:get_subtag_with_xmlns(Packet, <<"admin_block">>,  <<"urn:xmpp:receipts">>),
      if AdminBlock =:= false ->
        ok;
        true ->
          push(Server, <<"chat">>, Sender, Recipient,
            <<"adminblock">>, SubEl, Packet)
      end,
      MediaCall = fxml:get_subtag_with_xmlns(Packet, <<"mediacall">>,  <<"urn:xmpp:call">>),
      if MediaCall =:= false ->
        ok;
        true ->
          push(Server, <<"chat">>, Sender, Recipient,
            <<"mediacall">>, SubEl, Packet)
      end,
      Meeting = fxml:get_subtag_with_xmlns(Packet, <<"meeting">>,
        <<"urn:xmpp:receipts">>),
      if Meeting =:= false ->
        ok;
        true ->
          MeetingMsgId = fxml:get_attr_s(<<"message_id">>, Meeting#xmlel.attrs),
          MeetingStatus = fxml:get_attr_s(<<"status">>, Meeting#xmlel.attrs),
          ?INFO_MSG("send_offline_message meeting push source=~ts to=~ts stanza_id=~ts meeting_msg_id=~ts status=~ts",
                    [PushSource, jid:to_string(Recipient), MsgId, MeetingMsgId, MeetingStatus]),
          push(Server, <<"chat">>, Sender, Recipient,
            <<"meeting_reminder">>, SubEl, Packet)
      end;
      _ ->
        Call = fxml:get_subtag_with_xmlns(Packet, <<"call">>,
          <<"urn:xmpp:call">>),
        if Call =:= false ->
          push(Server, <<"chat">>, Sender, Recipient, <<"chat">>,
            SubEl, Packet);
          true ->
            {value, CallStatus} = fxml:get_tag_attr(<<"call_status">>, Call),
            if CallStatus =:= <<"CALLING">> ->
              push(Server, <<"chat">>, Sender, Recipient,
                <<"call">>, SubEl, Packet);
              CallStatus =:= <<"ENDED">> ->
                push(Server, <<"chat">>, Sender, Recipient,
                  <<"call">>, SubEl, Packet);
              CallStatus =:= <<"RECONNECT">> ->
                push(Server, <<"chat">>, Sender, Recipient,
                  <<"call">>, SubEl, Packet);
              true -> ok
            end
        end,
        ReCall = fxml:get_subtag_with_xmlns(Packet, <<"recall">>,
          <<"urn:xmpp:receipts">>),
        if ReCall =:= false -> ok;
          true ->
            push(Server, <<"chat">>, Sender, Recipient,
              <<"recall">>, SubEl, Packet)
        end
    end;
  ChatType == normal ->
    ?LOG_INFO("ChatType is normal, check for reaction or group_reaction and send push accordingly"),
    case SubEl of
      <<"">> ->
        Reaction = fxml:get_subtag_with_xmlns(Packet, <<"reaction">>,
        <<"urn:xmpp:receipts">>),
        if Reaction =:= false ->
            ok;
          true ->
            push(Server, <<"normal">>, Sender, Recipient, <<"group_reaction">>, SubEl, Packet)
        end;
      _ -> 
        ok
    end;
    true -> ok
  end,
  Acc.

clear_all_query(From, Last_Msg_Id, Delete_Type, XmlBody, State) ->

    fly_mod_utils:clear_all(From, Delete_Type),
    #jid{luser = User, lserver = Server, lresource = _Resource} = From,
      case fly_mod_utils:get_mobile_user_message(User, Server) of
        true ->

          mod_offline:store_packet({From,xmpp:decode(XmlBody)});
        false ->

          ok
  end.

clear_call_log(From, Chat_Type, RoomId , XmlBody, State) ->

    fly_mod_utils:clear_call_log(From,RoomId),
    #jid{luser = User, lserver = Server, lresource = _Resource} = From,
      case fly_mod_utils:get_mobile_user_message(User, Server) of
        true ->

          mod_offline:store_packet({From,xmpp:decode(XmlBody)});
        false ->

          ok
      end.

get_string() ->
  R = crypto:rand_uniform(0, 16#10000000000000000),
  integer_to_binary(R).

  group_create_query(From, Participants, Channel, GroupJID, SubEl, IQ, MessageId1,CustomAttributes, State)->

  #jid{user = FUser, lserver = FServer} = From,
  Profile = fxml:get_subtag(SubEl, <<"profile">>),
  VCard = fxml:get_subtag(Profile, <<"vCard">>),
  NickName = fxml:get_subtag(VCard, <<"nickName">>),
  GroupName = fxml:get_tag_cdata(NickName),
  fly_mod_utils:group_notify_message(From, From, FUser, Channel, <<"1">>, <<"create_group">>, MessageId1,<<"">>,<<"">>),
  % Adds Participant
  lists:foreach(fun(Participant) ->
    ParticipantData = fxml:get_tag_cdata(Participant),
    FromJID = jid:make(fly_mod_utils:get_user_from_string_jid(ParticipantData),FServer,<<"">>),
    MessageID = <<(get_string()) / binary>>,
    GroupCreateID = <<(get_string()) / binary>>,
    #jid{user = PUser} = FromJID,
    fly_mod_utils:group_notify_message(From, FromJID, PUser, Channel, <<"1">>, <<"create_group">>, GroupCreateID,<<"">>,<<"">>),
    timer:sleep(50),
    mod_mix_pam:process_iq(#iq{from = FromJID, to = FromJID,type = set,id = MessageID,
      sub_els = [#mix_client_join{channel = GroupJID,  xmlns = <<"urn:xmpp:mix:pam:0">>,affiliation = <<"n">>,
      join = #mix_join{owner = jid:to_string(From),message_id = MessageID, nick = GroupName, group_create = <<"y">>, custom_attributes = #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}, xmlns = <<"urn:xmpp:mix:core:0">>, subscribe = [<<"urn:xmpp:mix:nodes:messages">>,<<"urn:xmpp:mix:nodes:presence">>,
      <<"urn:xmpp:mix:nodes:participants">>,<<"urn:xmpp:mix:nodes:info">>,<<"urn:xmpp:mix:nodes:config">>]}}]}),
    fly_mix_group_chat:update_group_status(From, GroupJID, SubEl, IQ, <<"2">>, Participant, MessageID)
  end, Participants#xmlel.children).

%% send_push_notifications
%%
%% @param record Sender
%% @param record Recipient
%% @param binary ChatType
%% @param record SubEl
%% @return atom
send_push_notifications(Sender, Recipient, ChatType, SubEl, Packet, State) ->
  MsgId = fxml:get_attr_s(<<"id">>,Packet#xmlel.attrs),
  if ChatType =:= <<"meeting_reminder">> ->
    ?INFO_MSG("send_push_notifications entry meeting_reminder to=~ts from=~ts stanza_id=~ts",
              [jid:to_string(Recipient), jid:to_string(Sender), MsgId]);
    true -> ok
  end,
  Rs = if ChatType == <<"meeting_reminder">> -> "";
    true -> has_more_resources(Recipient#jid.luser,Recipient#jid.server)
  end,

  CallMode =
    case lists:keyfind(<<"mediacall">>, #xmlel.name, Packet#xmlel.children) of
        #xmlel{attrs = Attrs} ->
            fxml:get_attr_s(<<"call_mode">>, Attrs);
        false ->
            <<"">>
    end,
  Ccodes = gen_mod:get_module_opt(Recipient#jid.server, fly_mod_offline_push, restricted_country_code), 
  ?LOG_INFO("Ccodes: ~p", [Ccodes]),

  DeviceDetails = 
  if CallMode =:= <<"onetoone">> ->
    fly_mod_utils:get_user_device_exclude_restricted_countries(Recipient#jid.server, Recipient#jid.luser, Rs, fly_mod_media:sql_in(Ccodes));
    true ->
      fly_mod_utils:get_user_device(Recipient#jid.server, Recipient#jid.luser, Rs, ChatType)
  end,

  ?LOG_INFO("DeviceDetails: ~p", [DeviceDetails]),

  case catch DeviceDetails of
    {selected, _, []} -> 
      ?INFO_MSG("~p device detail not found", [Recipient#jid.luser]),
      device_token_is_empty;
    
    {selected, _, Tokens} ->
      if ChatType == <<"call">> ->
        TimestampValue = <<"">>;
      ChatType == <<"recall">> ->
        TimestampValue = <<"">>;
      ChatType == <<"ptt">> ->
        TimestampValue = <<"">>;
      ChatType == <<"mediacall">> ->
        TimestampValue = <<"">>;
      ChatType == <<"adminblock">> ->
        TimestampValue = <<"">>;
      ChatType == <<"meeting_reminder">> ->
        TimestampValue = <<"">>;
      ChatType == <<"reaction">>; ChatType == <<"group_reaction">> ->
        TimestampValue = <<"">>;
      true ->
        Timestamp = fxml:get_subtag(Packet, <<"timestamp">>),
        TimestampValue = fxml:get_attr_s(<<"time">>,
        Timestamp#xmlel.attrs)
      end,
      
      lists:map(fun(G) -> 
        [DeviceType, DeviceToken, VoipDeviceToken, Mode,IOSVersion, _DeviceId, UserType,PushType ] = G,

        case catch fly_mod_utils:check_blockedlist(Recipient#jid.server, Recipient#jid.luser, Sender#jid.luser) of
          {selected, _, [[_T]]} ->
            if ChatType == <<"poll">> ->
              ElementAcknowledge = xmpp:get_subtag(xmpp:decode(Packet), #poll{}),
              {poll,_,_,_,_,Chattype,_,_} = ElementAcknowledge,
              if Chattype =:=<<"normal">> ->
                call_push_method(DeviceType, DeviceToken, VoipDeviceToken, Mode,IOSVersion, UserType,PushType,Sender, Recipient, ChatType, SubEl, Packet,TimestampValue,State);
                true ->
                  fly_mod_utils:remove_offline(Recipient#jid.server, MsgId),
                  user_blocked
              end;
              true ->
            fly_mod_utils:remove_offline(Recipient#jid.server, MsgId),
            user_blocked
            end;
          {error,timeout}  ->
            ok;
          {selected, _, []} ->
            call_push_method(DeviceType, DeviceToken, VoipDeviceToken, Mode,IOSVersion, UserType,PushType,Sender, Recipient, ChatType,
            SubEl, Packet,TimestampValue,State)
        end

       end,Tokens);

    _Error ->
      ?INFO_MSG("push_message get_user_device_details error is ~p", [_Error]),
      database_error
  end.

call_push_method(DeviceType, DeviceToken, VoipDeviceToken, Mode,IOSVersion, UserType,PushType,Sender, Recipient, ChatType, SubEl, Packet,TimestampValue,State)->
  case DeviceType of
            <<"">> -> ?INFO_MSG("push_message user device is empty error is ~p", [Recipient#jid.luser]),
              device_type_is_empty;
            <<"android">> ->
              gcm_single_push(DeviceType,DeviceToken, UserType, ChatType, Sender,
                Recipient, SubEl, TimestampValue, Packet,
                State#state.rabbitmq_connection, State#state.rabbitmq_exchange);
              <<"web">> ->
                  gcm_single_push(DeviceType, DeviceToken, UserType, ChatType, Sender,
                    Recipient, SubEl, TimestampValue, Packet,
                    State#state.rabbitmq_connection, State#state.rabbitmq_exchange);
              <<"ios">> ->
                case ChatType of 
                  <<"mediacall">> when VoipDeviceToken == <<>> ->
                    ?INFO_MSG("voip token is empty ~p", [Recipient#jid.luser]);
                  <<"recall">> ->
                    ?INFO_MSG("(ios) recall restricted ~p", [Recipient#jid.luser]);
                  _ ->
                    apns_single_push(DeviceToken, UserType, VoipDeviceToken, IOSVersion, ChatType, Sender, Recipient, SubEl, TimestampValue,Packet, State, Mode,PushType)
                end;
            _ -> ?INFO_MSG("push_message user device not found error is ~p", [Recipient#jid.luser]),
              database_error
  end.
%% Prepare and push message to android devices
%%
%% @param record Sender
%% @param record Recipient
%% @param record Packet
%% @return atom
gcm_single_push(DeviceType,DeviceToken, PushType, ChatType, From, To, Message,
    TimestampValue, Packet, Channel, RMExchange) ->

  if ChatType == <<"chat">> ->
    FromUser = From#jid.luser,
    Server = To#jid.server,
    ToUser = To#jid.luser,
    MessageId = fxml:get_attr_s(<<"id">>, Packet#xmlel.attrs),
    ContentAcknowledge = xmpp:get_subtag(xmpp:decode(Packet), #chatcontent{}),
  if ContentAcknowledge =:= false ->
    MessageType = <<"">>,
    MentionList = <<"">>,
    EditMsgId = MessageId;
    true ->
    {_,_,_,_,MessageType,_,_,EditMsgId,MentionList,DisappearAt,_} = ContentAcknowledge
    end,
    % DecryptedMessage = fly_mod_security:aes_decrpyt(binary_to_list(MessageId), Message),
    % ParsedMessageJson = jiffy:decode(http_uri:decode(binary_to_list(DecryptedMessage))),
    % MessageType = proplists:get_value(<<"message_type">>,
    %   element(1, ParsedMessageJson)),
    SendFrom = list_to_binary(binary_to_list(FromUser) ++
      "@" ++ binary_to_list(Server)),
    SendTo = list_to_binary(binary_to_list(ToUser) ++
      "@" ++ binary_to_list(Server)),

    ChangedMessage = case MessageType of
                        <<"image">> -> <<"Image">>;
                        <<"audio">> -> <<"Audio">>;
                        <<"video">> -> <<"Video">>;
                        <<"location">> -> <<"Location">>;
                        <<"contact">> -> <<"Contact">>;
                        <<"file">> -> <<"Document">>;
                        <<"meet">> -> <<"Meet">>;
                        _ ->
                        <<"Text">>
                      end,

    BF = [{<<"sent_from">>, binary_to_list(SendFrom)},
      {<<"to_jid">>, binary_to_list(SendTo)},
      {<<"message_time">>, binary_to_list(TimestampValue)},
      {<<"chat_type">>, binary_to_list(ChatType)},
      {<<"user_jid">>, binary_to_list(SendFrom)},
      {<<"message_id">>, binary_to_list(MessageId)},
      {<<"userDomain">>, binary_to_list(Server)},
      {<<"user_type">>, binary_to_list(PushType)},
      {<<"message_content">>, binary_to_list(ChangedMessage)},
      {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
      {<<"title">>, binary_to_list(ChangedMessage)},
      {<<"type">>, binary_to_list(MessageType)}],
    Payload = create_android_json(DeviceToken, BF),
    if (EditMsgId =:= MessageId) or (EditMsgId =:= <<"">>) ->
      if DeviceType ==  <<"android">> ->
        send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Server, Packet);
      true ->
        send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Server, Packet)
      end;
    true ->
      ok
    end;
    ChatType == <<"reaction">>; ChatType == <<"group_reaction">> ->
    Server = To#jid.server,
    ToUser = To#jid.luser, % message sender
    ?LOG_INFO("message sender ~p from reaction pkt", [ToUser]),
    FromUser = From#jid.luser,
    StanzaId = fxml:get_attr_s(<<"id">>, Packet#xmlel.attrs),
    ReactionEl = fxml:get_subtag_with_xmlns(Packet, <<"reaction">>, <<"urn:xmpp:receipts">>),
    case ReactionEl of
        #xmlel{attrs = Attrs} ->
            Action     = fxml:get_attr_s(<<"action">>, Attrs),
            EmojiId    = fxml:get_attr_s(<<"emoji_id">>, Attrs),
            MsgId      = fxml:get_attr_s(<<"message_id">>, Attrs),
            FromUserJid= fxml:get_attr_s(<<"from_user">>, Attrs), % reaction sender
            Timestamp  = fxml:get_attr_s(<<"timestamp">>, Attrs),
            BF0 = [
                {<<"type">>, binary_to_list(<<"reaction">>)},
                {<<"chat_type">>, binary_to_list(if ChatType == <<"group_reaction">> -> <<"normal">>; true -> <<"chat">> end)},
                {<<"action">>, binary_to_list(Action)},
                {<<"message_id">>, binary_to_list(MsgId)},
                {<<"reaction_id">>, binary_to_list(StanzaId)},
                {<<"reaction_to">>, binary_to_list(jid:to_string(To))},
                {<<"reaction_from">>, binary_to_list(FromUserJid)},
                {<<"emoji_id">>, binary_to_list(EmojiId)},
                {<<"timestamp">>, binary_to_list(Timestamp)},
                {<<"userDomain">>, binary_to_list(Server)},
                {<<"user_type">>, binary_to_list(PushType)},
                {<<"chat_id">>, binary_to_list(jid:to_string(From))},
                {<<"push_from">>, binary_to_list(<<"MirrorFly">>)}
            ],
            
            
        case ChatType of
          <<"group_reaction">> ->
            MsgSender = fxml:get_attr_s(<<"message_sender">>, Attrs),
            
            BF1 = BF0 ++ [{<<"message_sender">>,  binary_to_list(MsgSender)}],
            ?LOG_INFO("MsgSender ~p ToUser ~p is equal? ~p", [MsgSender, ToUser, MsgSender =:= ToUser]),

            case MsgSender =:= ToUser of
              true ->
                Payload = create_android_json(DeviceToken, BF1),
                ?LOG_INFO("[android_push] reaction payload : ~p", [Payload]),
                case DeviceType of
                    <<"android">> ->
                          if Action == <<"update">>; Action == <<"remove">> ->  
                            FUser = fly_mod_utils:get_user_from_string_jid(FromUserJid),
                            ?LOG_INFO("Updating push sent status for reaction update, message id: ~p, user: ~p, toUser: ~p", [MsgId, FUser, ToUser]),
                            fly_mod_utils:update_push_sent(Server, FUser, ToUser, MsgId);
                            true -> 
                            ok
                          end,
                        send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Server, Packet);
                    _ ->
                      send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Server, Packet)
                end;
              false ->
                ?LOG_INFO("skipping push, reaction should only route for message sender ~p but got ~p",[MsgSender, ToUser]),
                ok
            end;

          <<"reaction">> ->
            Q = fly_mod_utils:chat_history_query(Server, MsgId),
            ?LOG_INFO("Chat history query result for reaction push: ~p", [Q]),

            case Q of 
              {selected, _, [[F, _, _, _, _]]} -> 
                if FromUser =/= F -> 
                  Payload = create_android_json(DeviceToken, BF0),
                  ?LOG_INFO("[android_push] reaction payload : ~p", [Payload]),

                  case DeviceType of
                    <<"android">> ->
                      send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Server, Packet);
                    _ ->
                      send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Server, Packet)
                  end;
                true -> 
                  ok
                end;
              _ -> 
                ok
            end;
          _ ->
            ok
        end;
        _ -> ok
      end;
    ChatType == <<"poll">> ->
    FromUser = From#jid.luser,
    Server = To#jid.server,
    ToUser = To#jid.luser,
    MessageId = fxml:get_attr_s(<<"id">>, Packet#xmlel.attrs),
    SendFrom = list_to_binary(binary_to_list(FromUser) ++
      "@" ++ binary_to_list(Server)),
    ElementAcknowledge = xmpp:get_subtag(xmpp:decode(Packet), #poll{}),
    {poll,PollId,VoterUserId,VoteId,Status,_Chattype,PollOptionId,PollUser} = ElementAcknowledge,
    VoterId = fly_mod_utils:get_user_from_string_jid(VoterUserId),
    BF = [{<<"type">>, "poll"},
        {<<"message_content">>, "Poll"},
        {<<"send_from">>, binary_to_list(SendFrom)},
        {<<"poll_id">>, binary_to_list(PollId)},
        {<<"vote_id">>, binary_to_list(VoteId)},
        {<<"voter_user_id">>, binary_to_list(VoterId)},
        {<<"status">>, binary_to_list(Status)},
        {<<"message_id">>, binary_to_list(MessageId)},
        {<<"poll_option_id">>, binary_to_list(PollOptionId)},
        {<<"poll_time">>, binary_to_list(TimestampValue)},
        {<<"to_user">>, binary_to_list(PollUser)},
        {<<"userDomain">>, binary_to_list(Server)},
        {<<"user_type">>, binary_to_list(PushType)},
        {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
        {<<"title">>, "Poll"}],
      Payload = create_android_json(DeviceToken, BF),
      if DeviceType ==  <<"android">> ->
        send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet);
      true ->
        send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet)
      end;
    ChatType == <<"seen">> ->
    FromUser = From#jid.luser,
    Server = To#jid.server,
    ToUser = To#jid.luser,
    ElementAcknowledge = xmpp:get_subtag(xmpp:decode(Packet), #seen{}),
    {seen,MessageId,_,_Time,_,_GroupId} = ElementAcknowledge,
    SendFrom = list_to_binary(binary_to_list(FromUser) ++
      "@" ++ binary_to_list(Server)),
    SendTo = list_to_binary(binary_to_list(ToUser) ++
      "@" ++ binary_to_list(Server)),

    BF = [{<<"sent_from">>, binary_to_list(SendFrom)},
      {<<"to_jid">>, binary_to_list(SendTo)},
      {<<"message_time">>, binary_to_list(TimestampValue)},
      {<<"chat_type">>, binary_to_list(ChatType)},
      {<<"user_jid">>, binary_to_list(SendFrom)},
      {<<"message_id">>, binary_to_list(MessageId)},
      {<<"userDomain">>, binary_to_list(Server)},
      {<<"user_type">>, binary_to_list(PushType)},
      {<<"message_content">>, binary_to_list(ChatType)},
      {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
      {<<"title">>, binary_to_list(ChatType)},
      {<<"type">>, binary_to_list(ChatType)}],
    Payload = create_android_json(DeviceToken, BF),
    if DeviceType ==  <<"android">> ->
      send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet);
      true ->
        send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet)
      end;
    ChatType == <<"recall">> ->
      FromUser = From#jid.luser,
      Server = To#jid.server,

      ReCall = fxml:get_subtag_with_xmlns(Packet, <<"recall">>,
        <<"urn:xmpp:receipts">>),
      {value, MessageId} = fxml:get_tag_attr(<<"id">>,
        ReCall),

      SendFrom = list_to_binary(binary_to_list(FromUser) ++
        "@" ++ binary_to_list(Server)),
      BF = [{<<"type">>, "recall"},
        {<<"message_id">>, binary_to_list(MessageId)},
        {<<"message_content">>, "This message was deleted"},
        {<<"send_from">>, binary_to_list(SendFrom)},
        {<<"userDomain">>, binary_to_list(Server)},
        {<<"user_type">>, binary_to_list(PushType)},
        {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
        {<<"title">>, "This message was deleted"}],
      Payload = create_android_json(DeviceToken, BF),
      if DeviceType ==  <<"android">> ->
        send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet);
        true ->
          send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet)
        end;

    ChatType == <<"mediacall">> ->
      FromUser = From#jid.luser,
      Server = To#jid.server,
      MediaCall = fxml:get_subtag_with_xmlns(Packet, <<"mediacall">>,
        <<"urn:xmpp:call">>),
      MessageId = fxml:get_attr_s(<<"id">>,
      Packet#xmlel.attrs),
      SendFrom = list_to_binary(binary_to_list(FromUser) ++
        "@" ++ binary_to_list(Server)),

      RoomId = case fxml:get_tag_attr(<<"room_id">>, MediaCall) of
        {value, Roomid} ->
        Roomid;
          _ ->
          <<"">>
      end,
      CallType = case fxml:get_tag_attr(<<"call_type">>, MediaCall) of
        {value, Calltype} ->
          Calltype;
        _ ->
          <<"">>
      end,
      CallTime = case fxml:get_tag_attr(<<"call_time">>, MediaCall) of
        {value, Calltime} ->
          Calltime;
        _ ->
          <<"">>
      end,
      StartTime = case fxml:get_tag_attr(<<"start_time">>, MediaCall) of
                    {value, Starttime} ->
                    Starttime;
                    _ ->
                    <<"">>
                  end,
      EndTime = case fxml:get_tag_attr(<<"end_time">>, MediaCall) of
                  {value, Endtime} ->
                  Endtime;
                  _ ->
                  <<"">>
                  end,
      CallMode = case fxml:get_tag_attr(<<"call_mode">>, MediaCall) of
        {value, Callmode} ->
          Callmode;
        _ ->
          <<"">>
      end,
      CallStatus = case fxml:get_tag_attr(<<"call_status">>, MediaCall) of
        {value, Callstatus} ->
          Callstatus;
        _ ->
          <<"">>
      end,
      GroupCallId = case fxml:get_tag_attr(<<"group_id">>, MediaCall) of
        {value, GroupcallId} ->
          GroupcallId;
        _ ->
          <<"">>
      end,

      RoomLink = case fxml:get_tag_attr(<<"call_link">>, MediaCall) of
        {value, Roomlink} ->
          Roomlink;
        _ ->
          <<"">>
      end,

      CallerName = case fxml:get_tag_attr(<<"caller_name">>, MediaCall) of
      {value, Callername} ->
        Callername;
      _ ->
        <<"">>
    end,
          Expiry = get_timestamp(),

    MetaData = case fxml:get_tag_attr(<<"meta_data">>, MediaCall) of
    {value, Metadata} ->
      Metadata;
    _ ->
      <<"">>
  end,
      SessionStatus = case fxml:get_tag_attr(<<"session_status">>, MediaCall) of
                      {value, Sessionstatus} ->
                      Sessionstatus;
                      _ ->
                      <<"">>
                    end,

      case fxml:get_subtag(MediaCall, <<"users">>) of
        false  ->

          ok;
        Users ->
          User = lists:flatmap(fun(U) ->
            [fxml:get_tag_cdata(U)] end, Users#xmlel.children),

          case fxml:get_subtag(MediaCall, <<"invite">>) of
          false  ->
            BF = [{<<"type">>, "mediacall"},
              {<<"message_id">>, binary_to_list(MessageId)},
              {<<"room_id">>, binary_to_list(RoomId)},
              {<<"users">>, lists:flatten(lists:join(",", [binary_to_list(B) || B <- User]))},
              {<<"caller_id">>, binary_to_list(SendFrom)},
              {<<"call_type">>, binary_to_list(CallType)},
              {<<"call_time">>, CallTime},
              {<<"start_time">>, binary_to_list(StartTime)},
              {<<"end_time">>, binary_to_list(EndTime)},
              {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
              {<<"call_status">>, binary_to_list(CallStatus)},
              {<<"caller_name">>, binary_to_list(CallerName)},
              {<<"group_id">>, binary_to_list(GroupCallId)},
              {<<"session_status">>, binary_to_list(SessionStatus)},
              {<<"userDomain">>, binary_to_list(Server)},
              {<<"user_type">>, binary_to_list(PushType)},
              {<<"call_mode">>, binary_to_list(CallMode)},
              {<<"expiration">>, integer_to_list(Expiry)},
              {<<"call_link">>, binary_to_list(RoomLink)},
              {<<"meta_data">>, binary_to_list(MetaData)},
              {<<"title">>, "Calling"}];
          InviteUsers ->
            InviteUser = lists:flatmap(fun(I) ->
              [fxml:get_tag_cdata(I)] end, InviteUsers#xmlel.children),
            BF = [{<<"type">>, "mediacall"},
            {<<"message_id">>, binary_to_list(MessageId)},
            {<<"room_id">>, binary_to_list(RoomId)},
            {<<"users">>, lists:flatten(lists:join(",", [binary_to_list(B) || B <- User]))},
            {<<"inviteusers">>, lists:flatten(lists:join(",", [binary_to_list(C) || C <- InviteUser]))},
            {<<"caller_id">>, binary_to_list(SendFrom)},
            {<<"call_type">>, binary_to_list(CallType)},
            {<<"call_time">>, CallTime},
            {<<"start_time">>, binary_to_list(StartTime)},
            {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
            {<<"userDomain">>, binary_to_list(Server)},
            {<<"user_type">>, binary_to_list(PushType)},
            {<<"end_time">>, binary_to_list(EndTime)},
            {<<"call_status">>, binary_to_list(CallStatus)},
            {<<"group_id">>, binary_to_list(GroupCallId)},
            {<<"caller_name">>, binary_to_list(CallerName)},
            {<<"session_status">>, binary_to_list(SessionStatus)},
            {<<"call_mode">>, binary_to_list(CallMode)},
            {<<"meta_data">>, binary_to_list(MetaData)},
            {<<"expiration">>, integer_to_list(Expiry)},
            {<<"call_link">>, binary_to_list(RoomLink)},
            {<<"title">>, "Calling"}]
          end,
          Payload = create_android_json(DeviceToken, BF),
          if DeviceType ==  <<"android">> ->
            send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet);
      true ->
        send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet)
      end
      end;
    ChatType == <<"adminblock">> ->
      FromUser = From#jid.luser,
      Server = To#jid.server,
      AdminBlock = fxml:get_subtag_with_xmlns(Packet, <<"admin_block">>,
        <<"urn:xmpp:receipts">>),

      SendFrom = list_to_binary(binary_to_list(FromUser) ++
        "@" ++ binary_to_list(Server)),

      BlockStatus = case fxml:get_tag_attr(<<"block_status">>, AdminBlock) of
        {value, Blockstatus} ->
        Blockstatus;
          _ ->
          <<"">>
      end,
        BlockUser = case fxml:get_tag_attr(<<"jid">>, AdminBlock) of
        {value, Blockuser} ->
        Blockuser;
        _ ->
        <<"">>
      end,

            BF = [{<<"type">>, "adminblock"},
              {<<"push_from">>, "MirrorFly"},
              {<<"user_jid">>, binary_to_list(BlockUser)},
              {<<"userDomain">>, binary_to_list(Server)},
              {<<"user_type">>, binary_to_list(PushType)},
              {<<"block_status">>, binary_to_list(BlockStatus)},
              {<<"title">>, "Blocking"}],

          Payload = create_android_json(DeviceToken, BF),
          if DeviceType ==  <<"android">> ->
            send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet);
            true ->
              send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Server, Packet)
            end;
    ChatType == <<"meeting_reminder">> ->
      Server = To#jid.server,
      Meeting = fxml:get_subtag_with_xmlns(Packet, <<"meeting">>,
        <<"urn:xmpp:receipts">>),
      MessageId = fxml:get_attr_s(<<"message_id">>, Meeting#xmlel.attrs),
      ?INFO_MSG("send_push_notifications meeting_reminder to=~ts device=~ts meeting_msg_id=~ts stanza_id=~ts",
                [jid:to_string(To), DeviceType, MessageId, fxml:get_attr_s(<<"id">>, Packet#xmlel.attrs)]),
      SessionId = fxml:get_attr_s(<<"session_id">>, Meeting#xmlel.attrs),
      RoomId = fxml:get_attr_s(<<"room_id">>, Meeting#xmlel.attrs),
      ChatId = fxml:get_attr_s(<<"chat_id">>, Meeting#xmlel.attrs),
      CallMode = fxml:get_attr_s(<<"call_mode">>, Meeting#xmlel.attrs),
      UserJid = fxml:get_attr_s(<<"user_jid">>, Meeting#xmlel.attrs),
      CallType = fxml:get_attr_s(<<"call_type">>, Meeting#xmlel.attrs),
      ScheduledAt = fxml:get_attr_s(<<"scheduled_at">>, Meeting#xmlel.attrs),
      ReminderMins = fxml:get_attr_s(<<"reminder_before_minutes">>, Meeting#xmlel.attrs),
      Status = fxml:get_attr_s(<<"status">>, Meeting#xmlel.attrs),
      MessageFrom = fxml:get_attr_s(<<"message_from">>, Meeting#xmlel.attrs),
      ChatTypeParam = fxml:get_attr_s(<<"chat_type">>, Meeting#xmlel.attrs),
      MessageTo = fxml:get_attr_s(<<"message_to">>, Meeting#xmlel.attrs),

      BF = [
        {<<"type">>, "meeting_reminder"},
        {<<"status">>, binary_to_list(Status)},
        {<<"session_id">>, binary_to_list(SessionId)},
        {<<"room_id">>, binary_to_list(RoomId)},
        {<<"chat_id">>, binary_to_list(ChatId)},
        {<<"user_jid">>, binary_to_list(UserJid)},
        {<<"call_mode">>, binary_to_list(CallMode)},
        {<<"call_type">>, binary_to_list(CallType)},
        {<<"scheduled_at">>, binary_to_list(ScheduledAt)},
        {<<"message_id">>, binary_to_list(MessageId)},
        {<<"reminder_before_minutes">>, binary_to_list(ReminderMins)},
        {<<"userDomain">>, binary_to_list(Server)},
        {<<"user_type">>, binary_to_list(PushType)},
        {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
        {<<"title">>, "Meeting Reminder"},
        {<<"message_from">>, binary_to_list(MessageFrom)},
        {<<"chat_type">>, binary_to_list(ChatTypeParam)},
        {<<"message_to">>, binary_to_list(MessageTo)}
      ],
      Payload = create_android_json(DeviceToken, BF),
      if DeviceType == <<"android">> ->
        send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Server, Packet);
      true ->
        send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Server, Packet)
      end;
    true -> {ok, <<"chat type is different gcm">>}
  end.

%% Prepare and push message to android devices
%%
%% @param record Sender
%% @param record Recipient
%% @param record Packet
%% @return atom

gcm_group_push(DeviceToken, PushType, ChatType, GroupName,
    FromUser, ToUser, Message, Packet, TimestampValue,
    Channel, RMExchange) ->
  if ChatType == <<"normal">> ->
    Event = fxml:get_subtag(Packet, <<"event">>),
    Items = fxml:get_subtag(Event, <<"items">>),
    #jid{luser = GId, lserver = GServer} = FromUser,
    GroupId = list_to_binary(binary_to_list(GId) ++
      "@" ++ binary_to_list(GServer)),
    {value, NameSpace} = fxml:get_tag_attr(<<"node">>,
      Items),
    if (Items =/= false) and
      (NameSpace =:= <<"urn:xmpp:mix:nodes:messages">>) ->
      #jid{lserver = LServer} = ToUser,

      {value, MessageId} = fxml:get_tag_attr(<<"message_id">>,
        Message),
      {value, MsgFrom} = fxml:get_tag_attr(<<"sent_from">>,
        Message),
      MessageContent = fxml:get_tag_cdata(Message),
      DecryptedMessage = fly_mod_security:aes_decrpyt(binary_to_list(MessageId),
          MessageContent),
      ParsedMessageJson = jiffy:decode(http_uri:decode(binary_to_list(DecryptedMessage))),
      MessageType = proplists:get_value(<<"message_type">>,
        element(1,
          ParsedMessageJson)),

      ChangedMessage = case MessageType of
                          <<"image">> -> binary_to_list(<<"Image">>);
                          <<"audio">> -> binary_to_list(<<"Audio">>);
                          <<"video">> -> binary_to_list(<<"Video">>);
                          <<"location">> ->
                          binary_to_list(<<"Location">>);
                          <<"contact">> ->
                          binary_to_list(<<"Contact">>);
                          <<"file">> -> binary_to_list(<<"Document">>);
                          _ ->
                          binary_to_list(<<"Text">>)
                        end,
      BF = [{<<"user_jid">>, binary_to_list(GroupId)},
        {<<"sent_from">>, binary_to_list(MsgFrom)},
        {<<"message_time">>, binary_to_list(TimestampValue)},
        {<<"chat_type">>, binary_to_list(ChatType)},
        {<<"userDomain">>, binary_to_list(LServer)},
        {<<"user_type">>, binary_to_list(PushType)},
        {<<"message_id">>, binary_to_list(MessageId)},
        {<<"title">>, ChangedMessage},
        {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
        {<<"type">>, binary_to_list(MessageType)}],
      Payload = create_android_json(DeviceToken, BF),
      send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, LServer, Packet);
      (Items =/= false) and
        (NameSpace =:= <<"urn:xmpp:mix:nodes:participants">>) ->
        #jid{luser = LUser, lserver = LServer} = ToUser,
        Item = fxml:get_subtag(Items, <<"item">>),
        NotifyId = fxml:get_attr_s(<<"id">>,
          Packet#xmlel.attrs),
        {value, MsgFrom} = fxml:get_tag_attr(<<"publisher">>,
          Item),
        {value, NodeId} = fxml:get_tag_attr(<<"id">>, Item),
        Participant = fxml:get_subtag(Item, <<"participant">>),
        {value, ParticipantJid} = fxml:get_tag_attr(<<"jid">>,
          Participant),
        SendFrom = list_to_binary(binary_to_list(LUser) ++
          "@" ++ binary_to_list(LServer)),
        [N, _H] = string:tokens(binary_to_list(MsgFrom), "@"),
        Name = list_to_binary(N),

        VCard = case catch fly_mod_utils:get_vcard(LServer, Name) of
                  {selected, [{SVCARD, _CreatedAt}]} ->
                    case fxml_stream:parse_element(SVCARD) of
                      {error, _Reason} -> [];
                      VCARD ->
                        [VCARD],
                        %% Remove the namespace from the xml
                        VCARD#xmlel{attrs = lists:keydelete(<<"xmlns">>, 1, VCARD#xmlel.attrs)}
                    end;
                  {selected, []} -> _CreatedAt = TimestampValue, <<"">>;
                  _ -> _CreatedAt = TimestampValue, <<"">>
                end,
        case catch fly_mod_utils:get_vcard(LServer, GId) of
                      {selected, [{GVCARD, GrpCreatedAt}]} ->
                        GVCARD;
                      {selected, []} -> GrpCreatedAt = TimestampValue, <<"">>;
                      _ -> GrpCreatedAt = TimestampValue, <<"">>
                    end,
          if VCard == <<"">> ->
    UserNickName = <<"">>;
    true ->
        UserNickName = case fxml:get_path_s(VCard,[{elem, <<"nickName">>}, cdata]) of
                          <<"">> ->
                          fxml:get_path_s(VCard,
                            [{elem, <<"FN">>},
                              cdata]);
                          Nickname -> Nickname
                        end
      end,

        PublisherVcard = case catch fly_mod_utils:get_vcard(LServer, MsgFrom) of
            {selected, [{PVCARD, _CreatedTime}]} ->
              PVCARD;
            {selected, []} ->
              <<"">>;
            _ ->
              <<"">>
          end,

        if ParticipantJid =:= SendFrom ->
          MessageContent = <<GroupName / binary, <<":">> / binary,
            UserNickName / binary,
            <<" added you">> / binary>>,
          BF = [{<<"user_jid">>, binary_to_list(GroupId)},
            {<<"group_id">>, binary_to_list(GroupId)},
            {<<"message_content">>, binary_to_list(MessageContent)},
            {<<"group_name">>, binary_to_list(GroupName)},
            {<<"created_at">>, binary_to_list(GrpCreatedAt)},
            {<<"added_at">>, binary_to_list(TimestampValue)},
            {<<"notify_id">>, binary_to_list(NotifyId)},
            {<<"message_time">>, binary_to_list(TimestampValue)},
            {<<"node_id">>, binary_to_list(NodeId)},
            {<<"userDomain">>, binary_to_list(LServer)},
            {<<"user_type">>, binary_to_list(PushType)},
            {<<"user_name">>, binary_to_list(UserNickName)},
            {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
            {<<"sent_from">>, binary_to_list(MsgFrom)},
            % {<<"sender_username">>, binary_to_list(Name)},
            {<<"publisher_profile">>, binary_to_list(PublisherVcard)},
            % {<<"custom_attributes">>, binary_to_list(CustAttr)},
            {<<"title">>, binary_to_list(GroupName)},
            {<<"type">>, "normal"}],
          Payload = create_android_json(DeviceToken, BF),
          
          send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, LServer, Packet);
          
          true -> {ok, <<"ParticipantJid =/= SendFrom gcm">>}
        end;
      true -> {ok, <<"item empty and namspace changed gcm">>}
    end;
    true -> {ok, <<"chat type is different gcm">>}
  end.

%%%===================================================================
%%% RabbitMQ Connection Management with Safe Channel Lifecycle
%%%===================================================================

create_rabbit_mq_create_connection(Host) ->
    maybe_cleanup_old_connection(),
    RabbitMQHost = gen_mod:get_module_opt(Host, ?PROCNAME, rabbitmq_host),
    RabbitMQExchange = gen_mod:get_module_opt(Host, ?PROCNAME, rabbitmq_exchange),
    RabbitMQUsername = gen_mod:get_module_opt(Host, ?PROCNAME, rabbitmq_username),
    RabbitMQPassWord = gen_mod:get_module_opt(Host, ?PROCNAME, rabbitmq_password),

    case amqp_connection:start(
        #amqp_params_network{
            host = binary_to_list(RabbitMQHost),
            username = RabbitMQUsername,
            password = RabbitMQPassWord
        }) of
        {ok, RMQConnection} ->
            ?INFO_MSG("RabbitMQ connection established: ~p", [RMQConnection]),
            Channel = create_rabbit_mq_channel_connection(RMQConnection, Host),
            case check_rabbit_mq_connection_table(rabbit_mq_connection) of
                true -> ets:delete_all_objects(rabbit_mq_connection);
                _ -> ok
            end,
            ets:insert(rabbit_mq_connection, {pid, RMQConnection}),
            ets:insert(rabbit_mq_connection, {channel, Channel}),
            [Channel, RabbitMQExchange];
        Error ->
            ?ERROR_MSG("RabbitMQ connection failed: ~p", [Error]),
            Error
    end.

%%%-------------------------------------------------------------------
%%% Safely close old RabbitMQ connections and channels
%%%-------------------------------------------------------------------
maybe_cleanup_old_connection() ->
    maybe_close_old_channel(),
    case ets:lookup(rabbit_mq_connection, pid) of
        [{pid, OldConn}] when is_pid(OldConn) ->
            catch amqp_connection:close(OldConn),
            ets:delete_all_objects(rabbit_mq_connection),
            ?INFO_MSG("Closed old RabbitMQ connection: ~p", [OldConn]);
        _ ->
            ok
    end.

%%%-------------------------------------------------------------------
%%% Safely create a new channel for an existing connection
%%%-------------------------------------------------------------------
create_rabbit_mq_channel_connection(RMQConnection, Host) ->
    maybe_close_old_channel(),
    case amqp_connection:open_channel(RMQConnection) of
        {ok, Channel} ->
            case check_rabbit_mq_connection_table(rabbit_mq_connection) of
                true -> ets:delete_all_objects(rabbit_mq_connection);
                _ -> ok
            end,
            ets:insert(rabbit_mq_connection, {pid, RMQConnection}),
            ets:insert(rabbit_mq_connection, {channel, Channel}),
            ?INFO_MSG("Created new RabbitMQ channel: ~p", [Channel]),
            Channel;
        {error, Reason} ->
            io:format("Failed to open channel: ~p~n", [Reason]),
            catch amqp_connection:close(RMQConnection),
            [ChannelNewPid, _] = create_rabbit_mq_create_connection(Host),
            ChannelNewPid
    end.

%%%-------------------------------------------------------------------
%%% Close old channel if it exists
%%%-------------------------------------------------------------------
maybe_close_old_channel() ->
    case ets:lookup(rabbit_mq_connection, channel) of
        [{channel, OldChannel}] when is_pid(OldChannel) ->
            catch amqp_channel:close(OldChannel),
            ets:delete(rabbit_mq_connection, channel),
            ?INFO_MSG("Closed old RabbitMQ channel: ~p", [OldChannel]);
        _ -> ok
    end.

%%%-------------------------------------------------------------------
%%% Check ETS table for active RabbitMQ connection
%%%-------------------------------------------------------------------
check_rabbit_mq_connection_table(Table) ->
    case ets:lookup(Table, pid) of
        [{pid, _}] -> true;
        _ -> false
    end.

%%%-------------------------------------------------------------------
%%% Ensure channel and connection are alive, recreate if not
%%%-------------------------------------------------------------------
check_rabbit_mq_connection_is_alive(ChannelPid, Host) ->
    ChannelConnection =
        case is_pid(ChannelPid) of
            true ->
                case is_process_alive(ChannelPid) of
                    true ->
                        ChannelPid;
                    false ->
                        catch amqp_channel:close(ChannelPid),
                        handle_connection_recovery(Host)
                end;
            false ->
                handle_connection_recovery(Host)
        end,
    ChannelConnection.

%%%-------------------------------------------------------------------
%%% Helper: Recover connection and channel
%%%-------------------------------------------------------------------
handle_connection_recovery(Host) ->
    case ets:match(rabbit_mq_connection, {pid, '$1'}) of
        [[RabbitMQConnectionPid]] ->
            case is_pid(RabbitMQConnectionPid) of
                true ->
               case is_process_alive(RabbitMQConnectionPid) of
                  true ->
                      ChannelNewPid = create_rabbit_mq_channel_connection(RabbitMQConnectionPid, Host),
                      ?INFO_MSG("Recovered alive RabbitMQ connection, new channel pid: ~p", [ChannelNewPid]),
                      ChannelNewPid;
                  false ->
                      [ChannelNewPid, _] = create_rabbit_mq_create_connection(Host),
                      ?INFO_MSG("Recreated dead RabbitMQ connection, new channel pid: ~p", [ChannelNewPid]),
                      ChannelNewPid
              end
            end;
        _ ->
            [ChannelNewPid, _] = create_rabbit_mq_create_connection(Host),
            ?INFO_MSG("No RabbitMQ connection found, new channel pid: ~p", [ChannelNewPid]),
            ChannelNewPid
    end.

%% Send Android push payloads to the rabbit mq server
send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Host) ->
  send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Host, undefined).

send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Host) ->
  send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange, Host, undefined).

send_android_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Host, Packet) ->
  ?LOG_INFO("send_android_payload_to_rabbitmq ChatType: ~p, Payload: ~s", [ChatType, Payload]),

  ChannelPid = check_rabbit_mq_connection_is_alive(Channel,Host),
  if (ChatType =:= <<"call">>)  or (ChatType =:= <<"mediacall">>)->
    RKey = <<"android_call">>,
    %% extract stanza info
    StanzaId = safe_get_msg_id(Packet),
    Type = safe_get_msg_type(Packet),
    {FUserId, _, FResource} = safe_get_from_parts(Packet),
    {TUserId, _, TResource} = safe_get_to_parts(Packet),
    ?LOG_INFO("publishing to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey,
      #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
    case amqp_channel:cast(ChannelPid,
      #'basic.publish'{
        exchange = RMExchange,
        routing_key = RKey},
      #amqp_msg{payload = list_to_binary(Payload)}) of
      ok ->
        ?LOG_INFO("published to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey,
          #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
        {ok, <<"success">>};
      Error ->
        ?LOG_INFO("publish_failed to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p error=~p", [TUserId, RMExchange, RKey,
          #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}, Error]),
        ?ERROR_MSG("Android: Unable to send call push notification to the rabbitmq server server: ~p", [Error])
    end;
     ChatType =:= <<"group_reaction">> ->
    RKey = <<"aos_grp_react_push">>,
    StanzaId = safe_get_msg_id(Packet),
    Type = safe_get_msg_type(Packet),
    {FUserId, _, FResource} = safe_get_from_parts(Packet),
    {TUserId, _, TResource} = safe_get_to_parts(Packet),
    ?LOG_INFO("chat type group_reaction, publishing to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey,
      #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
      case amqp_channel:cast(ChannelPid,
        #'basic.publish'{
          exchange = RMExchange,
          routing_key = RKey},
        #amqp_msg{payload = list_to_binary(Payload)}) of
        ok ->
          ?LOG_INFO("published to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey,
            #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
          {ok, <<"success">>};
          Error ->
            ?LOG_INFO("publish_failed to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p error=~p", [TUserId, RMExchange, RKey,
              #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}, Error]),
            ?ERROR_MSG("Android: Unable to send push messages to the rabbitmq server Q[aos_grp_react_push] server: ~p", [Error])
      end;
    true ->
      RKey = <<"android_message">>,
      StanzaId = safe_get_msg_id(Packet),
      Type = safe_get_msg_type(Packet),
      {FUserId, _, FResource} = safe_get_from_parts(Packet),
      {TUserId, _, TResource} = safe_get_to_parts(Packet),
      ?LOG_INFO("publishing to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey,
        #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
      case amqp_channel:cast(ChannelPid,
        #'basic.publish'{
          exchange = RMExchange,
          routing_key = RKey},
        #amqp_msg{payload = list_to_binary(Payload)}) of
        ok ->
          ?LOG_INFO("published to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey,
            #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
          {ok, <<"success">>};
          Error ->
            ?LOG_INFO("publish_failed to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p error=~p", [TUserId, RMExchange, RKey,
              #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}, Error]),
            ?ERROR_MSG("Android: Unable to send push messages to the rabbitmq server server: ~p", [Error])
      end
  end.

%% Send Android push payloads to the rabbit mq server
send_web_payload_to_rabbitmq(Channel, ChatType, Payload, RMExchange,Host, Packet) ->
  ?LOG_INFO("send_web_payload_to_rabbitmq ChatType: ~p, Payload: ~s", [ChatType, Payload]),

  ChannelPid = check_rabbit_mq_connection_is_alive(Channel,Host),
  if (ChatType =:= <<"call">>)  or (ChatType =:= <<"mediacall">>)->
    RKey = <<"web_call">>,
    StanzaId = safe_get_msg_id(Packet),
    Type = safe_get_msg_type(Packet),
    {FUserId, _, FResource} = safe_get_from_parts(Packet),
    {TUserId, _, TResource} = safe_get_to_parts(Packet),
    ?LOG_INFO("publishing to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey, #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
    ?LOG_INFO("publishing to rabbitmq for user=~p with exchange=~p routing_key=~p payload_len=~p", [TUserId, RMExchange, RKey, byte_size(list_to_binary(Payload))]),
    case amqp_channel:cast(ChannelPid,
      #'basic.publish'{
        exchange = RMExchange,
        routing_key = RKey},
      #amqp_msg{payload = list_to_binary(Payload)}) of
      ok ->
        ?LOG_INFO("published to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey, #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
        {ok, <<"success">>};
      Error ->
        ?LOG_INFO("publish_failed to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p error=~p", [TUserId, RMExchange, RKey, #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}, Error]),
        ?ERROR_MSG("Android: Unable to send call push notification to the rabbitmq server server: ~p", [Error])
    end;
    true ->
      RKey = <<"web_message">>,
      StanzaId = safe_get_msg_id(Packet),
      Type = safe_get_msg_type(Packet),
      {FUserId, _, FResource} = safe_get_from_parts(Packet),
      {TUserId, _, TResource} = safe_get_to_parts(Packet),
      ?LOG_INFO("publishing to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, RKey, #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
      ?LOG_INFO("publishing to rabbitmq for user=~p with exchange=~p routing_key=~p payload_len=~p", [TUserId, RMExchange, RKey, byte_size(list_to_binary(Payload))]),
      case amqp_channel:cast(ChannelPid,
        #'basic.publish'{
          exchange = RMExchange,
          routing_key = RKey},
        #amqp_msg{payload = list_to_binary(Payload)}) of
        ok ->
          ?LOG_INFO("published to rabbitmq for user=~p with exchange=~p routing_key=~p", [TUserId, RMExchange, RKey]),
          {ok, <<"success">>};
        Error ->
          ?ERROR_MSG("Android: Unable to send push messages to the rabbitmq server server: ~p", [Error])
      end
  end.
%% Send IOS push payloads to the rabbit mq server
send_payload(Payload, ChatType, RMQConnection, RMExchange,Host, PushType) ->
  %% wrapper for backward compatibility; delegate to 7-arg version with undefined Packet
  send_payload(Payload, ChatType, RMQConnection, RMExchange, Host, PushType, undefined).

send_payload(Payload, ChatType, RMQConnection, RMExchange,Host, PushType, Packet) ->
  ?LOG_INFO("send_payload (IOS) ChatType: ~p, PushType: ~p, Payload: ~s", [ChatType, PushType, Payload]),
  ChannelPid = check_rabbit_mq_connection_is_alive(RMQConnection,Host),

  if ChatType =:= <<"mediacall">> ->

    Queue = <<"ios_call">>,

    StanzaId = safe_get_msg_id(Packet),
    Type = safe_get_msg_type(Packet),
    {FUserId, _, FResource} = safe_get_from_parts(Packet),
    {TUserId, _, TResource} = safe_get_to_parts(Packet),
    ?LOG_INFO("publishing to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, Queue,
      #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
    case amqp_channel:cast(ChannelPid,
      #'basic.publish'{
        exchange = RMExchange,
        routing_key = Queue},
      #amqp_msg{payload = list_to_binary(Payload)}) of
      ok ->
        ?LOG_INFO("published to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, Queue,
          #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
        {ok, <<"success">>};
      Error ->
        ?LOG_INFO("publish_failed to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p error=~p", [TUserId, RMExchange, Queue,
          #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}, Error]),
        ?ERROR_MSG("IOS: Unable to send call push to the rabbitmq server server: ~p", [Error])
    end;
    true ->
      Queue =
      if
          PushType =:= <<"fcm">> ->
              <<"ios_message_fcm">>;
          ChatType =:= <<"group_reaction">> ->
              <<"ios_grp_react_push">>;
          true ->
              <<"ios_message">>
      end,
      StanzaId = safe_get_msg_id(Packet),
      Type = safe_get_msg_type(Packet),
      {FUserId, _, FResource} = safe_get_from_parts(Packet),
      {TUserId, _, TResource} = safe_get_to_parts(Packet),
      ?LOG_INFO("publishing to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, Queue,
        #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
      case amqp_channel:cast(ChannelPid,
        #'basic.publish'{
          exchange = RMExchange,
          routing_key = Queue},
        #amqp_msg{payload = list_to_binary(Payload)}) of
        ok ->
          ?LOG_INFO("published to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p", [TUserId, RMExchange, Queue,
            #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}]),
          {ok, <<"success">>};
        Error ->
          ?LOG_INFO("publish_failed to rabbitmq for user=~p with exchange=~p routing_key=~p stanza: ~p error=~p", [TUserId, RMExchange, Queue,
            #{stanza_id => StanzaId, type => Type, from_user_id => FUserId, from_resource => FResource, to_user_id => TUserId, to_resource => TResource}, Error]),
          ?ERROR_MSG("IOS: Unable to send push messages to the rabbitmq server server: ~p", [Error])
      end
  end.

response_to_binary(Json) when is_binary(Json) -> Json;
response_to_binary(Json) when is_list(Json) ->
  list_to_binary(Json).

create_json(List1, List2, Token, Mode, ViopStatus,Expiration, PushType) ->
  if Expiration =:= 0 ->
    if PushType =:= <<"fcm">> ->
    lists:append(["{\"deviceToken\":\"", Token, "\",\"isVoip\":\"", integer_to_list(ViopStatus), "\",\"mode\":\"", binary_to_list(Mode), "\",\"data\":{",  create_keyvalue(List2), "}}"]);

    true ->
      lists:append(["{\"deviceToken\":\"", Token, "\",\"isVoip\":\"", integer_to_list(ViopStatus), "\",\"mode\":\"", binary_to_list(Mode), "\",\"data\":{\"aps\":{", create_keyvalue(List1),
    "}, ", create_keyvalue(List2), "}}"])
    end;
  true ->
  % if PushType =:= <<"fcm">> ->
  %   lists:append(["{\"deviceToken\":\"", Token, "\",\"isVoip\":\"", integer_to_list(ViopStatus), "\",\"expiration\":\"", integer_to_list(Expiration), "\",\"mode\":\"", binary_to_list(Mode), "\",\"data\":{",  create_keyvalue(List2), "}}"]);

  %   true ->
      lists:append(["{\"deviceToken\":\"", Token, "\",\"isVoip\":\"", integer_to_list(ViopStatus), "\",\"expiration\":\"", integer_to_list(Expiration), "\",\"mode\":\"", binary_to_list(Mode), "\",\"data\":{\"aps\":{", create_keyvalue(List1),
    "}, ", create_keyvalue(List2), "}}"])
    % end
  end.


% helper for creating json
create_keyvalue([Head]) -> create_pair(Head);
create_keyvalue([Head | Tail]) ->
  lists:append([create_pair(Head), ",",
    create_keyvalue(Tail)]).

create_pair({Key, Value}) ->
  case Key of
    Key when is_binary(Key) ->
      lists:append([add_quotes(binary_to_list(Key)), ":", add_quotes(Value)]);
    _ ->
      lists:append([add_quotes(atom_to_list(Key)), ":",
        add_quotes(Value)])
  end.

add_quotes(String) ->
  lists:append(["\"", String, "\""]).

safe_get_msg_id(Packet) ->
  try xmpp:get_id(Packet) catch _:_ -> <<>> end.

safe_get_msg_type(Packet) ->
  try xmpp:get_type(Packet) catch _:_ -> <<>> end.

safe_get_from_parts(Packet) ->
  try jid:tolower(xmpp:get_from(Packet)) catch _:_ -> {<<>>, <<>>, <<>>} end.

safe_get_to_parts(Packet) ->
  try jid:tolower(xmpp:get_to(Packet)) catch _:_ -> {<<>>, <<>>, <<>>} end.

    apns_single_push(DeviceToken, UserType, VoipDeviceToken, _IOSVersion, ChatType, Sender,
    Recipient, SubEl, TimestampValue, Packet,
    #state{host = _Host, rabbitmq_connection = Channel, rabbitmq_exchange = RMExchange}, Mode, PushType) ->

  if ChatType == <<"chat">> ->
    MessageId = fxml:get_attr_s(<<"id">>,
      Packet#xmlel.attrs),

      ContentAcknowledge = xmpp:get_subtag(xmpp:decode(Packet), #chatcontent{}),

      if ContentAcknowledge =:= false ->
        MessageType = <<"">>,
        EditMsgId = MessageId,
        MentionList = <<"">>;
        true ->
        {_,_,_,_,MessageType,_,_,EditMsgId,MentionList,DisappearAt,_} = ContentAcknowledge
        end,

    Server = Recipient#jid.server,
    % DecryptedMessage = fly_mod_security:aes_decrpyt(binary_to_list(MessageId),
    %     SubEl),
    % Message1 = http_uri:decode(binary_to_list(DecryptedMessage)),
    % ParsedMessageJson = jiffy:decode(response_to_binary(Message1)),
    % MessageType = proplists:get_value(<<"message_type">>, element(1, ParsedMessageJson)),
    FromUser = Sender#jid.luser,
  case catch
  fly_mod_utils:get_nickname(Recipient#jid.server, FromUser)
of
  {selected, _, []} -> UserprofileNickName = FromUser;
  {selected, [{UserprofileNick}]} -> UserprofileNickName = UserprofileNick
end,

    case catch
        fly_mod_utils:get_roster_nick(Recipient#jid.server,
          Recipient#jid.user, FromUser)
      of
        {selected, _, []} -> UserNickName = UserprofileNickName;
        {selected, _, [[Nick]]} -> UserNickName = Nick
      end,

    ChangedMessage = case MessageType of
                        <<"image">> ->
                        Message_Content = <<"">>,
                        binary_to_list(UserNickName) ++
                        ": " ++ binary_to_list(<<"Image">>);
                        <<"audio">> ->
                        Message_Content = SubEl,
                        binary_to_list(UserNickName) ++
                        ": " ++ binary_to_list(<<"Audio">>);
                        <<"video">> ->
                        Message_Content = <<"">>,
                        binary_to_list(UserNickName) ++
                        ": " ++ binary_to_list(<<"Video">>);
                        <<"location">> ->
                        Message_Content = SubEl,
                        binary_to_list(UserNickName) ++
                        ": " ++ binary_to_list(<<"Location">>);
                        <<"contact">> ->
                        Message_Content = SubEl,
                        binary_to_list(UserNickName) ++
                        ": " ++ binary_to_list(<<"Contact">>);
                        <<"meet">> ->
                        Message_Content = SubEl,
                        binary_to_list(UserNickName) ++
                        ": " ++ binary_to_list(<<"Meet">>);
                        <<"story_reply">> ->
                        Message_Content = <<"">>,
                        binary_to_list(UserNickName);
                        _ ->
                        Message_Content = SubEl,
                        binary_to_list(UserNickName)
                      end,
    FromUser = Sender#jid.luser,
    ToUser = Recipient#jid.luser,
    SendFrom = list_to_binary(binary_to_list(FromUser) ++
      "@" ++ binary_to_list(Server)),
    SendTo = list_to_binary(binary_to_list(ToUser) ++
      "@" ++ binary_to_list(Server)),
    Expiry = 0,

    Args = [{message_id, binary_to_list(MessageId)},
      {message_time, binary_to_list(TimestampValue)},
      {chat_type, binary_to_list(ChatType)},
      {message_content, binary_to_list(Message_Content)},
      {from_user, binary_to_list(SendFrom)},
      {user_name, binary_to_list(UserNickName)},
      {push_from, binary_to_list(<<"MirrorFly">>)},
      {userDomain, binary_to_list(Recipient#jid.server)},
      {user_type, binary_to_list(UserType)},
      {to_user, binary_to_list(SendTo)},
      {type, binary_to_list(MessageType)}],

      Msg = [{<<"mutable-content">>, integer_to_list(1)},
        {alert, ChangedMessage},
        {mode, binary_to_list(Mode)},
        {sound, binary_to_list(<<"default">>)}],
      JSON = create_json(Msg, Args, binary_to_list(DeviceToken), Mode,0,0,PushType),
      if (EditMsgId =:= MessageId) or (EditMsgId =:= <<"">>) ->
      send_payload(JSON, ChatType, Channel, RMExchange,Server, PushType, Packet);
      true ->
        ok
      end;
    ChatType == <<"adminblock">> ->

      Server = Recipient#jid.server,
      FromUser = Sender#jid.luser,
    case catch
    fly_mod_utils:get_nickname(Recipient#jid.server, FromUser)
  of
    {selected, _, []} -> UserprofileNickName = FromUser;
    {selected, [{UserprofileNick}]} -> UserprofileNickName = UserprofileNick
  end,
      case catch
        fly_mod_utils:get_roster_nick(Recipient#jid.server,
          Recipient#jid.user, FromUser)
      of
        {selected, _, []} -> UserNickName = UserprofileNickName;
        {selected, _, [[Nick]]} -> UserNickName = Nick
      end,
      FromUser = Sender#jid.luser,
      Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),
      FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
      SendFrom = list_to_binary(binary_to_list(FromUser) ++
        "@" ++ binary_to_list(Server)),
      AdminBlock = fxml:get_subtag_with_xmlns(Packet, <<"admin_block">>,
        <<"urn:xmpp:receipts">>),
      {value, BlockStatus} = fxml:get_tag_attr(<<"block_status">>,
        AdminBlock),
      {value, Jid} = fxml:get_tag_attr(<<"jid">>, AdminBlock),

      Message = binary_to_list(UserNickName) ++
        ": " ++ binary_to_list(<<"Block Status">>),
      Args = [{user_jid, binary_to_list(Jid)},
        {push_from, binary_to_list(<<"MirrorFly">>)},
        {userDomain, binary_to_list(Recipient#jid.server)},
        {user_name, binary_to_list(UserNickName)},
        {type, binary_to_list(<<"adminblock">>)},
        {userDomain, binary_to_list(Server)},
        {user_type, binary_to_list(UserType)},
        {block_status, binary_to_list(BlockStatus)}],

        Msg = [{<<"mutable-content">>, integer_to_list(1)},
          {alert, Message},
          {mode, binary_to_list(Mode)},
          {sound, binary_to_list(<<"default">>)}],
        JSON = create_json(Msg, Args, binary_to_list(DeviceToken), Mode,0,0,PushType),
        send_payload(JSON, ChatType, Channel, RMExchange,Server, PushType, Packet);

    ChatType == <<"recall">> ->
      RecallChattype = fxml:get_attr_s(<<"type">>, Packet#xmlel.attrs),
      Server = Recipient#jid.server,
      FromUser = Sender#jid.luser,
      SendFrom = list_to_binary(binary_to_list(FromUser) ++
        "@" ++ binary_to_list(Server)),

    case catch
    fly_mod_utils:get_nickname(Recipient#jid.server, FromUser)
  of
    {selected, _, []} -> UserprofileNickName = FromUser;
    {selected, [{UserprofileNick}]} -> UserprofileNickName = UserprofileNick
  end,
      case catch
        fly_mod_utils:get_roster_nick(Recipient#jid.server,
          Recipient#jid.user, FromUser)
      of
        {selected, _, []} -> UserNickName = UserprofileNickName;
        {selected, _, [[Nick]]} -> UserNickName = Nick
      end,
      FromUser = Sender#jid.luser,

      ReCall = fxml:get_subtag_with_xmlns(Packet, <<"recall">>,
        <<"urn:xmpp:receipts">>),
      {value, MessageId} = fxml:get_tag_attr(<<"id">>,
        ReCall),

      Message = binary_to_list(<<"This message was deleted">>),
      Range = binary:split(MessageId, <<",">>, [global]),
        lists:foreach(fun(DeleteMsgID) ->
          Args = [
        {message_id, binary_to_list(DeleteMsgID)},
        {from_user, binary_to_list(SendFrom)},
        {userDomain, binary_to_list(Recipient#jid.server)},
        {user_name, binary_to_list(UserNickName)},
        {chat_type, binary_to_list(RecallChattype)},
        {userDomain, binary_to_list(Server)},
        {user_type, binary_to_list(UserType)},
        {push_from, binary_to_list(<<"MirrorFly">>)},
        {type, binary_to_list(<<"recall">>)}],

        Msg = [{<<"mutable-content">>, integer_to_list(1)},
          {alert, Message},
          {mode, binary_to_list(Mode)},
          {sound, binary_to_list(<<"default">>)}],
        JSON = create_json(Msg, Args, binary_to_list(DeviceToken), Mode,0,0,PushType),

        send_payload(JSON, ChatType, Channel, RMExchange,Server, PushType, Packet)
                      end, Range);
      ChatType == <<"reaction">>; ChatType == <<"group_reaction">> ->

          Server = Recipient#jid.server,
          FromUser = Sender#jid.luser,

          %% Get nickname
          case catch fly_mod_utils:get_nickname(Server, FromUser) of
              {selected, _, []} ->
                  UserprofileNickName = FromUser;
              {selected, [{UserprofileNick}]} ->
                  UserprofileNickName = UserprofileNick
          end,

          case catch fly_mod_utils:get_roster_nick(
                  Server, Recipient#jid.user, FromUser) of
              {selected, _, []} ->
                  UserNickName = UserprofileNickName;
              {selected, _, [[Nick]]} ->
                  UserNickName = Nick
          end,

          %% Extract reaction element safely
          ReactionEl = fxml:get_subtag_with_xmlns(Packet, <<"reaction">>,<<"urn:xmpp:receipts">>),
          case ReactionEl of
              #xmlel{attrs = Attrs} ->
                  Action    = fxml:get_attr_s(<<"action">>, Attrs),
                  EmojiId   = fxml:get_attr_s(<<"emoji_id">>, Attrs),
                  FromUserJid= fxml:get_attr_s(<<"from_user">>, Attrs), % reaction sender
                  MsgId     = fxml:get_attr_s(<<"message_id">>, Attrs),
                  Timestamp = fxml:get_attr_s(<<"timestamp">>, Attrs),
                  StanzaId = fxml:get_attr_s(<<"id">>, Packet#xmlel.attrs),
                  ToUser = Recipient#jid.luser, % messag sender

                  AlertMessage = binary_to_list(UserNickName) ++ " reacted with " ++ binary_to_list(EmojiId), {<<"type">>, <<"reaction">>},

                  Args0 = [
                      {type, binary_to_list(<<"reaction">>)},
                      {chat_type, binary_to_list(if ChatType == <<"group_reaction">> -> <<"normal">>; true -> <<"chat">> end)},
                      {action, binary_to_list(Action)},
                      {message_id, binary_to_list(MsgId)},
                      {reaction_id, binary_to_list(StanzaId)},
                      {reaction_to, binary_to_list(jid:to_string(Recipient))},
                      {reaction_from, binary_to_list(FromUserJid)},
                      {emoji_id, binary_to_list(EmojiId)},
                      {timestamp, binary_to_list(Timestamp)},
                      {userDomain, binary_to_list(Server)},
                      {user_type, binary_to_list(PushType)},
                      {chat_id, binary_to_list(jid:to_string(Sender))},
                      {push_from, binary_to_list(<<"MirrorFly">>)}
                  ],

                  Msg = [
                      {<<"mutable-content">>, integer_to_list(1)},
                      {alert, AlertMessage},
                      {mode, binary_to_list(Mode)},
                      {sound, binary_to_list(<<"default">>)}
                  ],

                  case ChatType of
                    <<"group_reaction">> ->
                      MsgSender = fxml:get_attr_s(<<"message_sender">>, Attrs),
                      
                      Args1 = Args0 ++ [{message_sender,  binary_to_list(MsgSender)}],
                      ?LOG_INFO("MsgSender ~p ToUser ~p is equal? ~p", [MsgSender, ToUser, MsgSender =:= ToUser]),

                      case MsgSender =:= ToUser of
                        true ->
                            JSON = create_json(Msg, Args1, binary_to_list(DeviceToken), Mode, 0, 0, PushType),

                            ?LOG_INFO("[group ios_push] reaction payload: ~p", [JSON]),
                            if Action == <<"update">>; Action == <<"remove">> ->  
                              FUser = fly_mod_utils:get_user_from_string_jid(FromUserJid),
                              ?LOG_INFO("Updating push sent status for reaction update, message id: ~p, user: ~p, toUser: ~p", [MsgId, FUser, ToUser]),
                              fly_mod_utils:update_push_sent(Server, FUser, ToUser, MsgId);
                             true -> 
                              ok
                            end,
                            send_payload(JSON, ChatType, Channel, RMExchange, Server, PushType, Packet);
                        false ->
                          ?LOG_INFO("skipping ios group push, reaction should only route for message sender ~p but got ~p",[MsgSender, ToUser]),
                          ok
                      end;

                    <<"reaction">> ->
                      Q = fly_mod_utils:chat_history_query(Server, MsgId),
                      ?LOG_INFO("Chat history query result for reaction push: ~p", [Q]),
                      case Q of 
                        {selected, _, [[F, _, _, _, _]]} -> 
                          if FromUser =/= F -> 
                            JSON = create_json(Msg, Args0, binary_to_list(DeviceToken), Mode, 0, 0, PushType),

                            ?LOG_INFO("[ios_push]] reaction payload: ~p", [JSON]),
                            send_payload(JSON, ChatType, Channel, RMExchange, Server, PushType, Packet);
                          true ->
                            ?LOG_INFO("skipping ios push, reaction is from message sender ~p",[FromUser]),
                            ok
                          end;
                        _ ->
                          ok
                        end;
                    _ ->
                      ok
                  end;
              _ ->
                  ok
          end;
        ChatType == <<"poll">> ->
          MessageId = fxml:get_attr_s(<<"id">>,Packet#xmlel.attrs),
                        Server = Recipient#jid.server,
                        FromUser = Sender#jid.luser,
                        SendFrom = list_to_binary(binary_to_list(FromUser) ++
                          "@" ++ binary_to_list(Server)),

                      case catch
                      fly_mod_utils:get_nickname(Recipient#jid.server, FromUser)
                    of
                      {selected, _, []} -> UserprofileNickName = FromUser;
                      {selected, [{UserprofileNick}]} -> UserprofileNickName = UserprofileNick
                    end,
                        case catch
                          fly_mod_utils:get_roster_nick(Recipient#jid.server,
                            Recipient#jid.user, FromUser)
                        of
                          {selected, _, []} -> UserNickName = UserprofileNickName;
                          {selected, _, [[Nick]]} -> UserNickName = Nick
                        end,
                        FromUser = Sender#jid.luser,

                        ElementAcknowledge = xmpp:get_subtag(xmpp:decode(Packet), #poll{}),
                      {poll,PollId,VoterUserId,VoteId,Status,_Chattype,PollOptionId,PollUser} = ElementAcknowledge,
                      VoterId = fly_mod_utils:get_user_from_string_jid(VoterUserId),
                        Message = binary_to_list(Status),

                            Args = [
                          {poll_id, binary_to_list(PollId)},
                          {voter_user_id, binary_to_list(VoterId)},
                          {vote_id, binary_to_list(VoteId)},
                          {status, binary_to_list(Status)},
                          {poll_option_id, binary_to_list(PollOptionId)},
                          {to_user, binary_to_list(PollUser)},
                          {from_user, binary_to_list(SendFrom)},
                          {message_id, binary_to_list(MessageId)},
                          {userDomain, binary_to_list(Recipient#jid.server)},
                          {poll_time, binary_to_list(TimestampValue)},
                          {user_name, binary_to_list(UserNickName)},
                          {chat_type, Message},
                          {userDomain, binary_to_list(Server)},
                          {user_type, binary_to_list(UserType)},
                          {push_from, binary_to_list(<<"MirrorFly">>)},
                          {type, binary_to_list(<<"poll">>)}],

                          Msg = [{<<"mutable-content">>, integer_to_list(1)},
                            {alert, Message},
                            {mode, binary_to_list(Mode)},
                            {sound, binary_to_list(<<"default">>)}],
                          JSON = create_json(Msg, Args, binary_to_list(DeviceToken), Mode,0,0,PushType),
                          send_payload(JSON, ChatType, Channel, RMExchange,Server, PushType, Packet);
    ChatType == <<"mediacall">> ->
      Server = Recipient#jid.server,
      FromUser = Sender#jid.luser,
    case catch
    fly_mod_utils:get_nickname(Recipient#jid.server, FromUser)
  of
    {selected, _, []} -> UserprofileNickName = FromUser;
    {selected, [{UserprofileNick}]} -> UserprofileNickName = UserprofileNick
  end,
      case catch
        fly_mod_utils:get_roster_nick(Recipient#jid.server,
          Recipient#jid.user, FromUser)
      of
        {selected, _, []} -> UserNickName = UserprofileNickName;
        {selected, _, [[Nick]]} -> UserNickName = Nick
      end,

      FromUser = Sender#jid.luser,
      SendFrom = list_to_binary(binary_to_list(FromUser) ++
        "@" ++ binary_to_list(Server)),
      MediaCall = fxml:get_subtag_with_xmlns(Packet, <<"mediacall">>,
        <<"urn:xmpp:call">>),

      RoomId = case fxml:get_tag_attr(<<"room_id">>, MediaCall) of
                  {value, Roomid} ->
                  Roomid;
                  _ ->
                  <<"">>
                end,
      CallType = case fxml:get_tag_attr(<<"call_type">>, MediaCall) of
                    {value, Calltype} ->
                    Calltype;
                    _ ->
                    <<"">>
                  end,
      CallTime = case fxml:get_tag_attr(<<"call_time">>, MediaCall) of
                    {value, Calltime} ->
                    Calltime;
                    _ ->
                    <<"">>
                  end,
      CallMode = case fxml:get_tag_attr(<<"call_mode">>, MediaCall) of
                    {value, Callmode} ->
                    Callmode;
                    _ ->
                    <<"">>
                  end,
      CallStatus = case fxml:get_tag_attr(<<"call_status">>, MediaCall) of
                    {value, Callstatus} ->
                    Callstatus;
                    _ ->
                    <<"">>
                    end,
      GroupCallId = case fxml:get_tag_attr(<<"group_id">>, MediaCall) of
                    {value, GroupcallId} ->
                    GroupcallId;
                    _ ->
                    <<"">>
                    end,
      RoomLink = case fxml:get_tag_attr(<<"call_link">>, MediaCall) of
        {value, Roomlink} ->
          Roomlink;
        _ ->
          <<"">>
      end,

      MetaData = case fxml:get_tag_attr(<<"meta_data">>, MediaCall) of
      {value, Metadata} ->
        Metadata;
      _ ->
        <<"">>
    end,

      SessionStatus = case fxml:get_tag_attr(<<"session_status">>, MediaCall) of
                        {value, Sessionstatus} ->
                          Sessionstatus;
                        _ ->
                          <<"">>
                      end,
      StartTime = case fxml:get_tag_attr(<<"start_time">>, MediaCall) of
                    {value, Starttime} ->
                      Starttime;
                    _ ->
                      <<"">>
                  end,
      EndTime = case fxml:get_tag_attr(<<"end_time">>, MediaCall) of
                  {value, Endtime} ->
                    Endtime;
                  _ ->
                    <<"">>
                end,

      if GroupCallId =:= <<"">> ->
        GroupName = <<"">>,
        Message = binary_to_list(UserNickName) ++ ": Incoming call";
      true ->
        GroupIdUser = fly_mod_utils:get_user_from_string_jid(GroupCallId),
        {selected, [{GroupName}]} = fly_mod_utils:get_nickname(Server, GroupIdUser),
        Message = binary_to_list(GroupName) ++ ": Incoming call"
              end,
              Expiry = get_timestamp(),

      case fxml:get_subtag(MediaCall, <<"users">>) of
        false  ->

          ok;

        Users ->
          User = lists:flatmap(fun(U) ->
            [fxml:get_tag_cdata(U)] end, Users#xmlel.children),
            case fxml:get_subtag(MediaCall, <<"invite">>) of
          false  ->
          Args = [
            {room_id, binary_to_list(RoomId)},
            {caller_id, binary_to_list(SendFrom)},
            {users, lists:flatten(lists:join(",", [binary_to_list(B) || B <- User]))},
            {call_type, binary_to_list(CallType)},
            {call_status, binary_to_list(CallStatus)},
            {push_from, binary_to_list(<<"MirrorFly">>)},
            {group_id, binary_to_list(GroupCallId)},
            {start_time, binary_to_list(StartTime)},
            {caller_name,binary_to_list(UserNickName)},
            {group_name,binary_to_list(GroupName)},
            {userDomain, binary_to_list(Recipient#jid.server)},
            {user_type, binary_to_list(UserType)},
            {end_time, binary_to_list(EndTime)},
            {call_link, binary_to_list(RoomLink)},
            {session_status, binary_to_list(SessionStatus)},
            {userDomain, binary_to_list(Server)},
            {call_time, CallTime},
            {meta_data, binary_to_list(MetaData)},
            {expiration, integer_to_list(Expiry)},
            {call_mode, binary_to_list(CallMode)},
            {type, "media_call"}];
          InviteUsers ->
            InviteUser = lists:flatmap(fun(I) ->
            [fxml:get_tag_cdata(I)] end, InviteUsers#xmlel.children),
            Args = [
            {room_id, binary_to_list(RoomId)},
            {caller_id, binary_to_list(SendFrom)},
            {users, lists:flatten(lists:join(",", [binary_to_list(B) || B <- User]))},
            {inviteusers, lists:flatten(lists:join(",", [binary_to_list(C) || C <- InviteUser]))},
            {call_type, binary_to_list(CallType)},
            {call_status, binary_to_list(CallStatus)},
            {push_from, binary_to_list(<<"MirrorFly">>)},
            {group_id, binary_to_list(GroupCallId)},
            {caller_name,binary_to_list(UserNickName)},
            {group_name,binary_to_list(GroupName)},
            {userDomain, binary_to_list(Recipient#jid.server)},
            {user_type, binary_to_list(UserType)},
            {start_time, binary_to_list(StartTime)},
            {end_time, binary_to_list(EndTime)},
            {call_link, binary_to_list(RoomLink)},
            {userDomain, binary_to_list(Server)},
            {session_status, binary_to_list(SessionStatus)},
            {call_time, CallTime},
            {meta_data, binary_to_list(MetaData)},
            {expiration, integer_to_list(Expiry)},
            {call_mode, binary_to_list(CallMode)},
            {type, "media_call"}]
          end,

                Msg = [{<<"mutable-content">>, integer_to_list(1)},
                {alert, Message},
                {mode, binary_to_list(Mode)},
                {sound, binary_to_list(<<"default">>)}],
                JSON = create_json(Msg, Args, binary_to_list(VoipDeviceToken), Mode,1,Expiry,PushType),

          send_payload(JSON, ChatType, Channel, RMExchange,Server, PushType, Packet)
      end;
    ChatType == <<"meeting_reminder">> ->
      Server = Recipient#jid.server,
      Meeting = fxml:get_subtag_with_xmlns(Packet, <<"meeting">>,
        <<"urn:xmpp:receipts">>),
      MessageId = fxml:get_attr_s(<<"message_id">>, Meeting#xmlel.attrs),
      SessionId = fxml:get_attr_s(<<"session_id">>, Meeting#xmlel.attrs),
      RoomId = fxml:get_attr_s(<<"room_id">>, Meeting#xmlel.attrs),
      ChatId = fxml:get_attr_s(<<"chat_id">>, Meeting#xmlel.attrs),
      CallMode = fxml:get_attr_s(<<"call_mode">>, Meeting#xmlel.attrs),
      CallType = fxml:get_attr_s(<<"call_type">>, Meeting#xmlel.attrs),
      ScheduledAt = fxml:get_attr_s(<<"scheduled_at">>, Meeting#xmlel.attrs),
      TouserJid = fxml:get_attr_s(<<"user_jid">>, Meeting#xmlel.attrs),
    
      ReminderMins = fxml:get_attr_s(<<"reminder_before_minutes">>, Meeting#xmlel.attrs),
      Status = fxml:get_attr_s(<<"status">>, Meeting#xmlel.attrs),
      MessageFrom = fxml:get_attr_s(<<"message_from">>, Meeting#xmlel.attrs),
      ChatTypeParam = fxml:get_attr_s(<<"chat_type">>, Meeting#xmlel.attrs),
      MessageTo = fxml:get_attr_s(<<"message_to">>, Meeting#xmlel.attrs),

      Args = [
        {type, "meeting_reminder"},
        {status, binary_to_list(Status)},
        {session_id, binary_to_list(SessionId)},
        {room_id, binary_to_list(RoomId)},
        {chat_id, binary_to_list(ChatId)},
        {call_mode, binary_to_list(CallMode)},
        {user_jid, binary_to_list(TouserJid)},
        {call_type, binary_to_list(CallType)},
        {scheduled_at, binary_to_list(ScheduledAt)},
        {message_id, binary_to_list(MessageId)},
        {reminder_before_minutes, binary_to_list(ReminderMins)},
        {userDomain, binary_to_list(Server)},
        {user_type, binary_to_list(UserType)},
        {push_from, binary_to_list(<<"MirrorFly">>)},
        {message_from, binary_to_list(MessageFrom)},
        {chat_type, binary_to_list(ChatTypeParam)},
        {message_to, binary_to_list(MessageTo)}
      ],

      Msg = [
        {<<"mutable-content">>, integer_to_list(1)},
        {alert, "Meeting Reminder"},
        {mode, binary_to_list(Mode)},
        {sound, binary_to_list(<<"default">>)}
      ],
      JSON = create_json(Msg, Args, binary_to_list(DeviceToken), Mode, 0, 0, PushType),
      send_payload(JSON, ChatType, Channel, RMExchange, Server, PushType, Packet);
    true -> {ok, <<"chat type is different in ios">>,ChatType}
  end.

apns_group_push(DeviceToken, UserType, ChatType, Sender,
    Recipient, GroupName, SubEl, TimestampValue, Packet,
    #state{rabbitmq_connection = Channel, rabbitmq_exchange = RMExchange}, Mode, PushType) ->
  #jid{luser = LUser, lserver = LServer} = Recipient,
  #jid{luser = FUser, lserver = FServer} = Sender,
  {MSeconds, Seconds, _} = erlang:now(),
  Expiry = 0,
  if (ChatType == <<"normal">>) and (Packet =/= "") ->
    Event = fxml:get_subtag(Packet, <<"event">>),
    Items = fxml:get_subtag(Event, <<"items">>),
    {value, NameSpace} = fxml:get_tag_attr(<<"node">>,
      Items),
    if (Items =/= false) and
      (NameSpace =:= <<"urn:xmpp:mix:nodes:messages">>) ->
      GroupId = list_to_binary(binary_to_list(FUser) ++
        "@" ++ binary_to_list(FServer)),
      {value, MessageId} = fxml:get_tag_attr(<<"message_id">>,
        SubEl),
      {value, MsgFrom} = fxml:get_tag_attr(<<"sent_from">>,
        SubEl),
      Message = fxml:get_tag_cdata(SubEl),
      DecryptedMessage = fly_mod_security:aes_decrpyt(binary_to_list(MessageId), Message),
      Message1 = http_uri:decode(binary_to_list(DecryptedMessage)),
      ParsedMessageJson = jiffy:decode(response_to_binary(Message1)),
      MessageType = proplists:get_value(<<"message_type">>,
        element(1,
          ParsedMessageJson)),
      [N, _H] = string:tokens(binary_to_list(MsgFrom), "@"),
      Name = list_to_binary(N),
      {selected, [{UserNickName}]} = fly_mod_utils:get_nickname(Recipient#jid.server, Name),

      ChangedMessage = case MessageType of
                          <<"image">> ->
                          Message_Content = <<"">>,
                          binary_to_list(UserNickName) ++
                            "@" ++
                            binary_to_list(GroupName) ++
                            ": " ++
                            binary_to_list(<<"Image">>);
                          <<"audio">> ->
                          Message_Content = Message,
                          binary_to_list(UserNickName) ++
                            "@" ++
                            binary_to_list(GroupName) ++
                            ": " ++
                            binary_to_list(<<"Audio">>);
                          <<"video">> ->
                          Message_Content = <<"">>,
                          binary_to_list(UserNickName) ++
                            "@" ++
                            binary_to_list(GroupName) ++
                            ": " ++
                            binary_to_list(<<"Video">>);
                          <<"location">> ->
                          Message_Content = Message,
                          binary_to_list(UserNickName) ++
                            "@" ++
                            binary_to_list(GroupName) ++
                            ": " ++
                            binary_to_list(<<"Location">>);
                          <<"contact">> ->
                          Message_Content = Message,
                          binary_to_list(UserNickName) ++
                            "@" ++
                            binary_to_list(GroupName) ++
                            ": " ++
                            binary_to_list(<<"Contact">>);
                          <<"story_reply">> ->
                          Message_Content = <<"">>,
                          binary_to_list(UserNickName) ++
                            "@" ++
                            binary_to_list(GroupName);
                          _ ->
                          Message_Content = Message,

                          binary_to_list(UserNickName) ++
                            "@" ++
                            binary_to_list(GroupName)
                        end,
      Msg = [{<<"mutable-content">>, integer_to_list(1)},
        {alert, ChangedMessage},  {mode, binary_to_list(Mode)},
        {sound, binary_to_list(<<"default">>)}],
      Args = [{message_id, binary_to_list(MessageId)},
        {message_time, binary_to_list(TimestampValue)},
        {chat_type, binary_to_list(ChatType)},
        {message_content, binary_to_list(Message_Content)},
        {from_user, binary_to_list(GroupId)},
        {group_name, binary_to_list(GroupName)},
        {user_name,binary_to_list(UserNickName)},
        {user_type, binary_to_list(UserType)},
        {push_from, binary_to_list(<<"MirrorFly">>)},
        {userDomain, binary_to_list(Recipient#jid.server)},
        {sent_from, binary_to_list(MsgFrom)},
        {type, binary_to_list(MessageType)}],
      JSON = create_json(Msg, Args, binary_to_list(DeviceToken), Mode,0,0,PushType),
      send_payload(JSON, ChatType, Channel, RMExchange, LServer, PushType, Packet);
      (Items =/= false) and
        (NameSpace =:= <<"urn:xmpp:mix:nodes:participants">>) ->
        Item = fxml:get_subtag(Items, <<"item">>),
        {value, MsgFrom} = fxml:get_tag_attr(<<"publisher">>,
          Item),
        {value, NodeId} = fxml:get_tag_attr(<<"id">>, Item),
        Participant = fxml:get_subtag(Item, <<"participant">>),
        NotifyId = fxml:get_attr_s(<<"id">>,
          Packet#xmlel.attrs),
        {value, ParticipantJid} = fxml:get_tag_attr(<<"jid">>,
          Participant),
        SendFrom = list_to_binary(binary_to_list(LUser) ++
          "@" ++ binary_to_list(LServer)),
        GroupId = list_to_binary(binary_to_list(FUser) ++
          "@" ++ binary_to_list(FServer)),
        [N, _H] = string:tokens(binary_to_list(MsgFrom), "@"),
        Name = list_to_binary(N),
        {selected, [{UserNickName}]} = fly_mod_utils:get_nickname(Recipient#jid.server, Name),
          case fxml:get_subtag(Items, <<"retract">>) of
          false ->
            MessageContent = <<GroupName / binary, <<":">> / binary, UserNickName / binary,  <<" added you">> / binary>>;
          Item ->
            MessageContent = <<GroupName / binary, <<":">> / binary,  UserNickName / binary, <<" removed you">> / binary>>
        end,

        if ParticipantJid =:= SendFrom ->
          Msg = [{<<"mutable-content">>, integer_to_list(1)},
            {alert, binary_to_list(MessageContent)},
            {mode, binary_to_list(Mode)},
            {sound, binary_to_list(<<"default">>)}],
          Args = [{message_content,
            binary_to_list(MessageContent)},
            {group_name, binary_to_list(GroupName)},
            {user_name, binary_to_list(UserNickName)},
            {sent_from, binary_to_list(MsgFrom)},
            {notify_id, binary_to_list(NotifyId)},
            {caller_name,binary_to_list(UserNickName)},
            {user_type, binary_to_list(UserType)},
            {added_at, binary_to_list(TimestampValue)},
            {push_from, binary_to_list(<<"MirrorFly">>)},
            {userDomain, binary_to_list(Recipient#jid.server)},
            {node_id, binary_to_list(NodeId)},
            {group_id, binary_to_list(GroupId)}],
          JSON = create_json(Msg, Args, binary_to_list(DeviceToken), Mode,0,Expiry,PushType),
         
          send_payload(JSON, ChatType, Channel, RMExchange, LServer, PushType, Packet);
         
          true -> {ok, <<"ParticipantJid =/= SendFrom ios">>}
        end;
      true ->
        {ok,
          <<"item empty and namspace changed in group "
          "ios">>}
    end;
    true -> {ok, <<"chat type is different in group ios">>}
  end.

%% Hook lisenter to for offline message hook
%%
%% @param record Sender
%% @param record Recipient
%% @param record Packet
%% @return atom

queryexecfunction(From, clearall, Chat_Type, Delete_Type, XMLBody)->
  Server = gen_mod:get_module_proc(From#jid.lserver,
    ?PROCNAME),

  queryfunction(Server,<<"clear_all">>, From, Chat_Type, Delete_Type, XMLBody);
queryexecfunction(From, calllog, Chat_Type, Delete_Type, XMLBody)->
  Server = gen_mod:get_module_proc(From#jid.lserver,
    ?PROCNAME),

  queryfunction(Server,<<"call_log">>, From, Chat_Type, Delete_Type, XMLBody).

groupcreationfunction(From, groupcreation, Participants, Channel, GroupJID, SubEl, IQ, MessageId1,CustomAttributes)->
  Server = gen_mod:get_module_proc(From#jid.lserver,
    ?PROCNAME),
groupcreationfunction(Server,<<"group_creation">>, From, Participants, Channel, GroupJID, SubEl, IQ, MessageId1,CustomAttributes).

send_own_offline_message(Sender, Recipient, Packet) ->
  ChatType = fxml:get_attr_s(<<"type">>, Packet#xmlel.attrs),
  SubEl = fxml:get_subtag_cdata(Packet, <<"body">>),
  Server = gen_mod:get_module_proc(Sender#jid.lserver, ?PROCNAME),
  Seen = xmpp:get_subtag(xmpp:decode(Packet), #seen{}),
      if Seen =/= false ->
        ownpush(Server, <<"chat">>, Sender, Recipient, <<"seen">>, SubEl, Packet);
      true ->
        ok
      end,
  Recall = xmpp:get_subtag(xmpp:decode(Packet), #recall{}),
      if Recall =/= false ->
      ownpush(Server, <<"chat">>, Sender, Recipient, <<"recall">>, SubEl, Packet);
      true ->
        ok
  end,
  Mute = xmpp:get_subtag(xmpp:decode(Packet), #recall{}),
  if Mute =/= false ->
  ownpush(Server, <<"chat">>, Sender, Recipient, <<"mute">>, SubEl, Packet);
  true ->
    ok
end,
  if ChatType == <<"chat">> ->
    case SubEl of
      <<"">> ->
        ok;
      _ ->
        ownpush(Server, <<"chat">>, Sender, Recipient, <<"chat">>, SubEl, Packet)
    end;
    ChatType == normal ->
      {selected, [{GroupName}]} = fly_mod_utils:get_nickname(Sender#jid.server, Recipient#jid.luser),
      EventTag = fxml:get_subtag(Packet, <<"event">>),
      Items = fxml:get_subtag(EventTag, <<"items">>),
          if Items =/= false ->
            Item = fxml:get_subtag(Items, <<"item">>),
                    if Item =/= false ->
                      MsgBody = fxml:get_subtag(Item, <<"body">>),
                      owngroup_push(Server, <<"normal">>, Sender, Recipient,
                        ChatType, MsgBody, Packet, GroupName);
                      true -> ok
                    end;
            true -> ok
          end;
    true -> ok
  end.

%% send_push_notifications
%%
%% @param record Sender
%% @param record Recipient
%% @param binary ChatType

send_own_push_notifications(Sender, Recipient, ChatType,
    SubEl, Packet, State) ->
  %% if Sender#jid.luser =/= Recipient#jid.luser ->
  Rs = has_more_resources(Sender#jid.luser,Sender#jid.server),
  case catch
    fly_mod_utils:get_user_device(Sender#jid.server,
      Sender#jid.luser,Rs,ChatType)
  of
    {selected, _, []} ->
      device_token_is_empty;
    {selected, _, Tokens} ->
    SubEls1 = lists:map(fun(G) ->
        [DeviceType, DeviceToken, VoipDeviceToken, Mode,IOSVersion, DeviceId, UserType, PushType] = G,

                    if ChatType =:= <<"call">> ->
                      TimestampValue = <<"">>;
                      true ->
                        Timestamp = fxml:get_subtag(Packet, <<"timestamp">>),
                        TimestampValue = fxml:get_attr_s(<<"time">>,
                          Timestamp#xmlel.attrs)
                    end,
                  case DeviceType of
                    <<"">> -> device_type_is_empty;
                    <<"android">> ->
                      gcm_single_push(DeviceType, DeviceToken, UserType,  ChatType, Sender,
                        Recipient, SubEl, TimestampValue, Packet,
                        State#state.rabbitmq_connection, State#state.rabbitmq_exchange);
                    % <<"ios">> ->
                    %   apns_single_push(DeviceToken,VoipDeviceToken,IOSVersion, ChatType, Sender, Recipient, SubEl, TimestampValue, Packet, State, Mode);
                    _ -> database_error
                  end

          end,Tokens);
    _Error ->
      ?INFO_MSG("push_message get_user_device_details error is ~p", [_Error]),
      ok
    %    end;
    %    true -> ok
  end.

% gets a timestamp in ms from the epoch
get_timestamp() ->
    {Mega,Sec,Micro} = erlang:now(),
    (Mega * 1000000 + Sec + 30) * 1000000 + Micro.

send_bulk_group_push_notification(FromUser, Server, MessageContent, Members, Node, Stanza, Type,  State) ->
  Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),
  FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
  ChatType = <<"normal">>,
  #jid{luser = Group, lserver = GroupHost} = FromUser,
  GroupID = list_to_binary(binary_to_list(Group) ++
    "@" ++ binary_to_list(GroupHost)),
  Expiry = 0,

  if Node =:= <<"urn:xmpp:mix:nodes:messages">> ->
    Output = get_status(Members),
    ResourcesList = get_resources(Members),
    OfflineUsers = lists:filter(fun(Elem) -> not lists:member(Elem, [0]) end, Output),
    OnlineResources = lists:filter(fun(Elem) -> not lists:member(Elem, [0]) end, ResourcesList),
    [MessageType, MessageId, MesssageSend,_GroupName, _MSGBody,_EditMsg,_MentionList, _DisappearAt, _MetaData] = MessageContent,
    case catch fly_mod_utils:get_bulk_user_device(Server, list_to_binary(OfflineUsers), list_to_binary(OnlineResources), <<"android">>,MesssageSend)
    of {selected, _, []} ->
    ok;
      {selected, _, ATokens} ->
        lists:map(fun(G) ->
          [Touser, AndroidDeviceToken, UserType, PushType] = G,
        ChangedMessage = case MessageType of
                            <<"image">> -> binary_to_list(<<"Image">>);
                            <<"audio">> -> binary_to_list(<<"Audio">>);
                            <<"video">> -> binary_to_list(<<"Video">>);
                            <<"location">> ->
                            binary_to_list(<<"Location">>);
                            <<"contact">> ->
                            binary_to_list(<<"Contact">>);
                            <<"file">> -> binary_to_list(<<"Document">>);
                            _ ->
                            binary_to_list(<<"Text">>)
                          end,
        Load = [{<<"user_jid">>, binary_to_list(GroupID)},
          {<<"sent_from">>, binary_to_list(MesssageSend)},
          {<<"sent_to">>, binary_to_list(Touser)},
          {<<"message_time">>, FlatTimeStamp},
          {<<"chat_type">>, binary_to_list(ChatType)},
          {<<"userDomain">>, binary_to_list(Server)},
          {<<"user_type">>, binary_to_list(UserType)},
          {<<"message_id">>, binary_to_list(MessageId)},
          {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
          {<<"title">>, ChangedMessage},
          {<<"type">>, binary_to_list(MessageType)}],
        AndPayload = create_android_json(AndroidDeviceToken, Load),
        send_android_payload_to_rabbitmq(State#state.rabbitmq_connection, <<"normal">>, AndPayload, State#state.rabbitmq_exchange, Server)
      end,ATokens)
    end,
    case catch fly_mod_utils:get_bulk_user_device(Server,
      OfflineUsers, OnlineResources, <<"ios">>, <<"0">>,MesssageSend)
    of {selected, _, []} -> {ok, <<"user not using ios device">>};
      {selected, _, ITokens} ->
        lists:map(fun(G) ->
          [Touser, IOSDevice, IOSDeviceUserType, IOSDevicePushType] = G,
        ios_send_bulk_push(Server, Touser, MessageContent, FromUser, FlatTimeStamp, ChatType, GroupID, <<"0">>, IOSDevice, Expiry, State,<<"13above">>,IOSDeviceUserType, IOSDevicePushType)
        end,ITokens)
    end,
    case catch fly_mod_utils:get_bulk_voip_user_device(Server,
      OfflineUsers, <<"ios">>, <<"0">>,MesssageSend)
    of {selected, _, []} -> {ok, <<"user not using ios device">>};
    {selected, _, VTokens} ->
      lists:map(fun(G) ->
      [Touser, IOSVoipDevice, IOSVoipDeviceUserType, IOSVoipDevicePushType] = G,
        ios_send_bulk_push(Server, Touser,  MessageContent, FromUser, FlatTimeStamp, ChatType, GroupID, <<"0">>, IOSVoipDevice, Expiry, State,<<"13below">>,IOSVoipDeviceUserType, IOSVoipDevicePushType)
        end,VTokens)
    end,
    case catch fly_mod_utils:get_bulk_user_device(Server,
      OfflineUsers, OnlineResources, <<"ios">>, <<"1">>,MesssageSend)
    of {selected, _, []} -> {ok, <<"user not using ios device">>};
    {selected, _, IOTokens} ->
      lists:map(fun(G) ->
      [Touser, IOSDevices, IOSDevicesUserType, IOSDevicesPushType] = G,
        ios_send_bulk_push(Server, Touser, MessageContent, FromUser, FlatTimeStamp, ChatType, GroupID, <<"1">>, IOSDevices, Expiry, State,<<"13above">>,IOSDevicesUserType, IOSDevicesPushType)
        end,IOTokens)
    end,
    case catch fly_mod_utils:get_bulk_voip_user_device(Server,
      OfflineUsers, <<"ios">>, <<"1">>,MesssageSend)
    of {selected, _, []} -> {ok, <<"user not using ios device">>};
        {selected, _, VITokens} ->
        lists:map(fun(G) ->
        [Touser, IOSVoipDevices, IOSVoipDevicesUserType, IOSVoipDevicesPushType] = G,
        ios_send_bulk_push(Server, Touser, MessageContent, FromUser, FlatTimeStamp, ChatType, GroupID, <<"1">>, IOSVoipDevices, Expiry, State,<<"13below">>,IOSVoipDevicesUserType, IOSVoipDevicesPushType)
        end,VITokens)
    end;
    Node =:= <<"urn:xmpp:mix:nodes:participants">> ->
      [Chan,MsgFrom,ParticipantJid,NodeId,UserNickName,NotifyId] = MessageContent,
      [Owner, _] = binary:split(MsgFrom, <<"@">>),
      case catch fly_mod_utils:get_bulk_group_create_android_user_device(Server,
        Members)
      of {selected, _, []} ->

        ?INFO_MSG("token is empty ~p", []),
        ok;
          {selected, _, ATokens} ->
          lists:map(fun(G) ->
          [Touser, AndroidDeviceToken, UserType, PushType] = G,
        {selected, [{UserName}]} = fly_mod_utils:get_nickname(Server, Owner),
          [NewUser, _] = binary:split(ParticipantJid, <<"@">>),
          {selected, [{ReceiverUserName}]} = fly_mod_utils:get_nickname(Server, NewUser),
          Event = fxml:get_subtag(Stanza, <<"event">>),
          Items = fxml:get_subtag(Event, <<"items">>),
          Item = fxml:get_subtag(Items, <<"item">>),
          PublisherVcard = case catch fly_mod_utils:get_vcard(Server, Owner) of
            {selected, [{PVCARD, _CreatedTime}]} ->
              PVCARD;
            {selected, []} ->
              <<"">>;
            _ ->
              <<"">>
          end,
            VCard = case catch fly_mod_utils:get_vcard(Server, Group)
              of
                {selected, [{SVCARD, _CreatedAt}]} ->
                  case fxml_stream:parse_element(SVCARD) of
                    {error, _Reason} -> [];
                    VCARD ->
                      [VCARD],
                      %% Remove the namespace from the xml
                      VCARD#xmlel{attrs = lists:keydelete(<<"xmlns">>, 1, VCARD#xmlel.attrs)}
                  end;
                {selected, []} -> SVCARD = <<"">>,
                  <<"">>;
                _ -> SVCARD = <<"">>, <<"">>
              end,
              case catch fly_mod_utils:get_group_profile_type(Server,Group) of
                                    {selected, _, []} ->
                                    Status = <<"">>,
                                    History = <<"">>,
                                    MessageMode = <<"">>,
                                    AccessMode = <<"">>,
                                    ChannelStatus = <<"">>,
                                    InviteUri = <<"">>,
                                    Description = <<"">>,
                                    CustomFeatures = <<"">>;
                                    {selected, _, [[GStatus, GHistory ,GMessageMode,GAccessMode,GChannelStatus,GInviteUri,GCustomFeatures,GDescription]]} ->
                                      Status = GStatus,
                                      History = GHistory,
                                      MessageMode = GMessageMode,
                                      AccessMode = GAccessMode,
                                      ChannelStatus = fly_mix_group_chat:map_status(GChannelStatus),
                                      InviteUri = GInviteUri,
                                      Description = GDescription,
                                      CustomFeatures = GCustomFeatures;
                                    _ ->
                                      Status = <<"">>,
                                      History = <<"">>,
                                      MessageMode = <<"">>,
                                      AccessMode = <<"">>,
                                      ChannelStatus = <<"">>,
                                      InviteUri = <<"">>,
                                      Description = <<"">>,
                                      CustomFeatures = <<"">>
                                    end,
          if Type =:= <<"added">> ->
          if NewUser =:= Members ->
            Content = <<UserNickName / binary, <<":">> / binary, UserName / binary, <<" added you">> / binary>>;
          true ->
            Content = <<UserNickName / binary, <<":">> / binary, UserName / binary, <<" added ">> / binary, ReceiverUserName / binary>>,
            ok
          end,
          CustAttr = fxml:get_subtag(Item, <<"custom_attributes">>),
          Load = [{<<"user_jid">>, binary_to_list(Chan)},
            {<<"group_id">>, binary_to_list(Chan)},
            {<<"message_content">>, binary_to_list(Content)},
            {<<"group_name">>, binary_to_list(UserNickName)},
            {<<"group_vcard">>, binary_to_list(SVCARD)},
            {<<"created_at">>, FlatTimeStamp},
            {<<"userDomain">>, binary_to_list(Server)},
            {<<"user_type">>, binary_to_list(UserType)},
            {<<"added_at">>, FlatTimeStamp},
            {<<"notify_id">>, binary_to_list(NotifyId)},
            {<<"message_time">>, FlatTimeStamp},
            {<<"node_id">>, binary_to_list(NodeId)},
            {<<"history">>, binary_to_list(History)},
            {<<"messagemode">>, binary_to_list(MessageMode)},
            {<<"accessmode">>, binary_to_list(AccessMode)},
            {<<"channel_status">>, binary_to_list(ChannelStatus)},
            {<<"invite_uri">>, binary_to_list(InviteUri)},
            {<<"customfeatures">>, binary_to_list(CustomFeatures)},
            {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
            {<<"sent_from">>, binary_to_list(MsgFrom)},
            {<<"sent_to">>, binary_to_list(Touser)},
            {<<"user_name">>, binary_to_list(UserName)},
            {<<"status">>, binary_to_list(Status)},
            {<<"description">>, binary_to_list(Description)},
            {<<"added_user">>, binary_to_list(ReceiverUserName)},
            {<<"participant">>, binary_to_list(ParticipantJid)},
            {<<"publisher_profile">>, binary_to_list(PublisherVcard)},
            {<<"custom_attributes">>, binary_to_list(fxml:get_tag_cdata(CustAttr))},
            {<<"title">>, binary_to_list(UserNickName)},
            {<<"type">>, "normal"}];
          true ->
            if VCard == <<"">> ->
            GroupNickName = <<"">>;
            true ->
                GroupNickName = case fxml:get_path_s(VCard, [{elem, <<"nickName">>}, cdata]) of
                        <<"">> ->
                          fxml:get_path_s(VCard, [{elem, <<"FN">>}, cdata]);
                        GNickname ->  GNickname
                      end
              end,
            if NewUser =:= Members ->
              Content = <<GroupNickName / binary, <<":">> / binary, UserName / binary, <<" removed you">> / binary>>;
                true ->
              Content = <<GroupNickName / binary, <<":">> / binary, UserName / binary, <<" removed ">> / binary, ReceiverUserName / binary>>,
              ok
            end,
            Load = [{<<"user_jid">>, binary_to_list(Chan)},
            {<<"group_id">>, binary_to_list(Chan)},
            {<<"message_content">>, binary_to_list(Content)},
            {<<"group_name">>, binary_to_list(GroupNickName)},
            {<<"group_vcard">>, binary_to_list(SVCARD)},
            {<<"created_at">>, FlatTimeStamp},
            {<<"removed_at">>, FlatTimeStamp},
            {<<"userDomain">>, binary_to_list(Server)},
            {<<"user_type">>, binary_to_list(UserType)},
            {<<"notify_id">>, binary_to_list(NotifyId)},
            {<<"message_time">>, FlatTimeStamp},
            {<<"node_id">>, binary_to_list(NodeId)},
            {<<"push_from">>, binary_to_list(<<"MirrorFly">>)},
            {<<"sent_from">>, binary_to_list(MsgFrom)},
            {<<"sent_to">>, binary_to_list(Touser)},
            {<<"publisher_profile">>, binary_to_list(PublisherVcard)},
            {<<"title">>, binary_to_list(GroupNickName)},
            {<<"type">>, "normal"}]
          end,
          AndPayload = create_android_json(AndroidDeviceToken, Load),
          
          send_android_payload_to_rabbitmq(State#state.rabbitmq_connection, <<"normal">>, AndPayload, State#state.rabbitmq_exchange, Server)
          
        end,
        ATokens)
      end,
      Rs = fly_mod_offline_push:has_more_resources(Members,Server),
      case catch fly_mod_utils:get_user_for_ios_group_device(Server, Members,Rs)
      of {selected, _, []} ->
        {ok, <<"user not using ios device">>};
        {selected, _, Tokens} ->
        lists:map(fun(G) ->
        [Touser, _DeviceType, DeviceToken, VoipDeviceToken,Mode,IOSVersion, UserType, PushType] = G,
          if IOSVersion >= <<"13">>
              ->
                ios_group_create_push(Touser, MessageContent, Server,Members, Group, FlatTimeStamp, ChatType, Mode, DeviceToken, Expiry, Stanza, State,<<"13above">>,Type,UserType, PushType);
            true ->
                ios_group_create_push(Touser, MessageContent, Server,Members, Group, FlatTimeStamp, ChatType, Mode, VoipDeviceToken, Expiry, Stanza, State,<<"13below">>,Type,UserType, PushType)
            end
          end,
          Tokens)
        end;
    true ->
      ok
  end.

ios_group_create_push(Touser, MessageContent, Server, Members, _Group, FlatTimeStamp, ChatType, Mode, IOSDeviceToken, Expiry, _Stanza, State, IOSPushType, Type, UserType, PushType) ->
  [Chan,MsgFrom,ParticipantJid,NodeId,UserNickName,NotifyId] = MessageContent,
  [Owner, _] = binary:split(MsgFrom, <<"@">>),
  [NewUser, _] = binary:split(ParticipantJid, <<"@">>),
  {selected, [{NewUserName}]} = fly_mod_utils:get_nickname(Server, NewUser),
  {selected, [{ReceiverUserName}]} = fly_mod_utils:get_nickname(Server, Owner),
  {selected, [{GroupName}]} = fly_mod_utils:get_nickname(Server, Chan),
  case catch fly_mod_utils:get_group_profile_type(Server,Chan) of
                                    {selected, _, []} ->
                                    Status = <<"">>,
                                    History = <<"">>,
                                    MessageMode = <<"">>,
                                    AccessMode = <<"">>,
                                    ChannelStatus = <<"">>,
                                    InviteUri = <<"">>,
                                    Description = <<"">>,
                                    CustomFeatures = <<"">>;
                                    {selected, _, [[GStatus, GHistory ,GMessageMode,GAccessMode,GChannelStatus,GInviteUri,GCustomFeatures,GDescription]]} ->
                                      Status = GStatus,
                                      History = GHistory,
                                      MessageMode = GMessageMode,
                                      AccessMode = GAccessMode,
                                      ChannelStatus = fly_mix_group_chat:map_status(GChannelStatus),
                                      InviteUri = GInviteUri,
                                      Description = GDescription,
                                      CustomFeatures = GCustomFeatures;
                                    _ ->
                                      Status = <<"">>,
                                      History = <<"">>,
                                      MessageMode = <<"">>,
                                      AccessMode = <<"">>,
                                      ChannelStatus = <<"">>,
                                      InviteUri = <<"">>,
                                      Description = <<"">>,
                                      CustomFeatures = <<"">>
                                    end,
  if Type =:= <<"added">> ->
          if NewUser =:= Members ->
            Message = <<GroupName / binary, <<":">> / binary, Owner / binary, <<" added you">> / binary>>;
          true ->
            Message = <<GroupName / binary, <<":">> / binary, Owner / binary, <<" added ">> / binary, NewUser / binary>>
          end;
      true ->
        if NewUser =:= Members ->
            Message = <<GroupName / binary, <<":">> / binary, Owner / binary, <<" removed you">> / binary>>;
          true ->
            Message = <<GroupName / binary, <<":">> / binary,  Owner / binary, <<" removed ">> / binary, NewUser / binary>>
          end
        end,
  Args = [{message_content,
    binary_to_list(Message)},
    {group_name, binary_to_list(GroupName)},
    {user_id, binary_to_list(Owner)},
    {updated_userid, binary_to_list(NewUser)},
    {user_name, binary_to_list(ReceiverUserName)},
    {updated_username, binary_to_list(NewUserName)},
    {sent_from, binary_to_list(MsgFrom)},
    {sent_to, binary_to_list(Touser)},
    {created_at, FlatTimeStamp},
    {history, binary_to_list(History)},
    {messagemode, binary_to_list(MessageMode)},
    {accessmode, binary_to_list(AccessMode)},
    {channel_status, binary_to_list(ChannelStatus)},
    {invite_uri, binary_to_list(InviteUri)},
    {customfeatures, binary_to_list(CustomFeatures)},
    {notify_id, binary_to_list(NotifyId)},
    {added_at, FlatTimeStamp},
    {userDomain, binary_to_list(Server)},
    {user_type, binary_to_list(UserType)},
    {status, binary_to_list(Status)},
    {description, binary_to_list(Description)},
    {push_from, binary_to_list(<<"MirrorFly">>)},
    {node_id, binary_to_list(NodeId)},
    {group_id, binary_to_list(Chan)}],
    
  if  IOSPushType =:= <<"13above">> ->
    Msg = [{<<"mutable-content">>, integer_to_list(1)}, {alert, binary_to_list(Message)}, {mode, binary_to_list(Mode)}, {sound, binary_to_list(<<"default">>)}],
    IOSPayLoad = create_json(Msg, Args, binary_to_list(IOSDeviceToken),Mode,0,0,PushType),
    send_payload(IOSPayLoad, ChatType, State#state.rabbitmq_connection, State#state.rabbitmq_exchange,Server, PushType);
    true ->
      Msg = [{<<"content-available">>, integer_to_list(1)},{is_voip, integer_to_list(1)},{alert, binary_to_list(Message)}, {mode, binary_to_list(Mode)}, {sound, binary_to_list(<<"default">>)}],
      IOSPayLoad = create_json(Msg, Args, binary_to_list(IOSDeviceToken),Mode,1,0,PushType),
      send_payload(IOSPayLoad, ChatType, State#state.rabbitmq_connection, State#state.rabbitmq_exchange,Server, PushType)

end.
ios_send_bulk_push(Server, ToUser, MessageContent, _FromUser, FlatTimeStamp, ChatType, GroupID, Mode, IOSDeviceToken, _Expiry, State,IOSPushType, UserType, PushType) ->
[MessageType, MessageId, MesssageSend,GroupName, MSGBody, _EditMsg,_MentionList, _DisappearAt, _MetaData] = MessageContent,
  ChangedMessage = case MessageType of
                    <<"image">> ->
                      Message_Content = <<"">>,
                      binary_to_list(<<"Image">>);
                    <<"audio">> ->
                      Message_Content = MSGBody,
                      binary_to_list(<<"Audio">>);
                    <<"video">> ->
                      Message_Content = <<"">>,
                      binary_to_list(<<"Video">>);
                    <<"location">> ->
                      Message_Content = MSGBody,
                      binary_to_list(<<"Location">>);
                    <<"contact">> ->
                      Message_Content = MSGBody,
                      binary_to_list(<<"Contact">>);
                    <<"story_reply">> ->
                      Message_Content = <<"">>,
                      binary_to_list(GroupName);
                    _ ->
                      Message_Content = MSGBody,
                      binary_to_list(GroupName)
                    end,
  Args = [{message_id, binary_to_list(MessageId)}, {message_time, FlatTimeStamp}, {chat_type, binary_to_list(ChatType)},
    {message_content, binary_to_list(Message_Content)}, {from_user, binary_to_list(GroupID)}, {group_name, binary_to_list(GroupName)},
    {userDomain, binary_to_list(Server)}, {user_type, binary_to_list(UserType)}, {push_from, binary_to_list(<<"MirrorFly">>)},
    {sent_from, binary_to_list(MesssageSend)}, {sent_to, binary_to_list(ToUser)}, {type, binary_to_list(MessageType)}],
  if IOSPushType =:= <<"13above">> ->
    Msg = [{<<"mutable-content">>, integer_to_list(1)}, {alert, ChangedMessage},{mode, binary_to_list(Mode)}, {sound, binary_to_list(<<"default">>)}],
    IOSPayLoad = create_json(Msg, Args, binary_to_list(IOSDeviceToken), Mode,0,0,PushType),
    send_payload(IOSPayLoad, ChatType, State#state.rabbitmq_connection, State#state.rabbitmq_exchange,Server, PushType);
    true ->
      Msg = [{<<"content-available">>, integer_to_list(1)},{is_voip, integer_to_list(1)}, {alert, ChangedMessage}, {mode, binary_to_list(Mode)},{sound, binary_to_list(<<"default">>)}],
      IOSPayLoad = create_json(Msg, Args, binary_to_list(IOSDeviceToken), Mode, 1,0,PushType),
      send_payload(IOSPayLoad, ChatType, State#state.rabbitmq_connection, State#state.rabbitmq_exchange,Server, PushType)
  end.

get_status(Members) ->
  lists:flatmap(fun(#jid{luser = User, lserver = Server}) ->
    [get_data(User, Server)] end, Members).

get_resources(Members) ->
  lists:flatmap(fun(#jid{luser = User, lserver = Server}) ->
    [has_more_resources(User, Server)] end, Members).

get_data(TUser, TServer) ->
  binary_to_list(TUser) ++ "','".

has_more_resources(User,LServer) ->
  Resources = ejabberd_sm:get_user_resources(User, LServer),
  if length(Resources) =:= 0 ->
    Rs = "";
  true ->
    Rs = lists:flatmap(fun(R) ->
      Substring = string:str(binary_to_list(R),binary_to_list(<<"Web-">>)),
      if Substring =:= 1 ->
        "";
      true ->
        Resource = fly_mod_utils:get_device_from_resource(R),
        binary_to_list(Resource) ++ "','"
      end
    end,Resources)
  end,
  Rs.

send_own_group_push_notifications(FromUser, ToUser,
    ChatType, SubEl, Packet, GroupName, State) ->
    Rs = has_more_resources(FromUser#jid.luser,FromUser#jid.server),
  case catch fly_mod_utils:get_user_device(FromUser#jid.server,
    FromUser#jid.luser,Rs,ChatType)
  of
    {selected, _, []} -> ok;
    {selected, _, Tokens} ->
      Timestamp = fxml:get_subtag(Packet, <<"timestamp">>),
      TimestampValue = fxml:get_attr_s(<<"time">>,
      Timestamp#xmlel.attrs),
      SubEls1 = lists:map(fun(G) ->
        [DeviceType, DeviceToken, VoipDeviceToken, Mode,IOSVersion,DeviceId, UserType, PushType] = G,
        case DeviceType of
                  <<"">> -> ok;
                  <<"android">> ->
                    gcm_group_push(DeviceToken, UserType, ChatType, GroupName,
                      FromUser, ToUser, SubEl, Packet, TimestampValue,
                      State#state.rabbitmq_connection, State#state.rabbitmq_exchange);
                  % <<"ios">> ->
                    % apns_group_push(DeviceToken, UserType, ChatType, FromUser, ToUser,
                    %   GroupName, SubEl, TimestampValue, Packet,
                    %   State, Mode, PushType);
                  _ -> ok
                end
          end,Tokens);
    _Error ->
      ?INFO_MSG("push_message get_user_device_details error is ~p",[_Error]),
      ok
  end.

create_android_json(DeviceToken, BF) ->
  RandomId = fly_mod_utils:get_iq_message_id(7),
  Expiry = get_timestamp(),
  lists:append(["{\"deviceToken\":\"", binary_to_list(DeviceToken), "\",\"expiration\":\"", integer_to_list(Expiry), "\",\"collapse_key\":\"", binary_to_list(RandomId),  "\",\"data\":{", create_keyvalue(BF), "}}"]).

create_bulk_push_json(DeviceTokens, BF) ->
  lists:append(["{\"deviceTokens\":", "[\"", DeviceTokens, "\"],\"data\":{", create_keyvalue(BF), "}}"]).

create_bulk_ios_json(List1, List2, Tokens, Mode,VoipStatus,Expiration) ->
  lists:append(["{\"deviceTokens\":", "[\"", Tokens, "\"],\"isVoip\":\"", integer_to_list(VoipStatus), "\",\"expiration\":\"", integer_to_list(Expiration), "\",\"mode\":\"", binary_to_list(Mode), "\",\"data\":{\"aps\":{", create_keyvalue(List1),
    "}, ", create_keyvalue(List2), "}}"]).

mod_opt_type(rabbitmq_host) -> fun iolist_to_binary/1;
mod_opt_type(rabbitmq_username) -> fun iolist_to_binary/1;
mod_opt_type(rabbitmq_exchange) -> fun iolist_to_binary/1;
mod_opt_type(rabbitmq_password) -> fun iolist_to_binary/1;
mod_opt_type(iqdisc) -> fun gen_iq_handler:check_type/1;
mod_opt_type(db_type) ->
  fun(T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(restricted_country_code) ->
    econf:list(econf:binary());
mod_opt_type(_) ->
  [db_type, iqdisc, rabbitmq_host, rabbitmq_username, rabbitmq_password, rabbitmq_exchange, restricted_country_code].

depends(_, _) ->
  [].

mod_options(_Host) ->
  [{rabbitmq_host, undefined},
    {rabbitmq_username, undefined},
    {rabbitmq_exchange, undefined},
    {rabbitmq_password, undefined},
    {restricted_country_code, []}].

