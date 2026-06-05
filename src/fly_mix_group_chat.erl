%%%=================================================================
%%% File       : mod_mixgroupchat.erl
%%% Author     : Contus <venkatesh@contus.in>
%%% Purpose    : Manage add group, get group.
%%% Created At : 04. Jul 2016 3:29 PM
%%%=================================================================


-module(fly_mix_group_chat).

-behaviour(ejabberd_config).

-author('venkatesh@contus.in').

-protocol({xep, 12, '2.0'}).

-behaviour(gen_mod).


%% API
-export([route/1]).
-export([start/2, stop/1, depends/2, mod_options/1, mod_opt_type/1, process_set_group_info/5, update_group_info_to_members/8,
  process_local_iq/1, init/1, carboncall_message/4, update_group_status/7, map_status/1]).
-callback init(binary(), gen_mod:opts()) -> ok | {error, db_failure}.

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").
-include("translate.hrl").
-define(EJABBERD_DEBUG, true).
-define(NODES, [?NS_MIX_NODES_MESSAGES,
  ?NS_MIX_NODES_PRESENCE,
  ?NS_MIX_NODES_PARTICIPANTS,
  ?NS_MIX_NODES_CONFIG,?NS_MIX_CORE_0]).

init([Host|_]) ->

    process_flag(trap_exit, true),
    Opts = gen_mod:get_module_opts(Host, ?MODULE),
    MyHosts = gen_mod:get_opt_hosts(Opts),
    lists:foreach(
        fun(MyHost) ->
        ejabberd_router:register_route(
            MyHost, Host, {apply, ?MODULE, route}),
        gen_iq_handler:add_iq_handler(ejabberd_local, MyHost,
            ?NS_MIX_GROUP_CHAT, ?MODULE, process_local_iq),
        gen_iq_handler:add_iq_handler(ejabberd_sm, MyHost,
            ?NS_MIX_GROUP_CHAT, ?MODULE, process_local_iq)
        end, MyHosts),
    {ok, {}}.

start(ServerHost, Opts) ->
    gen_mod:start_child(?MODULE, ServerHost, Opts).

stop(Host) ->
  gen_iq_handler:remove_iq_handler(ejabberd_local, Host,
    ?NS_MIX_GROUP_CHAT),

  gen_iq_handler:remove_iq_handler(ejabberd_sm, Host,
    ?NS_MIX_GROUP_CHAT).

-spec route(stanza()) -> ok.
route(#iq{} = IQ) ->
    ejabberd_router:process_iq(IQ);

%% Contus Changed the type from groupchat to normal
route(#message{type = normal, id = ID, lang = Lang,
    to = #jid{luser = <<_, _ / binary>>}} = Msg) ->
    case ID of
  <<>> ->
  Txt = ?T("Attribute 'id' is mandatory for MIX messages"),
  Err = xmpp:err_bad_request(Txt, Lang),
  ejabberd_router:route_error(Msg, Err);
  _ ->
    mod_mix:process_mix_message(Msg)
  end;
route(Pkt) ->
    ?DEBUG("Dropping packet:~n~ts", [xmpp:pp(Pkt)]).

%% Handling the IQ

process_local_iq(#iq{from = From, to = To, type = Type} = IQ) ->
  SubEl = fxml:get_subtag_with_xmlns(xmpp:encode(IQ), <<"query">>, <<"jabber:iq:mixgroupchat">>),
  case Type of

    set ->

      process_iq_set(From, To, SubEl, xmpp:encode(IQ));

    get ->

      process_iq_get(From, To, SubEl, xmpp:encode(IQ))

  end.

%% Set method for the IQ

process_iq_set(From, To, SubEl, IQ) ->
  #jid{luser = _LUser} = From,
  RequestType = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),

  case RequestType of

    <<"create_group">> ->
      create_group(From, To, SubEl, IQ);
    <<"create_group_service">> ->
      create_group_service(From, To, SubEl, IQ);
    <<"update_profile_service">> ->
      update_profile_service(From, To, SubEl, IQ);
    <<"composing">> ->
      process_send_composing_status(From, To, SubEl, IQ);
    <<"gone">> ->
      process_send_gone_status(From, To, SubEl, IQ);
    <<"recall">> ->
      process_send_recall_status(From, To, SubEl, IQ);
    <<"add_participants">> ->
      process_add_participants(From, To, SubEl, IQ);
    <<"remove_participant">> ->
      process_remove_participant(From, To, SubEl, IQ);
    <<"set_group_info_web">> ->
      process_set_group_info_web(From, To, SubEl, IQ);
    <<"set_group_info">> ->
      process_set_group_info(From, To, SubEl, IQ,<<"update">>);
    <<"make_admin">> ->
      process_make_admin(From, To, SubEl, IQ);
    <<"remove_admin">> ->
      process_remove_admin(From, To, SubEl, IQ);
    <<"admin_remove_participant">> ->
      process_admin_remove_participant(From, To, SubEl, IQ);
    <<"admin_exit_group">> ->
      process_admin_exit_group(From, To, SubEl, IQ);
    <<"admin_remove_admin">> ->
      process_admin_remove_admin(From, To, SubEl, IQ);
    <<"user_exit_group">> ->
      process_user_exit_group(From, To, SubEl, IQ, RequestType);
    <<"user_exit_group_api">> ->
      process_user_exit_group(From, To, SubEl, IQ, RequestType);
    <<"push_to_talk">> ->
      process_push_to_talk(From, To, SubEl, IQ);
    <<"user_delete_group">> ->
      process_user_delete_group(From, To, SubEl, IQ);
    <<"add_participants_service">> ->
      add_participants_service(From, To, SubEl, IQ);
    <<"remove_participant_service">> ->
      remove_participant_service(From, To, SubEl, IQ);
    <<"make_admin_service">> ->
      make_admin_service(From, To, SubEl, IQ);
    <<"delete_group_service">> ->
      user_delete_group_service(From, To, SubEl, IQ);
    <<"channel_status_update">> ->
      channel_status_update(From, To, SubEl, IQ);
    no_such_subtag ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});
    empty_value ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = <<"empty_value">>, result_type = <<"unknown request">>});
    _Status ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _Status, result_type = <<"unknown request">>})
  end.

%%%===================================================================================================================================
%%
%% Function : create_group/4
%% Params   : From, To, SubEl, IQ
%% Purpose  : End to End group creation - Creates group channel, adds owner, add particiapants and set group info.
%% IQStanza :
%%   <iq id='kl2fax27' to='mix.host' type='set'><query xmlns='jabber:iq:mixgroupchat' status="create_group" group_id="groupId">
%%   <participants><participant>user_jid@host</participant></participants><nick>GroupName</nick><profile ><vCard xmlns='vcard-temp'>
%%   <nickName>GroupName</nickName></vCard></profile></query></iq>
%%
%%%=====================================================================================================================================
create_group(From, To, SubEl, IQ) ->

  #jid{lserver = TServer} = To,
  #jid{user = FUser, lserver = FServer} = From,
  RequestType = <<"create_group">>,
  MessageId = <<(get_string()) / binary>>,
  MessageId1 = <<(get_string()) / binary>>,
  Channel = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  Participants = fxml:get_subtag(SubEl, <<"participants">>),
  GroupJID = jid:make(Channel, TServer),
  Profile = fxml:get_subtag(SubEl, <<"profile">>),
  VCard = fxml:get_subtag(Profile, <<"vCard">>),
  NickName = fxml:get_subtag(VCard, <<"nickName">>),
  GroupName = fxml:get_tag_cdata(NickName),
  CustAtr = fxml:get_subtag_with_xmlns(xmpp:encode(SubEl), <<"custom_attributes">>, <<"ocp:json">>),
  if  CustAtr =:= false ->
    CustomAttributes = "";
  true ->
    CustomAttributes = fxml:get_tag_cdata(CustAtr)
  end,
  % Creates Group
  AccessUri = generate_group_access_uri(GroupName),
  CreateIQ = #iq{
    type = set, 
    from = From, 
    to = To, 
    id = MessageId,
    sub_els = [
      #mix_create{channel = Channel, xmlns = <<"urn:xmpp:mix:core:0">>},
      #xmlel{name = <<"accessUri">>, attrs = [], children = [{xmlcdata, AccessUri}]}
    ]
  },
  mod_mix:process_mix_core(CreateIQ),

  % Adds Owner
  mod_mix_pam:process_iq(#iq{from = From, to = From, type = set,id = MessageId1,
        sub_els = [#mix_client_join{channel = GroupJID, xmlns = <<"urn:xmpp:mix:pam:0">>,affiliation = <<"o">>,
        join = #mix_join{nick = GroupName, message_id = MessageId1, group_create = <<"y">>, custom_attributes = #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}, xmlns = <<"urn:xmpp:mix:core:0">>, subscribe = [<<"urn:xmpp:mix:nodes:messages">>,<<"urn:xmpp:mix:nodes:presence">>,
          <<"urn:xmpp:mix:nodes:participants">>,<<"urn:xmpp:mix:nodes:subject">>,<<"urn:xmpp:mix:nodes:config">>]}}]}),
  process_set_group_info(From, GroupJID, SubEl, IQ, <<"new">>),

  fly_mod_offline_push:groupcreationfunction(From, groupcreation, Participants, Channel, GroupJID, SubEl, IQ, MessageId1,CustomAttributes),
 
  fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, group_id = Channel, result_type = <<"Group Created successfully">>}).

generate_group_access_uri(GroupName) when is_binary(GroupName) ->
    Slug = generate_slug(GroupName),
    Token = random_token(),
    <<Slug/binary, "-", Token/binary>>.

generate_slug(Str) when is_binary(Str) ->
    Lower = string:lowercase(Str),
    Step1 = re:replace(Lower, <<"[^a-z0-9\\s-]">>, <<>>, [global, {return, binary}]),
    Step2 = re:replace(Step1, <<"\\s+">>, <<"-">>, [global, {return, binary}]),
    Step3 = re:replace(Step2, <<"-+">>, <<"-">>, [global, {return, binary}]),
    re:replace(Step3, <<"^-|-$">>, <<>>, [global, {return, binary}]);

generate_slug(_) ->
    <<>>.

random_token() ->
    Int = crypto:strong_rand_bytes(9),
    Num = binary:decode_unsigned(Int),
    Base36 = string:lowercase(integer_to_list(Num, 36)),
    list_to_binary(lists:sublist(Base36, 7)).


create_group_service(From, To, SubEl, IQ) ->
  #jid{lserver = TServer} = To,
  Host = To#jid.lserver,
  #jid{ lserver = FServer} = From,
  ServerHost = ejabberd_router:host_of_route(Host),
  Channel = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  Adminuser = fxml:get_path_s(SubEl, [{attr, <<"admin_user">>}]),
  AdminUser = fly_mod_utils:get_user_from_string_jid(Adminuser),
  MsgId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  Profile = fxml:get_subtag(SubEl, <<"profile">>),
  VCard = fxml:get_subtag(Profile, <<"vCard">>),
  GroupName = fxml:get_subtag(VCard, <<"nickName">>),
  NickName = fxml:get_tag_cdata(GroupName),
  GroupJid = jid:make(Channel, TServer),
  RequestType = <<"create_group">>,
  fly_mod_utils:update_vcard_date(FServer, Channel),
  RouteToJid = jid:make(AdminUser, FServer),
  mod_mix:notify_participant_joined_api(ServerHost, GroupJid, RouteToJid, [NickName, Adminuser, RouteToJid, [AdminUser] ],MsgId),
  fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Notify to group members successfully">>}).

