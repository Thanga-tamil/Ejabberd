%%%=========================================================
%%% File       : mod_user_activities.erl
%%% Author     : Contus <ejabberd@contus.in>
%%% Purpose    : Receive Vcard Update Iq (an empty iq with specific status)
%%% Created At : 21 Jul 2016
%%%=========================================================

-module(fly_mod_user_activities).
-author("ejabberd@contus.in").

-behavior(gen_server).
-define(PROCNAME, fly_mod_user_activities).
-define(EJABBERD_DEBUG, true).
-behaviour(gen_mod).
-record(state, {jid = undefined}).

%% API
-export([start/2, stop/1, depends/2, mod_options/1, mod_opt_type/1, process_terminated/2, process_local_iq/1, push_vcard_updates/1,
        set_presence/4, unset_presence/4, update_user_stream/1, send_block_list/3, push_to_rosters/2, media_permission_revoke/3]).

-export([ handle_cast/2,  handle_info/2, handle_call/3]).

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").

-type host() :: string().
-type name() :: string().
-type value() :: string().
-type opts() :: [{name(), value(), value()}, ...].


start_link(Host, Opts) ->
  Proc = gen_mod:get_module_proc(Host, ?PROCNAME),
  gen_server:start_link({local, Proc}, ?MODULE,
    [Host, Opts], []).

%===================================================================
% API
%===================================================================

-spec start(host(), opts()) -> ok.
start(Host, _Opts) ->
  gen_iq_handler:add_iq_handler(ejabberd_local, Host, ?NS_USER_ACTIVITIES, ?MODULE, process_local_iq),
  gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_USER_ACTIVITIES, ?MODULE, process_local_iq),
  ejabberd_hooks:add(vcard_set, Host, ?MODULE, push_vcard_updates, 100),
  ejabberd_hooks:add(vcard_iq_set, Host, ?MODULE, push_vcard_updates, 100),
  ejabberd_hooks:add(set_presence_hook, Host, ?MODULE, set_presence, 100),
  ejabberd_hooks:add(unset_presence_hook, Host, ?MODULE, unset_presence, 100),
  ejabberd_hooks:add(user_ping_timeout, Host, ?MODULE, update_user_stream, 100),
  ejabberd_hooks:add(c2s_terminated, Host, ?MODULE, process_terminated, 50),
  ClientName = gen_mod:get_module_opt(Host, fly_mod_user_activities, client_name),
  ets:new(ClientName, [set, public, named_table]),
  fly_mod_utils:update_license_lookup(Host),
ok.

-spec stop(host()) -> ok.
stop(Host) ->
  gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?NS_USER_ACTIVITIES),
  gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_USER_ACTIVITIES),
  ejabberd_hooks:delete(vcard_set, Host, ?MODULE, push_vcard_updates, 100),
  ejabberd_hooks:delete(vcard_iq_set, Host, ?MODULE, push_vcard_updates, 100),
  ejabberd_hooks:delete(set_presence_hook, Host, ?MODULE, set_presence, 100),
  ejabberd_hooks:delete(unset_presence_hook, Host, ?MODULE, unset_presence, 100),
  ejabberd_hooks:delete(user_ping_timeout, Host, ?MODULE, update_user_stream, 100),
  ejabberd_hooks:delete(c2s_terminated, Host, ?MODULE, process_terminated, 50),
  ok.

depends(_, _) ->
  [].

%%=========================================================
%% Function: %% handle_call(Request, From, State) -> {reply, Reply, State} |
%%                                      {reply, Reply, State, Timeout} |
%%                                      {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, Reply, State} |
%%                                      {stop, Reason, State}
%% Description: Handling call messages
%%=========================================================
handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

%%=========================================================
%% Function: handle_cast(Msg, State) -> {noreply, State} |
%%                                      {noreply, State, Timeout} |
%%                                      {stop, Reason, State}
%% Description: Handling cast messages
%%=========================================================


handle_cast(_Data, State) -> {noreply, State}.

handle_info(_Info, State) -> {noreply, State}.

process_terminated(#{sid := SID, socket := _Socket,
  jid := JID, user := U, server := S, resource := R} = State,
    Reason) ->
  Status = format_reason(State, Reason),
  State1 = case maps:is_key(pres_last, State) of
              true ->
              State;
              false ->
              Pres = #presence{type = unavailable, from = JID},
              ejabberd_sm:close_session_unset_presence(SID, U, S, R, Status),
              push_presence_to_group_members(JID, Pres),
              push_presence_to_unknown_rosters(JID, Pres),
              State
            end,
  State1;
process_terminated(#{socket := Socket,
  stop_reason := {tls, _}} = State, Reason) ->
  ?WARNING_MSG("(~s) Failed to secure c2s connection: ~s",
    [xmpp_socket:pp(Socket), format_reason(State, Reason)]),
  State;
process_terminated(State, _Reason) ->
  State.

push_presence_to_group_members(From, Packet) ->
  #jid{luser = FUser,lserver = FServer} = From,
  case catch fly_mod_utils:get_my_all_group_id_rosters(FServer, FUser) of
    {selected, _, []} ->
      ok;
    {selected, _, RosterUsers} ->
        push_presence_packets(RosterUsers,Packet,From)
  end.

push_presence_to_unknown_rosters(From, Packet) ->
  #jid{luser = User,lserver = Server} = From,
  Resources = ejabberd_sm:get_user_resources(User, Server),
  % if length(Resources) =:= 0 ->
  %     fly_mod_utils:set_last_o(User, Server, <<"0">>);
  %   true ->
  %     ok
  % end,
  case catch fly_mod_utils:get_roster_from_recent_jid(From) of
    {selected, _, []} ->
      ok;
    {selected, _, Rosters} ->
      push_presence_packets(Rosters,Packet,From);
    _ ->
      error
  end.

push_presence_packets(Rosters,Packet,From) ->
  #jid{lserver = Server} = From,
  lists:foreach(fun([RosterJid]) ->
      lists:foldl(fun(Resource,_Acc) ->
      ejabberd_router:route(From, jid:make(RosterJid, Server, Resource), Packet)
                  end,[],ejabberd_sm:get_user_resources(RosterJid, Server))
                end, Rosters).

%% Handling the IQ
process_local_iq(#iq{from = From, to = To, type = Type, sub_els = [#user_activities{status = RequestType}]} = IQ) ->
  case Type of
    set ->
      process_iq_set(From, To, RequestType, xmpp:encode(IQ));
    get ->
      process_iq_get(From, To,RequestType, xmpp:encode(IQ));
    _ ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = <<"error">>, result_type = <<"invalid iq type">>})
  end.

%% Set method for the IQ
process_iq_set(From, _To, RequestType, IQ) ->
  SubEl = fxml:get_subtag_with_xmlns(IQ, <<"query">>, <<"jabber:iq:user_activities">>),
  case RequestType of
    <<"set_web_password">> ->
      set_web_password(From, SubEl, IQ);
    <<"update_license_data">> ->
      set_user_validate(From, SubEl, IQ);
    <<"register_notify">> ->
      push_register_notify_presence(From, RequestType, SubEl,IQ);
    <<"clear_message">> ->
      clear_message(From, RequestType, SubEl, IQ);
    <<"clear_all">> ->
      clear_all(From, RequestType, SubEl, IQ);
    <<"delete_message">> ->
      delete_message(From, RequestType, SubEl, IQ);
    <<"api_delete_message">> ->
      delete_message(From, RequestType, SubEl, IQ);
    <<"api_recall">> ->
      api_recall(From, SubEl, IQ);
    <<"hide_lastseen">> ->
      hide_lastseen(From, SubEl,IQ);
    <<"user_logout">> ->
      user_logout(From, RequestType, SubEl, IQ);
    <<"user_logout_by_admin">> ->
      user_logout_by_admin(From, RequestType, SubEl, IQ);
    <<"send_delivery">> ->
      message_delivery(From, RequestType, SubEl,IQ);
    <<"sms_seen">> ->
      send_seen_message(From, RequestType, SubEl,IQ);
    <<"send_sms">> ->
      send_sms_message(From, RequestType, SubEl,IQ);
    <<"send_push">> ->
      send_push(From, RequestType, SubEl, IQ);
    <<"call_message">> ->
      call_message(From, RequestType, SubEl, IQ);
    <<"call_status">> ->
      call_message(From, RequestType, SubEl, IQ);
    <<"carbon_call">> ->
      carboncall_message(From, RequestType, SubEl, IQ);
    <<"update_mute_notification">> ->
      update_mute_notification(From, RequestType, SubEl, IQ);
    <<"mute_chat">> ->
      mute_notification(From, RequestType, SubEl, IQ);
    <<"update_archive_chat">> ->
      update_archive_chat(From, RequestType, SubEl, IQ);
    <<"update_user_busy">> ->
      update_user_busy(From, RequestType, SubEl, IQ);
    <<"register_update">> ->
      register_update_to_rosters(From, RequestType, SubEl, IQ);
    <<"user_settings">> ->
      set_user_settings(From, RequestType, SubEl, IQ);
    <<"update_unread_count">> ->
      update_unread_count(From, RequestType, SubEl, IQ);
    <<"update_admin_block_status">> ->
      update_admin_block_status(From, RequestType, SubEl, IQ);
    <<"send_contact_sync_status">> ->
      send_contact_sync_status(From, RequestType, SubEl, IQ);
    <<"send_deleted_user_status">> ->
      send_deleted_user_status(From, RequestType, SubEl, IQ);
    <<"poll_add">> ->
      poll_update(From, RequestType, SubEl, IQ);
    <<"poll_delete">> ->
      poll_update(From, RequestType, SubEl, IQ);
    <<"acknowledge">> ->
      acknowledge(From, RequestType, SubEl, IQ);
    <<"read_all">> ->
      read_all(From, RequestType, SubEl, IQ);
    <<"poll_acknowledge">> ->
      poll_ack(From, RequestType, SubEl, IQ);
    no_such_subtag ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});
    empty_value ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = <<"empty_value">>, result_type = <<"unknown request">>});
    _Status ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = _Status, result_type = <<"unknown request">>})
  end.

%% Get method for the IQ
process_iq_get(From, To, RequestType, IQ) ->
  SubEl = fxml:get_subtag_with_xmlns(IQ, <<"query">>, <<"jabber:iq:user_activities">>),
  case RequestType of
    <<"recent_chat">> ->
      recent_chat(From, RequestType, SubEl, IQ);
    <<"recent_topic_chat">> ->
      recent_topic_chat(From, RequestType, SubEl, IQ);
    <<"meta_chat">> ->
      meta_chat(From, RequestType, SubEl, IQ);
    <<"get_server_time">> ->
      get_server_time(From,RequestType, IQ);
    <<"single_chat">> ->
      get_single_chat_messages(From, RequestType, SubEl, IQ);
    <<"single_chat_media">> ->
      get_single_chat_media_messages(From, RequestType, SubEl, IQ);
    <<"group_chat">> ->
      get_group_chat_messages(From, RequestType, SubEl, IQ);
    <<"group_chat_media">> ->
      get_group_chat_media_messages(From, RequestType, SubEl, IQ);
    <<"single_chat_fullmedia">> ->
      get_single_chat_fullmedia_messages(From, RequestType, SubEl, IQ);
    <<"group_chat_fullmedia">> ->
      get_group_chat_fullmedia_messages(From, RequestType, SubEl, IQ);
    <<"message_status">> ->
      get_message_status(From, RequestType, SubEl, IQ);
    <<"block_user">> ->
      get_block_list(From, RequestType, SubEl, IQ);
    <<"call_status">> ->
      get_call_status(From, RequestType, SubEl, IQ);
    <<"reply_message">> ->
      get_reply_message(From, RequestType, SubEl, IQ);
    <<"bot_chat">> ->
      get_bot_chat_messages(From, RequestType, SubEl, IQ);
    <<"get_last">> ->
      get_last_iq(From, To, RequestType, SubEl, IQ);
    <<"user_settings">> ->
      get_user_settings(From, To, RequestType, SubEl, IQ);
    <<"all_archived_chats">> ->
      get_all_archived_chats(From, RequestType, SubEl, IQ);
    <<"get_busy_status">> ->
      get_busy_status(From, RequestType, SubEl, IQ);
    <<"get_recentchat_profile">> ->
      process_get_recent_profile(From, RequestType, SubEl, IQ);

    no_such_subtag ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});
    empty_value ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = <<"empty_value">>, result_type = <<"unknown request">>});
    _Status ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = _Status, result_type = <<"unknown request">>})
  end.

get_last_iq(_From, #jid{luser = TUser, lserver = TServer, lresource = _TResource}= _To, RequestType, _SubEl, IQ) ->

  Res = fly_mod_utils:get_last(TUser, TServer),
  case ejabberd_sm:get_user_resources(TUser, TServer) of
    [] ->
      case Res of
        {ok, {TimeStamp}} ->
          TimeStamp2 = erlang:system_time(second),
          Sec = TimeStamp2 - TimeStamp,
          FlatTimeStamp = lists:flatten(io_lib:format("~p", [Sec])),
          XMLTag = [#xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"seconds">>, list_to_binary(FlatTimeStamp)}], children = []}],
          fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = XMLTag });
        error ->
          fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No info about last activity found">>});
        _ ->
          fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No info about last activity found">>})
      end;
    _ ->
      case Res of
        {ok, _, _} ->
          XMLTag = [#xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"seconds">>, <<"0">>}], children = []}],
          fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = XMLTag });
        error ->
          fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No info about last activity found">>});
        _ ->
          fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No info about last activity found">>})
      end
  end.

get_user_settings(From, _To, RequestType, _SubEl, IQ) ->
  case catch fly_mod_utils:get_user_settings(From) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Settings not available">>});
    {error, _} ->
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Settings not available">>});
    {selected, _,Result} ->
      SubEls1 = lists:map(fun(G) ->
        [ArchiveStatus] = G,
        ArchiveElement = #xmlel{name = <<"archive">>, attrs = [],
          children = [{xmlcdata, ArchiveStatus}]},
        #xmlel{name = <<"user_settings">>, attrs = [],
          children = [ArchiveElement]}
      end, Result),
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = SubEls1 })
  end.

