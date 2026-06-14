-module(mod_amqp_proc).

-author('Thangatamil').

%% internal functions %%
-export([process_listener_payload/3, update_license/2,
         process_push/2]).

% q :: data
% none

% q :: api_data
-define(CONTACT_PERMISSION, <<"Contact_Permission">>).
-define(BLOCK_USER, <<"block_user">>).
-define(USER_EXIT_GROUP, <<"userExitGroup">>).
-define(DELETE_CONTACT, <<"deleteContact">>).
-define(USER_LOGOUT, <<"userLogout">>).
-define(USER_LEVEL_UNBLOCK, <<"user_level_unblock">>).
-define(USER_LEVEL_BLOCK, <<"user_level_block">>).
-define(MUTE_CHAT, <<"mute_chat">>).
-define(LOGOUT_SESSIONS, <<"logout_sessions">>).
-define(MEDIA_DELETE, <<"media_delete">>).

% q :: api_message
-define(MSG_DELIVERY, <<"message_delivery">>).

% q :: api_call
-define(MEDIA_CALL, <<"mediacall">>).
-define(CARBON_MEDIA_CALL, <<"carbonmediacall">>).
-define(CALL_ACTIVITY, <<"call_activity">>).

-define(MOD_OFFLINE, fly_mod_offline_push).

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").

%%====================================================================%% 
%%                   consumer payload handler func                    %%  
%%====================================================================%%
process_listener_payload(Type, Map, Host) ->

    TypeList = [ 
                 ?CONTACT_PERMISSION, ?BLOCK_USER, ?USER_EXIT_GROUP,
                 ?DELETE_CONTACT, ?USER_LOGOUT, ?USER_LEVEL_UNBLOCK, 
                 ?USER_LEVEL_BLOCK, ?MUTE_CHAT, ?LOGOUT_SESSIONS,
                 ?MEDIA_DELETE, ?MSG_DELIVERY, ?CARBON_MEDIA_CALL,
                 ?MEDIA_CALL, ?CALL_ACTIVITY
               ],
    
    case lists:member(Type, TypeList) of
        true ->
            Id = binary:part(base64:encode(crypto:strong_rand_bytes(8)),0,10),
            IQ = handle_payload(Map, Host, Id, Type),
            ?LOG_INFO("[~p] Iq: ~p", [Type, IQ]),
            case lists:member(Type, [?USER_EXIT_GROUP, ?MEDIA_DELETE]) of
                true -> 
                    ok;
                false ->
                    ejabberd_router:route(IQ)
            end;
        false ->
            ?LOG_INFO("rabbit mq consumer payload has 
                      no matching type, 'skipping process'")
    end.

update_license(LicenseData, Host) ->

    Id = binary:part(base64:encode(crypto:strong_rand_bytes(8)),0,10),
    AdminJid = jid:make(<<"123456789">>, Host),

    IQ =
    #iq{
        type = set, id = Id, from = AdminJid, to = AdminJid, 
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"xmlns">>, <<"jabber:iq:user_activities">>},
                    {<<"license_data">>, LicenseData},
                    {<<"status">>, <<"update_license_data">>}
                ],
                children = []
            }
        ]
    },

    ejabberd_router:route(IQ).

