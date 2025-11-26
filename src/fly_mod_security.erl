%%%-------------------------------------------------------------------
%%% File       : mod_security.erl
%%% Author     : Contus <ejabberd@contus.in>
%%% Purpose    : Encrypt and Decrypt the Messages using crypto.
%%% Created At : 13. Oct 2016 1:13 PM
%%%-------------------------------------------------------------------
-module(fly_mod_security).

-behaviour(ejabberd_config).

-author("Contus").

-export([depends/2, mod_options/1, aes_decrpyt/2,aes_encrpyt_license/3,has_more_resources/3,get_user_resource/3,aes_encrpyt_license/5,
  close_sessions/3, aes_decrpyt_license/3,aes_encrpyt_group_desc_notifier/3]).
-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").
-define(AES256_BLOCK_SIZE, 16).
-define(EJABBERD_DEBUG, true).

%%%----------------------------------------------------------------------
%%% Here we can implement all our custom query methods for the custom modules
%%% Method 	: check_user_exists
%%% Params	: LServer,User,Contact
%%% Author  : Contus <ejabberd@contus.in>
%%% Purpose : Check whether the user is exist or not in the particular server
%%%----------------------------------------------------------------------
%% hash the key
%%
%% @param list Key
%% @return list
get_hash_key(Key) ->
  <<KeyHash:256/big-unsigned-integer>> = crypto:hash(sha256, Key),
  string:sub_string(lists:flatten(io_lib:format("~64.16.0b", [KeyHash])), 1, 32).

%% de pad the crypted binary
%% covert binary to string
%%
%% @param binary Bin
%% @return list
depad(Bin) ->
  Len = byte_size(Bin),
  Pad = binary:last(Bin),
  case Pad =< 16 of
    true ->
      %% The last byte less-equal than our block size and hence represents a padding value
      BinPad = list_to_binary(lists:duplicate(Pad, Pad)),
      %% verify the padding is indeed k values of k and return the unpadded data
      DataLen = Len - Pad,
      case Bin of
        <<Data:DataLen / binary, BinPad / binary>> ->
          Data;
        _ ->
          {error, "Data not properly padded"}
      end;
    false ->
      %% The last byte is greater than our block size; we interpret as no padding
      Bin
  end.