get_all_archived_chats( From, RequestType, _SubEl, IQ) ->
  case catch fly_mod_utils:get_archived_chats(From) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No archived chats available">>});
    {selected, _, Result} ->
      SubEls1 = lists:map(fun(G) ->
        [FromUser, ChatType] = G,
        #xmlel{name = <<"user">>, attrs = [{<<"chat_type">>, ChatType}],
          children = [{xmlcdata, FromUser}]}
      end, Result),
      Xml = [#xmlel{name = <<"archived_chats">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = Xml })
  end.

get_busy_status( From, RequestType, _SubEl, IQ) ->
  case catch fly_mod_utils:get_busy_status(From) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No busy status">>});
    {selected, _, Result} ->
      Xml = lists:map(fun(G) ->
        [BusyMsg, BusyStatus] = G,
        #xmlel{name = <<"busy">>, attrs = [{<<"busy_status">>, BusyStatus},{<<"busy_message">>, BusyMsg}],
          children = []}
      end, Result),
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = Xml })
  end.

set_user_settings(From, RequestType, SubEl, IQ) ->
  Archive = fxml:get_path_s(SubEl, [{attr, <<"archive">>}]),
  fly_mod_utils:set_user_settings(From, Archive),

  #jid{luser = User,lserver = Server, lresource = Resource} = From,
  To = jid:make({User, Server, <<>>}),
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"user_settings">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"archive">>, Archive}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),
    NewPacket = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(To)}, {<<"to">>, jid:to_string(From)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
      children = [#xmlel{name = <<"user_settings">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"archive">>, Archive}],
        children = []}]},
    mod_offline:store_packet({From, xmpp:decode(NewPacket)}),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated">>}).

update_unread_count(From, RequestType, SubEl, IQ) ->
  ToUserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  [ToUser | _S] = string:tokens(binary_to_list(ToUserJid), "@"),
  fly_mod_utils:update_recent_unread_chat(From, ToUser),
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  #jid{luser = User, lserver = Server, lresource = Resource} = From,
  To = jid:make({User, Server, <<>>}),
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"unread_count">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"to_user">>,ToUserJid}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),
    NewPacket = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(To)}, {<<"to">>, jid:to_string(From)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
      children = [#xmlel{name = <<"unread_count">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"to_user">>,ToUserJid}],
        children = []}]},
    mod_offline:store_packet({From, xmpp:decode(NewPacket)}),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated">>}).

%% Hook lisenter to push the vcard update to rosters using iq
%%
%%
%% @param binary LUser
%% @param binary LServer
%% @param record VCARD
%% @return IQ(Result)
push_vcard_updates(#iq{from = #jid{luser = LUser, lserver = LServer}} = IQ) ->
  VCARD = fxml:get_subtag_with_xmlns(xmpp:encode(IQ), <<"vCard">>, <<"vcard-temp">>),
  Nickname = fxml:get_path_s(VCARD,
    [{elem, <<"nickName">>}, cdata]),
  Status = fxml:get_path_s(VCARD,
    [{elem, <<"status">>}, cdata]),
  Image = fxml:get_path_s(VCARD,
    [{elem, <<"image">>}, cdata]),
  Email = fxml:get_path_s(VCARD,
    [{elem, <<"email">>}, cdata]),

  Mobile = fxml:get_path_s(VCARD,
    [{elem, <<"mobileNumber">>}, cdata]),
  if Mobile =:= false ->
    ok;
    true ->
      fly_mod_utils:create_user_ifuserexit(LServer, LUser, Nickname, Image, Mobile, Status, Email)
  end,

  Packet = #xmlel{
    name = <<"iq">>,
    attrs = [{<<"type">>, <<"result">>},{<<"id">>, p1_rand:get_string()}],
    children = [VCARD]
  },

  lists:foreach(fun(R) ->
    ejabberd_router:route(jid:make(LUser, LServer, <<>>), jid:make(LUser, LServer, R), Packet)
                end,
    ejabberd_sm:get_user_resources(LUser, LServer)),

  % push_to_email_contacts(jid:make(LUser, LServer, <<>>), Packet).
  push_to_rosters_and_recent(jid:make(LUser, LServer, <<>>), Packet).

%% Hook lisenter to to update the user rosters on timeout
%%
%% @param record Jid
%% @return IQ(Result)
update_user_stream(From) ->
  #jid{user = User, lserver = Server, lresource = Resource} = From,
  sendofflinepresence(User, Server, Resource).

set_presence(User, Server, Resource, _Status) ->
  Resources = ejabberd_sm:get_user_resources(User, Server),

  case (length(Resources) > 0) of
    true ->
      %UserJid = jid:make({User, Server,  Resource}),
      %State = #{jid => #jid{luser = User, lserver = Server, lresource = Resource} = UserJid},
      % mod_offline:route_offline_messages(State) ,
      fly_mod_utils:set_last_o(User, Server, <<"1">>),
      JID = jid:make({User, Server, <<>>}),
      push_to_rosters(JID, #xmlel{name = <<"presence">>,
        attrs = [{<<"type">>, <<"available">>}],
        children = []
      });
    false ->
      ok

  end.

unset_presence(User, Server, Resource, _Status) ->
  sendofflinepresence(User, Server,Resource).

sendofflinepresence(User, Server,Resource) ->
  MobileResource = string:str(binary_to_list(Resource), binary_to_list(<<"Mobile">>)),

  Resources = ejabberd_sm:get_user_resources(User, Server),
  case (length(Resources) =:= 0) of
    true ->
      JID = jid:make({User, Server, <<>>}),
      push_to_rosters(JID, #xmlel{name = <<"presence">>,
        attrs = [{<<"type">>, <<"unavailable">>}],
        children = []
      }),
      if MobileResource =:= 1 ->
        LResource = re:replace(binary_to_list(Resource),"Mobile-", ""),
        UResource = iolist_to_binary(LResource),
      case catch fly_mod_utils:get_offline_message(Server, User, UResource) of
    {selected, _, []} ->
      ok;
    {selected, _, Messages} ->
        lists:map(fun(G) ->
        [ChatType, Packet] = G,
        El = #xmlel{} = fxml_stream:parse_element(Packet),
        FromUser = #jid{} = jid:from_string(fxml:get_attr_s(<<"from">>, El#xmlel.attrs)),
        ToUser = #jid{} = jid:from_string(fxml:get_attr_s(<<"to">>, El#xmlel.attrs)),
        #jid{luser = TUser, lserver = TServer} = ToUser,
        if TUser =:= User ->
        MessageId = fxml:get_attr_s(<<"id">>, El#xmlel.attrs),
        if ChatType =:= <<"chat">> ->
          fly_mod_offline_push:send_offline_message({ToUser, xmpp:decode(El)});
          ChatType =:= <<"normal">> ->
          fly_mod_offline_push:send_offline_message({ToUser,xmpp:decode(El)});
          true ->
            ok
        end,
        fly_mod_utils:update_offline_status(Server, MessageId, User);
        true ->
          ok
      end

                          end, Messages)
  end,
      fly_mod_utils:set_last_o(User, Server, <<"0">>);
      true ->
      ok
end;
    false -> ok
  end.

process_get_recent_profile(From, RequestType, SubEl, IQ) ->
  #jid{luser = FUser, lserver = FServer} = From,
  Updatedat = fxml:get_path_s(SubEl, [{attr, <<"updated_at">>}]),
  case catch fly_mod_utils:get_recent_profile(FServer, FUser, Updatedat) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No recent chat for you">>});
    {selected, _, UserProfiles} ->
      SubEls1 = lists:map(fun(G) ->
        [UserName,  Vcard] = G,
        VCard = case fxml_stream:parse_element(Vcard) of
                    {error, _Reason} -> [];
                    VCARD -> [VCARD]
                  end,
        #xmlel{name = <<"vcarddetails">>, attrs = [{<<"username">>,  UserName }],
          children = VCard}
                          end,
        UserProfiles),

      ProfileXml = [#xmlel{name = <<"vcard">>, children = SubEls1}],

      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = ProfileXml})
  end.

user_logout(From, RequestType, SubEl, IQ) ->
  #jid{luser = LUser, lserver = LServer, lresource = LResource} = From,
  SocketId = fxml:get_path_s(SubEl, [{attr, <<"socket_id">>}]),
  MessageId = p1_rand:get_string(),
  To = jid:make({LUser, LServer, <<>>}),
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
    children = [#xmlel{name = <<"logout">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, <<"logout">>}, {<<"socket_id">>, SocketId}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),

    NewPacket = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(To)}, {<<"to">>, jid:to_string(From)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [#xmlel{name = <<"logout">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, <<"logout">>}, {<<"socket_id">>, SocketId}],
        children = []}]},
    mod_offline:store_packet({From, xmpp:decode(NewPacket)}),
  Resources = ejabberd_sm:get_user_resources(LUser, LServer),
  if length(Resources) =:= 1 ->
    push_to_rosters(To, #xmlel{name = <<"presence">>,
      attrs = [{<<"type">>, <<"unavailable">>}],
      children = []
    });
    true ->
      ok
  end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"user logged out successfully">>}).

user_logout_by_admin(From, RequestType, SubEl, IQ) ->
  ToUserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  ToJid = jid:from_string(ToUserJid),
  #jid{luser = TUser, lserver = TServer} = ToJid,
  MessageId = p1_rand:get_string(),

  lists:foreach(fun(R) ->
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, ToUserJid}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [#xmlel{name = <<"logout">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, <<"logout">>}],
        children = []}]},
      ejabberd_router:route(From, jid:make(TUser, TServer, R), XmlBody)
  end, ejabberd_sm:get_user_resources(TUser, TServer)),

  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"user logged out successfully">>}).

  message_delivery(_From, RequestType, SubEl,IQ) ->
  MessageFrom = fxml:get_path_s(SubEl, [{attr, <<"message_from">>}]),
  MessageTo = fxml:get_path_s(SubEl, [{attr, <<"message_to">>}]),
  OldMessageId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  GroupId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  LResource = fxml:get_path_s(SubEl, [{attr, <<"device_id">>}]),
  MessageId = fly_mod_utils:get_iq_message_id(16),
  MsgId = fly_mod_utils:get_iq_message_id(16),
  FromJid = jid:from_string(MessageFrom),

  #jid{user = FUser, lserver = FServer} = FromJid,
  if (MessageTo =:= <<"">>) or (MessageTo =:= <<>>) ->
      case catch fly_mod_utils:get_message_from(FServer,  OldMessageId) of
            {seleced, _, []} ->
              ToJid = #jid{user = TUser, lserver = TServer} = FromJid;
            {selected, _, [[MsgFrom]]} ->
              ToJid = jid:from_string(MsgFrom),
              #jid{user = TUser, lserver = TServer} = ToJid
      end;
    true ->
      ToJid = jid:from_string(MessageTo),
      #jid{user = TUser, lserver = TServer} = ToJid
end,
  Substring = string:str(binary_to_list(LResource),binary_to_list(<<"Mobile-">>)),
  if Substring =:= 1 ->
    MResource = fly_mod_utils:get_device_from_resource(LResource);
  true ->
    MResource = LResource
  end,
  fly_mod_utils:update_offline(FServer, OldMessageId,MResource),
  fly_mod_utils:update_delivery(FromJid, TUser, OldMessageId, GroupId),
  BusyMsg = fly_mod_utils:get_userbusy_message(FServer, TUser, FUser),
  if BusyMsg =/= <<"">> andalso GroupId =:= <<"">> ->
    BodyString = fly_mod_security:aes_encrpyt_license(MsgId, <<"ddc0f15cc2c90fca">>, BusyMsg),
    MsgBody3 = XML = #xmlel{name = <<"message">>, attrs = [{<<"xmlns">>, <<"jabber:client">>},{<<"from">>, MessageFrom}, {<<"to">>, MessageTo},
      {<<"type">>, <<"chat">>},{<<"id">>, MsgId}],
    children = [
      #xmlel{name = <<"chatcontent">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:content">>},{<<"message_type">>, <<"auto_text">>},{<<"edit_msg_id">>, MsgId},
        {<<"block_user">>, <<"0">>}],children = []},
      #xmlel{name = <<"body">>, attrs = [{<<"message_type">>, <<"auto_text">>}], children = [{xmlcdata, BodyString}]}]},
    ReceivedTimestamps = now_to_microseconds(erlang:now()),
    ReceivedFlatTimeStamps = lists:flatten(io_lib:format("~p", [ReceivedTimestamps])),
    ReceivedMsgTags = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(ReceivedFlatTimeStamps)}], children = []},
    MsgBody2 = fxml:append_subtags(MsgBody3, [ReceivedMsgTags]),
      ejabberd_router:route(FromJid, ToJid, MsgBody2),
      store_offline_user_send(MsgBody2,FromJid,ToJid),
      TResources = ejabberd_sm:get_user_resources(TUser, TServer),
      if length(TResources) =:= 0 ->
        mod_offline:store_packet({FromJid, xmpp:decode(MsgBody2)});
      true ->
        ok
      end,
      fly_mod_stanza_ack:store_in_table(FServer,FUser,TUser,MsgId,BodyString,<<"chat">>,<<"auto_text">>,<<"">>,  <<"{}">> ,<<"0">>,<<"">>, ReceivedFlatTimeStamps),
      fly_mod_utils:insert_status(FromJid, ToJid, MsgId,<<"auto_text">>,<<"">>, <<"{}">>, <<"chat">>,<<"">>,<<"0">>,BodyString,ReceivedFlatTimeStamps,MsgId);
true ->
    ok
end,
  case catch fly_mod_utils:message_status(FServer, OldMessageId, TUser) of
                                    {selected, _, []} ->
                                      GStatus = <<"0">>;
                                    {selected, _, [[GroupStatus]]} ->
                                      GStatus = GroupStatus;
                                    _ ->
                                      GStatus = <<"0">>
                                  end,
  XmlBody = #xmlel{name = <<"message">>, attrs = [{<<"from">>, MessageFrom}, {<<"to">>, MessageTo}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
  children = [#xmlel{name = <<"delivered">>, attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"id">>, OldMessageId},{<<"message_status">>, GStatus}, {<<"group_id">>, GroupId}], children = []}]},
  ReceivedTimestamp = now_to_microseconds(erlang:now()),
  ReceivedFlatTimeStamp = lists:flatten(io_lib:format("~p", [ReceivedTimestamp])),
  ReceivedXMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(ReceivedFlatTimeStamp)}], children = []},
  XmlBody1 = fxml:append_subtags(XmlBody, [ReceivedXMLTag]),
  ejabberd_router:route(FromJid, ToJid, XmlBody1),
  fly_mod_stanza_ack:send_ack_response(FromJid, ToJid, OldMessageId, <<"delivered">>),
  TResource = ejabberd_sm:get_user_resources(TUser, TServer),
      if length(TResource) =:= 0 ->
        ReceivedTimeStampedPacket = fxml:append_subtags(XmlBody, [ReceivedXMLTag]),
        mod_offline:store_packet({FromJid, xmpp:decode(ReceivedTimeStampedPacket)});
      true ->
        ok
      end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Send successfully">>}).

