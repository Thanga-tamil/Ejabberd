-module(fly_redis).

-author('Thangatamil').

-include_lib("xmpp/include/xmpp.hrl").

-export([store_block/4, check_block/1]).

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

  case ejabberd_redis:q([<<"SCARD">>, Key]) of
    {ok, <<"0">>} ->
      ejabberd_redis:q([<<"SADD">>, Key, <<"empty">>]);
    _ ->
      ok
  end,
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


check_block(FUser) ->

   Key = <<"user:", FUser/binary, ":block">>,
   
   ejabberd_redis:q([<<"SMEMBERS">>, Key]).