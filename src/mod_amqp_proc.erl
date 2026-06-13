-module(mod_amqp_proc).

-author('Thangatamil').

%% internal functions %%
-export([process_listener_payload/3]).

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

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").

%%====================================================================%% 
%%                   consumer payload handler func                    %%  
%%====================================================================%%
process_listener_payload(Type, Map, Host) ->

    TypeList = [ ?CONTACT_PERMISSION, ?BLOCK_USER, ?USER_EXIT_GROUP,
                 ?DELETE_CONTACT, ?USER_LOGOUT, ?USER_LEVEL_UNBLOCK, 
                 ?USER_LEVEL_BLOCK, ?MUTE_CHAT, ?LOGOUT_SESSIONS,
                 ?MEDIA_DELETE
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
      end || C <- CustomList].

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