send_seen_message(_From, RequestType, SubEl,IQ) ->
  MessageFrom = fxml:get_path_s(SubEl, [{attr, <<"send_to">>}]),
  MessageTo = fxml:get_path_s(SubEl, [{attr, <<"send_from">>}]),
  MessageId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  GroupId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  Messageid = p1_rand:get_string(),
  FromJid = jid:from_string(MessageFrom),
  ToJid = jid:from_string(MessageTo),
  #jid{user = FUser, lserver = FServer} = FromJid,
  #jid{user = TUser, lserver = TServer} = ToJid,
  fly_mod_utils:update_seen(FromJid, FUser, MessageId, GroupId),
  case catch fly_mod_utils:message_status(FServer, MessageId, FUser) of
                                    {selected, _, []} ->
                                      GStatus = <<"0">>;
                                    {selected, _, [[GroupStatus]]} ->
                                      GStatus = GroupStatus;
                                    _ ->
                                      GStatus = <<"0">>
                                  end,
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, MessageFrom}, {<<"to">>, MessageTo}, {<<"type">>, <<"chat">>}, {<<"id">>, Messageid}],
      children = [#xmlel{name = <<"seen">>,
      attrs = [{<<"xmlns">>, <<"urn:xmpp:receipts">>}, {<<"message_status">>, GStatus},{<<"group_id">>, GroupId},{<<"id">>, MessageId}],
      children = []}]},
  ReceivedTimestamp = now_to_microseconds(erlang:now()),
  ReceivedFlatTimeStamp = lists:flatten(io_lib:format("~p", [ReceivedTimestamp])),
  ReceivedXMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(ReceivedFlatTimeStamp)}],
    children = []},
  XmlBody1 = fxml:append_subtags(XmlBody, [ReceivedXMLTag]),
  BroadcastId = <<"">>,
  BroadcastMsgId = <<"">>,
  ejabberd_router:route(FromJid, ToJid, XmlBody1),
  case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
    true ->
      mod_offline:store_packet({FromJid, xmpp:decode(XmlBody1)});
    false ->
      ok
  end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Send successfully">>}).

  poll_ack(From,RequestType,SubEl,IQ) ->
  #jid{user = FUser, lserver = FServer,lresource = LResource} = From,
  PollMsgId = fxml:get_path_s(SubEl, [{attr, <<"id">>}]),
  Substring = string:str(binary_to_list(LResource),binary_to_list(<<"Mobile-">>)),
  if Substring =:= 1 ->
    MResource = fly_mod_utils:get_device_from_resource(LResource);
  true ->
    MResource = <<"">>
  end,
  fly_mod_utils:remove_poll_offline(FServer, MResource,PollMsgId),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Ack successfully">>}).

  acknowledge(From,RequestType,SubEl,IQ) ->
  #jid{user = FUser, lserver = FServer,lresource = LResource} = From,
  MsgId = fxml:get_path_s(SubEl, [{attr, <<"id">>}]),
  Substring = string:str(binary_to_list(LResource),binary_to_list(<<"Mobile-">>)),
  if Substring =:= 1 ->
    MResource = fly_mod_utils:get_device_from_resource(LResource);
  true ->
    MResource = <<"">>
  end,
  fly_mod_utils:remove_poll_offline(FServer, MResource,MsgId),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Ack successfully">>}).

read_all(From,RequestType,SubEl,IQ) ->
  #jid{user = FUser, lserver = FServer,lresource = LResource} = From,
  Readto = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  fly_mod_utils:read_all(FServer,FUser, Readto),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Read successfully">>}).

poll_update(From,RequestType,SubEl,IQ) ->
#jid{user = FUser, lserver = FServer} = From,
PollOptionId = fxml:get_path_s(SubEl, [{attr, <<"poll_option_id">>}]),
VoterUserId = fxml:get_path_s(SubEl, [{attr, <<"voter_user_id">>}]),
PollId = fxml:get_path_s(SubEl, [{attr, <<"poll_id">>}]),
ChatType = fxml:get_path_s(SubEl, [{attr, <<"type">>}]),
SendTo = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
VoteId = fxml:get_path_s(SubEl, [{attr, <<"vote_id">>}]),
MessageId = p1_rand:get_string(),
CustAtr = fxml:get_subtag_with_xmlns(xmpp:encode(SubEl), <<"custom_attributes">>, <<"ocp:json">>),
ReceivedTimestamp = now_to_microseconds(erlang:now()),
ReceivedFlatTimeStamp = lists:flatten(io_lib:format("~p", [ReceivedTimestamp])),
ReceivedXMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(ReceivedFlatTimeStamp)}],
  children = []},
if CustAtr =:= false ->
  CustomAttributes = "";
true ->
  CustomAttributes = fxml:get_tag_cdata(CustAtr)
end,
if ChatType == <<"chat">> ->
  ToJid = jid:from_string(SendTo),
  #jid{user = TUser, lserver = TServer} = ToJid,
  XmlBody = #xmlel{name = <<"message">>,attrs = [{<<"from">>, jid:to_string(From)},{<<"to">>, SendTo},{<<"id">>, MessageId},{<<"type">>, <<"chat">>}],
    children = [#xmlel{name = <<"poll">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:receipts">>},{<<"chat_type">>, <<"chat">>},{<<"poll_id">>, PollId},{<<"voter_user_id">>, VoterUserId},{<<"vote_id">>, VoteId},{<<"status">>, RequestType},{<<"poll_option_id">>, PollOptionId},{<<"to_user">>, SendTo}]},
      #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}]},
  Packet = fxml:append_subtags(XmlBody, [ReceivedXMLTag]),
  ejabberd_router:route(From, ToJid, Packet),
  case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
    true ->
      mod_offline:store_packet({ToJid,xmpp:decode(Packet)}),
      fly_mod_offline_push:send_offline_message({From,xmpp:decode(Packet)});
    false ->
      ok
  end,
  store_offline_user_send(Packet,From,ToJid);

ChatType == <<"groupchat">> ->
  ToUser = binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])),
  [GUser | _S] = string:tokens(ToUser, "@"),
  MsgId = p1_rand:get_string(),
  case catch fly_mod_utils:get_group_users(FServer, GUser) of
  {selected, _, []} ->
  ok;
  {selected, _, GroupMembers} ->
    Members = lists:flatmap(fun([UJid]) -> [UJid] end, GroupMembers),
    lists:foreach(fun(To) ->
  RouteToJid = jid:make(To, FServer, <<>>),
  #jid{user = TUser, lserver = TServer} = RouteToJid,
  XmlBody = #xmlel{name = <<"message">>,attrs = [{<<"from">>, jid:to_string(From)},{<<"to">>, jid:to_string(RouteToJid)},{<<"id">>, MsgId},{<<"type">>, <<"chat">>}],
    children = [#xmlel{name = <<"poll">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:receipts">>},{<<"chat_type">>, <<"normal">>},{<<"status">>, RequestType},{<<"poll_id">>, PollId},{<<"voter_user_id">>, VoterUserId},{<<"vote_id">>, VoteId},{<<"poll_option_id">>, PollOptionId},{<<"to_user">>, SendTo}]},
      #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}]},
      Packet = fxml:append_subtags(XmlBody, [ReceivedXMLTag]),
      ejabberd_router:route(From, RouteToJid, Packet),
  case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
    true ->
      mod_offline:store_packet({From, xmpp:decode(Packet)}),
      fly_mod_offline_push:send_offline_message({From,xmpp:decode(Packet)});
    false ->
      ok
  end

              end, Members)
end;
  true ->
  ok
  end,
fly_mod_utils:poll_vote_update(FServer,PollId,VoterUserId,RequestType,PollOptionId,SendTo,ReceivedFlatTimeStamp,VoteId),
fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Send successfully">>}).

  send_sms_message(_From, RequestType, SubEl,IQ) ->
  MessageFrom = fxml:get_path_s(SubEl, [{attr, <<"message_from">>}]),
  MessageTo = fxml:get_path_s(SubEl, [{attr, <<"message_to">>}]),
  MessageType = fxml:get_path_s(SubEl, [{attr, <<"message_type">>}]),
  MessageId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  EditMsgId = fxml:get_path_s(SubEl, [{attr, <<"edit_message_id">>}]),
  MessageTag = fxml:get_path_s(SubEl, [{attr, <<"message">>}]),
  GroupId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  ChatType = fxml:get_path_s(SubEl, [{attr, <<"chat_type">>}]),
  TopicId = fxml:get_path_s(SubEl, [{attr, <<"topic_id">>}]),
  Metadata = fxml:get_path_s(SubEl, [{attr, <<"meta_data">>}]),
  ScheduledDatetime = fxml:get_path_s(SubEl, [{attr, <<"scheduled_datetime">>}]),
  if Metadata =:= <<>> ->
    MetaData = <<"{}">>;
  true ->
    MetaData = Metadata
  end,
  if ChatType == <<"chat">> ->
  FromJid = jid:from_string(MessageFrom),
  ToJid = jid:from_string(MessageTo),
  #jid{user = FUser, lserver = FServer} = FromJid,
  #jid{user = TUser, lserver = TServer} = ToJid,
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, MessageFrom}, {<<"to">>, MessageTo}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [#xmlel{name = <<"chatcontent">>,
      attrs = [{<<"xmlns">>, <<"urn:xmpp:content">>}, {<<"broadcast_id">>, <<"">>},{<<"message_type">>, MessageType},{<<"topic_id">>, TopicId},{<<"meta_data">>, MetaData},{<<"edit_msg_id">>, EditMsgId},{<<"scheduled_datetime">>, ScheduledDatetime}],
      children = []}]},
  XMLTag = #xmlel{name = <<"body">>, attrs = [{<<"message_type">>, MessageType}],
                children = [{xmlcdata, MessageTag}]},
              TimeStampedPacket = fxml:append_subtags(XmlBody, [XMLTag]),
  ReceivedTimestamp = now_to_microseconds(erlang:now()),
  ReceivedFlatTimeStamp = lists:flatten(io_lib:format("~p", [ReceivedTimestamp])),
  ReceivedXMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(ReceivedFlatTimeStamp)}],
    children = []},
  XmlBody1 = fxml:append_subtags(TimeStampedPacket, [ReceivedXMLTag]),
  ejabberd_router:route(FromJid, ToJid, XmlBody1),
  store_offline_user_send(XmlBody1,FromJid,ToJid),
  case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
    true ->
      mod_offline:store_packet({FromJid, xmpp:decode(XmlBody1)});
    false ->
      ok
  end,
  case catch fly_mod_utils:check_blockeduser(FServer, FUser, TUser) of
            {selected, _, []} ->
              BlockUser = <<"0">>;
            {selected, _, _ResultSet} ->
              BlockUser = TUser
          end,
          SUser = FUser,
          SType = ChatType,
          BarePeer = TUser,
          MsgContent = MessageTag,
          fly_mod_stanza_ack:send_ack_response(FromJid, ToJid, MessageId, <<"acknowledge">>),
          fly_mod_stanza_ack:store_in_table(FServer,BarePeer,SUser,MessageId,MsgContent,SType,MessageType,TopicId, MetaData ,BlockUser, EditMsgId, ReceivedFlatTimeStamp),
        if BlockUser == <<"0">> ->
          case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
            true ->
              fly_mod_offline_push:send_offline_message({FromJid, xmpp:decode(XmlBody1)});
            false ->
              ok
          end;
        true ->
          ok
        end,
  fly_mod_utils:insert_status(FromJid, ToJid, MessageId,MessageType,TopicId, MetaData, SType,<<"">>,BlockUser,MsgContent,ReceivedFlatTimeStamp,EditMsgId);
  ChatType == <<"normal">> ->
  FromJid = jid:from_string(MessageFrom),
  ToJid = jid:from_string(GroupId),
  XmlBody = #xmlel{name = <<"message">>, attrs = [{<<"from">>, MessageFrom}, {<<"to">>, MessageTo}, {<<"type">>, <<"normal">>}, {<<"id">>, MessageId},{<<"xmlns">>, <<"jabber:client">>}],
  children = [#xmlel{name = <<"chatcontent">>,
      attrs = [{<<"xmlns">>, <<"urn:xmpp:content">>},{<<"message_type">>, MessageType},{<<"topic_id">>, TopicId},{<<"meta_data">>, MetaData},{<<"edit_msg_id">>, EditMsgId},{<<"scheduled_datetime">>, ScheduledDatetime}],
      children = []}]},
  SubjectTag = #xmlel{name = <<"subject">>, attrs = [],
                children = [{xmlcdata, MessageType}]},
    XMLTag = #xmlel{name = <<"body">>, attrs = [],
                children = [{xmlcdata, MessageTag}]},
    Packet = fxml:append_subtags(XmlBody, [SubjectTag]),
    NewPacket = fxml:append_subtags(Packet, [XMLTag]),
  ejabberd_router:route(FromJid, ToJid, NewPacket);
  true ->
  ok
  end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Send successfully">>}).

  store_offline_user_send(Packet, #jid{luser = FUser, lserver = FServer, lresource = LResource} = From, To) ->
  fly_mod_offline_push:send_own_offline_message(From, To, xmpp:encode(Packet)),

  Resources = ejabberd_sm:get_user_resources(FUser, FServer),
  if length(Resources) =:= 0 ->
    {U, S, R} = jid:tolower(From),
    Sender = jid:make({U, S, R}),
    Dest = jid:make({U, S, <<>>}),
    NewPacket = build_forward_packet(xmpp:decode(Packet), Sender, Dest, sent),
    mod_offline:store_packet({To,NewPacket});
  true ->
    lists:foldl(fun(SResource,_Acc) ->
      {U, S, RS} = jid:tolower(From),
      Dest = jid:make({U, S, SResource}),
      Sender = jid:make({U, S, <<>>}),
      New = build_forward_packet(xmpp:decode(Packet), Sender, Dest, sent),
      ejabberd_router:route(xmpp:set_from_to(New, Sender, Dest))
      end,[],Resources)
  end.

  build_forward_packet(#message{type = T} = Msg, Sender, Dest, Direction) ->
      Forwarded = #forwarded{sub_els = [Msg]},
      Carbon = case Direction of
      sent -> #carbons_sent{forwarded = Forwarded};
      received -> #carbons_received{forwarded = Forwarded}
      end,
      #message{from = Sender, to = Dest, type = T, sub_els = [Carbon], meta = #{carbon_copy => true}}.

carboncall_message(From, RequestType, SubEl,IQ) ->
  SocketId = fxml:get_path_s(SubEl, [{attr, <<"socket_id">>}]),
  Call_Status = fxml:get_path_s(SubEl, [{attr, <<"call_status">>}]),
  #jid{luser = LUser, lserver = LServer, lresource = LResource} = From,
  WebResource = string:str(binary_to_list(LResource), binary_to_list(<<"Web">>)),
  MessageId = p1_rand:get_string(),
  length(lists:foldl(fun(SResource,_Acc) ->
    MobileResource = string:str(binary_to_list(SResource), binary_to_list(<<"Mobile">>)),
    if WebResource =:= 1 ->
      if MobileResource =:= 1 ->
        ToJid = jid:make(LUser, LServer, SResource),
        XmlBody = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(ToJid)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
          children = [#xmlel{name = <<"call">>,
            attrs = [{<<"xmlns">>,<<"urn:xmpp:call">>}, {<<"call_status">>,Call_Status}, {<<"socket_id">>, SocketId}],
            children = []}]},
        ejabberd_router:route(From, ToJid, XmlBody);

        true ->
          ok
      end;
      true ->
        if MobileResource =:= 0 ->
          ToJid = jid:make(LUser, LServer, SResource),
          XmlBody = #xmlel{name = <<"message">>,
            attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(ToJid)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
            children = [#xmlel{name = <<"call">>,
              attrs = [{<<"xmlns">>,<<"urn:xmpp:call">>}, {<<"call_status">>,Call_Status}, {<<"socket_id">>, SocketId}],
              children = []}]},
          ejabberd_router:route(From, ToJid, XmlBody);

          true ->
            ok
        end
    end
    end,[],ejabberd_sm:get_user_resources(LUser, LServer))),

  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Send successfully">>}).

