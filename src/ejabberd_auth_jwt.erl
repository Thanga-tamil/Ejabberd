%%%----------------------------------------------------------------------
%%% File    : ejabberd_auth_jwt.erl
%%% Author  : Mickael Remond <mremond@process-one.net>
%%% Purpose : Authentication using JWT tokens
%%% Created : 16 Mar 2019 by Mickael Remond <mremond@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2024   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License along
%%% with this program; if not, write to the Free Software Foundation, Inc.,
%%% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%%%
%%%----------------------------------------------------------------------

-module(ejabberd_auth_jwt).

-author('mremond@process-one.net').

-behaviour(ejabberd_auth).

-export([start/1, stop/1, check_password/4, 
         store_type/1, plain_password_required/1,
         user_exists/2, use_cache/1]).

%% 'ejabberd_hooks' callback:
-export([check_decoded_jwt/5]).

-include("logger.hrl").
-include("ejabberd_sql_pt.hrl").
-include_lib("xmpp/include/xmpp.hrl").

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start(Host) ->
    %% We add our default JWT verifier with hook priority 100.
    %% So if you need to check or verify your custom JWT before the 
    %% default verifier, It's better to use this hook with priority 
    %% little than 100 and return bool() or {stop, bool()} in your own 
    %% callback function.
    ejabberd_hooks:add(check_decoded_jwt, Host, ?MODULE, check_decoded_jwt, 100),
    case ejabberd_option:jwt_key(Host) of
	undefined ->
	    ?ERROR_MSG("Option jwt_key is not configured for ~ts: "
		       "JWT authentication won't work", [Host]);
	_ ->
	    ok
    end.

stop(Host) ->
    ejabberd_hooks:delete(check_decoded_jwt, Host, ?MODULE, check_decoded_jwt, 100).

plain_password_required(_Host) -> true.

store_type(_Host) -> external.

-spec check_password(binary(), binary(), binary(), binary()) -> 
    {ets_cache:tag(), boolean() | {stop, boolean()}}.
check_password(User, AuthzId, Server, Token) ->
    %% MREMOND: Should we move the AuthzId check at a higher level in
    %%          the call stack?
    if AuthzId /= <<>> andalso AuthzId /= User ->
            {nocache, false};
       true ->
            if Token == <<"">> -> {nocache, false};
               true ->
                    Res = check_jwt_token(User, Server, Token),
                    Rule = ejabberd_option:jwt_auth_only_rule(Server),
                    case acl:match_rule(Server, Rule,
                                        jid:make(User, Server, <<"">>)) of
                        deny ->
                            {nocache, Res};
                        allow ->
                            {nocache, {stop, Res}}
                    end
            end
    end.

user_exists(User, Host) ->
  %% Checking that the user has an active session
  %% If the session was negociated by the JWT auth method then 
  %% we define that the user exists %% Any other cases will return 
  %% that the user doesn't exist
  {nocache, case ejabberd_sm:get_user_info(User, Host) of
              [{_, Info}] -> 
                proplists:get_value(auth_module, Info) == ejabberd_auth_jwt;
              _ -> false
            end}.

use_cache(_) ->
    false.

%%%----------------------------------------------------------------------
%%% 'ejabberd_hooks' callback
%%%----------------------------------------------------------------------
check_decoded_jwt(true, Fields, _Signature, Server, User) ->
    JidField = ejabberd_option:jwt_jid_field(Server),
    case maps:find(JidField, Fields) of
        {ok, SJid} when is_binary(SJid) ->
            try
                JID = jid:decode(SJid),
                JID#jid.luser == User andalso JID#jid.lserver == Server
            catch error:{bad_jid, _} ->
                false
            end;
        _ -> % error | {ok, _UnknownType}
            false
    end;
check_decoded_jwt(Acc, _, _, _, _) ->
    Acc.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------
check_jwt_token(User, Server, Token) ->
    % validate is client is app user 
    logger:info("~s", 
	            [jiffy:encode(
                  #{'mod' => ?MODULE,
                    'fun' => ?FUNCTION_NAME,
                    'jid' => <<User/binary, $@, Server/binary>>,
                    'jwt' => Token,
                    'type' => <<"auth_info">>
                  })
		    ]),
    case verify_jwt(Server, User, Token, redis) of
        true ->
            JWK = ejabberd_option:jwt_key(Server),
            logger:debug("secret.jwt k ~p", [JWK]),

            try jose_jwt:verify(JWK, Token) of
                {true, {jose_jwt, Fields}, Signature} ->
                    check_claims(Fields, Signature, Server, User);
                {false, _, _} ->
                    false
            catch
                A:B ->
                    logger:info("jwt verification failed for user ~p@~p~n 
                           JWK and token: ~p~n with error: ~p",
                           [User, Server, {JWK, Token}, {A, B}]),

                    false
            end;
        false -> 
            false
    end.

check_claims(Fields, Signature, Server, User) ->
    Now = erlang:system_time(second),

    logger:info("jwt_fields => ~p", [Fields]),

    case maps:find(<<"exp">>, Fields) of
        error ->
            %% No expiry in token => We consider token invalid:
            false;
        {ok, Exp} ->
            logger:info("~p",
                        [jiffy:encode(
                            #{'mod' => ?MODULE,
                              'fun' => ?FUNCTION_NAME,
                              'now' => Now,
                              'exp' => Exp,
                              'type' => <<"claims_info">>
                            })
                        ]),

            if Exp > Now ->
                ejabberd_hooks:run_fold(
                                check_decoded_jwt,
                                Server,
                                true,
                                [Fields, Signature, Server, User]);
            true ->
                %% return false, if token has expired
                logger:warning("auth token has expired at ~p, 
                                current time is ~p~n", [Exp, Now]),
                false
            end
    end.

% Client should have jwt token in redis & db via gateway if no jwt token 
% in cache check sql as a fallback if not found consider the 
% token is invalid::unauth

verify_jwt(Server, User, Key, redis) ->
    Res = ejabberd_redis:q([<<"GET">>, Key]),
    logger:debug("redis:: GET ~p => ~p", [Key, Res]),
    case Res of
        {ok, ErUser} when is_binary(ErUser) ->
            User =:= ErUser;
        {_, _} -> 
            (fun verify_jwt/4)
            (Server, User, Key, db)
    end;
verify_jwt(Server, User, Token, db) ->
    logger:info(
    "verify token=> ~p in sql for user=> ~p", [Token, User]),

    Q = ?SQL("SELECT @(username)s FROM chat_access_tokens
              WHERE token=%(Token)s"),

    case ejabberd_sql:sql_query(Server, Q) of
        {selected, []} -> false;
        {selected, [{SqlUser}]} ->
            User =:= SqlUser 
            andalso 
            insert_token_in_redis(Token, jid:make(User, Server))
    end.

insert_token_in_redis(Token, Jid) ->
    Res = ejabberd_redis:q([<<"SET">>, Token, jid:to_string(Jid)]),
    logger:debug("redis:: SET ~p => ~p", [Token, Res]),
    case Res of
        {ok, <<"OK">>} -> true;
        {_, _} -> false
    end.