process_push(Payload, Host) ->

    UserDetails = get_user_details(Payload, Host),
    MessageData = get_msg_data(Payload, Host),

    case {UserDetails, MessageData} of 
        {#{<<"device_type">> := DeviceType}, #{}} 
            when DeviceType =:= <<"ios">> -> 

            %% send ios push payload to rabbit-mq
            prep_and_send(Host, Payload, UserDetails, MessageData, ios),

            ok;
        {#{<<"device_type">> := DeviceType}, #{}} 
            when DeviceType =:= <<"android">> -> 
            
            %% send android push payload to rabbit-mq
            ok;
        {#{<<"device_type">> := DeviceType}, #{}} ->
            logger:warning("unknow deviceType ~p, " 
                    "skip push processing", [DeviceType]);
        _ ->    
            logger:warning("user details data not "
                "sufficient to process push, "
                "user_details ::~p "
                "message_details :: ~p ", 
                [UserDetails, MessageData])
    end.

get_user_details(Payload, Host) ->

    UserId = maps:get(<<"username">>, Payload),
    DeviceId = maps:get(<<"deviceId">>, Payload),

    Table = <<"chat_users_details">>,
    Selects = <<"*">>,
    Where = [<<"username = '">>,UserId,<<"' and device_id = '">>,DeviceId,<<"'">>],

    fly_sql:get_map(Host, Table, Selects, Where).

get_msg_data(Payload, Host) ->

    UserId = maps:get(<<"username">>, Payload),
    MessageId = maps:get(<<"messageId">>, Payload),

    Table = <<"message_status">>,
    Selects = <<"message_id, message_time, chat_type, txt, from_notification, "
                "from_user, to_user, message_type">>,
    Where = [<<"message_id = '">>,MessageId,<<"' AND to_user = '">>,UserId,<<"' LIMIT 1">>],

    fly_sql:get_map(Host, Table, Selects, Where).

prep_and_send(Host, Payload, UserDetails, MessageData, ios) ->

    case {UserDetails, MessageData} of 
        {#{<<"device_token">> := DeviceToken,
          <<"mode">> := Mode,
          <<"user_type">> := UserType,
          <<"push_server_type">> := PushType},

         #{<<"message_id">> := MessageId,
           <<"message_time">> := MessageTime,
           <<"chat_type">> := ChatType,
           <<"txt">> := Txt,
           <<"from_notification">> := FromNotification,
           <<"from_user">> := FromUser,
           <<"to_user">> := ToUser,
           <<"message_type">> := MessageType}} ->

            From =
                if ChatType =:= <<"normal">> -> 
                    <<FromNotification/binary, "@mix-", Host/binary>>;
                true -> 
                    FromUser
                end,
            
            DeviceId = maps:get(<<"deviceId">>, Payload),

            Args = to_list_values([
                {push_from, <<"MirrorFly">>},
                {to_user, ToUser},
                {from_user, From},
                {userDomain, Host},
                {type, MessageType},
                {user_type, UserType},
                {chat_type, ChatType},
                {message_content, Txt},
                {message_id, MessageId},
                {message_time, MessageTime}
            ]),

            Msg = to_list_values([
                   {<<"mutable-content">>, 
                            integer_to_list(1)},
                   {alert, DeviceId},
                   {mode, Mode},
                   {sound, <<"default">>}
                  ]),

            Token = binary_to_list(DeviceToken),

            Json = ?MOD_OFFLINE:create_json(Msg, 
                        Args, Token, Mode, 0, 0, PushType),

            ?MOD_OFFLINE:send_payload(Host, Json, 
                        ChatType, PushType, false, ios);

        _ ->    
            logger:warning("data not sufficient "
                "to send payload to rabbit-mq, "
                "user_details ::~p "
                "message_details :: ~p ", 
                [UserDetails, MessageData])
    end;
prep_and_send(Host, _, UserDetails, _, android) ->
    
    case UserDetails of 
        #{<<"device_token">> := DeviceToken,
          <<"push_server_type">> := PushType} ->
            Json = ?MOD_OFFLINE:create_android_json(DeviceToken, <<>>),

            ?MOD_OFFLINE:send_payload(Host, Json, <<>>, 
                            PushType, false, ios);
        _->
            ok
    end.

to_list_values(Props) ->
    [{K, to_list(V)} || {K, V} <- Props].

to_list(Bin) when is_binary(Bin) ->
    binary_to_list(Bin);
to_list(Value) ->
    Value.

handle_payload(Map, Host, Id, ?CONTACT_PERMISSION) ->
    CustomStrBin = maps:get(<<"customString">>, Map),
    CustomMap = jiffy:decode(CustomStrBin, [return_maps]),

    ToUser = maps:get(<<"toUser">>, CustomMap),

    TUser =
    case binary:split(ToUser, <<"@">>) of
        [LUser, _] ->
            jid:nodeprep(LUser);
        [_] ->
            ToUser
    end,

    Jid = jid:make(TUser, Host),
    PermissionStatus = maps:get(<<"permissionStatus">>, CustomMap),
    PsBin = integer_to_binary(PermissionStatus),

    #iq{
        type = set, id = Id, from = Jid, to = Jid, 
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"xmlns">>, <<"jabber:iq:user_activities">>},
                    {<<"permission_status">>, PsBin},
                    {<<"to_user">>, <<TUser/binary, "@", Host/binary>>},
                    {<<"status">>, <<"send_contact_sync_status">>}
                ],
                children = []
            }
        ]
    };