update_mute_notification(From, RequestType, SubEl, IQ) ->
  MuteStatus = fxml:get_path_s(SubEl, [{attr, <<"mute_status">>}]),
  ToUserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  [ToUser | _S] = string:tokens(binary_to_list(ToUserJid), "@"),
  fly_mod_utils:update_mute_chat(From, ToUser, MuteStatus),
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  #jid{luser = User,lserver = Server, lresource = Resource} = From,
  To = jid:make({User, Server, <<>>}),
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"mute">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"to_user">>,ToUserJid}, {<<"mute_status">>, MuteStatus}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),

    NewPacket = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(To)}, {<<"to">>, jid:to_string(From)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
      children = [#xmlel{name = <<"mute">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"to_user">>,ToUserJid}, {<<"mute_status">>, MuteStatus}],
        children = []}]},
    mod_offline:store_packet({From, xmpp:decode(NewPacket)}),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated successfully">>}).

  mute_notification(From, RequestType, SubEl, IQ) ->
    UserIds = fxml:get_path_s(SubEl, [{attr, <<"user_list">>}]),
    MuteAction = fxml:get_path_s(SubEl, [{attr, <<"action">>}]),
    MuteSettings = fxml:get_path_s(SubEl, [{attr, <<"mute_setting">>}]),
    ToUser = fxml:get_path_s(SubEl, [{attr, <<"from_user">>}]),
    NewMessageId = fly_mod_utils:get_iq_message_id(20),
    #jid{luser = _User,lserver = Server, lresource = _Resource} = From,
    To = jid:make(ToUser, Server),
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(To)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
      children = [#xmlel{name = <<"mute">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"action">>,MuteAction}, {<<"mute_setting">>,MuteSettings}, {<<"user_list">>,UserIds}],
        children = []}]},
    ReceivedTimestamp = now_to_microseconds(erlang:now()),
  ReceivedFlatTimeStamp = lists:flatten(io_lib:format("~p", [ReceivedTimestamp])),
  ReceivedXMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(ReceivedFlatTimeStamp)}],
    children = []},
  XmlBody1 = fxml:append_subtags(XmlBody, [ReceivedXMLTag]),
  ejabberd_router:route(To, To, XmlBody1),
  % store_offline_user_send(XmlBody1,To,To),
  case fly_mod_utils:get_mobile_user_message(ToUser, Server) of
          true ->
            mod_offline:store_packet({To,xmpp:decode(XmlBody1)});
          false ->
            ok
        end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated successfully">>}).

update_archive_chat(FromJid, RequestType, SubEl, IQ) ->
  ArchiveStatus = fxml:get_path_s(SubEl, [{attr, <<"archive_status">>}]),
  ToUserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  FromUserJid = fxml:get_path_s(SubEl, [{attr, <<"from_user">>}]),
  [ToUser | _S] = string:tokens(binary_to_list(ToUserJid), "@"),

  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  if  FromUserJid =:= <<"">> ->
    #jid{luser = User,lserver = Server, lresource = Resource} = FromJid,
    From = FromJid,
    To = jid:make({User, Server, <<>>});
  true ->
    [User | Server] = string:tokens(binary_to_list(FromUserJid), "@"),
    From = jid:make({list_to_binary(User), list_to_binary(Server), <<>>}),
    To = From
  end,
  fly_mod_utils:update_archive_chat(From, ToUser, ArchiveStatus),

  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"archive">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"to_user">>,ToUserJid}, {<<"archive_status">>, ArchiveStatus}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),
  case fly_mod_utils:get_mobile_user_message(User, Server) of
    true ->
      mod_offline:store_packet({From,xmpp:decode(XmlBody)});
    false ->
      ok
  end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated successfully">>}).

  update_user_busy(From, RequestType, SubEl, IQ) ->
    BusyStatus = fxml:get_path_s(SubEl, [{attr, <<"busy_status">>}]),
    BusyMsg = fxml:get_path_s(SubEl, [{attr, <<"busy_message">>}]),
    fly_mod_utils:update_user_busy(From, BusyStatus, BusyMsg),
    NewMessageId = fly_mod_utils:get_iq_message_id(20),
    #jid{luser = User,lserver = Server, lresource = Resource} = From,
    To = jid:make({User, Server, <<>>}),
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
      children = [#xmlel{name = <<"busy">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"busy_message">>,BusyMsg}, {<<"busy_status">>, BusyStatus}],
        children = []}]},
    ejabberd_router:route(From, To, XmlBody),
    case fly_mod_utils:get_mobile_user_message(User, Server) of
      true ->
        mod_offline:store_packet({From,xmpp:decode(XmlBody)});
      false ->
        ok
    end,
    fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated successfully">>}).

register_update_to_rosters(From, RequestType, SubEl, IQ) ->

  ToUserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  ToJid = jid:from_string(ToUserJid),

  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)},{<<"type">>, <<"chat">>}, {<<"id">>, p1_rand:get_string()}],
    children = [#xmlel{name = <<"register_update">>,
      attrs = [{<<"xmlns">>, <<"urn:xmpp:register_update">>}, {<<"status">>, RequestType}],
      children = []}]},
  {selected, _, Rosters} = fly_mod_utils:get_roster_from_recent_jid(ToJid),
  push_register_packets(Rosters,XmlBody,ToJid),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated to rosters successfully">>}).

push_register_packets(Rosters,Packet,From) ->
  #jid{lserver = Server} = From,
  lists:foreach(fun([RosterJid]) ->
      NewPacket0 = xmpp:decode(Packet),
      NewPacket1 = xmpp:set_to(NewPacket0,jid:make(RosterJid, Server)),
      NewPacket2 = xmpp:set_id(NewPacket1,fly_mod_utils:get_iq_message_id(15)),
      mod_offline:store_packet({jid:make(RosterJid, Server),NewPacket2}),
      ejabberd_router:route(From, jid:make(RosterJid, Server), Packet)
                end, Rosters).

send_push(From, RequestType, SubEl, IQ) ->
  MessageTo = fxml:get_path_s(SubEl, [{attr, <<"message_to">>}]),
  ToJid = jid:from_string(MessageTo),
  #jid{lserver = FServer} = From,
  #jid{user = TUser} = ToJid,
  % case catch fly_mod_utils:get_offline_message(FServer, TUser) of
  %   {selected, _, []} ->
  %     ok;
  %   {selected, _, Messages} ->
  %       lists:map(fun(G) ->
  %       [ChatType, Packet] = G,
  %       El = #xmlel{} = fxml_stream:parse_element(Packet),
  %       FromUser = #jid{} = jid:from_string(
  %         fxml:get_attr_s(<<"from">>, El#xmlel.attrs)),
  %       ToUser = #jid{} = jid:from_string(
  %         fxml:get_attr_s(<<"to">>, El#xmlel.attrs)),
  %       if ChatType =:= <<"chat">> ->
  %         mod_offline_push:send_offline_message(FromUser, ToUser, El);
  %         ChatType =:= <<"normal">> ->
  %           mod_offline_push:send_offline_message(FromUser, ToUser, El);
  %         true ->
  %           ok
  %       end
  %                         end, Messages)
  % end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Send successfully">>}).

now_to_microseconds({Mega, Sec, Micro}) ->
  %%Epoch time in milliseconds from 1 Jan 1970
  (Mega * 1000000 + Sec) * 1000000 + Micro.

call_message(_From, RequestType, SubEl, IQ) ->

  MessageFrom = fxml:get_path_s(SubEl, [{attr, <<"message_from">>}]),
  MessageTo = fxml:get_path_s(SubEl, [{attr, <<"message_to">>}]),
  Socket_Id = fxml:get_path_s(SubEl, [{attr, <<"socket_id">>}]),
  Call_Status = fxml:get_path_s(SubEl, [{attr, <<"call_status">>}]),
  Call_Type = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
  Caller_Device = fxml:get_path_s(SubEl, [{attr, <<"caller_device">>}]),
  Call_Id = fxml:get_path_s(SubEl, [{attr, <<"call_id">>}]),
  MessageId = p1_rand:get_string(),
  FromJid = jid:from_string(MessageFrom),
  ToJid = jid:from_string(MessageTo),
  #jid{user = TUser, server = TServer} = ToJid,
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, MessageFrom}, {<<"to">>, MessageTo}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
    children = [#xmlel{name = <<"call">>,
      attrs = [{<<"xmlns">>, <<"urn:xmpp:call">>}, {<<"caller_device">>, Caller_Device}, {<<"call_id">>, Call_Id}, {<<"call_type">>, Call_Type}, {<<"call_status">>, Call_Status}, {<<"socket_id">>, Socket_Id}],
      children = []}]},
  case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
    true ->
      Pkt = xmpp:decode(XmlBody),
      fly_mod_offline_push:send_offline_message({FromJid, Pkt});
    false ->
      ok
  end,
  ejabberd_router:route(FromJid, ToJid, XmlBody),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Send successfully">>}).


%% send presence to the user while a vcard is updated
%%
%%
%% @param record From
%% @param record Packet
%% @return atom
push_to_rosters(From, Packet) ->
  %%#jid{luser = RosterUser,lserver = Server} = From,
  case catch fly_mod_utils:get_roster_from_recent_jid(From) of
    {selected, _, []} ->
      ok;
    {selected, _, Rosters} ->
      push_all_packets(Rosters,Packet,From);
    _ ->
      error
  end.

push_to_rosters_and_recent(From, Packet) ->
  case catch fly_mod_utils:get_roster_from_recent_jid(From) of
    {selected, _, []} ->
      [];
    {selected, _, Rosters} ->
      push_all_packets(Rosters, Packet, From);
    _ ->
      error
  end.

push_to_rosters_and_recent_admin_block(To, From,BlockStatus,ToUserJid) ->
  case catch fly_mod_utils:get_roster_from_recent_jid(To) of
    {selected, _, []} ->
      [];
    {selected, _, Rosters} ->
      push_all_packets_with_offline(Rosters, From,BlockStatus,ToUserJid);
    _ ->
      error
  end.

% push_to_email_contacts(From, Packet) ->
%   case catch fly_mod_utils:get_email_contacts(From) of
%     {selected, _, []} ->
%       ok;
%     {selected, _, EmailContacts} ->
%       push_all_packets(EmailContacts, Packet, From);
%     _ ->
%       error
%   end.

push_to_rosters_and_recent_user_deleted(From, Packet) ->
  case catch fly_mod_utils:get_roster_from_recent_jid(From) of
    {selected, _, []} ->
      [];
    {selected, _, Rosters} ->
      push_all_packets_with_offline_delete(Rosters, Packet, From);
    _ ->
      error
  end,
  case catch fly_mod_utils:get_users_from_group(From) of
    {selected, _, []} ->
      [];
    {selected, _, Users} ->
      push_all_packets_with_offline_delete(Users, Packet, From);
    _ ->
      error
  end.

push_all_packets(Rosters,Packet,From) ->
  #jid{lserver = Server} = From,
  lists:foreach(fun([RosterJid]) ->
    lists:foreach(fun(Resource) ->
      ejabberd_router:route(From, jid:make(RosterJid, Server, Resource), Packet)
                  end, ejabberd_sm:get_user_resources(RosterJid, Server))
                end, Rosters).

push_all_packets_with_offline(Rosters,From,BlockStatus,ToUserJid) ->
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  #jid{lserver = Server} = From,
  lists:foreach(fun([RosterJid]) ->
    Tojid = jid:make(RosterJid, Server, <<>>),
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(Tojid)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
      children = [#xmlel{name = <<"admin_block">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"chat_type">>, <<"chat">>}, {<<"type">>, <<"admin_block">>}, {<<"jid">>,ToUserJid}, {<<"block_status">>, BlockStatus}],
        children = []}]},
      ejabberd_router:route(From, Tojid, XmlBody),
      mod_offline:store_packet({From, xmpp:decode(XmlBody)})
  end, Rosters).

