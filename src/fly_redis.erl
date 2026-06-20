-module(fly_redis).

-author('Thangatamil').

-include_lib("xmpp/include/xmpp.hrl").

-export([store_block/4, check_block/3, check_mute/3]).

% block
store_block(FromUser, JIDs, <<"SADD">>, Msg) -> 

  FUser = FromUser#jid.luser,

  Key = <<"user:", FUser/binary, ":block">>,

  BlockedUsers = [BlockedUser || {BlockedUser, _, _} <- JIDs],

  ejabberd_redis:q([<<"SREM">>, Key, <<"empty">>]),
  Res = ejabberd_redis:q([<<"SADD">>, Key] ++ BlockedUsers),

  logger:info("user:: ~p " ++ Msg ++ " user/s:: ~p "
      "result:: ~p", [FUser, BlockedUsers, Res]);

% unblock
store_block(FromUser, JIDs, <<"SREM">>, Msg) -> 

  FUser = FromUser#jid.luser,

  Key = <<"user:", FUser/binary, ":block">>,

  BlockedUsers = [BlockedUser || {BlockedUser, _, _} <- JIDs],

  Res = ejabberd_redis:q([<<"SREM">>, Key] ++ BlockedUsers),

  set_empty(FUser, <<":block">>),

  logger:info("user:: ~p " ++ Msg ++ " result:: ~p",
            [FUser, Res]);

% unblock all 
store_block(FromUser, _, <<"DEL">>, Msg) -> 

  FUser = FromUser#jid.luser,

  Key = <<"user:", FUser/binary, ":block">>,

  Res = ejabberd_redis:q([<<"DEL">>, Key]),
  ejabberd_redis:q([<<"SADD">>, Key, <<"empty">>]),
  logger:info("user:: ~p " ++ Msg ++ " result:: ~p",
              [FUser, Res]).

check_block(Host, FUser, TUser) -> 

  Key = <<"user:", TUser/binary, ":block">>,

  Res = ejabberd_redis:q([<<"SMEMBERS">>, Key]),

  case Res of 
    {ok, [<<"empty">>]} ->
      logger:info("blocking lookup completed in redis with 'empty';"),
      allow;
    {ok, []} ->
      % make a db I/O to get all the blocked users 
      % and persist in redis cache to reduce I/O's.

      logger:info("blocking lookup going for DB I/O;"),

      BlockedUserList = fly_mod_utils:get_blocked_users(Host, TUser),

      logger:info("blocked users list  from db:: ~p", [BlockedUserList]),

      LUserList = 
      case BlockedUserList of 
        {selected, _, []} -> 
            set_empty(TUser, <<":block">>),
            [];
        {selected, _, BUsers} ->
            JIDs = 
            [jid:tolower(JID) || 
             [B] <- BUsers, JID <- [jid:from_string(B)], 
             JID =/= error],

             FromJid = jid:make(TUser, Host),
             store_block(FromJid, JIDs, <<"SADD">>, "blocked"),

            [LUser || [B] <- BUsers, 
             JID <- [jid:from_string(B)], 
             JID =/= error, {LUser, _, _} 
             <- [jid:tolower(JID)]];
        _ -> 
          []
      end,

      case lists:member(FUser, LUserList) of 
        true -> 
          not_allow;
        false -> 
          allow
      end;
    {ok, BlockedUsers} ->
      logger:info("blocking lookup completed in redis;"),
      case lists:member(FUser, BlockedUsers) of 
        true -> 
          not_allow;
        false -> 
          allow
      end
  end.

set_empty(User, Type) ->
  
  Key = <<"user:", User/binary, Type/binary>>,

  case ejabberd_redis:q([<<"SCARD">>, Key]) of
    {ok, <<"0">>} ->
      ejabberd_redis:q([<<"SADD">>, Key, <<"empty">>]);
    _ ->
      ok
  end.

check_mute(Host, FUser, TUser) ->
  Key = <<"user:", TUser/binary, ":mute">>,

  Res = ejabberd_redis:q([<<"SMEMBERS">>, Key]),

  case Res of 
    {ok, [<<"empty">>]} -> 
      logger:info("mute lookup completed in redis with 'empty';"),
      allow;
    {ok, []} ->

      logger:info("mute lookup going for DB I/O;"),

      MutedUsersList = fly_mod_utils:get_muted_chats(Host, TUser),

      logger:info("mute users list from db:: ~p", [MutedUsersList]),

      MutedList = 
      case MutedUsersList of 
        {selected, _, []} -> 
            set_empty(TUser, <<":mute">>),
            [];
        {selected, _, MUsers} ->
            store_mute(TUser, [M || [M] <- MUsers], "Mute");
        _ -> 
          []
      end,

      case lists:member(TUser, MutedList) orelse
           lists:member(FUser, MutedList) of
           true  -> muted;
           false -> allow
      end;

    {ok, MutedUsers} ->
        logger:info("mute lookup completed in redis;"),
        case lists:member(TUser, MutedUsers) orelse
             lists:member(FUser, MutedUsers) of
             true  -> muted;
             false -> allow
        end
  end.

store_mute(User, Mutes, Msg) -> 

  Key = <<"user:", User/binary, ":mute">>,


  ejabberd_redis:q([<<"SREM">>, Key, <<"empty">>]),
  Res = ejabberd_redis:q([<<"SADD">>, Key] ++ Mutes),

  logger:info("user:: ~p " ++ Msg ++ " user/s:: ~p "
      "result:: ~p", [User, Res]),
  
  Mutes.