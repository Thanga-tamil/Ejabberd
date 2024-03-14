%%%============================================================================
%%% File    : fly_mod_bot.erl
%%% Author  : venkatesh <venkatesh@ocntus.in>
%%% Purpose : Message Receipts XEP-0184 0.5
%%% Created : 16 Feb 2024 by Venkatesh <venkatesh@ocntus.in>
%%% Usage   : Add the following line in modules section of ejabberd.cfg:
%%%              {fly_mod_bot,  [{host, "zilan"}]}
%%%===========================================================================

-module(fly_mod_bot).

  -behaviour(gen_mod).


-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").

-type host() :: string().
-type name() :: string().
-type value() :: string().
-type opts() :: [{name(), value()}, ...].

%%-define(NS_RECEIPTS, <<"urn:xmpp:receipts">>).
-define(EJABBERD_DEBUG, true).
-define(BOTURL, <<"https://api.openai.com/v1/chat/completions">>).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([start/2, stop/1,depends/2, mod_options/1]).
-export([on_user_send_packet/1, send_ack_response/4,  should_acknowledge_on_send/1 ]).
%% gen_server callbacks.
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).
-record(state, {server_host = <<"">> :: binary(), permissions = dict:new() :: dict:dict()}).

%%%===================================================================
%%% API
%%%===================================================================
start(Host, Opts) ->
    gen_mod:start_child(?MODULE, Host, Opts).

stop(Host) ->
    gen_mod:stop_child(?MODULE, Host).

reload(_Host, _NewOpts, _OldOpts) ->
    ok.
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

start_link() ->
    Return = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []),
    io:format("start_link: ~p~n", [Return]),
    Return.

init([Host, _Opts]) ->
    ejabberd_hooks:add(user_send_packet, Host, ?MODULE, on_user_send_packet, 100),
    {ok, #state{server_host = Host}}.

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.

handle_cast({send_ack, Msg}, State) ->
    ejabberd_router:route(Msg),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, State) ->
    %% Note: we don't remove component_* hooks because they are global
    %% and might be registered within a module on another virtual host
    Host = State#state.server_host,

    ejabberd_hooks:delete(user_send_packet, Host, ?MODULE, on_user_send_packet, 100).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% ====================================================================
%% Internal functions
%% ====================================================================


% on_user_send_packet({#message{from = From, to = To,type = normal,
%   id = SubmissionID} = Packet, _C2SState}) ->
%   {_FUser, FServer, _} = jid:tolower(From),
%   IsValid = fly_mod_utils:validate_license(FServer, true, <<"chat">>),
%   if IsValid =:= true ->
%   case fxml:get_subtag(xmpp:encode(Packet),<<"composing">>) of
%     false ->
%     case fxml:get_subtag(xmpp:encode(Packet),<<"gone">>) of
%       false ->
%         send_ack_response(From, To, SubmissionID, <<"acknowledge">>, <<"">>, <<"">>);
%       _ ->
%         ok
%       end;
%     _ ->
%       ok
%     end,
%   {Packet,_C2SState};
% true ->
%     {drop,_C2SState}
% end;