push_all_packets_with_offline_delete(Rosters,_Packet,From) ->
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  #jid{lserver = Server} = From,
  lists:foreach(fun([RosterJid]) ->
    Tojid = jid:make(RosterJid, Server, <<>>),
    XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)},{<<"to">>, jid:to_string(Tojid)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"user_deleted">>,
      attrs = [{<<"xmlns">>, ?NS_USER_ACTIVITIES}, {<<"user">>,jid:to_string(From)}],
      children = []}]},
      ejabberd_router:route(From,Tojid, XmlBody),
      % case get_user_resource_offline(User, Server) of
      %   true ->
          mod_offline:store_packet({From, xmpp:decode(XmlBody)})
      %   false ->
      %     ok
      % end
  end, Rosters).

%%push_all_packets(Rosters, BlockedUsers, Packet,From) ->
%%  lists:foreach(fun([RosterJid]) ->
%%    ?INFO_MSG("Lict check: ~p",[RosterJid]),
%%    ?INFO_MSG("Lict check: ~p",[lists:member(RosterJid, BlockedUsers)]),
%%    case lists:member(RosterJid, BlockedUsers) of
%%      true ->
%%        ok;
%%      false ->
%%        #jid{user = User, server = Server} = jid:from_string(RosterJid),
%%        lists:foreach(fun(Resource) ->
%%          ejabberd_router:route(From, jid:make(User, Server, Resource), Packet)
%%                      end, ejabberd_sm:get_user_resources(User, Server))
%%    end
%%        end, Rosters).

%% push user registered notification presence to the rosters
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
push_register_notify_presence(From, RequestType, _SubEl, IQ) ->
  push_to_rosters(From, #xmlel{
    name = <<"presence">>,
    attrs = [],
    children = [#xmlel{
      name = <<"query">>,
      attrs = [{<<"xmlns">>, <<"jabber:iq:user_activities">>}],
      children = []
    }]
  }),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Registered presence is triggered successfully">>}).

get_call_status(From, RequestType,  SubEl, IQ) ->
  #jid{ lserver = LServer} = From,
  SocketId = fxml:get_path_s(SubEl, [{attr, <<"socket_id">>}]),
  case catch fly_mod_utils:get_callstatus(LServer, SocketId) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"call details not available">>});
    {selected, _, ResultSet} ->
      SubEls1 = lists:map(fun([Status]) ->
        CallStatus = #xmlel{name = <<"status">>, attrs = [], children = [{xmlcdata, Status}]},
        #xmlel{name = <<"callstatus">>, attrs = [], children = [CallStatus]}
                          end, ResultSet),
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = SubEls1 })
  end.

  get_reply_message(From, RequestType,  SubEl, IQ) ->
  #jid{ lserver = LServer} = From,

  ReplyId = fxml:get_path_s(SubEl, [{attr, <<"reply_id">>}]),
  OldMessageId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),

  case catch fly_mod_utils:get_reply_message(LServer, ReplyId) of
    {selected, _, []} ->
      case catch fly_mod_utils:get_single_message(LServer, ReplyId, OldMessageId) of
        {selected, _, []} ->
        ReplyMsg = ok;
        {selected, _, Result} ->
          ReplyMsg = Result
      end;
    {selected, _, Result} ->
        ReplyMsg = Result
    end,
      if ReplyMsg == ok ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Message Not Available">>});
      true ->
      SubEls1 = lists:map(fun(G) ->
        [MessageTag, MessageId, EditMsgId, MessageFrom, Chat_Type, DeletedBy, DeletedStatus, MsgStatus, From_Notification, To_Notification, To_User, Message_Time, Message_Notification, Recall_Status, Created_At, TopicId, EditStatus, Update_at, MetaData, MessageContentTag] = G,
        MsgIdElement = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MessageId}]},
        EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
        children = [{xmlcdata, EditMsgId}]},
        DeletedByElement = #xmlel{name = <<"deleted_by">>, attrs = [],
          children = [{xmlcdata, DeletedBy}]},
        DeletedStatusElement = #xmlel{name = <<"deleted_status">>, attrs = [],
          children = [{xmlcdata, DeletedStatus}]},
        ChatTypeElement = #xmlel{name = <<"chat_type">>, attrs = [],
          children = [{xmlcdata, Chat_Type}]},
        FromNotificationElement = #xmlel{name = <<"from_notification">>, attrs = [],
          children = [{xmlcdata, From_Notification}]},
        ReplyUserElement = #xmlel{name = <<"replyfromuser">>, attrs = [],
          children = [{xmlcdata, MessageFrom}]},
        if MessageTag =:= <<"">> ->
          Message = #xmlel{name = <<"body">>, attrs = [],
          children = [{xmlcdata, MessageContentTag}]};
        true ->
        Message = #xmlel{name = <<"body">>, attrs = [],
          children = [{xmlcdata, MessageTag}]}
        end,
        MessageStatus = #xmlel{name = <<"status">>, attrs = [],
          children = [{xmlcdata, MsgStatus}]},
        ToNotification = #xmlel{name = <<"to_notification">>, attrs = [],
          children = [{xmlcdata, To_Notification}]},
        ToUser = #xmlel{name = <<"to_user">>, attrs = [],
          children = [{xmlcdata, To_User}]},
        MessageTime = #xmlel{name = <<"message_time">>, attrs = [],
          children = [{xmlcdata, Message_Time}]},
        MessageNotification = #xmlel{name = <<"message_notification">>, attrs = [],
          children = [{xmlcdata, Message_Notification}]},
        MetaDataElement = #xmlel{name = <<"meta_data">>, attrs = [],
          children = [{xmlcdata, MetaData}]},
        EditStatusElement = #xmlel{name = <<"edit_msg_status ">>, attrs = [],
          children = [{xmlcdata, EditStatus}]},
        TimeElements = #xmlel{name = <<"time">>, attrs = [],
          children = [{xmlcdata, Update_at}]},
        TopicIdElement = #xmlel{name = <<"topic_id">>, attrs = [],
          children = [{xmlcdata, TopicId}]},
        RecallStatus = #xmlel{name = <<"recall_status">>, attrs = [],
          children = [{xmlcdata, Recall_Status}]},
        CreatedAt = #xmlel{name = <<"created_at">>, attrs = [],
          children = [{xmlcdata, Created_At}]},

        #xmlel{name = <<"chat">>, attrs = [],
          children = [MsgIdElement, EditStatusElement, EMsgidElement, TimeElements, DeletedByElement, DeletedStatusElement, MetaDataElement, TopicIdElement, ChatTypeElement, ReplyUserElement, Message, MessageStatus, FromNotificationElement, ToNotification, ToUser, MessageTime, MessageNotification, RecallStatus, CreatedAt]}
                          end,
                          ReplyMsg),
      GroupXml = [#xmlel{name = <<"replymessage">>, attrs = [{<<"id">>, OldMessageId}], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = GroupXml })
                        end.

get_block_list(From, RequestType, _SubEl, IQ) ->
  #jid{luser = User, lserver = LServer} = From,

  case catch fly_mod_utils:get_blockedlist(LServer, User) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No blocked list available">>});
    {selected, _, ResultSet} ->

      SubEls1 = lists:map(fun([Name]) ->

        BlockName = #xmlel{name = <<"members">>, attrs = [], children = [{xmlcdata, Name}]},

        #xmlel{name = <<"blocklist">>, attrs = [], children = [BlockName]}
                          end, ResultSet),
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = SubEls1 })
  end.

send_block_list(From, To, RequestType) ->
  #jid{luser = User, lserver = LServer} = From,
  MessageId = p1_rand:get_string(),
  if RequestType =:= <<"unblock">> ->
    fly_mod_utils:delete_spool(LServer, User);
    true ->
      ok
  end,
  lists:map(fun(JID) ->
    ToJid = jid:from_string(jid:to_string(JID)),
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(ToJid)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [#xmlel{name = <<"userblocked">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"blocked_user">>, User}, {<<"type">>, RequestType}],
        children = []}]},
    ejabberd_router:route(From, ToJid, XmlBody)

            end,
    To).

%% clear the users message in db and notify to other resource
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
clear_message(#jid{luser = User, lserver = Server, lresource = _Resource} = From,  RequestType, SubEl, IQ) ->
  Chat_Type = fxml:get_path_s(SubEl, [{attr, <<"chat_type">>}]),
  Type = fxml:get_path_s(SubEl, [{attr, <<"type">>}]),
  Favourite = fxml:get_path_s(SubEl, [{attr, <<"favourite">>}]),
  Message_ID = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  DeleteAction = fxml:get_path_s(SubEl, [{attr, <<"delete_type">>}]),
  Last_Msg_Id = fxml:get_path_s(SubEl, [{attr, <<"last_msg_id">>}]),
  Log_Ids = fxml:get_path_s(SubEl, [{attr, <<"calllog_ids">>}]),
  % if Chat_Type =:= <<"chat">> ->
    Timestamp = now_to_microseconds(erlang:now()),
    FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
    Remove_User = fxml:get_path_s(SubEl, [{attr, <<"remove_user">>}]),
    MessageId = p1_rand:get_string(),
    To = jid:make({User, Server, <<>>}),
    if Last_Msg_Id =:= <<"">> andalso Log_Ids =:= <<"">> ->
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [
            #xmlel{name = <<"messageclear">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"favourite">>, Favourite}, {<<"remove_message_user">>, Remove_User},{<<"message_id">>, Message_ID}, {<<"type">>, RequestType},  {<<"chat_type">>, Chat_Type}, {<<"delete_type">>, DeleteAction}],
        children = []},
            #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
                children = []}
          ]};
      true->
      XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [
            #xmlel{name = <<"messageclear">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"favourite">>, Favourite},{<<"last_msg_id">>, Last_Msg_Id}, {<<"remove_message_user">>, Remove_User},{<<"message_id">>, Message_ID}, {<<"calllog_ids">>, Log_Ids}, {<<"type">>, Type}, {<<"status">>, RequestType}, {<<"chat_type">>, Chat_Type}, {<<"delete_type">>, DeleteAction}],
        children = []},
            #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
                children = []}
          ]}
        end,
    ejabberd_router:route(From, To, XmlBody),
    if Last_Msg_Id =:= <<"">>->
      fly_mod_utils:clear_message(From, Remove_User, Favourite, DeleteAction);
    true->
      fly_mod_utils:clear_message(From, Remove_User, Favourite, DeleteAction,Last_Msg_Id)
      end,
        case fly_mod_utils:get_mobile_user_message(User, Server) of
        true ->
          mod_offline:store_packet({From,xmpp:decode(XmlBody)});
        false ->
          ok
      end,
      if Type =:= <<"calllog">> ->
        Range = binary:split(Log_Ids, <<",">>, [global]),

        lists:foreach(fun(N) ->
          fly_mod_utils:clear_particular_call_log(From, N)
        end, Range),
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Clear calls successfully">>});
  true ->
    if DeleteAction =:= <<"1">> ->
      fly_mod_utils:updategroup_clear(From, Remove_User);
    true ->
      ok
    end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Clear Message successfully">>})
  end.

%% clear the all users messages in db and notify to other resource
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
clear_all(#jid{luser = User, lserver = Server, lresource = _Resource} = From, RequestType, SubEl, IQ) ->
  Chat_Type = fxml:get_path_s(SubEl, [{attr, <<"type">>}]),
  Delete_Type = fxml:get_path_s(SubEl, [{attr, <<"delete_type">>}]),
  Last_Msg_Id = fxml:get_path_s(SubEl, [{attr, <<"last_msg_id">>}]),
  Log_Ids = fxml:get_path_s(SubEl, [{attr, <<"calllog_ids">>}]),
  MessageId = p1_rand:get_string(),
  Timestamp = now_to_microseconds(erlang:now()),
  FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
  To = jid:make(User, Server),
      if Last_Msg_Id =:= <<"">> andalso Log_Ids =:= <<"">> ->
      XmlBody = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [
            #xmlel{name = <<"messageclear">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, RequestType}, {<<"delete_type">>, Delete_Type}],
        children = []},
            #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
                children = []}]};
      true ->
      XmlBody = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [
            #xmlel{name = <<"messageclear">>, attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, Chat_Type},{<<"status">>, RequestType}, {<<"delete_type">>, Delete_Type},{<<"last_msg_id">>, Last_Msg_Id},{<<"calllog_ids">>, Log_Ids}],
          children = []},
            #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
                children = []}
          ]}
      end,
      ejabberd_router:route(From, To, XmlBody),
      case fly_mod_utils:get_mobile_user_message(User, Server) of
        true ->
          mod_offline:store_packet({From,  xmpp:decode(XmlBody)});
        false ->
          ok
        end,
  if Chat_Type =:= <<"chat">> ->
  fly_mod_offline_push:queryexecfunction(From, clearall, Last_Msg_Id, Delete_Type, XmlBody),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Clear All Message successfully">>});
  true ->
  fly_mod_offline_push:queryexecfunction(From, calllog, Chat_Type, Log_Ids,XmlBody),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Clear All Call Logs successfully">>})
  end.