handle_payload(Map, Host, Id, ?BLOCK_USER) ->
    CustomStrBin = maps:get(<<"customString">>, Map),
    CustomMap = jiffy:decode(CustomStrBin, [return_maps]),
    ToUser = maps:get(<<"toUser">>, CustomMap),

    TUser =
    case binary:split(ToUser, <<"@">>) of
        [LUser, _] ->
            jid:nodeprep(LUser);
        [_] ->
            ToUser
    end,
    Jid = jid:make(TUser, Host),
    Type = maps:get(<<"type">>, CustomMap),
    BlockStatus = maps:get(<<"blockStatus">>, CustomMap),
    BsBin = integer_to_binary(BlockStatus),

    #iq{
        type = set, id = Id, from = Jid, to = Jid,
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"xmlns">>, <<"jabber:iq:user_activities">>},
                    {<<"block_status">>, BsBin},
                    {<<"to_user">>, <<TUser/binary, "@", Host/binary>>},
                    {<<"type">>, Type},
                    {<<"status">>, <<"update_admin_block_status">>}
                ],
                children = []
            }
        ]
    };

handle_payload(Map, Host, _, ?USER_EXIT_GROUP) ->

    CustomStrBin = maps:get(<<"customString">>, Map, <<>>),
    CustomList =
        case CustomStrBin of
            <<>> ->
                [];
            Bin when is_binary(Bin) ->
                jiffy:decode(Bin, [return_maps]);
            _ ->
                []
        end,

    case CustomList of
        [] ->
            ok;

        [First | _] ->
            Username = maps:get(<<"username">>, First, <<>>),

            DeletedChannels =
                lists:foldl(fun(Item, Acc) ->
                    User = maps:get(<<"username">>, Item, <<>>),
                    Chan = maps:get(<<"channel">>, Item, <<>>),

                    case send_user_left_iq(User, Chan, Host) of
                        true ->
                            [Chan | Acc];
                        false ->
                            Acc
                    end
                end, [], CustomList),

            case DeletedChannels of
                [] ->
                    ok;
                _ ->
                    delete_in_tables(Host, Username, DeletedChannels)
            end
    end;

handle_payload(Map, Host, Id, Type) 
    when Type =:= ?DELETE_CONTACT;
    Type =:= ?USER_LOGOUT  ->
    ToUser = maps:get(<<"customString">>, Map),
    TUser =
    case binary:split(ToUser, <<"@">>) of
        [LUser, _] ->
            jid:nodeprep(LUser);
        [_] ->
            ToUser
    end,
    Jid = jid:make(TUser, Host),
    Status =
    if Type =:= ?DELETE_CONTACT -> 
        <<"send_deleted_user_status">>;
    true -> 
        <<"user_logout_by_admin">>
    end,
  
    #iq{
        id = Id, type = set, from = Jid, to = Jid, 
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"xmlns">>, <<"jabber:iq:user_activities">>},
                    {<<"status">>, Status},
                    {<<"to_user">>, <<TUser/binary, "@", Host/binary>>}
                ],
                children = []
            }]
    };

handle_payload(Map, Host, Id, Type) 
    when Type =:= ?USER_LEVEL_BLOCK;
    Type =:= ?USER_LEVEL_UNBLOCK ->
    
    CustomString = maps:get(<<"customString">>, Map),

    CustomMap = jiffy:decode(CustomString, [return_maps]),
    RequestFrom = maps:get(<<"requestFrom">>, CustomMap),
    UserId = maps:get(<<"userId">>, CustomMap),

    MessageFrom = <<RequestFrom/binary, "@", Host/binary>>,
    ToUser = <<UserId/binary, "@", Host/binary>>,

    Name =
    if Type =:= ?USER_LEVEL_BLOCK -> 
        <<"block">>;
    true -> 
        <<"unblock">>
    end,
    Jid = jid:make(RequestFrom, Host),

    #iq{
        id = Id, type = set, from = Jid, to = Jid,
        sub_els = [
            #xmlel{
                name = Name,
                attrs = [{<<"xmlns">>, <<"urn:xmpp:blocking">>}, 
                         {<<"message_from">>, MessageFrom}],
                children = [#xmlel{name = <<"item">>, 
                                   attrs = [{<<"jid">>, ToUser}]}]
            }
        ]
    };