update_profile_service(From, To, SubEl, IQ) ->
  #jid{lserver = TServer} = To,
  Host = To#jid.lserver,
  #jid{ lserver = FServer} = From,
  _ServerHost = ejabberd_router:host_of_route(Host),
  Channel = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  AdminUser = fxml:get_path_s(SubEl, [{attr, <<"admin_user">>}]),
  Profile = fxml:get_subtag(SubEl, <<"profile">>),
  VCard = fxml:get_subtag(Profile, <<"vCard">>),
  GroupJid = jid:make(Channel, TServer, <<>>),
  ActionDoneBy = list_to_binary(binary_to_list(AdminUser) ++ "@" ++ binary_to_list(FServer)),
  _RequestType = <<"set_group_info">>,
  fly_mod_utils:update_vcard_date(FServer, Channel),
  case catch fly_mod_utils:get_group_users(FServer, Channel) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      case catch fly_mod_utils:get_group_profile_type(FServer,Channel) of
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
                                      ChannelStatus = map_status(GChannelStatus),
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
      lists:foreach(fun(ToJid) ->
        RouteToJid = jid:make(ToJid, FServer, <<>>),
        MessageId = <<(get_string()) / binary>>,
        Timestamp = now_to_microseconds(erlang:now()),
        FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
        Packet = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(GroupJid)},  {<<"id">>,MessageId}, {<<"type">>, <<"normal">>}, {<<"to">>, jid:to_string(RouteToJid)}],
          children = [#xmlel{name = <<"event">>, attrs = [{<<"xmlns">>, "http://jabber.org/protocol/pubsub#event"}],
          children = [#xmlel{name = <<"info">>, attrs = [{<<"status">>, <<"group_profile_updated">>}, {<<"groupstatus">>,  Status},{<<"description">>,  Description},{<<"history">>,  History }, {<<"messagemode">>,  MessageMode},{<<"accessmode">>,  AccessMode }, {<<"channel_status">>,  ChannelStatus },{<<"invite_uri">>,  InviteUri }, {<<"customfeatures">>,  CustomFeatures},{<<"done_by">>, ActionDoneBy}], children = [VCard]}]},
          #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, ""}]}, #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}]}]},
        ejabberd_router:route(GroupJid, RouteToJid, Packet),
        carboncall_message(ToJid, FServer,Packet,GroupJid),
        case fly_mod_utils:get_mobile_user_message(ToJid, FServer) of
          true ->
          mod_offline:store_packet({RouteToJid,xmpp:decode(Packet)});
          false ->
            ok
        end  end, JIDs),
        fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Notify profile update to group members successfully">>})
  end.

user_delete_group_service(From, To, SubEl, IQ) ->
  #jid{lserver = TServer} = To,
  Host = To#jid.lserver,
  #jid{ lserver = FServer} = From,
  _ServerHost = ejabberd_router:host_of_route(Host),
  Channel = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  GroupJid = jid:make(Channel, TServer),
  _RequestType = <<"user_delete_group">>,
  fly_mod_utils:update_vcard_date(FServer, Channel),
  case catch fly_mod_utils:get_group_users(FServer, Channel) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      lists:foreach(fun(Touser) ->
        ToUser = jid:make(Touser, FServer),
        MessageId = <<(get_string()) / binary>>,
        XmlBody = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(GroupJid)}, {<<"to">>, jid:to_string(ToUser)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
          children = [
            #xmlel{name = <<"groupdeleteservice">>,attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"group_id">>, Channel},  {<<"type">>, _RequestType}], children = []},
            #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, ""}]}
          ]},
        ejabberd_router:route(GroupJid, ToUser, XmlBody),
        carboncall_message(Touser, FServer,XmlBody,GroupJid),
        case fly_mod_utils:get_mobile_user_message(Touser, FServer) of
          true ->
            mod_offline:store_packet({ToUser,xmpp:decode(XmlBody)});
          false ->
            ok
        end
        end, JIDs),
        fly_mod_utils:delete_group(FServer, Channel),
        fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Notify to group members successfully">>})
  end.

channel_status_update(From, To, SubEl, IQ) ->
  #jid{lserver = TServer} = To,
  Host = To#jid.lserver,
  #jid{ lserver = FServer} = From,
  _ServerHost = ejabberd_router:host_of_route(Host),
  Channel = fxml:get_path_s(SubEl, [{attr, <<"channel_id">>}]),
  Action = fxml:get_path_s(SubEl, [{attr, <<"action">>}]),
  GroupJid = jid:make(Channel, TServer),
  RequestType = <<"channel_status_update">>,
  case catch fly_mod_utils:get_group_users(FServer, Channel) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      lists:foreach(fun(Touser) ->
        ToUser = jid:make(Touser, FServer),
        MessageId = <<(get_string()) / binary>>,
        XmlBody = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(GroupJid)}, {<<"to">>, jid:to_string(ToUser)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
          children = [
            #xmlel{name = <<"channel_status">>,attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"channel_id">>, Channel}, {<<"action">>, Action}, {<<"type">>, RequestType}], children = []},
            #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, ""}]}
          ]},
        ejabberd_router:route(GroupJid, ToUser, XmlBody),
        carboncall_message(Touser, FServer,XmlBody,GroupJid),
        case fly_mod_utils:get_mobile_user_message(Touser, FServer) of
          true ->
            mod_offline:store_packet({ToUser,xmpp:decode(XmlBody)});
          false ->
            ok
        end
        end, JIDs),
        fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Notify to group members successfully">>})
  end.

make_admin_service(From, To, SubEl, IQ) ->
  RequestType = <<"make_admin">>,
  Participants = fxml:get_subtag(SubEl, <<"participants">>),
  #jid{lserver = TServer} = To,
  Host = To#jid.lserver,
  #jid{ lserver = FServer} = From,
  _ServerHost = ejabberd_router:host_of_route(Host),
  Channel = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  AdminUser = fxml:get_path_s(SubEl, [{attr, <<"admin_user">>}]),
  GroupJid = jid:make(Channel, TServer, <<>>),
  fly_mod_utils:update_vcard_date(FServer, Channel),
  ActionDoneBy = list_to_binary(binary_to_list(AdminUser) ++ "@" ++ binary_to_list(FServer)),
  case catch fly_mod_utils:get_group_users(FServer, Channel) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      lists:foreach(
    fun(Participant) ->
      ParticipantData = fxml:get_tag_cdata(Participant),

      lists:foreach(fun(ToJid) ->
        RouteToJid = jid:make(ToJid, FServer, <<>>),
        MessageId = <<(get_string()) / binary>>,
        Timestamp = now_to_microseconds(erlang:now()),
        FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
        Packet = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(GroupJid)}, {<<"type">>, <<"normal">>}, {<<"id">>,MessageId}, {<<"to">>, jid:to_string(RouteToJid)}],
          children = [
            #xmlel{name = <<"event">>, attrs = [{<<"xmlns">>, "http://jabber.org/protocol/pubsub#event"}],children = [#xmlel{name = <<"info">>, attrs = [{<<"status">>, <<"new_admin_added">>}, {<<"done_by">>, ActionDoneBy}, {<<"new_admin">>, ParticipantData}]}]},
            #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, ""}]},
            #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
                children = []}
          ]},
        ejabberd_router:route(GroupJid, RouteToJid, Packet),
        carboncall_message(ToJid, FServer,Packet,GroupJid),
        case fly_mod_utils:get_mobile_user_message(ToJid, FServer) of
          true ->
            mod_offline:store_packet({RouteToJid,xmpp:decode(Packet)});
          false ->
            ok
        end  end, JIDs)
    end, Participants#xmlel.children),
fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Notify add member to group members successfully">>})
  end.