%% delete the users message in db and notify to other resource
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
delete_message(FromUser, RequestType, SubEl, IQ) ->
  #jid{luser = FUser, lserver = FServer, lresource = _Resource} = FromUser,
  Chat_Type = fxml:get_path_s(SubEl, [{attr, <<"type">>}]),
  UserType = fxml:get_path_s(SubEl, [{attr, <<"chat_type">>}]),
  MessageId = p1_rand:get_string(),
  Timestamp = now_to_microseconds(erlang:now()),
  MessageIds = fxml:get_path_s(SubEl, [{attr, <<"message_ids">>}]),
  FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
  if RequestType == <<"api_delete_message">>->
    [ToJID | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),
    ToUser = jid:make({list_to_binary(ToJID), FServer, <<>>}),
    [FromJID | _FS] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"from_user">>}])), "@"),
    To = jid:make({list_to_binary(FromJID), FServer, <<>>}),
    From = jid:make({list_to_binary(FromJID), FServer, <<>>}),
    #jid{luser = User, lserver = Server} = From;
  true ->
    [ToJID | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),
    #jid{luser = User, lserver = Server} = FromUser,
    To = jid:make({User, Server, <<>>}),
    ToUser = jid:make({list_to_binary(ToJID), Server, <<>>}),
    From = FromUser
  end,
  if Chat_Type =:= <<"chat">> ->
    Range = binary:split(MessageIds, <<",">>, [global]),
    lists:foreach(fun(N) ->
      fly_mod_utils:delete_message(From, N),
      media_permission_revoke(Server, N, User)
    end, Range),
    case catch fly_mod_utils:get_last_messages(From, ToUser, list_to_binary(ToJID)) of
      {selected, _, []} ->
        LastMessageId = <<"">>,
        fly_mod_utils:delete_message_recentchat(Server, ToJID, User);
      {selected, _, [[MessageFrom,MessageTo, Message_id, Message_type, ChatType, Status, Recall_status, Message_time, From_notification, To_notification, Message_notification, Created_at,Topic_id,MetaData]]} ->
        LastMessageId = Message_id,
        if (Message_type =:= <<"text">>)  or (Message_type =:= <<"poll">>)->
          case catch fly_mod_utils:get_message(Server, ChatType, Message_id) of
            {selected, _, []} ->
              Body = <<"">>;
            {selected, _, [[Txt,Msg]]} ->
              if Txt =:= <<"">> ->
                Body = Msg;
              true ->
                Body = Txt
              end
          end,
          MessageType = Message_type,
          MsgContent = Body;
        Message_type =:= <<"auto_text">> ->
          MessageType = Message_type,
          case catch fly_mod_utils:get_message(Server, ChatType, Message_id) of
            {selected, _, []} ->
              Body = <<"">>;
            {selected, _, [[Txt,Msg]]} ->
               if Txt =:= <<"">> ->
                Body = Msg;
              true ->
                Body = Txt
              end
          end,
          MsgContent = Body;
          Message_type =:= <<"0">> ->
          MessageType = <<"notification">>,
          MsgContent = Message_notification;
        true ->
          MessageType = Message_type,
          MsgContent = Message_type
        end,
        if MetaData =:= <<>> ->
            Metadata = <<"{}">>;
          MetaData =:= <<"">> ->
            Metadata = <<"{}">>;
        true ->
            Metadata = MetaData
        end,
      if(ChatType =:= <<"chat">>) ->
        if(MessageFrom =:= User) ->
          fly_mod_utils:update_deleted_recent_chat(Server,MessageTo,User,Message_id,From_notification,MsgContent,ChatType,Message_type,To_notification,Status, Recall_status,Created_at, MessageFrom,Topic_id,Metadata,Message_time);
        true ->
          fly_mod_utils:update_deleted_recent_chat(Server,MessageFrom,User,Message_id,From_notification,MsgContent,ChatType,Message_type,To_notification,Status, Recall_status,Created_at, MessageFrom,Topic_id,Metadata,Message_time)
        end;
      true ->
        fly_mod_utils:update_deleted_grouprecent_chat(Server,From_notification,MessageFrom,Message_id,From_notification,MsgContent,ChatType,MessageType,To_notification,Status, Recall_status,Created_at, User,Topic_id,Metadata,Message_time)
      end
    end,
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [#xmlel{name = <<"messageclear">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"message_ids">>, MessageIds}, {<<"type">>, RequestType},{<<"chat_type">>, UserType}, {<<"last_message_id">>, LastMessageId}, {<<"to_user">>, ToJID}],
          children = []},
            #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
                children = []}
          ]},
    ejabberd_router:route(From, To, XmlBody),
      case fly_mod_utils:get_mobile_user_message(User, Server) of
        true ->
          mod_offline:store_packet({From,  xmpp:decode(XmlBody)});
        false ->
          ok
        end,
    fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Delete Message successfully">>});
  true ->
    To = jid:make({User, Server, <<>>}),
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
      children = [#xmlel{name = <<"messageclear">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"message_ids">>, MessageIds}, {<<"type">>, RequestType},{<<"chat_type">>, UserType}],
        children = []}]},
    ejabberd_router:route(From, To, XmlBody),
    fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Delete Message successfully">>})
  end.

  api_recall(#jid{luser = User, lserver = Server, lresource = _Resource} = FromUser, SubEl, IQ) ->
  MsgId = fxml:get_path_s(SubEl, [{attr, <<"message_ids">>}]),
  Chat_Type = fxml:get_path_s(SubEl, [{attr, <<"chat_type">>}]),
  [ToJID | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),
  [FromJID | _FS] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"from_user">>}])), "@"),
  To = jid:make({list_to_binary(FromJID), Server, <<>>}),
  From = To,
  TUser = list_to_binary(ToJID),
  RequestType = <<"recall">>,
  if Chat_Type =:= <<"normal">> ->
    FromJid = jid:remove_resource(From),
    Status = <<"message_recalled">>,
  case catch fly_mod_utils:get_group_users(Server, TUser) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      fly_mix_group_chat:update_group_info_to_members(FromJid, To, Status,MsgId, JIDs, <<"8">>, SubEl),
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Recall status send successfully">>})
  end;
  true ->
    fly_mod_stanza_ack:send_ack_response(From, To, MsgId,  <<"recall">>),
    MessageId = p1_rand:get_string(),
    Timestamp = now_to_microseconds(erlang:now()),
    FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
    XmlBody = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
    children = [#xmlel{name = <<"recall">>, attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"id">>, MsgId}, {<<"chat_type">>, <<"chat">>}], children = []},
    #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}], children = []}]},
    ejabberd_router:route(From, To, XmlBody),
      case fly_mod_utils:get_mobile_user_message(list_to_binary(FromJID), Server) of
        true ->
        mod_offline:store_packet({From,  xmpp:decode(XmlBody)});
        false ->
          ok
      end,
      TResources = ejabberd_sm:get_user_resources(list_to_binary(FromJID), Server),
      if length(TResources) =:= 0 ->
        ok;
      true ->
        fly_mod_offline_push:send_offline_message({From,XmlBody})
      end,
      fly_mod_utils:update_recall(From, MsgId),
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Recall status send successfully">>})
end.

media_permission_revoke(Server, MessageId, User) ->

  case catch fly_mod_utils:get_chat_media_by_messageid(Server, MessageId) of
    {selected, _, []} ->
      ok;
    {selected, _, Result} ->
      lists:map(fun(G) ->
        [ToUsers] = G,
          ToUserList = binary_to_list(ToUsers),
          RemoveUser1 = <<User / binary, <<",">> / binary>>,
          RemoveUser2 = <<<<",">> / binary, User / binary>>,
          UsersList1 = re:replace(ToUserList,binary_to_list(RemoveUser1), ""),
          UsersList2 = re:replace(UsersList1,binary_to_list(RemoveUser2), ""),
          UsersList3 = re:replace(UsersList2,binary_to_list(User), ""),
          UpdatedToUserList = iolist_to_binary(UsersList3),
          fly_mod_utils:revoke_media_permission(Server, UpdatedToUserList, MessageId)
      end, Result)
  end.

get_bot_chat_messages( From, RequestType, SubEl, IQ) ->
  Position = fxml:get_path_s(SubEl, [{attr, <<"position">>}]),
  MsgsId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  [ToUser | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),

  case catch fly_mod_utils:get_bot_chat_messages(From, list_to_binary(ToUser), Position, MsgsId) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No  chats available">>});
    {selected, _, Result} ->

      SubEls1 = lists:map(fun(G) ->
        [_StatusId,MessageUser, MessageTag, Bot, Time, MsgId, Status, RecallStatus,FavouriteStatus,FavouriteBy] = G,
        UserElements = #xmlel{name = <<"user">>, attrs = [],
          children = [{xmlcdata, MessageUser}]},
        StatusElements = #xmlel{name = <<"status">>, attrs = [],
          children = [{xmlcdata, Status}]},
        BotElements = #xmlel{name = <<"bot">>, attrs = [],
          children = [{xmlcdata, Bot}]},
        TimeElements = #xmlel{name = <<"time">>, attrs = [],
          children = [{xmlcdata, Time}]},
        MsgidElement = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MsgId}]},
        RecallElement = #xmlel{name = <<"recallstatus">>, attrs = [],
          children = [{xmlcdata, RecallStatus}]},
        FavouriteElement = #xmlel{name = <<"favouritestatus ">>, attrs = [],
          children = [{xmlcdata, FavouriteStatus}]},
        FavouriteByElement = #xmlel{name = <<"favouriteby ">>, attrs = [],
          children = [{xmlcdata, FavouriteBy}]},
        BodyElement = #xmlel{name = <<"message">>, attrs = [],
          children = [{xmlcdata, MessageTag}]},

        #xmlel{name = <<"chat">>, attrs = [],
          children = [UserElements, StatusElements, BotElements,TimeElements, BodyElement, MsgidElement, RecallElement,FavouriteElement,FavouriteByElement]}
                          end,
        Result),
      GroupXml = [#xmlel{name = <<"history">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = GroupXml })

  end.
%% get recent users message from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
recent_chat( From, RequestType, SubEl, IQ) ->
  % Limit = fxml:get_path_s(SubEl, [{attr, <<"limit">>}]),
  #jid{luser = FUser, lserver = FServer} = From,
  case catch fly_mod_utils:get_recent_chat_web(From) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No recent chats available">>});
    {error,"query timed out"} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No recent chats available">>});
    {error,_} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No recent chats available">>});
    {selected, _, Result} ->
      SubEls1 = recent_message_stanza_result(Result,FServer),
      GroupXml = [#xmlel{name = <<"participants">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = GroupXml })

  end.

  recent_topic_chat( From, RequestType, SubEl, IQ) ->
    Limit = fxml:get_path_s(SubEl, [{attr, <<"limit">>}]),
    Topic_id = fxml:get_path_s(SubEl, [{attr, <<"topic_id">>}]),
    Topic_time = fxml:get_path_s(SubEl, [{attr, <<"topic_time">>}]),
    #jid{luser = FUser, lserver = FServer} = From,
    case catch fly_mod_utils:get_recent_chat_topic(From, Topic_time, Topic_id, Limit) of
      {selected, _, []} ->
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No recent chats available">>});
      {error,"query timed out"} ->
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No recent chats available">>});
      {error,_} ->
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No recent chats available">>});
      {selected, _, Result} ->
        ?LOG_INFO("topic result~p",[Result]),
        SubEls1 = recent_message_stanza_result(Result,FServer),
        GroupXml = [#xmlel{name = <<"participants">>, attrs = [], children = SubEls1}],
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = GroupXml })
    end.

  recent_message_stanza_result(Result,FServer) ->
      SubEls = lists:map(fun(G) ->
          [Id, MsgFrom, UserName, MsgId, UserPublisher, Body, Chattype, Message_type, MetaData, Notification_to, Status, RecallStatus, MessageTime, Time, Unread, MuteStatus, ArchiveStatus, UpdatedAt] = G,
        UserElement = #xmlel{name = <<"user">>, attrs = [],
            children = [{xmlcdata, UserName}]},
          Publisher = #xmlel{name = <<"publisher">>, attrs = [],
            children = [{xmlcdata, UserPublisher}]},
          StatusElement = #xmlel{name = <<"status">>, attrs = [],
            children = [{xmlcdata, Status}]},
          MessageTimeElement = #xmlel{name = <<"message_time">>, attrs = [],
            children = [{xmlcdata, MessageTime}]},
          TimeElement = #xmlel{name = <<"time">>, attrs = [],
            children = [{xmlcdata, Time}]},
          MsgidElement = #xmlel{name = <<"msgid">>, attrs = [],
            children = [{xmlcdata, MsgId}]},
          RowIdElement = #xmlel{name = <<"topic_id">>, attrs = [],
            children = [{xmlcdata, Id}]},
          MsgfromElement = #xmlel{name = <<"msgfrom">>, attrs = [],
            children = [{xmlcdata, MsgFrom}]},
          MessageTypeElements = #xmlel{name = <<"Message_type">>, attrs = [],
            children = [{xmlcdata, Message_type}]},
          ChattypeElement = #xmlel{name = <<"chattype">>, attrs = [],
            children = [{xmlcdata, Chattype}]},
          RecallElement = #xmlel{name = <<"recallstatus">>, attrs = [],
            children = [{xmlcdata, RecallStatus}]},
          BodyElement = #xmlel{name = <<"message">>, attrs = [],
            children = [{xmlcdata, Body}]},
          NotificationElement = #xmlel{name = <<"Notification_to">>, attrs = [],
            children = [{xmlcdata, Notification_to}]},
          UnreadElement = #xmlel{name = <<"unread">>, attrs = [],
            children = [{xmlcdata, Unread}]},
          MuteStatusElement = #xmlel{name = <<"mute_status">>, attrs = [],
            children = [{xmlcdata, MuteStatus}]},
          ArchiveStatusElement = #xmlel{name = <<"archive_status">>, attrs = [],
            children = [{xmlcdata, ArchiveStatus}]},
          MetaDataElement = #xmlel{name = <<"meta_data">>, attrs = [],
            children = [{xmlcdata, MetaData}]},
          UpdatedAtElement = #xmlel{name = <<"updated_at">>, attrs = [],
            children = [{xmlcdata, UpdatedAt}]},
          #xmlel{name = <<"chat">>, attrs = [],
            children = [RowIdElement, UserElement, Publisher, StatusElement, MessageTypeElements, MessageTimeElement, TimeElement, ChattypeElement, BodyElement, MsgidElement, MetaDataElement, MsgfromElement, RecallElement, NotificationElement, UnreadElement, MuteStatusElement, ArchiveStatusElement, UpdatedAtElement]}
                            end,
          Result).

  meta_chat( From, RequestType, SubEl, IQ) ->
    RowID = fxml:get_path_s(SubEl, [{attr, <<"row_id">>}]),
    Limit = fxml:get_path_s(SubEl, [{attr, <<"limit">>}]),
    MessageFrom = fxml:get_path_s(SubEl, [{attr, <<"message_from">>}]),
    FromJid = jid:from_string(MessageFrom),
    #jid{user = FUser, lserver = FServer} = FromJid,
    TopicId = fxml:get_path_s(SubEl, [{attr, <<"topic_ic">>}]),

    if TopicId =:= <<"">> ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No Meta chats available">>});
    true ->
    case catch fly_mod_utils:get_meta_chat_web(FromJid,TopicId,RowID,Limit) of
      {selected, _, []} ->
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No Meta chats available">>});
      {error,"query timed out"} ->
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No Meta chats available">>});
      {error,_} ->
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No Meta chats available">>});
      {selected, _, Result} ->
        SubEls1 = SubEls1 = meta_message_stanza_result(Result),
      GroupXml = [#xmlel{name = <<"history">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = GroupXml })
    end
  end.

get_server_time(_From,RequestType, IQ) ->
  Timestamp = (calendar:datetime_to_gregorian_seconds(erlang:universaltime()) - 62167219200) * 1000000,
  FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
  XMLTag = [#xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
    children = []}],
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = XMLTag }).