%% Function triggers when receive message packets from sender
on_user_send_packet({#message{from = From,to = To,type = Type} = Packet, _C2SState}) ->
  #jid{user = FUser, lserver = FServer, lresource = LResource} = From,
  #jid{user = TUser, lserver = TServer} = To,
  IsValid = fly_mod_utils:validate_license(FServer, true, <<"chat">>),
  if IsValid =:= true ->
    MessageId = Packet#message.id,
  ContentAcknowledge = xmpp:get_subtag(Packet, #chatcontent{}),
  if (ContentAcknowledge =:= false) or (Type =:= normal)  ->
    {Packet,_C2SState};
    true ->
      case should_acknowledge_on_send(Packet) of
        S when (S == message_acknowledge) ->
          IdValue = xmpp:get_id(Packet),
          MsgContent = xmpp:get_text(Packet#message.body),

      DecryptedMessage = fly_mod_security:aes_decrpyt(binary_to_list(IdValue), MsgContent),
      Message1 = http_uri:decode(binary_to_list(DecryptedMessage)),
      ParsedMessageJson = jiffy:decode(response_to_binary(Message1)),
      MessageJson = proplists:get_value(<<"message">>, element(1, ParsedMessageJson)),

              AuthHeader = {"Authorization", "Bearer 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"},
              JSON = "{\"model\": \"gpt-4\",\"messages\": [ {\"role\": \"system\",\"content\": \"you are a content moderation engine in bank for arabic and english language. Identify all sensitive information like password & creditcards and offensive languages.Provide response in Json format only wihtout newline character  . always provide keyword senseitive True or false offensive true or false message reason\" }, {\"role\": \"user\",\"content\": \"" ++ binary_to_list(MessageJson)++ "\"}]}",
              Text = jiffy:decode(JSON),

    Base64Crypt = binary_to_list(http_uri:decode(jiffy:encode(Text))),

              Request = {"https://api.openai.com/v1/chat/completions", [{"Authorization", "Bearer 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"}], "application/json", Base64Crypt},
                try httpc:request(post, Request, [], []) of
                  {ok, {{_, 200, _}, _Headers, Body}} ->
                      ?INFO_MSG("Api response ~p", [Body]),
                      Json = jiffy:decode(Body),
                      Choices = proplists:get_value(<<"choices">>, element(1, Json)),
                      Choicesjson = jiffy:encode(hd(Choices)),

                     % Convert the binary string to a string
JsonString = binary_to_list(Choicesjson),

% Decode the JSON string
ParsedResponse = jiffy:decode(JsonString),

MessageJ = proplists:get_value(<<"message">>, element(1, ParsedResponse)),


 MessageJs = jiffy:encode(MessageJ),

%                      % Convert the binary string to a string
                     MessageJso = binary_to_list(MessageJs),

% Decode the JSON string
MsgResponse = jiffy:decode(MessageJso),

ContentJ = proplists:get_value(<<"content">>, element(1, MsgResponse)),

ContentJs = jiffy:encode(ContentJ),

%                      % Convert the binary string to a string
ContentJso = binary_to_list(ContentJs),

% Decode the JSON string
ContentResponse = jiffy:decode(ContentJso),
ContentResponseo = binary_to_list(ContentResponse),

% Decode the JSON string
ContentResponsed = jiffy:decode(ContentResponseo),

Sensitive = proplists:get_value(<<"sensitive">>, element(1, ContentResponsed)),
Offensive = proplists:get_value(<<"offensive">>, element(1, ContentResponsed)),
ReasonMsg = proplists:get_value(<<"message">>, element(1, ContentResponsed)),
?INFO_MSG("ReasonMsg ~p", [ReasonMsg]),
?INFO_MSG("Sensitive ~p", [Sensitive]),
?INFO_MSG("Offensive ~p", [Offensive]),


if(Sensitive =:= true) or (Offensive =:= true) ->
  MsgBody2 = create_msg(From, To, ReasonMsg, IdValue,Packet),
  ejabberd_router:route(To, From, MsgBody2),

      TResources = ejabberd_sm:get_user_resources(FUser, FServer),
      if length(TResources) =:= 0 ->
        mod_offline:store_packet({From, xmpp:decode(MsgBody2)});
      true ->
        ok
      end,
      {error, <<"Content not secred">>},
      {drop,_C2SState};
     (Sensitive =:= undefined) or (Offensive =:= undefined) ->
      ?INFO_MSG("Offensive undefined ~p", [Offensive]),
      on_user_send_packet({#message{from = From,to = To,type = Type} = Packet, _C2SState});
      true ->
        {Packet,_C2SState}
  end;


                  {ok, {{_, 400, _}, _, Body}} ->
                      ?INFO_MSG("INSIDE Sucess CASE 400", [jiffy:decode(response_to_binary(Body))]),
                      MsgBody2 = create_msg(From, To, <<"Invalid Contetn">> , IdValue,Packet),
                      error_logger:error_msg("Error in request. Reason was: Bad Request - ~p~n", [Body]),
                      ejabberd_router:route(To, From, MsgBody2),

      TResources = ejabberd_sm:get_user_resources(FUser, FServer),
      if length(TResources) =:= 0 ->
        mod_offline:store_packet({From, xmpp:decode(MsgBody2)});
      true ->
        ok
      end,
      {error, <<"Content not secred">>},
      {drop,_C2SState};

                  {ok, {{_, 401, _}, _, _}} ->
                      error_logger:error_msg("Error in request. Reason was: authorization error~n", []),
                      {error, auth_error},
                      MsgBody2 = create_msg(From, To, <<"Invalid Contetn">> , IdValue,Packet),
                      ejabberd_router:route(To, From, MsgBody2),

      TResources = ejabberd_sm:get_user_resources(FUser, FServer),
      if length(TResources) =:= 0 ->
        mod_offline:store_packet({From, xmpp:decode(MsgBody2)});
      true ->
        ok
      end,
      {error, <<"Content not secred">>},
      {drop,_C2SState};
                  {ok, {{_, Code, _}, _, _}} when Code >= 500 andalso Code =< 599 ->

                      {error, {retry, Code}},
                      MsgBody2 = create_msg(From, To, <<"Invalid Contetn">> , IdValue,Packet),
                      ejabberd_router:route(To, From, MsgBody2),

      TResources = ejabberd_sm:get_user_resources(FUser, FServer),
      if length(TResources) =:= 0 ->
        mod_offline:store_packet({From, xmpp:decode(MsgBody2)});
      true ->
        ok
      end,
      {error, <<"Content not secred">>},
      {drop,_C2SState};
                  {ok, {{_StatusLine, _, _}, _, _Body}} ->
                      error_logger:error_msg("Error in request. Reason was: timeout~n", []),
                      {error, timeout},
                      MsgBody2 = create_msg(From, To, <<"Invalid Contetn">> , IdValue,Packet),
                      ejabberd_router:route(To, From, MsgBody2),

      TResources = ejabberd_sm:get_user_resources(FUser, FServer),
      if length(TResources) =:= 0 ->
        mod_offline:store_packet({From, xmpp:decode(MsgBody2)});
      true ->
        ok
      end,
      {error, <<"Content not secred">>},
      {drop,_C2SState};
                  {error, Reason} ->
                      error_logger:error_msg("Error in request. Reason was: ~p~n", [Reason]),
                      {error, Reason},
                      MsgBody2 = create_msg(From, To, <<"Invalid Contetn">> , IdValue,Packet),
                      ejabberd_router:route(To, From, MsgBody2),

      TResources = ejabberd_sm:get_user_resources(FUser, FServer),
      if length(TResources) =:= 0 ->
        mod_offline:store_packet({From, xmpp:decode(MsgBody2)});
      true ->
        ok
      end,
      {error, <<"Content not secred">>},
      {drop,_C2SState};
                  OtherError ->
                      error_logger:error_msg("Error in request. Reason was: ~p~n", [OtherError]),

                      {noreply, unknown},
                      MsgBody2 = create_msg(From, To, <<"Invalid Contetn">> , IdValue,Packet),
                      ejabberd_router:route(To, From, MsgBody2),

      TResources = ejabberd_sm:get_user_resources(FUser, FServer),
      if length(TResources) =:= 0 ->
        mod_offline:store_packet({From, xmpp:decode(MsgBody2)});
      true ->
        ok
      end,
      {error, <<"Content not secred">>},
      {drop,_C2SState}
              catch
                  Exception ->

                      error_logger:error_msg("Error in request. Exception ~p while calling URL: ~p~n", [Exception, ?BOTURL]),
                      MsgBody2 = create_msg(From, To, <<"Invalid Contetn">> , IdValue,Packet),
                      ejabberd_router:route(To, From, MsgBody2),

                    TResources = ejabberd_sm:get_user_resources(FUser, FServer),
                    if length(TResources) =:= 0 ->
                        mod_offline:store_packet({From, xmpp:decode(MsgBody2)});
                    true ->
                        ok
                    end,
                    {error, <<"Content not secred">>},
                    {drop,_C2SState},
                    {error, Exception}
              end;


        S when (S == false) ->
ok
      end
  end;
true ->
    {drop,_C2SState}
end;

on_user_send_packet(Acc) ->
  Acc.

  should_acknowledge_on_send(Packet) ->
    if Packet#message.body =:= []  ->
      false ;
      true ->
        message_acknowledge
    end.

now_to_microseconds({Mega, Sec, Micro}) ->
  %%Epoch time in milliseconds from 1 Jan 1970
  (Mega * 1000000 + Sec) * 1000000 + Micro.

response_to_binary(Json) when is_binary(Json) -> Json;
response_to_binary(Json) when is_list(Json) ->
  list_to_binary(Json).
send_ack_response(From, To, ReceiptId, Type) ->
  #jid{user = _FUser, lserver = ServerHost} = From,
  SentTo = jid:to_string(To),
  XmlBody = #xmlel{name = <<"acknowledge">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"id">>, ReceiptId}, {<<"sent_to">>, SentTo}, {<<"type">>, Type}],
      children = []},
  Proc = gen_mod:get_module_proc(ServerHost, ?MODULE),
  Msg = #message{from = To, to = From, type = chat, sub_els = [XmlBody]},
  gen_server:cast(Proc, {send_ack,Msg}).

create_msg(From, To, ReasonMsg, ReplyId,Packet)->
  MsgId = p1_rand:get_string(),
  #jid{user = FUser, lserver = FServer, lresource = LResource} = From,
  #jid{user = TUser, lserver = TServer} = To,

  ContentAcknowledge = xmpp:get_subtag(Packet, #chatcontent{}),
  if ContentAcknowledge == false ->
            MessageType = <<"">>,
            Topicid = <<"">>,
            MetaData = <<"">>,
            EditMsgid = ReplyId;
            true ->
              {_,_,_,_, MessageType,Topicid, MetaData, EditMsgid,_} = ContentAcknowledge
          end,
          GetTimestamp = xmpp:get_subtag(Packet, #timestampmsg{}),
          if GetTimestamp =:= false ->
            Timestamp = now_to_microseconds(erlang:now()),
            FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp]));

            true ->
              {_, _, FlatTimeStamp} = GetTimestamp
          end,
  fly_mod_utils:delete_message(To, ReplyId),
  case catch fly_mod_utils:get_last_messages(To, From, FUser) of
      {selected, _, []} ->
        LastMessageId = <<"">>,
        fly_mod_utils:delete_message_recentchat(FServer, TUser, FUser);
      {selected, _, [[MessageFrom,MessageTo, Message_id, Message_type, ChatType, Status, Recall_status, From_notification, To_notification, Message_notification, Created_at,Topic_id,Meta_data]]} ->
        LastMessageId = Message_id,
        if Message_type =:= <<"text">> ->
          case catch fly_mod_utils:get_message(FServer, ChatType, Message_id) of
            {selected, _, []} ->
              Body = <<"">>;
            {selected, _, [[Txt]]} ->
              Body = Txt
          end,
          MsgContent = Body;
        Message_type =:= <<"auto_text">> ->
          case catch fly_mod_utils:get_message(FServer, ChatType, Message_id) of
            {selected, _, []} ->
              Body = <<"">>;
            {selected, _, [[Txt]]} ->
              Body = Txt
          end,
          MsgContent = Body;
          Message_type =:= <<"0">> ->
          MsgContent = Message_notification;
        true ->
          MsgContent = Message_type
        end,
        if Meta_data =:= <<>> ->
            Metadata = <<"{}">>;
          Meta_data =:= <<"">> ->
            Metadata = <<"{}">>;
        true ->
            Metadata = Meta_data
        end,
      if(ChatType =:= <<"chat">>) ->
        if(MessageFrom =:= TUser) ->
          fly_mod_utils:update_deleted_recent_chat(FServer,MessageTo,TUser,Message_id,From_notification,MsgContent,ChatType,Message_type,To_notification,Status, Recall_status,Created_at, MessageFrom,Topic_id,Metadata);
        true ->
          fly_mod_utils:update_deleted_recent_chat(FServer,MessageFrom,TUser,Message_id,From_notification,MsgContent,ChatType,Message_type,To_notification,Status, Recall_status,Created_at, MessageFrom,Topic_id,Metadata)
        end;
      true ->
        fly_mod_utils:update_deleted_grouprecent_chat(FServer,From_notification,MessageFrom,Message_id,From_notification,MsgContent,ChatType,Message_type,To_notification,Status, Recall_status,Created_at, TUser,Topic_id,Metadata)
      end
    end,
  NewMessageType = <<"irrelevant">>,
  BodyString = fly_mod_security:aes_encrpyt_license(MsgId, <<"ddc0f15cc2c90fca">>, ReasonMsg,ReplyId,NewMessageType),
  MsgBody3 = XML = #xmlel{name = <<"message">>, attrs = [{<<"xmlns">>, <<"jabber:client">>},{<<"from">>,  jid:to_string(To)}, {<<"to">>,  jid:to_string(From)},
  {<<"type">>, <<"chat">>},{<<"id">>, MsgId}],
children = [
  #xmlel{name = <<"chatcontent">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:content">>},{<<"message_type">>, <<"irrelevant">>},{<<"edit_msg_id">>, MsgId},
    {<<"block_user">>, <<"0">>}],children = []},
  #xmlel{name = <<"body">>, attrs = [{<<"message_type">>, <<"irrelevant">>}], children = [{xmlcdata, BodyString}]}]},
ReceivedTimestamps = now_to_microseconds(erlang:now()),
ReceivedFlatTimeStamps = lists:flatten(io_lib:format("~p", [ReceivedTimestamps])),
ReceivedMsgTags = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(ReceivedFlatTimeStamps)}], children = []},
fly_mod_stanza_ack:store_in_table(FServer,TUser,FUser,MsgId,BodyString,<<"chat">>,<<"irrelevant">>,<<"">>,  <<"{}">> ,<<"0">>,MsgId, ReceivedFlatTimeStamps),
fly_mod_utils:insert_status(To, From, MsgId,<<"irrelevant">>,<<"">>, <<"{}">>, <<"chat">>,<<"">>,<<"0">>,BodyString,ReceivedFlatTimeStamps,MsgId),
fly_mod_utils:delete_message(To, MsgId),
MsgBody2 = fxml:append_subtags(MsgBody3, [ReceivedMsgTags]).

depends(_, _) ->
  [].

mod_options(_) ->
  [].