add_participants_service(From, To, SubEl, IQ) ->
  RequestType = <<"add_participants">>,
  Participants = fxml:get_subtag(SubEl, <<"participants">>),
  #jid{lserver = TServer} = To,
  Host = To#jid.lserver,
  #jid{ lserver = FServer} = From,
  ServerHost = ejabberd_router:host_of_route(Host),
  Channel = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  AdminUser = fxml:get_path_s(SubEl, [{attr, <<"admin_user">>}]),
  Profile = fxml:get_subtag(SubEl, <<"profile">>),
  VCard = fxml:get_subtag(Profile, <<"vCard">>),
  GroupName = fxml:get_subtag(VCard, <<"nickName">>),
  NickName = fxml:get_tag_cdata(GroupName),
  fly_mod_utils:update_vcard_date(FServer, Channel),
  % mod_vcard:set_vcard(Channel, FServer, VCard),
  GroupJid = jid:make(Channel, TServer, <<>>),
  case catch fly_mod_utils:get_group_users(FServer, Channel) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      lists:foreach(
    fun(Participant) ->
      ParticipantData = fxml:get_tag_cdata(Participant),
      MsgId = case fxml:get_tag_attr(<<"message_id">>, Participant) of
                    {value, Msgid} ->
                      Msgid;
                    _ ->
                      Msgid = <<(get_string()) / binary>>
                  end,
      ConvertUserstring = fly_mod_utils:get_user_from_string_jid(ParticipantData),
      FromJID = jid:make(ConvertUserstring,FServer),
      mod_mix:notify_participant_joined_api(ServerHost, GroupJid, FromJID, [NickName, AdminUser, FromJID,JIDs ],MsgId)
    end, Participants#xmlel.children),
fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Notify add member to group members successfully">>})

  end.

  remove_participant_service(From, To, SubEl, IQ) ->
    RequestType = <<"remove_participant">>,
    Participants = fxml:get_subtag(SubEl, <<"participants">>),
    #jid{lserver = TServer} = To,
    Host = To#jid.lserver,
    #jid{ lserver = FServer} = From,
    ServerHost = ejabberd_router:host_of_route(Host),
    Channel = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
    AdminUserF = fxml:get_path_s(SubEl, [{attr, <<"admin_user">>}]),
    AdminUser = jid:make(fly_mod_utils:get_user_from_string_jid(AdminUserF),FServer),
    GroupJid = jid:make(Channel, TServer, <<>>),
    fly_mod_utils:update_vcard_date(FServer, Channel),
    case catch fly_mod_utils:get_group_users(FServer, Channel) of
      {selected, _, []} ->
        fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group Does Not exists">>});
      {selected, _, GroupMembers} ->
        JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
        lists:foreach(
      fun(Participant) ->
        ParticipantData = fxml:get_tag_cdata(Participant),
        ConvertUserstring = fly_mod_utils:get_user_from_string_jid(ParticipantData),
        FromJID = jid:make(ConvertUserstring,FServer,<<"">>),
        % mod_mix_sql:del_participant_message(ServerHost,Channel,FromJID),
        mod_mix:notify_participant_left_api(ServerHost, GroupJid, AdminUser, FromJID, FromJID, [ConvertUserstring]),
            lists:foreach(fun(ToJid) ->
              RouteToJid = jid:make(ToJid, FServer, <<>>),
              mod_mix:notify_participant_left_api(ServerHost, GroupJid, AdminUser, FromJID, RouteToJid, JIDs)
              end, JIDs)
      end, Participants#xmlel.children),
  fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Notify remove members to group members successfully">>})
    end.

%%%============================================================================================
%%
%% Function : process_send_composing_status/3
%% Params   : From, To, IQ
%% Purpose  : Send composing state to all group members
%% IQStanza :
%%   <iq to="hellomix@mix.localhost" type="set"> <query status="composing" xmlns="jabber:iq:mixgroupchat">
%%</query></iq>
%%
%%%============================================================================================
process_send_composing_status(From, To, SubEl, IQ) ->

  _RequestType = <<"composing">>,

  #jid{user = TUser, lserver = TServer} = To,

  #jid{lserver = FServer} = From,

  GroupId = << TUser / binary, <<"@">> / binary, TServer / binary >>,

  FromJid = jid:remove_resource(From),
  case catch fly_mod_utils:get_group_users(FServer, TUser) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      update_group_info_to_members(FromJid, To, _RequestType, GroupId, JIDs, "", SubEl, <<"">>)
  end,
  fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Composing status send successfully">>}).

%%%============================================================================================
%%
%% Function : process_send_gone_status/3
%% Params   : From, To, IQ
%% Purpose  : Send gone state to all group members
%% IQStanza :
%%   <iq to="hellomix@mix.localhost" type="set"> <query status="gone" xmlns="jabber:iq:mixgroupchat">
%%</query></iq>
%%
%%%============================================================================================

process_send_gone_status(From, To, SubEl, IQ) ->

  _RequestType = <<"gone">>,
  #jid{user = TUser, lserver = TServer} = To,
  #jid{ lserver = FServer} = From,
  GroupId = << TUser / binary, <<"@">> / binary, TServer / binary >>,
  FromJid = jid:remove_resource(From),
  case catch fly_mod_utils:get_group_users(FServer, TUser) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      update_group_info_to_members(FromJid, To, _RequestType, GroupId, JIDs, "", SubEl, <<"">>)
  end,
fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Gone status send successfully">>}).

%%%============================================================================================
%%
%% Function : process_send_recall_status/3
%% Params   : From, To, IQ
%% Purpose  : Send recall messsage to all group members
%% IQStanza :
%%   <iq to="hellomix@mix.localhost" type="set"> <query status="recall" msgid="messageid" xmlns="jabber:iq:mixgroupchat">
%%</query></iq>
%%
%%%============================================================================================

process_send_recall_status(From, To, SubEl, IQ) ->
  _RequestType = <<"recall">>,
  Status = <<"message_recalled">>,
  MsgId = fxml:get_path_s(SubEl, [{attr, <<"msgid">>}]),
  #jid{user = TUser} = To,
  #jid{lserver = FServer} = From,
  FromJid = jid:remove_resource(From),
  case catch fly_mod_utils:get_group_users(FServer, TUser) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      update_group_info_to_members(FromJid, To, Status,MsgId, JIDs, <<"8">>, SubEl, <<"">>)
  end,
  fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Recall status send successfully">>}).

%%%============================================================================================
%%
%% Function : process_add_participants/3
%% Params   : From, To, IQ
%% Purpose  : Add the participants from the Mobile to the particular Group
%% IQStanza :
%%   <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="add_participants" xmlns="jabber:iq:mixgroupchat">
%%  <subscriptions><subscribe node='urn:xmpp:mix:nodes:messages'></subscribe>
%%  <subscribe node='urn:xmpp:mix:nodes:presence'></subscribe>
%%  <subscribe node='urn:xmpp:mix:nodes:participants'></subscribe>
%%  <subscribe node='urn:xmpp:mix:nodes:subject'></subscribe>
%%  <subscribe node='urn:xmpp:mix:nodes:config'></subscribe></subscriptions>
%%  <participants><participant>919790355379@localhost</participant><participant>919677209509@localhost</participant></participants></query>
%%  </iq>
%%
%%%============================================================================================

process_add_participants(From, To, SubEl, IQ) ->
  RequestType = <<"add_participants">>,
  Subscriptions = fxml:get_subtag(SubEl, <<"subscriptions">>),
  CustAtr = fxml:get_subtag_with_xmlns(xmpp:encode(SubEl), <<"custom_attributes">>, <<"ocp:json">>),
  if  CustAtr =:= false ->
    CustomAttributes = "";
  true ->
    CustomAttributes = fxml:get_tag_cdata(CustAtr)
  end,
  lists:flatmap(
    fun(#xmlel{name = <<"subscribe">>, attrs = Attrs}) ->
      Node = fxml:get_attr_s(<<"node">>, Attrs),
      case lists:member(Node, ?NODES) of
        true -> [Node];
        false -> []
      end;
      (_) ->
        []
    end, Subscriptions#xmlel.children),
  Participants = fxml:get_subtag(SubEl, <<"participants">>),
  #jid{user = TUser} = To,
  #jid{lserver = FServer} = From,
  Nick = fxml:get_subtag(SubEl, <<"nick">>),
  if
    Nick =/= false  ->
      GroupNameElement = fxml:get_subtag(SubEl, <<"nick">>),
      GroupName = fxml:get_tag_cdata(GroupNameElement);
    true ->
      case fly_mod_utils:get_nickname(FServer, TUser) of
        {selected, [{GN}]} -> GroupName = GN;
        _ -> GroupName = TUser
      end
  end,
  lists:foreach(
    fun(Participant) ->
      ParticipantData = fxml:get_tag_cdata(Participant),
      FromJID = jid:make(fly_mod_utils:get_user_from_string_jid(ParticipantData),FServer,<<"">>),
      #jid{user = PUser, lserver = PServer} = FromJID,
      case catch fly_mod_utils:check_user_exists(PServer, PUser) of
      {selected, _, []} ->
        ok;
      {selected, _, _UserExist} ->
      MessageId = <<(get_string()) / binary>>,
      case catch fly_mod_utils:get_participants(FServer, TUser, fly_mod_utils:get_user_from_string_jid(ParticipantData)) of
        {selected, _, []} ->
          mod_mix_pam:process_iq(#iq{from = FromJID,to = FromJID,type = set,id = MessageId,
          sub_els = [#mix_client_join{channel = To,xmlns = <<"urn:xmpp:mix:pam:0">>,affiliation = <<"n">>,
          join = #mix_join{owner = jid:to_string(From), message_id = MessageId ,nick = GroupName, group_create = <<"n">>, custom_attributes = #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}, xmlns = <<"urn:xmpp:mix:core:0">>, subscribe = [<<"urn:xmpp:mix:nodes:messages">>,<<"urn:xmpp:mix:nodes:presence">>,
          <<"urn:xmpp:mix:nodes:participants">>,<<"urn:xmpp:mix:nodes:info">>,<<"urn:xmpp:mix:nodes:config">>]}}]}),
          fly_mod_utils:group_notify_message(From, FromJID, PUser, TUser, <<"2">>, RequestType, MessageId,<<"">>,<<"">>),
          update_group_status(From, To, SubEl, IQ, <<"2">>, Participant, MessageId);
        {selected, _, _GroupMembers} ->
          ok;
        {_, _} ->
          ok
      end
      end
    end, Participants#xmlel.children),
  fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Participants added successfully">>}).

%%%============================================================================================
%%
%% Function : process_remove_participant/3
%% Params   : From, To, IQ
%% Purpose  : Remove the participants from the particular Group.
%% IQStanza :
%%          <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="remove_participant" xmlns="jabber:iq:mixgroupchat">
%%          <participant>919790355379@localhost</participant></query>
%%          </iq>
%%
%%%============================================================================================

process_remove_participant(From, To, SubEl, IQ) ->

  _RequestType = <<"remove_participant">>,
  #jid{user = TUser, lserver = TServer} = To,
  #jid{ lserver = FServer} = From,
  Participant = fxml:get_subtag(SubEl, <<"participant">>),
  ParticipantFullJid = fxml:get_tag_cdata(Participant),
  ParticipantJid = fly_mod_utils:get_user_from_string_jid(ParticipantFullJid),
  FromJID = jid:make(ParticipantJid,TServer,<<"">>),
  GroupJID = jid:make(TUser,FServer,<<"">>),
  MessageId = <<(get_string()) / binary>>,
  Status = <<"new_admin_added">>,
  Jid = fly_mod_utils:make_admin_ifadminexit(TServer, ParticipantJid, TUser),
    if Jid =:= ok ->
        Adminuser = <<"">>;
      true ->
        Adminuser = Jid,
        case catch fly_mod_utils:get_group_users(TServer, TUser) of
          {selected, _, []} ->
          ok;
          {selected, _, GroupMembers} ->
            JIDs = lists:flatmap(fun([UJid]) -> [UJid] end, GroupMembers),
            update_group_info_to_members(From, To, Status, Jid, JIDs, <<"5">>, SubEl, <<"">>)
        end
  end,
    case catch fly_mod_utils:get_participants(TServer, TUser, ParticipantJid) of
      {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Member not removed in group">>});
      {selected, _, _GroupMembers} ->
      mod_mix_pam:process_iq(#iq{from = FromJID,to = GroupJID,type = set,id = MessageId,
      sub_els = [#mix_leave{admin_user = Adminuser, from_jid = From, xmlns = <<"urn:xmpp:mix:core:0">>}]}),
      update_group_status(From, To, SubEl, IQ, <<"3">>, Participant, MessageId),
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Exited from the group successfully">>});
      {_, _} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Member not removed in group">>})
      end.

%%%============================================================================================
%%
%% Function : process_set_group_info/3
%% Params   : From, To, IQ
%% Purpose  : Set the profile information.
%% IQStanza :
%%          <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="set_group_info" xmlns="jabber:iq:mixgroupchat">
%%            <profile><vCard xmlns='vcard-temp'>
%%            <NICKNAME>Dpv Mani</NICKNAME>
%%            <STATUS>Done my First Module!!!!!</STATUS>
%%            <PHOTO> <TYPE>image/jpeg</TYPE> <EXTVAL>http://www.example.com/image.jpg</EXTVAL></PHOTO>
%%            </vCard></profile></query>
%%          </iq>
%%
%%%============================================================================================

process_set_group_info(From, To, SubEl, IQ, NewStatus) ->
  _RequestType = <<"set_group_info">>,
  Profile = fxml:get_subtag(SubEl, <<"profile">>),
  VCard = fxml:get_subtag(Profile, <<"vCard">>),
  #jid{user = LUser} = To,
  #jid{lserver = FServer} = From,
  Status = <<"group_profile_updated">>,
  ?INFO_MSG("process_set_group_info -> NewStatus: ~p, From: ~p, To: ~p", [NewStatus, From, To]),
  ?INFO_MSG("VCard : ~p", [VCard]), 
  
  IncomingNickName = fxml:get_path_s(VCard, [{elem, <<"nickName">>}, cdata]),
  ?INFO_MSG("IncomingNickName : ~p", [IncomingNickName]),

  IncomingDescription = fxml:get_path_s(VCard, [{elem, <<"description">>}, cdata]),
  ?INFO_MSG("IncomingDescription : ~p", [IncomingDescription]),
  
  IncomingImage = fxml:get_path_s(VCard, [{elem, <<"image">>}, cdata]),
  ?INFO_MSG("IncomingImage : ~p", [IncomingImage]),

  IncomingMsgDisappear = fxml:get_path_s(VCard, [{elem, <<"msgDisappear">>}, cdata]),
  ?INFO_MSG("IncomingMsgDisappear : ~p", [IncomingMsgDisappear]),

  
  if NewStatus =:= <<"new">> ->
    mod_vcard:set_vcard(LUser, FServer, VCard),
    ok;
  true ->
    case catch fly_mod_utils:get_group_users(FServer, LUser) of
      {selected, _, []} ->
        ?INFO_MSG("Group does not exist or has no members for ~p", [LUser]),
        fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group does not exists">>});
      {selected, _, GroupMembers} ->
        ?INFO_MSG("GroupMembers found: ~p", [GroupMembers]),
        
        GroupInfo = fly_mod_utils:get_existing_group_info(FServer, LUser),
        ?INFO_MSG("Existing GroupInfo fetch result: ~p", [GroupInfo]),

        case GroupInfo of
          {selected, _, [[Nickname, Description, Image, OldMsgDisappear]]} ->
            ?INFO_MSG("Existing Group Info - Nickname: ~p, Description: ~p, Image: ~p, MsgDisappear: ~p", [Nickname, Description, Image, OldMsgDisappear]);
          _ ->
            ?LOG_INFO("No existing group info found for ~p", [LUser])
        end,
        
        JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
        SetVcard = mod_vcard:set_vcard(LUser, FServer, VCard),
        ?INFO_MSG("SetVcard result for ~p: ~p", [LUser, SetVcard]),
        MixParticipant = fly_mod_utils:update_mix_participant(FServer, LUser, IncomingNickName),
        ?LOG_INFO("MixParticipant update result: ~p", [MixParticipant]),

        case SetVcard of
          ok ->
            case catch fly_mod_utils:check_group_exists(FServer, LUser) of
              {selected, _, []} ->
                ?INFO_MSG("Group existence check failed during update for ~p", [LUser]),
                update_group_info_to_members(From, To, Status, VCard, JIDs, <<"1">>, SubEl, <<"">>);

              _ ->
                ?INFO_MSG("devinprogress -> FServer : ~p LUser : ~p", [FServer, LUser]),

                case catch GroupInfo of
                    {selected, _, [[OldNick, OldDesc, OldImage, OldMsgDisp]]} ->
                        % Track changes
                        Changes = [],
                        
                        % First handle nickname changes (since it always has a value)
                        NewChanges = case {OldNick, IncomingNickName} of
                            {OldNick, NewNick} when OldNick =:= NewNick ->
                                ?INFO_MSG("Nickname unchanged for group ~p: ~p", [LUser, NewNick]),
                                Changes;
                            {OldNick, NewNick} ->
                                ?INFO_MSG("Nickname updated for group ~p from ~p to ~p", [LUser, OldNick, NewNick]),
                                [nickname | Changes]
                        end,

                        % Then handle description changes - two cases: first add or update
                        NewChanges2 = case {OldDesc, IncomingDescription} of
                            {<<>>, <<>>} ->
                                NewChanges;
                            {<<>>, NewDesc} when NewDesc =/= <<>> ->
                                ?INFO_MSG("First description added for group ~p: ~p", [LUser, NewDesc]),
                                [description | NewChanges];
                            {OldDesc, NewDesc} when OldDesc =:= NewDesc ->
                                NewChanges;
                            {OldDesc, NewDesc} when OldDesc =/= <<>> andalso NewDesc =/= OldDesc ->
                                ?INFO_MSG("Description updated for group ~p from ~p to ~p", [LUser, OldDesc, NewDesc]),
                                [description | NewChanges];
                            _ ->
                                NewChanges
                        end,

                        % Finally handle image changes - similar to description: first add or update
                        ThirdChanges = case {OldImage, IncomingImage} of
                            {<<>>, <<>>} ->
                                NewChanges2;
                            {<<>>, NewImage} when NewImage =/= <<>> ->
                                ?INFO_MSG("First image added for group ~p", [LUser]),
                                [image | NewChanges2];
                            {OldImage, NewImage} when OldImage =:= NewImage ->
                                NewChanges2;
                            {OldImage, NewImage} when OldImage =/= <<>> andalso NewImage =/= OldImage ->
                                ?INFO_MSG("Image updated for group ~p", [LUser]),
                                [image | NewChanges2];
                            _ ->
                                NewChanges2
                        end,

                         % Handle msg_disappear changes
                        FinalChanges = case {OldMsgDisp, IncomingMsgDisappear} of
                            {OldMsgDisp, NewMsgDis} when OldMsgDisp =:= NewMsgDis ->
                                ThirdChanges;
                            {OldMsgDisp, NewMsgDis} ->
                                ?INFO_MSG("MsgDisappear updated for group ~p from ~p to ~p", [LUser, OldMsgDisp, NewMsgDis]),
                                [msg_disappear | ThirdChanges]
                        end,

                        % Then handle the notifications based on what changed
                        case length(FinalChanges) of
                            0 -> 
                                update_group_info_to_members(From, To, Status, VCard, JIDs, <<"4">>, SubEl, <<"">>);
                            1 -> % Single field changed - use specific notification codes
                                [Change] = FinalChanges,
                                case Change of
                                    nickname -> 
                                        update_group_info_to_members(From, To, Status, VCard, JIDs, <<"9">>, SubEl, <<"">>);
                                    description -> % notify id 10
                                        case OldDesc of
                                            <<>> ->
                                                NewNotifyStr = <<"added the group description \"", IncomingDescription/binary, "\"." >>,
                                                update_group_info_to_members(From, To, Status, VCard, JIDs, <<"10">>, SubEl, NewNotifyStr);
                                            _ ->
                                                UpdateNotifyStr = <<"updated the group description from \"", OldDesc/binary,"\" to \"", IncomingDescription/binary, "\"." >>,
                                                update_group_info_to_members(From, To, Status, VCard, JIDs, <<"10">>, SubEl, UpdateNotifyStr)
                                        end;
                                    image ->
                                        case OldImage of
                                            <<>> -> % First time adding image
                                                ?INFO_MSG("Image updated update_group_info_to_members 12 ~p", [OldImage]),
                                                update_group_info_to_members(From, To, Status, VCard, JIDs, <<"12">>, SubEl, <<"">>);
                                            _ -> % Updating existing image
                                                ?INFO_MSG("Image updated update_group_info_to_members 13 ~p", [OldImage]),
                                                update_group_info_to_members(From, To, Status, VCard, JIDs, <<"13">>, SubEl, <<"">>)
                                        end;
                                    msg_disappear ->
                                        NotifyId = if
                                            IncomingMsgDisappear =:= <<"0">> -> <<"23">>; % OFF
                                            OldMsgDisp =:= <<"0">> orelse OldMsgDisp =:= <<>> -> <<"21">>; % SET
                                            true -> <<"22">> % UPDATED
                                        end,
                                        update_group_info_to_members(From, To, Status, VCard, JIDs, NotifyId, SubEl, <<"">>);
                                     _  ->
                                      update_group_info_to_members(From, To, Status, VCard, JIDs, <<"4">>, SubEl, <<"">>)

                                end;
                            _ -> % Multiple fields changed - use generic update code
                                update_group_info_to_members(From, To, Status, VCard, JIDs, <<"4">>, SubEl, <<"">>)
                        end;

                    Error ->
                        ?ERROR_MSG("Error fetching group info for group ~p: ~p", [LUser, Error]),
                        update_group_info_to_members(From, To, Status, VCard, JIDs, <<"4">>, SubEl, <<"">>)
                end
            end,
            fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group info updated successfully">>});
          _ ->
            fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group info not updated">>})
        end
    end
end.

process_set_group_info_web(From, To, SubEl, IQ) ->

  _RequestType = <<"set_group_info_web">>,
  Profile = fxml:get_subtag(SubEl, <<"profile">>),
  VCard = fxml:get_subtag(Profile, <<"vCard">>),
  #jid{user = LUser} = To,
  #jid{lserver = FServer} = From,
  Status = <<"group_profile_updated">>,
  case catch fly_mod_utils:get_group_users(FServer, LUser) of
    {selected, _, []} ->
      mod_vcard:set_vcard(LUser, FServer, VCard),
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group does not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      case mod_vcard:set_vcard(LUser, FServer, VCard) of
        ok ->
          case catch fly_mod_utils:check_group_exists(FServer, LUser) of
            {selected, _, []} ->
              Notification = <<"1">>,
              update_group_info_to_members(From, To, Status, VCard, JIDs, Notification, SubEl, <<"">>);
            _ ->
              Notification = <<"4">>,
              update_group_info_to_members(From, To, Status, VCard, JIDs, Notification, SubEl, <<"">>)
          end,
          fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group info updated successfully">>});
        _ ->
          fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Group info not updated">>})
      end
  end.

%%%============================================================================================
%%
%% Function : process_make_admin/3
%% Params   : From, To, IQ
%% Purpose  : To remove participant from group by admin
%% IQStanza :
%%         <iq  to="hellomix@mix.localhost" id="919884275559" type="set"><query status="make_admin" xmlns="jabber:iq:mixgroupchat">
%%              <participant to="hellomix@mix.localhost">9487306387@localhost</participant></query>
%%         </iq>
%%
%%%============================================================================================
process_make_admin(From, To, SubEl, IQ) ->

  RequestType = <<"make_admin">>,
  Status = <<"new_admin_added">>,
  #jid{luser = _User, lserver = Server} = From,
  Participant = fxml:get_subtag(SubEl, <<"participant">>),
  ParticipantData = fxml:get_tag_cdata(Participant),
  #jid{user = TUser} = To,
  case catch fly_mod_utils:get_participants_update(Server, TUser, fly_mod_utils:get_user_from_string_jid(ParticipantData)) of
    {updated, 1} ->
      case catch fly_mod_utils:get_group_users(Server, TUser) of
        {selected, _, []} ->
        fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group does not exists">>});
        {selected, _, GroupMembers} ->
          JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
          update_group_info_to_members(From, To, Status, fly_mod_utils:get_user_from_string_jid(ParticipantData), JIDs, <<"5">>, SubEl, <<"">>),
          fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Admin updated successfully">>})
      end;
    {updated, 0} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Admin info not updated">>});
    {_, _} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Not a update query">>})
      end.

process_remove_admin(From, To, SubEl, IQ) ->

RequestType = <<"remove_admin">>,
#jid{luser = User, lserver = Server} = From,
Participant = fxml:get_subtag(SubEl, <<"participant">>),
ParticipantData = fxml:get_tag_cdata(Participant),
#jid{user = TUser} = To,
case catch fly_mod_utils:admin_user(Server, TUser, User) of
      {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"You are not a Admin">>});
      {selected, _, AdminMembers} ->

      Jid = fly_mod_utils:get_admin_update(Server, TUser, fly_mod_utils:get_user_from_string_jid(ParticipantData)),

      if Jid =:= ok ->
        case catch fly_mod_utils:get_group_users(Server, TUser) of
          {selected, _, []} ->
          ok;
          {selected, _, GroupMembers} ->
            JIDs = lists:flatmap(fun([UJid]) -> [UJid] end, GroupMembers),
            update_group_info_to_members(From, To, RequestType, fly_mod_utils:get_user_from_string_jid(ParticipantData), JIDs, <<"6">>, SubEl, <<"">>)
        end;
          true ->
            case catch fly_mod_utils:get_group_users(Server, TUser) of
              {selected, _, []} ->
              ok;
              {selected, _, GroupMembers} ->
                JIDs = lists:flatmap(fun([UJid]) -> [UJid] end, GroupMembers),
                Status = <<"new_admin_added">>,
                update_group_info_to_members(From, To, Status, Jid, JIDs, <<"5">>, SubEl, <<"">>),
                update_group_info_to_members(From, To, RequestType, fly_mod_utils:get_user_from_string_jid(ParticipantData), JIDs, <<"6">>, SubEl, <<"">>)
            end
      end,
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Admin removed successfully">>})
    end.
%%%============================================================================================
%%
%% Function : process_admin_remove_participant/3
%% Params   : From, To, IQ
%% Purpose  : To remove participant from group by admin
%% IQStanza :
%%         <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="admin_remove_participant" xmlns="jabber:iq:mixgroupchat">
%%              <participant>9751649808@localhost</participant></query>
%%         </iq>
%%
%%%============================================================================================

process_admin_remove_participant(From, To, SubEl, IQ) ->

  _RequestType = <<"admin_remove_participant">>,
  Participant = fxml:get_subtag(SubEl, <<"participant">>),
  ?INFO_MSG("process_admin_remove_participant Participant ~p",[Participant]),
  #jid{luser = _User, lserver = FServer} = From,
  ParticipantData = fxml:get_tag_cdata(Participant),
  MacroNameSpace = ?NS_MIX_GROUP_CHAT,
  #jid{user = TUser, lserver = _TServer} = To,
  MacroNameSpace = ?NS_MIX_GROUP_CHAT,
  FromJID = jid:make(fly_mod_utils:get_user_from_string_jid(ParticipantData),FServer,<<"">>),
  MessageId = <<(get_string()) / binary>>,
  ?INFO_MSG("process_admin_remove_participant FromJID ~p",[FromJID]),
  ?INFO_MSG("process_admin_remove_participant TUser ~p",[TUser]),
  ?INFO_MSG("process_admin_remove_participant ParticipantData ~p",[ParticipantData]),
  ?INFO_MSG("process_admin_remove_participant get_user_from_string_jid ~p",[fly_mod_utils:get_user_from_string_jid(ParticipantData)]),
  case catch fly_mod_utils:get_participants(FServer, TUser, fly_mod_utils:get_user_from_string_jid(ParticipantData)) of
      {selected, _, []} ->
      ?INFO_MSG("process_admin_remove_participant participant not found ~p",[TUser]),
      case catch fly_mod_utils:get_group_users(FServer, TUser) of                                                                                 
        {selected, _, GroupMembers} ->                                                                                                            
          JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),                                                                            
          mod_mix:notify_participant_left_api(FServer, To, From, FromJID, FromJID, JIDs);                                                         
        _ -> ok
      end,
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Participant not removed in group">>});
    {selected, _, _GroupMembers} ->
      ?INFO_MSG("process_admin_remove_participant FromJID ~p",[FromJID]),
      mod_mix:process_mix_core(#iq{from = FromJID , to = To, type = set ,id = MessageId,
      sub_els = [#mix_leave{from_jid = From, xmlns = <<"urn:xmpp:mix:core:0">>}]}),
      #jid{user = PUser} = FromJID,
      fly_mod_utils:update_group_removed_user(FServer, PUser, TUser),
      update_group_status(From, To, SubEl, IQ, <<"3">>, Participant, MessageId),
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Participant removed successfully">>});
      {_, _} ->
        ?INFO_MSG("process_admin_remove_participant final block ~p",[TUser]),
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, result_type = <<"Participant not removed in group">>})
      end.
%%%============================================================================================
%%
%% Function : process_admin_exit_group/3
%% Params   : From, To, IQ
%% Purpose  : To remove participant from group by admin
%% IQStanza :
%%         <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="admin_remove_participant" xmlns="jabber:iq:mixgroupchat">
%%              <participant>9751649808@localhost</participant></query>
%%         </iq>
%%
%%%============================================================================================

process_admin_exit_group(From, To, SubEl, IQ) ->

  _RequestType = <<"admin_exit_group">>,

  Participant = fxml:get_subtag(SubEl, <<"participant">>),

  #jid{luser = _User, lserver = Server} = From,

  ParticipantData = fxml:get_tag_cdata(Participant),

  ParticipantJid = jid:make(fly_mod_utils:get_user_from_string_jid(ParticipantData),Server,<<"">>),

  #jid{user = TUser} = To,
  #jid{user = PUser} = ParticipantJid,
  MessageId = <<(get_string()) / binary>>,
  Status = <<"new_admin_added">>,
  Jid = fly_mod_utils:make_admin_ifadminexit(Server, PUser, TUser),

  if Jid =:= ok ->
        Adminuser = <<"">>;
      true ->
        Adminuser = Jid,
        case catch fly_mod_utils:get_group_users(Server, TUser) of
          {selected, _, []} ->
          ok;
          {selected, _, GroupMembers} ->
            JIDs = lists:flatmap(fun([UJid]) -> [UJid] end, GroupMembers),
            update_group_info_to_members(From, To, Status, Jid, JIDs, <<"5">>, SubEl, <<"">>)

        end
  end,

      case catch fly_mod_utils:get_participants(Server, TUser, fly_mod_utils:get_user_from_string_jid(ParticipantData)) of

    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, removeduser = ParticipantData, admin_user = Adminuser, group_id = TUser, result_type = <<"Participant  not removed in group">>});
    {selected, _, _GroupMembers} ->
      mod_mix:process_mix_core(#iq{from = ParticipantJid , to = To,  type = set ,id = MessageId,
    sub_els = [#mix_leave{admin_user = Adminuser, from_jid = From, xmlns = <<"urn:xmpp:mix:core:0">>}]}),
      update_group_status(From, To, SubEl, IQ, <<"3">>, Participant, MessageId),
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, removeduser = ParticipantData, admin_user = Adminuser, group_id = TUser, result_type = <<"Exited from the group successfully">>});
      {_, _} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, removeduser = ParticipantData, admin_user = Adminuser, group_id = TUser, result_type = <<"Participant  not removed in group">>})
      end.