%% get recent users message from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
get_single_chat_messages( From, RequestType,  SubEl, IQ) ->
  Position = fxml:get_path_s(SubEl, [{attr, <<"position">>}]),
  RowID = fxml:get_path_s(SubEl, [{attr, <<"row_id">>}]),
  Limit = fxml:get_path_s(SubEl, [{attr, <<"limit">>}]),
  SendSeen = fxml:get_path_s(SubEl, [{attr, <<"send_seen">>}]),
  TopicId = fxml:get_path_s(SubEl, [{attr, <<"topic_id">>}]),

  [ToUser | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),
  MsgsId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),

  case catch fly_mod_utils:get_single_chat_messages(From, list_to_binary(ToUser), Position, MsgsId, Limit, RowID, SendSeen,TopicId) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No single chats available">>});
    {selected, _, Result} ->
      SubEls1 = message_stanza_result(Result),
      GroupXml = [#xmlel{name = <<"history">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,to_user = list_to_binary(ToUser),sub_els = GroupXml })

  end.


%% get recent users message from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
get_single_chat_media_messages( From, RequestType,  SubEl, IQ) ->
  Message_ID = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  Topicid = fxml:get_path_s(SubEl, [{attr, <<"topic_id">>}]),

  [ToUser | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),
  case catch fly_mod_utils:get_single_chat_media_messages(From, list_to_binary(ToUser), Message_ID,Topicid) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No Media, Links and Docs">>});
    {selected, _, Result} ->
      SubEls1 = lists:map(fun(G) ->
        [MessageTag, MessageId, EditMsgId,  MessageTime, TopicId, MetaData,MessageContentTag ] = G,
        MsgIdElement = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MessageId}]},
        EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
          children = [{xmlcdata, EditMsgId}]},
        if MessageTag =:= <<"">>->
        MessageElement = #xmlel{name = <<"message ">>, attrs = [],
          children = [{xmlcdata, MessageContentTag}]};
        true ->
        MessageElement = #xmlel{name = <<"message ">>, attrs = [],
          children = [{xmlcdata, MessageTag}]}
        end,
        TopicIdElement = #xmlel{name = <<"topic_id ">>, attrs = [],
          children = [{xmlcdata, TopicId}]},
        MetaDataElement = #xmlel{name = <<"meta_data ">>, attrs = [],
          children = [{xmlcdata, MetaData}]},
        MessageTimeElements = #xmlel{name = <<"message_time">>, attrs = [],
          children = [{xmlcdata, MessageTime}]},
        #xmlel{name = <<"chat">>, attrs = [],
          children = [MessageTimeElements, EMsgidElement, MsgIdElement, MessageElement, TopicIdElement, MetaDataElement]}
                          end,
        Result),
      GroupXml = [#xmlel{name = <<"mediamessages">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType,to_user = list_to_binary(ToUser),sub_els = GroupXml })
  end.

%% get group chat messages from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
get_group_chat_messages( From, RequestType, SubEl, IQ) ->
  Position = fxml:get_path_s(SubEl, [{attr, <<"position">>}]),
  RowID = fxml:get_path_s(SubEl, [{attr, <<"row_id">>}]),
  Limit = fxml:get_path_s(SubEl, [{attr, <<"limit">>}]),
  SendSeen = fxml:get_path_s(SubEl, [{attr, <<"send_seen">>}]),
  [ToUser | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),
  MsgsId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  case catch fly_mod_utils:get_group_chat_messages(From, list_to_binary(ToUser), Position, MsgsId, Limit, RowID, SendSeen) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No chats available">>});
    {selected, _, Result} ->
      SubEls1 = lists:map(fun(G) ->
        [RowId, MessageUser, MessageTag, Time, MsgId, EditMsgId, Status, FromUser, MsgType, RecallStatus, FavouriteStatus, FavouriteBy, ToNotification, MessageNotification, MessageTime, EditStatus, MetaData] = G,
        RowIdElement = #xmlel{name = <<"row_id">>, attrs = [],
          children = [{xmlcdata, RowId}]},
        UserElements = #xmlel{name = <<"user">>, attrs = [],
          children = [{xmlcdata, MessageUser}]},
        FromElements = #xmlel{name = <<"fromuser">>, attrs = [],
          children = [{xmlcdata, FromUser}]},
        StatusElements = #xmlel{name = <<"status">>, attrs = [],
          children = [{xmlcdata, Status}]},
        TimeElements = #xmlel{name = <<"time">>, attrs = [],
          children = [{xmlcdata, Time}]},
        MessageTimeElements = #xmlel{name = <<"message_time">>, attrs = [],
          children = [{xmlcdata, MessageTime}]},
        MsgidElement = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MsgId}]},
        EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
          children = [{xmlcdata, EditMsgId}]},
        MsgtypeElement = #xmlel{name = <<"msgtype">>, attrs = [],
          children = [{xmlcdata, MsgType}]},
        RecallElement = #xmlel{name = <<"recallstatus">>, attrs = [],
          children = [{xmlcdata, RecallStatus}]},
        FavouriteElement = #xmlel{name = <<"favouritestatus ">>, attrs = [],
          children = [{xmlcdata, FavouriteStatus}]},
        FavouriteByElement = #xmlel{name = <<"favouriteby ">>, attrs = [],
          children = [{xmlcdata, FavouriteBy}]},
        BodyElement = #xmlel{name = <<"body">>, attrs = [],
          children = [{xmlcdata, MessageTag}]},
        ToNotificationElement = #xmlel{name = <<"to_notification">>, attrs = [],
          children = [{xmlcdata, ToNotification}]},
        EditStatusElement = #xmlel{name = <<"edit_msg_status ">>, attrs = [],
          children = [{xmlcdata, EditStatus}]},
        MetaDataElement = #xmlel{name = <<"meta_data ">>, attrs = [],
          children = [{xmlcdata, MetaData}]},
        MsgNotificationElement = #xmlel{name = <<"message_notification">>, attrs = [],
          children = [{xmlcdata, MessageNotification}]},
        if (MsgType == <<"0">>) ->

          GStatusElements = #xmlel{name = <<"gstatus">>, attrs = [],
            children = [{xmlcdata, <<"0">>}]};
          true ->
            case catch fly_mod_utils:get_groupmessage_status(From, MsgId) of
              {selected, _, []} ->
                GStatus = <<"0">>;
              {selected, _, [[GroupStatus]]} ->
                GStatus = GroupStatus;
              _ ->
                GStatus = <<"0">>

            end,
            GStatusElements = #xmlel{name = <<"gstatus">>, attrs = [],
              children = [{xmlcdata, GStatus}]}
        end,
        #xmlel{name = <<"chat">>, attrs = [],
          children = [EditStatusElement, EMsgidElement, UserElements, MessageTimeElements,EditStatusElement, ToNotificationElement, MsgNotificationElement, FromElements, StatusElements, GStatusElements, TimeElements, BodyElement, MsgidElement, MsgtypeElement, MetaDataElement, RecallElement, FavouriteElement, FavouriteByElement, RowIdElement]}
                          end,
        Result),
      GroupXml = [#xmlel{name = <<"history">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,to_user = list_to_binary(ToUser),sub_els = GroupXml })
  end.

message_stanza_result(Result) ->
  SubEl = lists:map(fun(G) ->
    [RowId, MessageUser, Message_type, MessageTag, Time, MsgId, EditMsgId, Status, RecallStatus, FavouriteStatus, FavouriteBy, MessageTime, TopicId, EditStatus,  MetaData, MessageContentTag] = G,
    RowIdElement = #xmlel{name = <<"row_id">>, attrs = [],
      children = [{xmlcdata, RowId}]},
    UserElements = #xmlel{name = <<"user">>, attrs = [],
      children = [{xmlcdata, MessageUser}]},
    MessageTimeElements = #xmlel{name = <<"message_time">>, attrs = [],
      children = [{xmlcdata, MessageTime}]},
    StatusElements = #xmlel{name = <<"status">>, attrs = [],
      children = [{xmlcdata, Status}]},
    TimeElements = #xmlel{name = <<"time">>, attrs = [],
      children = [{xmlcdata, Time}]},
    MsgidElement = #xmlel{name = <<"msgid">>, attrs = [],
      children = [{xmlcdata, MsgId}]},
    EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
      children = [{xmlcdata, EditMsgId}]},
    RecallElement = #xmlel{name = <<"recallstatus">>, attrs = [],
      children = [{xmlcdata, RecallStatus}]},
    FavouriteElement = #xmlel{name = <<"favouritestatus ">>, attrs = [],
      children = [{xmlcdata, FavouriteStatus}]},
    FavouriteByElement = #xmlel{name = <<"favouriteby ">>, attrs = [],
      children = [{xmlcdata, FavouriteBy}]},
    MetaDataElement = #xmlel{name = <<"meta_data ">>, attrs = [],
      children = [{xmlcdata, MetaData}]},
    TopicIdElement = #xmlel{name = <<"topic_id ">>, attrs = [],
      children = [{xmlcdata, TopicId}]},
    EditStatusElement = #xmlel{name = <<"edit_msg_status ">>, attrs = [],
      children = [{xmlcdata, EditStatus}]},
    MessageTypeElements = #xmlel{name = <<"Message_type">>, attrs = [],
      children = [{xmlcdata, Message_type}]},
    if MessageTag =:= <<"">> ->
      MessageElement = #xmlel{name = <<"message ">>, attrs = [],
      children = [{xmlcdata, MessageContentTag}]};
    true ->
    MessageElement = #xmlel{name = <<"message ">>, attrs = [],
      children = [{xmlcdata, MessageTag}]}
    end,

    #xmlel{name = <<"chat">>, attrs = [],
      children = [MessageTimeElements, UserElements, EditStatusElement, EMsgidElement, MessageTypeElements, StatusElements,  TimeElements, MessageElement, MsgidElement, RecallElement, FavouriteElement, FavouriteByElement, TopicIdElement, MetaDataElement, RowIdElement]}
                      end,
    Result).

    meta_message_stanza_result(Result) ->
      SubEl = lists:map(fun(G) ->
        [RowId, MessageUser, MessageTo, Message_type, MessageTag, MsgId, EditMsgId, Status, RecallStatus, MessageTime, MetaData, MessageContentTag] = G,
        RowIdElement = #xmlel{name = <<"row_id">>, attrs = [],
          children = [{xmlcdata, RowId}]},
        UserElements = #xmlel{name = <<"user">>, attrs = [],
          children = [{xmlcdata, MessageUser}]},
        UserToElements = #xmlel{name = <<"to_user">>, attrs = [],
          children = [{xmlcdata, MessageTo}]},
        StatusElements = #xmlel{name = <<"status">>, attrs = [],
          children = [{xmlcdata, Status}]},
        TimeElements = #xmlel{name = <<"time">>, attrs = [],
          children = [{xmlcdata, MessageTime}]},
        MsgidElement = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MsgId}]},
        EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
          children = [{xmlcdata, EditMsgId}]},
        MessageTypeElements = #xmlel{name = <<"Message_type">>, attrs = [],
          children = [{xmlcdata, Message_type}]},
        RecallElement = #xmlel{name = <<"recallstatus">>, attrs = [],
          children = [{xmlcdata, RecallStatus}]},
        MetaDataElement = #xmlel{name = <<"meta_data ">>, attrs = [],
          children = [{xmlcdata, MetaData}]},
        if MessageTag =:= <<"">> ->
        MessageElement = #xmlel{name = <<"message ">>, attrs = [],
          children = [{xmlcdata, MessageContentTag}]};
        true ->
        MessageElement = #xmlel{name = <<"message ">>, attrs = [],
          children = [{xmlcdata, MessageTag}]}
        end,

        #xmlel{name = <<"chat">>, attrs = [],
          children = [UserElements, UserToElements, MessageTypeElements, StatusElements, EMsgidElement,  TimeElements, MessageElement, MsgidElement, RecallElement,MetaDataElement, RowIdElement]}
                          end,
        Result).
%% get group chat messages from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
get_group_chat_media_messages( From, RequestType,  SubEl, IQ) ->
  Message_ID = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  ToUser = binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])),
  [GroupId | _S] = string:tokens(ToUser, "@"),
  case catch fly_mod_utils:get_group_chat_media_messages(From, list_to_binary(ToUser), GroupId, Message_ID) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No Media, Links and Docs">>});
    {selected, _, Result} ->
      SubEls1 = lists:map(fun(G) ->
        [MessageTag, MsgId, EditMsgId, MessageTime, MessageContentTag] = G,
        if (MsgId == <<"0">>) ->
          BodyElement = #xmlel{name = <<"body">>, attrs = [],
            children = []};
          true ->
            if MessageTag =:= <<"">> ->
              BodyElement = #xmlel{name = <<"body">>, attrs = [],
              children = [{xmlcdata, MessageContentTag}]};
            true ->
            BodyElement = #xmlel{name = <<"body">>, attrs = [],
              children = [{xmlcdata, MessageTag}]}
            end
        end,
        MessageId = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MsgId}]},
        EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
          children = [{xmlcdata, EditMsgId}]},
        CurrentMsgIdElement = #xmlel{name = <<"msg_id">>, attrs = [],
          children = [{xmlcdata, Message_ID}]},
        MessageTimeElements = #xmlel{name = <<"message_time">>, attrs = [],
          children = [{xmlcdata, MessageTime}]},
        #xmlel{name = <<"groupchat">>, attrs = [],
          children = [MessageTimeElements,EMsgidElement, MessageId, BodyElement, CurrentMsgIdElement]}
                          end,
        Result),

      GroupXml = [#xmlel{name = <<"mediamessages">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, to_user = list_to_binary(ToUser), sub_els = GroupXml })
  end.
%% get group chat message status from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)