%% decrypted the encode value(only AES CBC 256)
%%
%% @param list Key
%% @param list Base64Crypt
%% @return mixed
aes_decrpyt(Key, Base64Crypt) ->
  Decrypt = crypto:crypto_one_time(aes_256_cbc, get_hash_key(Key), <<"ddc0f15cc2c90fca">>, base64:decode(Base64Crypt),false ),

  if is_binary(Decrypt)
    ->
    depad(Decrypt);
    true ->
      false
  end.

  aes_encrpyt_group_desc_notifier(Key, Iv, Base64Crypts) ->
    
    JSON = jiffy:encode(#{<<"message_type">> => <<"group_notifier_text">>,<<"message">> => Base64Crypts}),
    ?LOG_INFO("JSON ~p", [JSON]),

    Decrypt = crypto:crypto_one_time(aes_256_cbc,get_hash_key(binary_to_list(Key)),Iv,JSON,[{encrypt, true}, {padding, pkcs_padding}]),

    EncryptedText = base64:encode(Decrypt),

    ?INFO_MSG("EncryptedTexts ~p", [EncryptedText]),
    
    EncryptedText.

  aes_encrpyt_license(Key, Iv, Base64Crypts) ->

    JSON = "{\"message_type\":\"auto_text\",\"message\":\"" ++ binary_to_list(Base64Crypts)++ "\"}",
    Text = jiffy:decode(JSON),
    Base64Crypt = binary_to_list(http_uri:decode(jiffy:encode(Text))),
    % ?INFO_MSG("Base64Crypt ~p", [Base64Crypt]),
    Decrypt = crypto:crypto_one_time(aes_256_cbc, get_hash_key(binary_to_list(Key)), Iv, Base64Crypt, [{encrypt,true},{padding,pkcs_padding}]),
    EncryptedText = base64:encode(Decrypt).
    % ?INFO_MSG("EncryptedTexts ~p", [EncryptedText]),
    % DecryptedMessage = fly_mod_security:aes_decrpyt(binary_to_list(Key), EncryptedText),
    % ParsedMessageJson = jiffy:decode(http_uri:decode(binary_to_list(DecryptedMessage))),
    % ?INFO_MSG("ParsedMessageJson  ~p", [ParsedMessageJson]),
    % EncryptedText.

    aes_encrpyt_license(Key, Iv, Base64Crypts, ReplyId, MessageType) ->

    JSON = "{\"replyTo\":\"" ++ binary_to_list(ReplyId)++ "\",\"message_type\":\"" ++ binary_to_list(MessageType)++ "\",\"message\":\"" ++ binary_to_list(Base64Crypts)++ "\"}",
    Text = jiffy:decode(JSON),
    Base64Crypt = binary_to_list(http_uri:decode(jiffy:encode(Text))),
    ?INFO_MSG("Base64Crypt ~p", [Base64Crypt]),
    Decrypt = crypto:crypto_one_time(aes_256_cbc, get_hash_key(binary_to_list(Key)), Iv, Base64Crypt, [{encrypt,true},{padding,pkcs_padding}]),
    EncryptedText = base64:encode(Decrypt).

    pad_to4(Bin) ->
      Pad = size(Bin) rem 16,
      <<Bin/binary, 0:((4-Pad)*8)>>.

pad(Bin) ->
  Extra = 16  - (size(Bin) rem 16),
  %% io:format("S:~p E:~p~n",[size(Bin),Extra]),
  pad(Extra, Bin).

%% pad(K, Bin) -> Bin1
%%   K = 0..15 number of bytes to pad by

pad(0, Bin) ->
  %% have to add 15 random bytes and then a zero
  B1 = crypto:strong_rand_bytes(15),
  <<Bin/binary,B1/binary,0>>;
pad(K, Bin) ->
  B1 = crypto:strong_rand_bytes(K-1),
  <<Bin/binary,B1/binary,K>>.

aes_decrpyt_license(Key, Iv, Base64Crypt) ->
  Decrypt = crypto:crypto_one_time(aes_256_cbc, get_hash_key(Key), Iv, base64:decode(Base64Crypt), false),

  if is_binary(Decrypt) ->
    depad(Decrypt);
  true ->
    false
  end.



%% Get Resource segments
%%
%% @param binary Resource
%% @return list
get_resource_segments(Resource) ->

  string:tokens(binary_to_list(Resource),"-").

%% Check the audity one and audity two is same
%% Resource should in the format "AppName-Platform-Identifier"
%% Platform available are  mobile and web
%% only one session is allowed for a platform
%%
%% @param binary CurrentResource
%% @param binary OldResource
%% @return atom
is_same_platform(CurrentResource,OldResource) ->
  try
    if CurrentResource =:= OldResource ->
      no;
      true->
        [CurrentPlatform,_CurrentPlatformIdentifier] = get_resource_segments(CurrentResource),

        [OldPlatform,_OldPlatformIdentifier] = get_resource_segments(OldResource),

        if CurrentPlatform =:= OldPlatform ->
          yes;
          true ->
            no
        end
    end
  catch _:_ ->
    no
  end.

%% Check user has session with different resource
%% if exists lets send failure response
%% Note : ejabberd_sm:get_user_resources will not return resource untill the session is created
%%
%% @param record JID
%% @return number
has_more_resources(User, LServer,NewResource) ->

  length(lists:foldl(fun(SResource,Acc) ->


    case is_same_platform(NewResource,SResource) of
      yes ->
        close_sessions(User, LServer, SResource),
        Acc ++ [SResource];
      _ ->

        Acc
    end
                     end,[],ejabberd_sm:get_user_resources(User, LServer))).

get_user_resource(User, Server, NewResource) ->

  NewSubstring = string:str(binary_to_list(NewResource), binary_to_list(<<"Web">>)),

  lists:foreach(fun(SResource) ->
    if NewSubstring =:= 1 ->
      Substring =
        string:str(binary_to_list(SResource),
          binary_to_list(<<"Web">>));
      true ->
        Substring =
          string:str(binary_to_list(SResource),
            binary_to_list(<<"Mobile">>))
    end,

    if Substring =:= 1 ->
      if NewResource =/= SResource ->
        close_sessions(User, Server, SResource);
        true ->
          ok
      end ;

      true ->
        ok
    end
  end, ejabberd_sm:get_user_resources(User, Server)).

%%has_another_resources(User, LServer,NewResource) ->
%%lists:flatmap(fun(SResource) ->
%%    case is_same_platform(NewResource,SResource) of
%%        yes ->
%%            [session_exists];
%%        _ ->
%%            [new_session]
%%    end end, ejabberd_sm:get_user_resources(User, LServer)).


%% Check user has session with different resource
%% if exists lets send failure response
%% Note : ejabberd_sm:get_user_resources will not return resource untill the session is created
%%
%% @param record JID
%% @return number
close_sessions(LUser, LServer,SavedResource) ->
  case ejabberd_sm:get_session_pid(LUser, LServer, SavedResource)
  of
    Pid when is_pid(Pid) ->
      MessageId = fly_mod_utils:get_iq_message_id(10),
      From = jid:make(LUser, LServer, <<>>),
      To = jid:make(LUser, LServer, SavedResource),
      XmlBody = #xmlel{name = <<"message">>,
        attrs = [{<<"from">>,jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
        children = [#xmlel{name = <<"logout">>,
          attrs = [{<<"xmlns">>,  <<"urn:xmpp:receipts">>},  {<<"type">>, <<"logout">>}],
          children = []}]},

      ejabberd_router:route(From, To,XmlBody),
      ejabberd_c2s:close(Pid),
      ejabberd_sm:close_session(Pid, LUser, LServer,SavedResource);
    _ -> ok
  end.


depends(_, _) ->
  [].
mod_options(_Host) ->
[].