handle_payload(Map, Host, Id, ?MUTE_CHAT) ->

    CustomString = maps:get(<<"customString">>, Map),
    CustomMap = jiffy:decode(CustomString, [return_maps]),

    MuteSetting = maps:get(<<"muteSetting">>, CustomMap),
    FromUser = maps:get(<<"fromUser">>, CustomMap),
    Action = maps:get(<<"action">>, CustomMap),

    CommaSeparatedIds = 
    if MuteSetting =:= <<"false">> ->
        UserIds = maps:get(<<"userIds">>, CustomMap),
        GroupIds = maps:get(<<"groupIds">>, CustomMap),

        UserIdsWithHost = [<<U/binary, "@", Host/binary>> || U <- UserIds],
        GroupIdsWithHost = [<<G/binary, "@mix.", Host/binary>> || G <- GroupIds],

        CombinedIds = UserIdsWithHost ++ GroupIdsWithHost,

        iolist_to_binary(string:join(
        [binary_to_list(Cid) || Cid <- CombinedIds], 
        ","));
    true -> 
        <<"">>
    end,
    Jid = jid:make(FromUser, Host),

    #iq{
        id = Id,
        type = set,
        from = Jid,
        to = Jid,
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"xmlns">>, <<"jabber:iq:user_activities">>}, 
                    {<<"from_user">>, FromUser}, 
                    {<<"mute_setting">>, MuteSetting}, 
                    {<<"user_list">>, CommaSeparatedIds}, 
                    {<<"status">>, <<"mute_chat">>}, 
                    {<<"action">>, Action} 
                ],
                children = []
            }]
    };

handle_payload(Map, Host, Id, ?LOGOUT_SESSIONS) ->

    CustomString = maps:get(<<"customString">>, Map),
    CustomMap = jiffy:decode(CustomString, [return_maps]),

    UserId = maps:get(<<"username">>, CustomMap),
    SocketId = maps:get(<<"socket_id">>, CustomMap),
    DeviceId = maps:get(<<"device_id">>, CustomMap),
    SimBindLogout = maps:get(<<"sim_bind_logout">>, CustomMap),

    Jid = jid:make(UserId, Host),
   #iq{
        id = Id,
        type = set,
        from = Jid,
        to = Jid,
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"xmlns">>, <<"jabber:iq:user_activities">>}, 
                    {<<"status">>, <<"user_logout">>}, 
                    {<<"message_from">>, UserId},
                    {<<"socket_id">>, SocketId}, 
                    {<<"device_id">>, DeviceId},
                    {<<"sim_bind_logout">>, SimBindLogout}
                ],
                children = []
            }]
    };

handle_payload(Map, Host, Id, ?MEDIA_DELETE) ->

    CustomString = maps:get(<<"customString">>, Map),
    CustomList = jiffy:decode(CustomString, [return_maps]),

    AdminJid = jid:make(<<"123456789">>, Host),

    [ begin
        FromUser = maps:get(<<"fromUser">>, C),
        ToUser = maps:get(<<"toUser">>, C),
        MessageId = maps:get(<<"messageId">>, C),
        ChatType = maps:get(<<"chatType">>, C),

        FromJid = jid:make(FromUser, Host),
        ToJid = jid:make(ToUser, Host),
        send_receipt(Host, AdminJid, FromJid, ToJid, MessageId, Id, ChatType)
      end || C <- CustomList];

handle_payload(Map, Host, Id, ?MSG_DELIVERY) ->

    MsgFrom = maps:get(<<"messageFrom">>, Map),
    MsgTo = maps:get(<<"messageTo">>, Map),
    MsgId = maps:get(<<"messageId">>, Map),
    GroupId = maps:get(<<"groupId">>, Map, <<>>),
    DeviceId = maps:get(<<"deviceId">>, Map, <<>>),

    FromUser =
    case binary:split(MsgFrom, <<"@">>) of
        [MFrom, _] ->
            jid:nodeprep(MFrom);
        [_] ->
            MsgFrom
    end,

    ToUser =
    case binary:split(MsgTo, <<"@">>) of
        [MTo, _] ->
            jid:nodeprep(MTo);
        [_] ->
            MsgTo
    end,

    From = <<FromUser/binary, "@", Host/binary>>,
    To = <<ToUser/binary, "@", Host/binary>>,

    AdminJid = jid:make(<<"123456789">>, Host),

    #iq{type = set,
        id = Id,
        from = AdminJid,
        to = AdminJid,
        sub_els = [
                #xmlel{name = <<"query">>, 
                       attrs = [
                        {<<"message_from">>, From},
                        {<<"message_to">>, To},
                        {<<"message_id">>, MsgId},
                        {<<"group_id">>, GroupId},
                        {<<"device_id">>, DeviceId},
                        {<<"status">>, <<"send_delivery">>},
                        {<<"xmlns">>, <<"jabber:iq:user_activities">>}],
                children = []
            }]
        };