get_message_status(From, RequestType,  SubEl, IQ) ->
  #jid{ lserver = LServer} = From,
  MessageId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  case binary:split(MessageId, <<"-">>) of
    [_U, S] -> MsgId = S;
    _ ->
      MsgId = MessageId
  end,

  case catch fly_mod_utils:get_single_message(LServer, MsgId, MsgId) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Message Not Available">>});
    {selected, _, Result} ->
      SubEls1 = lists:map(fun(G) ->
        [MessageTag, MessageId, EditMsgId, MessageFrom, Chat_Type, DeletedBy, DeletedStatus, MsgStatus, From_Notification, To_Notification, To_User, Message_Time, Message_Notification, Recall_Status, Created_At, TopicId, EditStatus, Update_at, MetaData, MessageContentTag] = G,
        MsgIdElement = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MessageId}]},
        EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
          children = [{xmlcdata, EditMsgId}]},
        DeletedByElement = #xmlel{name = <<"deleted_by">>, attrs = [],
          children = [{xmlcdata, DeletedBy}]},
        DeletedStatusElement = #xmlel{name = <<"deleted_status">>, attrs = [],
          children = [{xmlcdata, DeletedStatus}]},
        ChatTypeElement = #xmlel{name = <<"chat_type">>, attrs = [],
          children = [{xmlcdata, Chat_Type}]},
        FromNotificationElement = #xmlel{name = <<"from_notification">>, attrs = [],
          children = [{xmlcdata, From_Notification}]},
        ReplyUserElement = #xmlel{name = <<"replyfromuser">>, attrs = [],
          children = [{xmlcdata, MessageFrom}]},
        if MessageTag =:= <<"">> ->
          Message = #xmlel{name = <<"body">>, attrs = [],
          children = [{xmlcdata, MessageContentTag}]};
            true ->
          Message = #xmlel{name = <<"body">>, attrs = [],
          children = [{xmlcdata, MessageTag}]}
        end,
        MessageStatus = #xmlel{name = <<"status">>, attrs = [],
          children = [{xmlcdata, MsgStatus}]},
        ToNotification = #xmlel{name = <<"to_notification">>, attrs = [],
          children = [{xmlcdata, To_Notification}]},
        ToUser = #xmlel{name = <<"to_user">>, attrs = [],
          children = [{xmlcdata, To_User}]},
        MessageTime = #xmlel{name = <<"message_time">>, attrs = [],
          children = [{xmlcdata, Message_Time}]},
        MessageNotification = #xmlel{name = <<"message_notification">>, attrs = [],
          children = [{xmlcdata, Message_Notification}]},
        MetaDataElement = #xmlel{name = <<"meta_data">>, attrs = [],
          children = [{xmlcdata, MetaData}]},
        TopicIdElement = #xmlel{name = <<"topic_id">>, attrs = [],
          children = [{xmlcdata, TopicId}]},
        EditStatusElement = #xmlel{name = <<"edit_msg_status ">>, attrs = [],
          children = [{xmlcdata, EditStatus}]},
        RecallStatus = #xmlel{name = <<"recallstatus">>, attrs = [],
          children = [{xmlcdata, Recall_Status}]},
        TimeElements = #xmlel{name = <<"time">>, attrs = [],
          children = [{xmlcdata, Update_at}]},
        CreatedAt = #xmlel{name = <<"created_at">>, attrs = [],
          children = [{xmlcdata, Created_At}]},

        #xmlel{name = <<"chat">>, attrs = [],
          children = [MsgIdElement, DeletedByElement, EditStatusElement, EditStatusElement, TimeElements, DeletedStatusElement, MetaDataElement, TopicIdElement, ChatTypeElement, ReplyUserElement, Message, MessageStatus, FromNotificationElement, ToNotification, ToUser, MessageTime, MessageNotification, RecallStatus, CreatedAt]}
                          end,
        Result),
        GroupXml = [#xmlel{name = <<"history">>, attrs = [], children = SubEls1}],
        fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType ,sub_els = GroupXml })
  end.

%% get group chat messages from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
get_group_chat_fullmedia_messages( From, RequestType,  SubEl, IQ) ->
  Message_ID = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  ToUser = binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])),
  Position = fxml:get_path_s(SubEl, [{attr, <<"position">>}]),
  [GroupId | _S] = string:tokens(ToUser, "@"),
  case catch fly_mod_utils:get_group_chat_fullmedia_messages(From, list_to_binary(ToUser), GroupId, Message_ID,Position) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No Media, Links and Docs">>});
    {selected, _, Result} ->
      SubEls1 = lists:map(fun(G) ->
        [MessageTag, MsgId, EditMsgId, MessageTime, MessageContentTag] = G,
        if (MsgId == <<"0">>) ->
          BodyElement = #xmlel{name = <<"body">>, attrs = [],
            children = []};
          true ->
            if MessageTag =:= <<"">> ->
              BodyElement = #xmlel{name = <<"body">>, attrs = [],
              children = [{xmlcdata, MessageContentTag}]};
              true->
            BodyElement = #xmlel{name = <<"body">>, attrs = [],
              children = [{xmlcdata, MessageTag}]}
            end
        end,
        MessageId = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MsgId}]},
        EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
          children = [{xmlcdata, EditMsgId}]},
        CurrentMsgIdElement = #xmlel{name = <<"msg_id">>, attrs = [],
          children = [{xmlcdata, Message_ID}]},
        MessageTimeElements = #xmlel{name = <<"message_time">>, attrs = [],
          children = [{xmlcdata, MessageTime}]},
        #xmlel{name = <<"groupchat">>, attrs = [],
          children = [MessageTimeElements, MessageId, EMsgidElement, BodyElement, CurrentMsgIdElement]}
                          end,
        Result),

      GroupXml = [#xmlel{name = <<"mediamessages">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, to_user = list_to_binary(ToUser), sub_els = GroupXml })
  end.

%% get recent users message from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
get_single_chat_fullmedia_messages( From, RequestType,  SubEl, IQ) ->
  Message_ID = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  Position = fxml:get_path_s(SubEl, [{attr, <<"position">>}]),
  [ToUser | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),
  case catch fly_mod_utils:get_single_chat_fullmedia_messages(From, list_to_binary(ToUser), Message_ID,Position) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"No Media, Links and Docs">>});
    {selected, _, Result} ->
      SubEls1 = lists:map(fun(G) ->
        [MessageTag, MessageId, EditMsgId, MessageTime, MessageContentTag] = G,
        MsgIdElement = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MessageId}]},
        CurrentMsgIdElement = #xmlel{name = <<"msg_id">>, attrs = [],
          children = [{xmlcdata, Message_ID}]},
        EMsgidElement = #xmlel{name = <<"editmsgid">>, attrs = [],
          children = [{xmlcdata, EditMsgId}]},
        if MessageTag =:= <<"">> ->
          MessageElement = #xmlel{name = <<"message ">>, attrs = [],
          children = [{xmlcdata, MessageContentTag}]};
        true->
        MessageElement = #xmlel{name = <<"message ">>, attrs = [],
          children = [{xmlcdata, MessageTag}]}
        end,
        MessageTimeElements = #xmlel{name = <<"message_time">>, attrs = [],
          children = [{xmlcdata, MessageTime}]},
        #xmlel{name = <<"chat">>, attrs = [],
          children = [MessageTimeElements, MsgIdElement, EMsgidElement, MessageElement, CurrentMsgIdElement]}
                          end,
        Result),
      GroupXml = [#xmlel{name = <<"mediamessages">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType,to_user = list_to_binary(ToUser),sub_els = GroupXml })
  end.

%% Hide the user last seen activities
%%
%%
%% @param record From
%% @param attributes

hide_lastseen(From,SubEl, IQ) ->
  Seenstatus = fxml:get_path_s(SubEl, [{attr, <<"mode">>}]),
  RequestType = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),
  #jid{luser = LUser, lserver = LServer} = From,
  fly_mod_utils:set_last_t(From, Seenstatus),
  if Seenstatus =:= <<"1">> ->
    JID = jid:make(LUser, LServer, <<>>),
    push_to_rosters(JID, #xmlel{name = <<"presence">>,
      attrs = [{<<"type">>, <<"unavailable">>}],
      children = []
    });
    true ->
    JID = jid:make(LUser, LServer, <<>>),
    push_to_rosters(JID, #xmlel{name = <<"presence">>,
      attrs = [{<<"type">>, <<"available">>}],
      children = []
    })
  end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Last seen hide successfully">>}).

update_admin_block_status(From, RequestType, SubEl, IQ) ->

  BlockStatus = fxml:get_path_s(SubEl, [{attr, <<"block_status">>}]),
  ToUserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  Type = fxml:get_path_s(SubEl, [{attr, <<"type">>}]),
  [ToUser | _Server] = string:tokens(binary_to_list(ToUserJid), "@"),
  ToJid = jid:from_string(ToUserJid),

  #jid{luser = _FUser, lserver = Server} = From,
  #jid{luser = TUser, lserver = TServer} = ToJid,
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  % fly_mod_utils:update_block_status_user(Server, ToJid, BlockStatus),
  if (Type =:= <<"chat">>)  or (Type =:= <<"user">>)->
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, ToUserJid}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
      children = [#xmlel{name = <<"admin_block">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"chat_type">>, Type}, {<<"type">>, <<"admin_block">>}, {<<"jid">>,ToUserJid}, {<<"block_status">>, BlockStatus}],
        children = []}]},
    ejabberd_router:route(From, ToJid, XmlBody),
    case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
        true ->
          mod_offline:store_packet({ToJid, xmpp:decode(XmlBody)}),
          fly_mod_offline_push:send_offline_message({TServer,xmpp:decode(XmlBody)});
        false ->
          ok
      end,

    push_to_rosters_and_recent_admin_block(ToJid, From,BlockStatus,ToUserJid);
  true ->
    % fly_mod_utils:update_block_status_group(Server, ToJid, BlockStatus),

    case catch fly_mod_utils:get_group_users(Server, ToUser) of
    {selected, _, []} ->
      ok;
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      lists:foreach(fun(GroupUser) ->
        RouteToJid = jid:make(GroupUser, Server, <<>>),
        XmlBody = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(RouteToJid)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
          children = [#xmlel{name = <<"admin_block">>,
            attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"chat_type">>, Type}, {<<"type">>, <<"admin_block">>}, {<<"jid">>,ToUserJid}, {<<"block_status">>, BlockStatus}],
            children = []}]},
        ejabberd_router:route(From, RouteToJid, XmlBody),
        % case get_user_resource_offline(GroupUser, Server) of
        % true ->
          mod_offline:store_packet({RouteToJid, xmpp:decode(XmlBody)})
        % false ->
        %   ok
      % end

      end, JIDs)
    end
  end,

  % casefly_mod_utils:get_mobile_user_message_message(ToUser, Server) of
  % true ->
  %   mod_offline:store_packet({From, xmpp:decode(XmlBody)});
  % false ->
  %     ok
  % end,

  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated successfully">>}).

send_contact_sync_status(_From, RequestType, SubEl, IQ) ->
  ToUserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  PermissionStatus = fxml:get_path_s(SubEl, [{attr, <<"permission_status">>}]),

  ToJid = jid:from_string(ToUserJid),
  #jid{luser = TUser, lserver = TServer} = ToJid,
  NewMessageId = fly_mod_utils:get_iq_message_id(20),

  lists:foreach(fun(R) ->
    XmlBody = #xmlel{name = <<"message">>,
      attrs = [{<<"to">>, ToUserJid}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
      children = [#xmlel{name = <<"contact_permission">>,
        attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"permission_status">>, PermissionStatus}, {<<"to_user">>,ToUserJid}],
        children = []}]},
    ejabberd_router:route(jid:make(TUser, TServer, <<>>), jid:make(TUser, TServer, R), XmlBody)
  end, ejabberd_sm:get_user_resources(TUser, TServer)),
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Updated successfully">>}).

send_deleted_user_status(_From, RequestType, SubEl, IQ) ->
  ToUserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  ToJid = jid:from_string(ToUserJid),
  #jid{luser = TUser, lserver = TServer} = ToJid,
  NewMessageId = fly_mod_utils:get_iq_message_id(20),

  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"to">>, ToUserJid}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"user_deleted">>,
      attrs = [{<<"xmlns">>, ?NS_USER_ACTIVITIES}, {<<"user">>,ToUserJid}],
      children = []}]},

  ejabberd_router:route(jid:make(TUser, TServer, <<>>), jid:make(TUser, TServer, <<>>), XmlBody),
  %%mod_offline:store_packet({ToJid, xmpp:decode(XmlBody)}),
  push_to_rosters_and_recent_user_deleted(ToJid, XmlBody),

  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"User Deleted Status Sent Successfully">>}).


%% Hide the user last seen activities
%%
%%
%% @param record From
%% @param attributes


set_web_password(From, SubEl, IQ) ->
  Password = fxml:get_path_s(SubEl, [{attr, <<"password">>}]),
  RequestType = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),
  case catch fly_mod_utils:set_web_password(From, Password) of
    {updated, 1} ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Web password updated successfully">>});
    _ERROR ->
      fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"Web password not updated">>})
  end.

set_user_validate(From, SubEl, IQ) ->
  RequestType = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),
  LicenseData = fxml:get_path_s(SubEl, [{attr, <<"license_data">>}]),

  #jid{luser = _FUser, lserver = FServer} = From,
  DecryptedData = fly_mod_utils:decrypt_license_data(FServer, LicenseData),
  IsActive = proplists:get_value(<<"isActive">>, DecryptedData),
  if IsActive =:= 0 ->
    ClientName = gen_mod:get_module_opt(FServer, fly_mod_user_activities, client_name),
    ets:insert(ClientName, {module, []}),
    ets:insert(ClientName, {expiry, 0});
  true ->
    fly_mod_utils:update_license_lookup(FServer)
  end,
  fly_mod_utils:generate_subel(IQ, #user_activities{type = RequestType, result_type = <<"License Key updated successfully">>}).

% -spec format_reason(state(), term()) -> binary().
format_reason(#{stop_reason := Reason}, _) ->
    xmpp_stream_in:format_error(Reason);
format_reason(_, normal) ->
    <<"unknown reason">>;
format_reason(_, shutdown) ->
    <<"stopped by supervisor">>;
format_reason(_, {shutdown, _}) ->
    <<"stopped by supervisor">>;
format_reason(_, _) ->
    <<"internal server error">>.

mod_opt_type(client_key) -> fun iolist_to_binary/1;
mod_opt_type(client_name) ->  econf:atom();
mod_opt_type(iqdisc) -> fun gen_iq_handler:check_type/1;
mod_opt_type(db_type) -> fun(T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(_) -> [db_type, iqdisc, client_key,client_name].

mod_options(_Host) ->
  [{client_key, undefined},{client_name, undefined}].