%%%============================================================================================
%%
%% Function : process_admin_remove_admin/3
%% Params   : From, To, IQ
%% Purpose  : To remove participant from group by admin
%% IQStanza :
%%         <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="admin_remove_admin" xmlns="jabber:iq:mixgroupchat">
%%              <participant>9751649808@localhost</participant></query>
%%         </iq>
%%
%%%============================================================================================

process_admin_remove_admin(From, To, SubEl, IQ) ->

  _RequestType = <<"admin_remove_admin">>,

  Participant = fxml:get_subtag(SubEl, <<"participant">>),

  #jid{luser = _User, lserver = Server} = From,

  ParticipantData = fxml:get_tag_cdata(Participant),
  ParticipantUser = fly_mod_utils:get_user_from_string_jid(ParticipantData),
  ParticipantJid = jid:make(ParticipantUser,Server,<<"">>),
  #jid{user = TUser} = To,
  #jid{user = PUser} = ParticipantJid,
  MessageId = <<(get_string()) / binary>>,
  case catch fly_mod_utils:get_participants(Server, TUser, fly_mod_utils:get_user_from_string_jid(ParticipantData)) of

    {selected, _, []} ->
    fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, group_id = TUser, result_type = <<"Participant  not removed in group">>});
    {selected, _, _GroupMembers} ->
    mod_mix:process_mix_core(#iq{from = ParticipantJid , to = To, type = set ,id = MessageId,
    sub_els = [#mix_leave{from_jid = From, xmlns = <<"urn:xmpp:mix:core:0">>}]}),
      Status = <<"new_admin_added">>,
      Jid = fly_mod_utils:make_admin_ifadminexit(Server,PUser, TUser),

  if Jid =:= ok ->
        Adminuser = <<"">>;
      true ->
        Adminuser = Jid,
        case catch fly_mod_utils:get_group_users(Server, TUser) of
          {selected, _, []} ->
          ok;
          {selected, _, GroupMembers} ->
            JIDs = lists:flatmap(fun([UJid]) -> [UJid] end, GroupMembers),
            update_group_info_to_members(From, To, Status, Jid, JIDs, <<"5">>, SubEl, <<"">>)

        end
  end,
      update_group_status(From, To, SubEl, IQ, <<"3">>, Participant, MessageId),
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType,  group_id = TUser, result_type = <<"Participant removed successfully">>});
      {_, _} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = _RequestType, group_id = TUser, result_type = <<"Participant  not removed in group">>})
      end.