handle_payload(Map, Host, _, ?MEDIA_CALL) ->

    RoomId = maps:get(<<"roomId">>, Map),
    CallType = maps:get(<<"callType">>, Map),
    CallMode = maps:get(<<"callMode">>, Map),
    CallFrom = maps:get(<<"callFrom">>, Map),
    CallStatus = maps:get(<<"callStatus">>, Map),
    RandomId = maps:get(<<"randomId">>, Map),
    GroupId = maps:get(<<"groupId">>, Map, <<>>),
    StartTime = maps:get(<<"startTime">>, Map, <<>>),
    EndTime = maps:get(<<"endTime">>, Map, <<>>),
    CallingTime = maps:get(<<"callingTime">>, Map, <<>>),
    Users = maps:get(<<"users">>, Map, []),
    InvitedUsers = maps:get(<<"invitedUsers">>, Map, []),

    UserEls = [#xmlel{name = <<"user">>, attrs = [], 
                    children = [{xmlcdata, User}]} || User <- Users],

    UsersEl = #xmlel{name = <<"users">>, attrs = [], children = UserEls},

    InviteEl =
        case CallStatus of
            <<"INVITEUSERS">> ->
                InviteUsersEls =
                    [#xmlel{name = <<"user">>,
                            attrs = [],
                            children = [{xmlcdata, User}]}
                     || User <- InvitedUsers],

                [#xmlel{name = <<"invite">>,
                        attrs = [],
                        children = InviteUsersEls}];
            _ ->
                []
        end,

    QueryAttrs0 = [
        {<<"status">>, <<"call_status">>},
        {<<"room_id">>, RoomId},
        {<<"group_id">>, GroupId},
        {<<"call_type">>, CallType},
        {<<"call_mode">>, CallMode},
        {<<"call_from">>, <<CallFrom/binary, "@", Host/binary>>},
        {<<"call_status">>, CallStatus},
        {<<"xmlns">>, <<"jabber:iq:media_call_activities">>}
    ],

    QueryAttrs1 =
        case CallingTime of
            <<>> -> QueryAttrs0;
            _ -> [{<<"call_time">>, CallingTime} | QueryAttrs0]
        end,

    QueryAttrs2 =
        case StartTime of
            <<>> -> QueryAttrs1;
            _ -> [{<<"start_time">>, StartTime} | QueryAttrs1]
        end,

    QueryAttrs =
        case EndTime of
            <<>> -> QueryAttrs2;
            _ -> [{<<"end_time">>, EndTime} | QueryAttrs2]
        end,

    #iq{
        type = set,
        id = RandomId,
        from = jid:make(CallFrom, Host),
        to = jid:make(CallFrom, Host),
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = QueryAttrs,
                children = [UsersEl] ++ InviteEl
            }
        ]
    };

handle_payload(Map, Host, _, ?CARBON_MEDIA_CALL) ->

    RoomId = maps:get(<<"roomId">>, Map),
    CallFrom = maps:get(<<"callFrom">>, Map),
    CallStatus = maps:get(<<"callStatus">>, Map),
    FromUser = maps:get(<<"fromUser">>, Map),
    RandomId = maps:get(<<"randomId">>, Map),

    #iq{
        type = set,
        id = RandomId,
        from = jid:make(CallFrom, Host),
        to = jid:make(FromUser, Host),
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"room_id">>, RoomId},
                    {<<"call_from">>, <<CallFrom/binary, "@", Host/binary>>},
                    {<<"call_status">>, CallStatus},
                    {<<"from_user">>, FromUser},
                    {<<"xmlns">>, <<"jabber:iq:carbon_media_call_activities">>}
                ],
                children = []
            }
        ]
    };