%%%============================================================================================
%%
%% Function : process_user_exit_group/4
%% Params   : From, To, IQ
%% Purpose  : To remove participant from group by admin
%% IQStanza :
%%         <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="user_exit_group" xmlns="jabber:iq:mixgroupchat">
%%              <participant>9751649808@localhost</participant></query>
%%         </iq>
%%
%%%============================================================================================

process_user_exit_group(From, To, SubEl, IQ, RequestFrom) ->
  _RequestType = <<"user_exit_group">>,
  ?INFO_MSG("process_user_exit_group RequestFrom ~p",[RequestFrom]),
  Participant = fxml:get_subtag(SubEl, <<"participant">>),
  ?INFO_MSG("process_user_exit_group Participant ~p",[Participant]),
  ParticipantData = fxml:get_tag_cdata(Participant),
  ?INFO_MSG("process_user_exit_group ParticipantData ~p",[ParticipantData]),
  #jid{luser = SUser, lserver = Server, lresource = Resource} = From,
  ParticipantJid = jid:make(fly_mod_utils:get_user_from_string_jid(ParticipantData),Server,<<>>),
  ?INFO_MSG("process_user_exit_group ParticipantJid ~p",[ParticipantJid]),
  #jid{user = PUser} = ParticipantJid,
  ?INFO_MSG("process_user_exit_group PUser ~p",[PUser]),
  MobileResource = string:str(binary_to_list(Resource), binary_to_list(<<"Mobile-">>)),
  ?INFO_MSG("process_user_exit_group MobileResource ~p",[MobileResource]),
  WebResource = string:str(binary_to_list(Resource), binary_to_list(<<"Web-">>)),
  ?INFO_MSG("process_user_exit_group WebResource ~p",[WebResource]),

  if MobileResource =:= 0 andalso WebResource =:= 0 ->
    FromUser = ParticipantJid;
  true ->
    if SUser =:= PUser ->
      FromUser = ParticipantJid;
    true ->
      FromUser = From
    end
  end,
  ?INFO_MSG("process_user_exit_group FromUser ~p",[FromUser]),
  ?INFO_MSG("process_user_exit_group SUser ~p",[SUser]),
  ?INFO_MSG("process_user_exit_group PUser ~p",[PUser]),
  ?INFO_MSG("process_user_exit_group From ~p",[From]),

  #jid{user = TUser} = To,
  ?INFO_MSG("process_user_exit_group To ~p",[To]),
  if RequestFrom =:= <<"user_exit_group_api">> ->
    FUser = PUser;
  true ->
    FUser = SUser
    end,
  ?INFO_MSG("process_user_exit_group RequestFrom ~p",[RequestFrom]),
  ?INFO_MSG("process_user_exit_group FUser ~p",[FUser]),
  MessageId = <<(get_string()) / binary>>,
  case catch fly_mod_utils:get_participants(Server, TUser, fly_mod_utils:get_user_from_string_jid(ParticipantData)) of
      {selected, _, []} ->
      Status = <<"user_exit_group">>,
      fly_mod_utils:generate_subel(IQ, #group_query{type = Status, removeduser = ParticipantData,  group_id = TUser, result_type = <<"Participant  not removed in group">>});
    {selected, _, _GroupMembers} ->
      Jid = fly_mod_utils:make_admin_ifadminexit(Server,PUser, TUser),
      ?INFO_MSG("process_user_exit_group Jid ~p",[Jid]),
      if Jid =:= ok ->
            if FUser =:= PUser ->
              Status = <<"user_exit_group">>;
              true ->
              Status = <<"admin_remove_participant">>
              end,
            Adminuser = <<"">>;
      true ->
            Adminuser = Jid,
            case catch fly_mod_utils:get_group_users(Server, TUser) of
              {selected, _, []} ->
              Status = <<"user_exit_group">>,
              ok;
              {selected, _, GroupMembers} ->
                JIDs = lists:flatmap(fun([UJid]) -> [UJid] end, GroupMembers),
                AdminStatus = <<"new_admin_added">>,
                if FUser =:= PUser ->
                  Status = <<"user_exit_group">>;
                true ->
                  Status = <<"admin_exit_group">>
                end,
                ?INFO_MSG("process_user_exit_group Status ~p",[Status]),
                ?INFO_MSG("process_user_exit_group AdminStatus ~p",[AdminStatus]),
                ?INFO_MSG("process_user_exit_group JIDs ~p",[JIDs]),
                ?INFO_MSG("process_user_exit_group Jid ~p",[Jid]),
                ?INFO_MSG("process_user_exit_group SubEl ~p",[SubEl]),
                update_group_info_to_members(FromUser, To, AdminStatus, Jid, JIDs, <<"5">>, SubEl, <<"">>)
            end
      end,
    mod_mix:process_mix_core(#iq{from = ParticipantJid ,  to = To, type = set ,id = MessageId,
    sub_els = [#mix_leave{admin_user = Adminuser, from_jid = FromUser, xmlns = <<"urn:xmpp:mix:core:0">>}]}),
            update_group_status(FromUser, To, SubEl, IQ, <<"3">>, Participant, MessageId),
      fly_mod_utils:generate_subel(IQ, #group_query{type = Status, removeduser = ParticipantData,  group_id = TUser, result_type = <<"Participant removed successfully">>});
    {_, _} ->
      Status = <<"user_exit_group">>,
      fly_mod_utils:generate_subel(IQ, #group_query{type = Status, removeduser = ParticipantData, group_id = TUser, result_type = <<"Participant  not removed in group">>})
      end.
%%%============================================================================================
%%
%% Function : process_push_to_talk/3
%% Params   : From, To, IQ
%% Purpose  : group user push to talk
%% IQStanza :
%%         <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="push_to_talk" xmlns="jabber:iq:mixgroupchat">
%%         </query>
%%         </iq>
%%
%%%============================================================================================

process_push_to_talk(From, To, SubEl, IQ) ->

  _RequestType = <<"push_to_talk">>,
  PttStatus = fxml:get_path_s(SubEl, [{attr, <<"ptt_status">>}]),
  #jid{ lserver = FServer} = From,
  #jid{user = TUser} = To,
  case catch fly_mod_utils:get_group_users(FServer, TUser) of
    {selected, _, []} ->
      ok;
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      MessageId = <<(get_string()) / binary>>,
      lists:foreach(fun(GroupUser) ->
        RouteToJid = jid:make(GroupUser, FServer, <<>>),
        XmlBody = #xmlel{name = <<"message">>,
        attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(RouteToJid)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
        children = [#xmlel{name = <<"ptt">>,attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"group_id">>, jid:to_string(To)},  {<<"id">>, MessageId}, {<<"ptt_status">>, PttStatus}],
          children = []}]},
        Timestamp = now_to_microseconds(erlang:now()),
              FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
              XMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
                children = []},
              TimeStampedPacket = fxml:append_subtags(XmlBody, [XMLTag]),

      fly_mod_offline_push:send_offline_message(From, RouteToJid, TimeStampedPacket),
      ejabberd_router:route(From, RouteToJid, TimeStampedPacket)
                    end, JIDs)
  end,

    if PttStatus =:= <<"login">> ->
        fly_mod_utils:generate_subel(IQ, #group_query{type = PttStatus, result_type = <<"ptt login successful">>});
      PttStatus =:= <<"logout">> ->
        fly_mod_utils:generate_subel(IQ, #group_query{type = PttStatus, result_type = <<"ptt logout successful">>});
      PttStatus =:= <<"start">> ->
        fly_mod_utils:generate_subel(IQ, #group_query{type = PttStatus, result_type = <<"ptt started successful">>});
      PttStatus =:= <<"stop">> ->
        fly_mod_utils:generate_subel(IQ, #group_query{type = PttStatus, result_type = <<"ptt stopped successful">>})
    end.

%%%============================================================================================
%%
%% Function : process_user_delete_group/3
%% Params   : From, To, IQ
%% Purpose  : user delete the group
%% IQStanza :
%%         <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="user_delete_group" xmlns="jabber:iq:mixgroupchat">
%%              </query>
%%         </iq>
%%
%%%============================================================================================


process_user_delete_group(From, To, SubEl, IQ) ->
  RequestType = <<"user_delete_group">>,
  #jid{luser = FUser, lserver = Server, lresource = Resource} = From,
  #jid{user = TUser} = To,
  RemovedUser = fxml:get_path_s(SubEl, [{attr, <<"removeduser">>}]),
  if RemovedUser =:= <<>> ->
    User = FUser,
    ToUser = jid:make(User, Server, <<>>);
    true ->
    ParticipantJid = jid:make(fly_mod_utils:get_user_from_string_jid(RemovedUser),Server,<<"">>),
    #jid{user = PUser} = ParticipantJid,
    ToUser = jid:make(PUser, Server, <<>>),
    User = PUser
  end,
  MessageId = <<(get_string()) / binary>>,
  CustAtr = fxml:get_subtag_with_xmlns(xmpp:encode(SubEl), <<"custom_attributes">>, <<"ocp:json">>),
  if CustAtr =:= false ->
    CustomAttributes = "";
  true ->
    CustomAttributes = fxml:get_tag_cdata(CustAtr)
  end,
  case catch fly_mod_utils:delete_group_user(Server, TUser, User) of
    {updated, 1} ->
      ToUser = jid:make(User, Server, <<>>),
      XmlBody = #xmlel{name = <<"message">>,
        attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(ToUser)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
        children = [
          #xmlel{name = <<"groupdelete">>,attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"group_id">>, TUser},  {<<"type">>, RequestType}], children = []},
          #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}
        ]},
      ejabberd_router:route(From, ToUser, XmlBody),
      case fly_mod_utils:get_mobile_user_message(User, Server) of
        true ->
          mod_offline:store_packet({From,  xmpp:decode(XmlBody)});
        false ->
          ok
        end,
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group deleted successfully">>});
    {updated, 0} ->
      ToUser = jid:make(User, Server, <<>>),
      XmlBody = #xmlel{name = <<"message">>,
        attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(ToUser)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
        children = [
          #xmlel{name = <<"groupdelete">>,attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"group_id">>, TUser},  {<<"type">>, RequestType}], children = []},
          #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}
        ]},
      ejabberd_router:route(From, ToUser, XmlBody),
      case fly_mod_utils:get_mobile_user_message(User, Server) of
        true ->
          mod_offline:store_packet({From,  xmpp:decode(XmlBody)});
        false ->
          ok
        end,
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group deleted successfully">>});
    _Error ->
      ?ERROR_MSG("group deleted process error is ~p", [_Error]),
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group not deleted">>})
  end.

%%%============================================================================================
%%
%% Function : group_message_status/3
%% Params   : From, To, IQ
%% Purpose  : To remove participant from group by admin
%% IQStanza :
%%         <iq to="hellomix@mix.localhost" id="919176632184" type="set"><query status="user_exit_group" xmlns="jabber:iq:mixgroupchat">
%%              <participant>9751649808@localhost</participant></query>
%%         </iq>
%%
%%%============================================================================================

group_message_status( #jid{luser = _User} = From, _To, SubEl, IQ) ->
  MessageId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  RequestType = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),
  case catch fly_mod_utils:get_group_message_status(From,MessageId) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group does not exists">>});
    {selected, _,ResultSet} ->
      SubEls1 = lists:map(fun(G) ->
        [ToUser,Status, Received, Seen] = G,
        UserElement = #xmlel{name = <<"user">>, attrs = [],
          children = [{xmlcdata, ToUser}]},
        StatusElement = #xmlel{name = <<"status">>, attrs = [],
          children = [{xmlcdata, Status}]},
        SeenElement = #xmlel{name = <<"seentime">>, attrs = [],
          children = [{xmlcdata, Seen}]},
        ReceivedElement = #xmlel{name = <<"receivetime">>, attrs = [],
          children = [{xmlcdata, Received}]},
        #xmlel{name = <<"participants">>, attrs = [],
          children = [UserElement,  StatusElement, SeenElement, ReceivedElement]}
                          end,
        ResultSet),
      GroupXml = [#xmlel{name = <<"group">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType ,message_id = MessageId,sub_els = GroupXml })
  end.


%%"<iq from=""1505390803405919176917650@mix.flydemo.contus.us"" type=""result"" to=""919176917650@flydemo.contus.us/Psi+"" id=""4882374234"">
%%<query xmlns=""jabber:iq:mixgroupchat"" status=""group_message_status"">
%%<group>
%%<participants>
%%<user>919884412492</user>
%%<status>0</status>
%%<seentime>0000-00-00 00:00:00</seentime>
%%<receivetime>0000-00-00 00:00:00</receivetime>
%%</participants>
%%<participants>
%%<user>919176917650</user>
%%<status>2</status>
%%<seentime>2017-09-20 08:18:22</seentime>
%%<receivetime>0000-00-00 00:00:00</receivetime>
%%</participants>
%%<participants>
%%<user>917401235955</user>
%%<status>2</status>
%%<seentime>2017-09-20 08:21:05</seentime>
%%<receivetime>0000-00-00 00:00:00</receivetime>
%%</participants>
%%</group>
%%</query>
%%</iq>"
%% Get method for the IQ Starts

process_iq_get(From, To, SubEl, IQ) ->
  #jid{luser = _LUser} = From,

  RequestType = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),

  case RequestType of

    <<"get_participants">> ->

      process_get_participants(From, To, SubEl, IQ, RequestType);

    <<"get_group_ids">> ->

      process_get_group_ids(From, To, SubEl, IQ, RequestType);

    <<"get_group_profile">> ->

      process_get_group_profile(From, To, SubEl, IQ, RequestType);

    <<"get_group_vcard">> ->

      process_get_group_vcard(From, To, SubEl, IQ, RequestType);

    <<"get_participant">> ->

      process_get_participant(From, To, SubEl, IQ, RequestType);

    <<"get_group_id">> ->

      process_get_group_id(From, To,SubEl, IQ, RequestType);

    <<"group_message_status">> ->

      group_message_status(From, To, SubEl, IQ);

    <<"get_removed_user">> ->

      process_get_removed_user(From, To, SubEl, IQ,RequestType);
    no_such_subtag ->

      fly_mod_utils:generate_subel(IQ, #group_query{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});

    empty_value ->

      fly_mod_utils:generate_subel(IQ, #group_query{type = <<"empty_value">>, result_type = <<"unknown request">>});

    _Status ->

      fly_mod_utils:generate_subel(IQ, #group_query{type = _Status, result_type = <<"unknown request">>})

  end.

%%%============================================================================================
%%
%% Function : process_get_participants/3
%% Params   : From, To, IQ
%% Purpose  : Get the participants from the group.
%% IQStanza :
%%          <iq to="hellomix@mix.localhost" type="get" id="aad4a">
%%          <query status="get_participants" xmlns="jabber:iq:mixgroupchat"/>
%%          </iq>
%%
%%%============================================================================================


process_get_participants(From, To, _SubEl, IQ, RequestType) ->

  #jid{luser = FUser, lserver = Server} = From,
  #jid{user = TUser} = To,

  case catch fly_mod_utils:get_group_participants(Server, TUser) of

    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"No Participants Exists">>});

    {selected, _, Members} ->
     VCard = case mod_vcard_sql:get_vcard(TUser, Server) of
		  {ok, GSVCard} -> GSVCard;
		  _ -> []
	      end,
      SubEls1 = lists:map(fun(G) ->

        [ItemId, UserId, Affiliation, CreatedAt, IsAdminBlocked, SVCARD] = G,
        UserVCard = case fxml_stream:parse_element(SVCARD) of
                       {error, _Reason} -> [];
                       VCARD -> [VCARD]
                     end,
        JidElement = #xmlel{name = <<"jid">>, attrs = [], children = [{xmlcdata, <<UserId / binary, <<"@">> / binary, Server / binary>>}]},
        
        AffiliationElement = #xmlel{name = <<"affiliation">>, attrs = [], children = [{xmlcdata, Affiliation}]},

        ItemIdElement = #xmlel{name = <<"itemid">>, attrs = [], children = [{xmlcdata, ItemId}]},

        CreatedElement = #xmlel{name = <<"created_at">>, attrs = [], children = [{xmlcdata, CreatedAt}]},

        IsAdminBlockedElement = #xmlel{name = <<"is_admin_blocked">>, attrs = [], children = [{xmlcdata, IsAdminBlocked}]},

        VcardElement = #xmlel{name = <<"user_profile">>, attrs = [], children = mod_vcard:remove_tag(UserVCard, FUser, UserId, Server)},

        #xmlel{name = <<"participant">>, attrs = [], children = [JidElement, AffiliationElement, ItemIdElement, CreatedElement, IsAdminBlockedElement, VcardElement]}

      end, Members),

      case catch fly_mod_utils:get_group_profile_type(Server,TUser) of
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
          ChannelStatus = map_status(GChannelStatus),
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
      GroupXml = [#xmlel{name = <<"groupinfo">>, attrs = [{<<"groupupdate">>,<<"0">>},{<<"status">>,  Status},{<<"description">>,  Description},{<<"history">>,  History }, {<<"messagemode">>,  MessageMode}, {<<"channel_status">>, ChannelStatus}, {<<"invite_uri">>, InviteUri}, {<<"accessmode">>,  AccessMode }, {<<"customfeatures">>,  CustomFeatures}], children = VCard}, #xmlel{name = <<"participants">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType ,sub_els = GroupXml })

  end.

%%%============================================================================================
%%
%% Function : process_get_participant/3
%% Params   : From, To, IQ
%% Purpose  : Get the participants from the group.
%% IQStanza :
%%          <iq to="hellomix@mix.localhost" type="get" id="aad4a">
%%          <query status="get_participants" xmlns="jabber:iq:mixgroupchat"/>
%%          </iq>
%%
%%%============================================================================================

process_get_participant(From, To, _SubEl, IQ, RequestType) ->

  #jid{luser = _User, lserver = Server} = From,
  #jid{user = TUser} = To,
  case catch fly_mod_utils:get_group_participants(Server, TUser) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group does not exists">>});
    {selected, _, Members} ->
      SubEls1 = lists:map(fun(G) ->
        [ItemId, JID, Affiliation,CreatedAt,IsAdminBlocked,UserVCard] = G,
        JidElement = #xmlel{name = <<"jid">>, attrs = [],
          children = [{xmlcdata, JID}]},
        AffiliationElement = #xmlel{name = <<"affiliation">>, attrs = [],
          children = [{xmlcdata, Affiliation}]},
        CreatedElement = #xmlel{name = <<"created_at">>, attrs = [],
          children = [{xmlcdata, CreatedAt}]},
        ItemIdElement = #xmlel{name = <<"itemid">>, attrs = [],
          children = [{xmlcdata, ItemId}]},
        IsAdminBlockedElement = #xmlel{name = <<"is_admin_blocked">>, attrs = [],
          children = [{xmlcdata, IsAdminBlocked}]},
        #xmlel{name = <<"participant">>, attrs = [],
          children = [JidElement, AffiliationElement, ItemIdElement, CreatedElement,IsAdminBlockedElement]}
                          end,
        Members),
      GroupXml = [#xmlel{name = <<"participants">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType ,sub_els = GroupXml })
  end.

%%%============================================================================================
%%
%% Function : process_get_group_id/3
%% Params   : From, To, IQ
%% Purpose  : Get the group ids of the User.
%% IQStanza :
%%          <iq type="get" id="aad4a">
%%          <query status="get_group_ids"  xmlns="jabber:iq:mixgroupchat"/>
%%          </iq>
%%
%%%============================================================================================

process_get_group_ids(From, To, _SubEl, IQ, RequestType) ->
  #jid{luser = FUser, lserver = FServer} = From,
  #jid{luser = _TUser, lserver = TServer} = To,
  case catch fly_mod_utils:get_my_all_group_ids(FServer, FUser) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"No groups available for you">>});
  {selected, _, GroupIds} ->
      SubEls1 = lists:map(fun(G) ->
        [GID, CreatedDate, Affiliation] = G,
        #xmlel{name = <<"groupid">>, attrs = [{<<"created_at">>,  CreatedDate},{<<"affiliation">>,  Affiliation } ], children = [{xmlcdata, <<GID / binary, <<"@">> / binary, TServer / binary>>}]}
                          end, GroupIds),
      GroupXml = [#xmlel{name = <<"group">>, children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType ,sub_els = GroupXml})
  end.

%%%============================================================================================
%%
%% Function : process_get_group_profile/3
%% Params   : From, To, IQ
%% Purpose  : Get the group ids of the User.
%% IQStanza :
%%          <iq type="get" id="aad4a">
%%          <query status="get_group_profile" group_id="id7643276"  xmlns="jabber:iq:mixgroupchat"/>
%%          </iq>
%%
%%%============================================================================================

process_get_group_profile(From, _To, SubEl, IQ, RequestType) ->
  #jid{luser = FUser, lserver = FServer} = From,
  GroupId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  case catch fly_mod_utils:get_group_profile(FServer, FUser,GroupId) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"No groups available for you">>});
    {selected, _, GroupIds} ->
      case catch fly_mod_utils:get_group_profile_type(FServer,GroupId) of
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
                                      ChannelStatus = map_status(GChannelStatus),
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
      SubEls1 = lists:map(fun(G) ->
        [GID, CreatedDate, Vcard, Affiliation, ItemId] = G,
        VCard = case fxml_stream:parse_element(Vcard) of
                    {error, _Reason} -> [];
                    VCARD -> [VCARD]
                  end,
        #xmlel{name = <<"groupdetails">>, attrs = [{<<"groupid">>,  GID }, {<<"affiliation">>,  Affiliation } , {<<"item_id">>, ItemId} , {<<"status">>,  Status},{<<"description">>,  Description},{<<"createddate">>,  CreatedDate},{<<"history">>,  History }, {<<"messagemode">>,  MessageMode},{<<"channel_status">>, ChannelStatus},{<<"invite_uri">>, InviteUri}, {<<"accessmode">>,  AccessMode }, {<<"customfeatures">>,  CustomFeatures}],
          children = VCard}
                          end,
        GroupIds),
      GroupXml = [#xmlel{name = <<"group">>, children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType ,sub_els = GroupXml})
  end.

%%%============================================================================================
%%
%% Function : process_get_group_profile/3
%% Params   : From, To, IQ
%% Purpose  : Get the group ids of the User.
%% IQStanza :
%%          <iq type="get" id="aad4a">
%%          <query status="get_group_profile" group_id="id7643276"  xmlns="jabber:iq:mixgroupchat"/>
%%          </iq>
%%
%%%============================================================================================

process_get_group_vcard(From, _To, SubEl, IQ, RequestType) ->
  #jid{ lserver = FServer} = From,
  GroupId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  case catch fly_mod_utils:get_group_vcard(FServer,GroupId) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"No groups available for you">>});
    {selected, _, GroupIds} ->
      case catch fly_mod_utils:get_group_profile_type(FServer,GroupId) of
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
                                      ChannelStatus = map_status(GChannelStatus),
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
      SubEls1 = lists:map(fun(G) ->
        [Vcard,CreatedDate] = G,
        VCard = case fxml_stream:parse_element(Vcard) of
                    {error, _Reason} -> [];
                    VCARD -> [VCARD]
                  end,
        #xmlel{name = <<"groupdetails">>, attrs = [{<<"groupid">>,  GroupId }, {<<"status">>,  Status},{<<"description">>,  Description},{<<"createddate">>,  CreatedDate},{<<"history">>,  History }, {<<"messagemode">>,  MessageMode}, {<<"channel_status">>,  ChannelStatus },{<<"invite_uri">>,  InviteUri }, {<<"accessmode">>,  AccessMode }, {<<"customfeatures">>,  CustomFeatures}],
          children = VCard}
                          end,
        GroupIds),
      GroupXml = [#xmlel{name = <<"group">>, children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType ,sub_els = GroupXml})
  end.

%%%============================================================================================
%%
%% Function : process_get_group_ids/3
%% Params   : From, To, IQ
%% Purpose  : Get the group ids of the User.
%% IQStanza :
%%          <iq type="get" id="aad4a">
%%          <query status="get_group_ids"  xmlns="jabber:iq:mixgroupchat"/>
%%          </iq>
%%
%%%============================================================================================

process_get_group_id(From, _To, _SubEl, IQ, RequestType) ->
  #jid{luser = FUser, lserver = FServer} = From,
  case catch fly_mod_utils:get_my_all_group_id(FServer, FUser) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"No groups available for you">>});
    {selected, _, GroupIds} ->
      SubEls1 = lists:map(fun(G) ->
        [GID, CreatedDate, Vcard, Affiliation, ItemId, IsAdminBlocked] = G,
        VCard = case fxml_stream:parse_element(Vcard) of
                    {error, _Reason} -> [];
                    VCARD -> [VCARD]
                  end,
                  case catch fly_mod_utils:get_group_profile_type(FServer,GID) of
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
                                      ChannelStatus = map_status(GChannelStatus),
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
        #xmlel{name = <<"groupdetails">>, attrs = [{<<"groupid">>,  GID }, {<<"affiliation">>,  Affiliation } , {<<"status">>,  Status},{<<"description">>,  Description}, {<<"createddate">>,  CreatedDate}, {<<"item_id">>, ItemId}, {<<"is_admin_blocked">>,  IsAdminBlocked },{<<"history">>,  History },{<<"messagemode">>,  MessageMode},{<<"channel_status">>,  ChannelStatus },{<<"invite_uri">>,  InviteUri },{<<"accessmode">>,  AccessMode }, {<<"customfeatures">>,  CustomFeatures}],
          children = VCard}
                          end,
        GroupIds),
      GroupXml = [#xmlel{name = <<"group">>, children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType ,sub_els = GroupXml})
  end.

map_status(StatusString) ->
    case StatusString of
        <<"ACTIVE">> -> <<"1">>;
        <<"INACTIVE">> -> <<"0">>;
        <<"DELETED">> -> <<"-1">>;
        _ -> <<"">>
    end.

process_get_removed_user(From, _To, SubEl, IQ, _RequestType) ->
  #jid{ lserver = FServer} = From,
  ItemId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  case catch
      fly_mod_utils:get_remove_user(FServer, ItemId)
    of
      {selected, _, []} -> UserName = ItemId;
      {selected, _, [[Nick]]} -> UserName = Nick
    end,
  fly_mod_utils:generate_subel(IQ, #group_query{type = UserName ,result_type = UserName}).

%%%============================================================================================
%%
%% Function : update_group_info_to_members/4
%% Params   : From, To, IQ
%% Purpose  : publish Group updates to all group members.
%%
%%%============================================================================================

update_group_info_to_members(ActionUser, GroupFrom, Status, Data, Members, Notification, SubEl, GroupDescription) ->
  #jid{user = AUser, lserver = _AServer} = ActionUser,
  ?INFO_MSG("update_group_info_to_members ActionUser ~p", [ActionUser]),
  ActionDoneBy = list_to_binary(binary_to_list(AUser) ++ "@" ++ binary_to_list(_AServer)),
  #jid{user = FUser, lserver = _FServer} = GroupFrom,
  CustAtr = fxml:get_subtag_with_xmlns(xmpp:encode(SubEl), <<"custom_attributes">>, <<"ocp:json">>),
  if  CustAtr =:= false ->
    CustomAttributes = "";
  true ->
    CustomAttributes = fxml:get_tag_cdata(CustAtr)
  end,
  Timestamp = now_to_microseconds(erlang:now()),
  FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
  if Status == <<"new_admin_added">> ->
      ParticipantJid = <<Data / binary, $@,_AServer / binary>>,
      fly_mod_utils:update_group_count(_AServer, FUser),
      MessageId = <<(get_string()) / binary>>,
      lists:foreach(fun(To) ->
        RouteToJid = jid:make(To, _AServer, <<>>),
        #jid{user = TUser, lserver = TServer} = RouteToJid,
        fly_mod_utils:group_notify_message(ActionUser, RouteToJid, Data, FUser, Notification, Status, MessageId,list_to_binary(FlatTimeStamp),<<"">>),
        Packet = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(GroupFrom)}, {<<"type">>, <<"normal">>}, {<<"id">>,MessageId}, {<<"to">>, jid:to_string(RouteToJid)}],
          children = [#xmlel{name = <<"event">>, attrs = [{<<"xmlns">>, "http://jabber.org/protocol/pubsub#event"}],children = [#xmlel{name = <<"info">>, attrs = [{<<"status">>, Status}, {<<"done_by">>, ActionDoneBy}, {<<"new_admin">>, ParticipantJid}]}]},
            #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}, #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
                children = []}]},
        ejabberd_router:route(GroupFrom, RouteToJid, Packet),
        carboncall_message(TUser, TServer,Packet,GroupFrom),
        case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
          true ->
          mod_offline:store_packet({RouteToJid,xmpp:decode(Packet)});
          false ->
            ok
        end
        end, Members);