handle_payload(Map, Host, _, ?CALL_ACTIVITY) ->

    RandomId = maps:get(<<"randomId">>, Map),
    SocketId = maps:get(<<"socketId">>, Map, <<>>),
    MessageTo = maps:get(<<"messageTo">>, Map),
    MessageFrom = maps:get(<<"messageFrom">>, Map),
    CallStatus = maps:get(<<"callStatus">>, Map),
    CallType = maps:get(<<"callType">>, Map),
    CallerDevice = maps:get(<<"callerDevice">>, Map, <<>>),
    CallerAttendStatus = maps:get(<<"callerAttendStatus">>, Map, <<>>),
    CallId = maps:get(<<"callId">>, Map, <<>>),

    #iq{
        type = set,
        id = RandomId,
        from = jid:make(MessageFrom, Host),
        to = jid:make(MessageTo, Host),
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"status">>, <<"call_status">>},
                    {<<"message_from">>, MessageFrom},
                    {<<"message_to">>, MessageTo},
                    {<<"call_status">>, CallStatus},
                    {<<"socket_id">>, SocketId},
                    {<<"call_type">>, CallType},
                    {<<"caller_device">>, CallerDevice},
                    {<<"call_attend_status">>, CallerAttendStatus},
                    {<<"call_id">>, CallId},
                    {<<"xmlns">>, <<"jabber:iq:user_activities">>}
                ],
                children = []
            }
        ]
    }.

send_receipt(Host, AdminJid, FromJid, ToJid, MessageId, Id, <<"chat">>) ->
    Pkt1 = #message{
            from = AdminJid, to = FromJid, type = chat, id = Id,
            sub_els = [#xmlel{
                    name = <<"recall">>,
                    attrs = [{<<"xmlns">>, <<"urn:xmpp:receipts">>}, 
                                {<<"id">>, MessageId}, {<<"group_id">>, <<>>}],
                    children = []
                }]
        },
    Pkt2 = #message{
            from = AdminJid, to = ToJid, type = chat, id = Id,
            sub_els = [#xmlel{
                    name = <<"recall">>,
                    attrs = [{<<"xmlns">>, <<"urn:xmpp:receipts">>}, 
                                {<<"id">>, MessageId}, {<<"group_id">>, <<>>}],
                    children = []
                }]
        },
    {Packet1, amqp} = ejabberd_hooks:run_fold(user_send_packet, 
                                    Host, {Pkt1, amqp}, []),

    ejabberd_router:route(Packet1),

    {Packet2, amqp} = ejabberd_hooks:run_fold(user_send_packet, 
                                    Host, {Pkt2, amqp}, []),
    
    ejabberd_router:route(Packet2);

send_receipt(_, AdminJid, _, ToJid, MessageId, Id, ChatType) ->

    #jid{luser = TLuser, lserver = TLserver} = ToJid,
    TMixJid = <<TLuser/binary, "@mix.", TLserver/binary>>,

    IQ = #iq{
            from = AdminJid,
            to = jid:from_string(TMixJid),
            type = set,
            id = Id,
            sub_els = [#xmlel{
                name = <<"query">>,
                attrs = [
                    {<<"xmlns">>, <<"jabber:iq:mixgroupchat">>},
                    {<<"status">>, <<"recall">>},
                    {<<"chat_type">>, ChatType},
                    {<<"msgid">>, MessageId}
                ]
            }]
        },

    ejabberd_router:route(IQ).

send_user_left_iq(User, Chan, Host) ->
    Id = fly_mod_utils:get_iq_message_id(20),
    GroupJid = <<Chan/binary, "@mix.", Host/binary>>,
    UserJid = <<User/binary, "@", Host/binary>>,

    IQ = #iq{
        type = set,
        id = Id,
        from = jid:make(User, Host),
        to = jid:from_string(GroupJid),
        sub_els = [
            #xmlel{
                name = <<"query">>,
                attrs = [{<<"xmlns">>, <<"jabber:iq:mixgroupchat">>},
                         {<<"status">>, <<"user_exit_group">>}],
                children = [
                    #xmlel{name = <<"participant">>, attrs = [], 
                    children = [{xmlcdata, UserJid}]}
                ]
            }
        ]
    },

    ejabberd_router:route(IQ), true.

delete_in_tables(_Host, _User, []) ->
    ok;

delete_in_tables(Host, User, DeletedChannels) ->
    InClause =
        iolist_to_binary(
            lists:join(<<",">>, [[<<"'">>, C, <<"'">>] || C <- DeletedChannels])
        ),

    Tables = [<<"mix_pam">>, <<"mix_subscription">>, <<"mix_participant">>],

    Clause = [<<"username = '">>, User, <<"' AND channel IN (">>, InClause, <<")">>],

    WhereClauses = [Clause, Clause, Clause],

    fly_sql:delete(Host, Tables, WhereClauses).