Status == <<"remove_admin">> ->
  ParticipantJid = <<Data / binary, $@,_AServer / binary>>,
  fly_mod_utils:update_group_count(_AServer, FUser),
  MessageId = <<(get_string()) / binary>>,
  lists:foreach(fun(To) ->
    RouteToJid = jid:make(To, _AServer, <<>>),
    #jid{user = TUser, lserver = TServer} = RouteToJid,
    fly_mod_utils:group_notify_message(ActionUser, RouteToJid, Data, FUser, Notification, Status, MessageId,list_to_binary(FlatTimeStamp),<<"">>),
    Packet = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(GroupFrom)}, {<<"type">>, <<"normal">>}, {<<"id">>,MessageId}, {<<"to">>, jid:to_string(RouteToJid)}],
      children = [#xmlel{name = <<"event">>, attrs = [{<<"xmlns">>, "http://jabber.org/protocol/pubsub#event"}],children = [#xmlel{name = <<"info">>, attrs = [{<<"status">>, Status}, {<<"done_by">>, ActionDoneBy},{<<"remove_admin">>, ParticipantJid}]}]},
        #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}, #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],children = []}]},
    ejabberd_router:route(GroupFrom, RouteToJid, Packet),
    carboncall_message(TUser, TServer,Packet,GroupFrom),
    case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
      true ->
      mod_offline:store_packet({RouteToJid,xmpp:decode(Packet)});
      false ->
        ok
    end
    end, Members);
    Status == <<"group_profile_updated">> ->
      ?INFO_MSG("update_group_info_to_members FUser ~p", [FUser]),
      fly_mod_utils:update_group_count(_AServer, FUser),
      MessageId = <<(get_string()) / binary>>,
      case catch fly_mod_utils:get_group_profile_type(_AServer,FUser) of
                                    {selected, _, []} ->
                                    TStatus = <<"">>,
                                    History = <<"">>,
                                    MessageMode = <<"">>,
                                    AccessMode = <<"">>,
                                    ChannelStatus = <<"">>,
                                    InviteUri = <<"">>,
                                    Description = <<"">>,
                                    CustomFeatures = <<"">>;
                                    {selected, _, [[GStatus, GHistory ,GMessageMode,GAccessMode,GChannelStatus,GInviteUri,GCustomFeatures,GDescription]]} ->
                                      TStatus = GStatus,
                                      History = GHistory,
                                      MessageMode = GMessageMode,
                                      AccessMode = GAccessMode,
                                      ChannelStatus = map_status(GChannelStatus),
                                      InviteUri = GInviteUri,
                                      Description = GDescription,
                                      CustomFeatures = GCustomFeatures;
                                    _ ->
                                      TStatus = <<"">>,
                                      History = <<"">>,
                                      MessageMode = <<"">>,
                                      AccessMode = <<"">>,
                                      ChannelStatus = <<"">>,
                                      InviteUri = <<"">>,
                                      Description = <<"">>,
                                      CustomFeatures = <<"">>
                                    end,
      lists:foreach(fun(To) ->
        RouteToJid = jid:make(To, _AServer, <<>>),
        ?INFO_MSG("update_group_info_to_members RouteToJid ~p", [RouteToJid]),
        #jid{user = TUser, lserver = TServer} = RouteToJid,
        EncryptedDescriptionNotifier = fly_mod_security:aes_encrpyt_group_desc_notifier(MessageId, <<"ddc0f15cc2c90fca">>, GroupDescription),
        fly_mod_utils:group_notify_message(ActionUser, RouteToJid, <<"">>, FUser, Notification, Status, MessageId,list_to_binary(FlatTimeStamp), EncryptedDescriptionNotifier),
        Packet = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(GroupFrom)},  {<<"id">>,MessageId}, {<<"type">>, <<"normal">>}, {<<"to">>, jid:to_string(RouteToJid)}],
          children = [
        #xmlel{
            name = <<"event">>,
            attrs = [{<<"xmlns">>, "http://jabber.org/protocol/pubsub#event"}],
            children = [
                #xmlel{
                    name = <<"info">>,
                    attrs = [
                        {<<"status">>, Status},
                        {<<"done_by">>, ActionDoneBy},
                        {<<"gstatus">>, TStatus},
                        {<<"description">>, Description},
                        {<<"history">>, History},
                        {<<"channel_status">>, ChannelStatus},
                        {<<"invite_uri">>, InviteUri},
                        {<<"messagemode">>, MessageMode},
                        {<<"accessmode">>, AccessMode},
                        {<<"customfeatures">>, CustomFeatures},
                        {<<"message_notification">>, Notification}
                    ],
                    children = [Data]
                }
            ]
        },
        #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}, #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}]}]},
        ejabberd_router:route(GroupFrom, RouteToJid, Packet),
        carboncall_message(TUser, TServer,Packet,GroupFrom),
        case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
          true ->
          mod_offline:store_packet({RouteToJid,xmpp:decode(Packet)});
          false ->
            ok
        end  end, Members);
    Status == <<"message_recalled">> ->
      MessageId = <<(get_string()) / binary>>,
      lists:foreach(fun(To) ->
        RouteToJid = jid:make(To, _AServer, <<>>),
        #jid{user = TUser, lserver = TServer} = RouteToJid,
        Packet = #xmlel{name = <<"message">>,attrs = [{<<"from">>, jid:to_string(ActionUser)},{<<"to">>, jid:to_string(RouteToJid)},{<<"id">>, MessageId},{<<"type">>, <<"chat">>}],
          children = [#xmlel{name = <<"recall">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:receipts">>},{<<"chat_type">>, <<"normal">>},{<<"id">>, Data},{<<"group_id">>, FUser}]},
            #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}]},
        case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
          true ->
            mod_offline:store_packet({RouteToJid,xmpp:decode(Packet)});
          false ->
            ok
        end,
        if ActionUser =/= RouteToJid ->
        fly_mod_offline_push:send_offline_message({_FServer,xmpp:decode(Packet)});
        true ->
        ok
        end,
        ejabberd_router:route(ActionUser, RouteToJid, Packet)
                    end, Members),
      fly_mod_utils:update_recall(ActionUser, Data);
    Status == <<"composing">> ->
      Packet = #xmlel{name = <<"message">>, attrs = [{<<"type">>, <<"headline">>}],
        children = [#xmlel{name = <<"composing">>, attrs = [{<<"type">>, <<"normal">>}, {<<"group_id">>, Data},{<<"xmlns">>, "http://jabber.org/protocol/chatstates"}]},
          #xmlel{name = <<"no-store">>, attrs = [{<<"xmlns">>, "urn:xmpp:hints"}]},#xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}]},
      lists:foreach(fun(To) ->
        RouteToJid = jid:make(To, _AServer, <<>>),
        if ActionUser =/= RouteToJid ->
          ejabberd_router:route(ActionUser, RouteToJid, Packet);
          true ->
            ok
        end end, Members);
    Status == <<"gone">> ->
      Packet = #xmlel{name = <<"message">>, attrs = [{<<"type">>, <<"headline">>}],
        children = [#xmlel{name = <<"gone">>, attrs = [{<<"type">>, <<"normal">>}, {<<"group_id">>, Data},{<<"xmlns">>, "http://jabber.org/protocol/chatstates"}]},
          #xmlel{name = <<"no-store">>, attrs = [{<<"xmlns">>, "urn:xmpp:hints"}]}, #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}]},
      lists:foreach(fun(To) ->
        RouteToJid = jid:make(To, _AServer, <<>>),
        if ActionUser =/= RouteToJid ->
          ejabberd_router:route(ActionUser, RouteToJid, Packet);
          true ->
            ok
        end end, Members);
    true ->
      ok
  end.

now_to_microseconds({Mega, Sec, Micro}) ->
  %%Epoch time in milliseconds from 1 Jan 1970
  (Mega * 1000000 + Sec) * 1000000 + Micro.

update_group_status(From, To, SubEl, IQ, MsgStatus, Participant, MessageId) ->
  #jid{lserver = FServer} = From,
  #jid{user = TUser} = To,
  RequestType = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),
  ParticipantData = fxml:get_tag_cdata(Participant),
  ParticipantJid = jid:make(fly_mod_utils:get_user_from_string_jid(ParticipantData),FServer,<<"">>),
  #jid{user = PUser, lserver = _PServer} = ParticipantJid,
  fly_mod_utils:update_group_count(FServer, TUser),
  case catch fly_mod_utils:get_group_users(FServer, TUser) of
    {selected, _, []} ->
      fly_mod_utils:group_notify_message(From, From, PUser, TUser, MsgStatus, RequestType, MessageId, <<"">>,<<"">>),
      fly_mod_utils:generate_subel(IQ, #group_query{type = RequestType, result_type = <<"Group Does Not exists">>});
    {selected, _, GroupMembers} ->
      JIDs = lists:flatmap(fun([Jid]) -> [Jid] end, GroupMembers),
      if RequestType =:= <<"add_participants">> ->
        NewJids = lists:filter(fun (Elem) -> PUser =/= Elem end, JIDs);
      true ->
        NewJids = JIDs
      end,
      lists:foreach(fun(Touser) ->
        RouteToJid = jid:make(Touser, FServer, <<>>),
        fly_mod_utils:group_notify_message(From, RouteToJid, PUser, TUser, MsgStatus, RequestType, MessageId,<<"">>,<<"">>)
      end, NewJids),
      case RequestType of
        <<"admin_remove_admin">> ->
          fly_mod_utils:group_notify_message(From, ParticipantJid, PUser, TUser, MsgStatus, RequestType, MessageId,<<"">>,<<"">>);
        <<"remove_participant">> ->
          fly_mod_utils:group_notify_message(From, ParticipantJid, PUser, TUser, MsgStatus, RequestType, MessageId,<<"">>,<<"">>);
        <<"admin_remove_participant">> ->
          fly_mod_utils:group_notify_message(From, ParticipantJid, PUser, TUser, MsgStatus, RequestType, MessageId,<<"">>,<<"">>);
        <<"admin_exit_group">> ->
          fly_mod_utils:group_notify_message(From, ParticipantJid, PUser, TUser, MsgStatus, RequestType, MessageId,<<"">>,<<"">>);
        <<"user_exit_group">> ->
          fly_mod_utils:group_notify_message(From, ParticipantJid, PUser, TUser, MsgStatus, RequestType, MessageId,<<"">>,<<"">>);
        _ ->
          ok
      end
  end.

carboncall_message(LUser, LServer,XmlBody ,From) ->
  Resources = ejabberd_sm:get_user_resources(LUser, LServer),
  if length(Resources) =:= 1 -> true;
    length(Resources) =:= 0 -> false;
    length(Resources) =:= 2 ->
    lists:foldl(fun(SResource,_Acc) ->
    WebResource = string:str(binary_to_list(SResource), binary_to_list(<<"Web">>)),
    if WebResource =:= 1 ->
        ToJid = jid:make(LUser, LServer, SResource),
        ejabberd_router:route(From, ToJid, XmlBody);
        true ->
          ok
      end
  end,[],Resources);
length(Resources) =:= 3 ->
    lists:foldl(fun(SResource,_Acc) ->
    WebResource = string:str(binary_to_list(SResource), binary_to_list(<<"Web">>)),
    if WebResource =:= 1 ->
        ToJid = jid:make(LUser, LServer, SResource),
        ejabberd_router:route(From, ToJid, XmlBody);
        true ->
          ok
      end
  end,[],Resources);
    length(Resources) > 3 -> false
  end.

get_string() ->
  R = crypto:rand_uniform(0, 16#100000000000000000000000000000000),
  AlphanumericList = string:to_lower(integer_to_list(R, 36)),
  Alphanumeric = list_to_binary(AlphanumericList).
% mod_opt_type(iqdisc) -> fun gen_iq_handler:check_type/1;
% mod_opt_type(db_type) -> fun(T) -> ejabberd_config:v_db(?MODULE, T) end;
% mod_opt_type(_) -> [db_type, iqdisc].

depends(_, _) ->
  [].

mod_opt_type(host) ->
    econf:host();
mod_opt_type(hosts) ->
    econf:hosts().

mod_options(Host) ->
  [{host, <<"mix.", Host / binary>>},
  {hosts, []}].
