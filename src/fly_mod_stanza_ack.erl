%%%============================================================================
%%% File    : mod_stanza_ack.erl
%%% Author  : Kay Tsar <kay@mingism.com>
%%% Purpose : Message Receipts XEP-0184 0.5
%%% Created : 25 May 2013 by Kay Tsar <kay@mingism.com>
%%% Usage   : Add the following line in modules section of ejabberd.cfg:
%%%              {mod_stanza_ack,  [{host, "zilan"}]}
%%% Copyright (C) 2013-The End of Time   Mingism
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%===========================================================================

-module(fly_mod_stanza_ack).

  -behaviour(gen_mod).


-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").

-type host() :: string().
-type name() :: string().
-type value() :: string().
-type opts() :: [{name(), value()}, ...].

%%-define(NS_RECEIPTS, <<"urn:xmpp:receipts">>).
-define(EJABBERD_DEBUG, true).


%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([start/2, stop/1,depends/2, mod_options/1]).
-export([on_user_send_packet/1, send_ack_response/4, store_in_table/12, should_acknowledge_on_send/1, should_acknowledge_on_receive/1, should_acknowledge_on_receipts/1]).
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
    ejabberd_hooks:add(user_send_packet, Host, ?MODULE, on_user_send_packet, 80),
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

    ejabberd_hooks:delete(user_send_packet, Host, ?MODULE, on_user_send_packet, 80).

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
  Substring = string:str(binary_to_list(LResource),binary_to_list(<<"Mobile-">>)),
      if Substring =:= 1 ->
        MResource = fly_mod_utils:get_device_from_resource(LResource);
      true ->
        MResource = <<"">>
      end,
  #jid{user = TUser, lserver = TServer} = To,

    MessageId = Packet#message.id,
  ContentAcknowledge = xmpp:get_subtag(Packet, #chatcontent{}),
  if (ContentAcknowledge =:= false) or (Type =:= normal)  ->
    BlockUser = <<"0">>,
      ok;
    true ->
      case should_acknowledge_on_send(Packet) of
        S when (S == message_acknowledge) ->
          IdValue = xmpp:get_id(Packet),
          ChatType = xmpp:get_type(Packet),
          if ContentAcknowledge == false ->
            MessageType = <<"">>,
            Topicid = <<"">>,
            MetaData = <<"">>,
            EditMsgid = MessageId;
            true ->
              {_,_,_,_, MessageType,Topicid, MetaData, EditMsgid,_} = ContentAcknowledge
          end,
          case catch fly_mod_utils:check_blockeduser(FServer, FUser, TUser) of
            {selected, _, []} ->
              UserBlocked = <<"0">>;
            {selected, _, _ResultSet} ->
              UserBlocked = TUser
          end,
          if UserBlocked =:= <<"0">> ->
          case catch fly_mod_utils:check_singlechatenabled(FServer, TUser) of
            {selected, _, []} ->
              UserDisabled = <<"0">>;
            {selected, _, _Result} ->
              UserDisabled = TUser
          end
        end,
        BlockUser = UserDisabled,
          SUser = case Type of
                    chat -> FUser;
                    groupchat -> ok
                  end,
          SType = erlang:atom_to_binary(ChatType, utf8),
          BarePeer = TUser,
          MsgContent = xmpp:get_text(Packet#message.body),
          send_ack_response(From, To, IdValue, <<"acknowledge">>),
          NewPacket = xmpp:set_from_to(Packet,From, To),
          GetTimestamp = xmpp:get_subtag(Packet, #timestampmsg{}),
          if GetTimestamp =:= false ->
            Timestamp = now_to_microseconds(erlang:now()),
            FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
            XMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
              children = []},
            TimeStampedPacket = fxml:append_subtags(NewPacket, [XMLTag]);
            true ->
              {_, _, FlatTimeStamp} = GetTimestamp,
              TimeStampedPacket = NewPacket
          end,
          store_in_table(FServer,BarePeer,SUser,MessageId,MsgContent,SType,MessageType,Topicid, MetaData,BlockUser, EditMsgid, FlatTimeStamp),

        if BlockUser == <<"0">> ->
          case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
            true ->
              mod_offline:store_packet({TimeStampedPacket ,xmpp:decode(TimeStampedPacket)});
            false ->
              ok
          end,
            case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
            true ->
            fly_mod_offline_push:send_offline_message({_C2SState,TimeStampedPacket});
            false ->
              ok
            end;
        true ->
          ok
        end,

        if MetaData =:= <<>> ->
            Metadata = <<"{}">>;
          MetaData =:= <<"">> ->
            Metadata = <<"{}">>;
        true ->
            Metadata = MetaData
        end,

        fly_mod_utils:insert_status(From, To, IdValue,MessageType, Topicid,  Metadata, erlang:atom_to_binary(ChatType, utf8),<<"">>,BlockUser,xmpp:get_text(Packet#message.body),FlatTimeStamp, EditMsgid);
        S when (S == false) ->
          BlockUser = <<"0">>,
          ok
      end
  end,
  %%Save the Message to temp storage for 10 sec when server
  case should_acknowledge_on_receive(Packet) of
    T when (T == message_delivered) ->
      ElementAcknowledge = xmpp:get_subtag(Packet, #delivered{}),
      {delivered,Id,_,_,_Time} = ElementAcknowledge,
      send_ack_response(From, To, Id, <<"delivered">>),
      fly_mod_utils:remove_offline(FServer, Id, MResource),
      NewReceivePacket = xmpp:set_from_to(Packet,From, To),
      GetReceiveTimestamp = xmpp:get_subtag(Packet, #timestampmsg{}),
      if GetReceiveTimestamp =:= false ->
        ReceivedTimestamp = now_to_microseconds(erlang:now()),
        ReceivedFlatTimeStamp = lists:flatten(io_lib:format("~p", [ReceivedTimestamp])),
        ReceivedXMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(ReceivedFlatTimeStamp)}],
          children = []},
        ReceivedTimeStampedPacket = fxml:append_subtags(xmpp:encode(NewReceivePacket), [ReceivedXMLTag]);
        true ->
          ReceivedTimeStampedPacket = NewReceivePacket
      end,
      case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
        true ->
          mod_offline:store_packet({ReceivedTimeStampedPacket,xmpp:decode(ReceivedTimeStampedPacket)});
        false ->
          ok
      end;

    T when (T == message_seen) ->
      ElementAcknowledge = xmpp:get_subtag(Packet, #seen{}),
      {seen,Id,_,_,_Time} = ElementAcknowledge,
      send_ack_response(From, To, Id,  <<"seen">>),
      NewSeenPacket = xmpp:set_from_to(Packet,From, To),
      GetSeenTimestamp = xmpp:get_subtag(Packet, #timestampmsg{}),
      if GetSeenTimestamp =:= false ->
        SeenTimestamp = now_to_microseconds(erlang:now()),
        SeenFlatTimeStamp = lists:flatten(io_lib:format("~p", [SeenTimestamp])),
        SeenXMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(SeenFlatTimeStamp)}],
          children = []},
        SeenTimeStampedPacket = fxml:append_subtags(xmpp:encode(NewSeenPacket), [SeenXMLTag]);
        true ->
          SeenTimeStampedPacket = NewSeenPacket
      end,
      fly_mod_utils:update_recent_group_unread_chat(Id,FUser,FServer),
      case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
        true ->
          mod_offline:store_packet({SeenTimeStampedPacket,xmpp:decode(SeenTimeStampedPacket)});
        false ->
          ok
      end;
    T when (T == message_recall) ->
      ElementAcknowledge = xmpp:get_subtag(Packet, #recall{}),
      {_,Id,_Time,_ChatType,_GroupId} = ElementAcknowledge,
      send_ack_response(From, To, Id,  <<"recall">>),
      NewRecallPacket = xmpp:set_from_to(Packet,From, To),
      GetRecallTimestamp = xmpp:get_subtag(Packet, #timestampmsg{}),
      if GetRecallTimestamp =:= false ->
        RecallTimestamp = now_to_microseconds(erlang:now()),
        RecallFlatTimeStamp = lists:flatten(io_lib:format("~p", [RecallTimestamp])),
        RecallXMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(RecallFlatTimeStamp)}],
          children = []},
        RecallTimeStampedPacket = fxml:append_subtags(NewRecallPacket, [RecallXMLTag]);
        true ->
          RecallTimeStampedPacket = NewRecallPacket
      end,
      case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
        true ->
          mod_offline:store_packet({RecallTimeStampedPacket,xmpp:decode(RecallTimeStampedPacket)});
        false ->
          ok
      end,
      TResources = ejabberd_sm:get_user_resources(TUser, TServer),
      if length(TResources) =:= 0 ->
        ok;
      true ->
        fly_mod_offline_push:send_offline_message({_C2SState,RecallTimeStampedPacket})
      end,
    fly_mod_utils:update_recall(From, Id);
    T when (T == ok) ->
      ok;
    _ ->
      ok
  end,
  case should_acknowledge_on_receipts(Packet) of
    U when (U == received_receipt) ->
      ReceiptsElementAcknowledge = xmpp:get_subtag(Packet, #acknowledge{}),
      if ReceiptsElementAcknowledge == false ->
        ok;
        true ->
          {_,ReceiptId,_BroadcastId,_SendTo,_MessageType} = ReceiptsElementAcknowledge,

          fly_mod_utils:remove_offline(FServer, ReceiptId, MResource)
      end;
    U when (U == seen_receipt) ->
      ReceiptsElementAcknowledge = xmpp:get_subtag(Packet, #acknowledge{}),
      if ReceiptsElementAcknowledge == false ->
        ok;
        true ->
          {_,ReceiptId,_BroadcastId,_SendTo,_MessageType} = ReceiptsElementAcknowledge,

          fly_mod_utils:remove_offline(FServer, ReceiptId, MResource)
      end;
    U when (U == recall_receipt) ->
      ReceiptsElementAcknowledge = xmpp:get_subtag(Packet, #acknowledge{}),
      if ReceiptsElementAcknowledge == false ->
        ok;
        true ->
          {_,ReceiptId,_BroadcastId,_SendTo,_MessageType} = ReceiptsElementAcknowledge,

          fly_mod_utils:remove_offline(FServer, ReceiptId, MResource)

      end;
    U when (U == ok) ->
      ok;
    _ ->
      ok
  end,
  if BlockUser == <<"0">> ->
  {Packet,_C2SState};
  true ->
    {drop,_C2SState}
end;
on_user_send_packet(Acc) ->
  Acc.

store_in_table(FServer, BarePeer, SUser, MessageId, MsgContent, SType, MessageType, Topicid, Metadata, BlockUser, EditMsgid, FlatTimeStamp) ->
  if Metadata =:= <<>> ->
    MetaData = <<"{}">>;
  true ->
    MetaData = Metadata
  end,
  case catch fly_mod_utils:update_recent_chat(FServer,BarePeer,SUser,MessageId,SUser,MsgContent,SType,MessageType,Topicid, MetaData, <<"0">>, EditMsgid, FlatTimeStamp) of
                {updated,1} ->
                  ok;
                {updated,0}->
                  fly_mod_utils:insert_recent_chat(FServer,BarePeer,SUser,MessageId,SUser,MsgContent,SType,MessageType,Topicid, MetaData, <<"">>,<<"0">>,FlatTimeStamp );
                _ ->
                  ok
              end,
              ClientName = gen_mod:get_module_opt(FServer, fly_mod_user_activities, client_name),
              [[Interception]] = ets:match(ClientName, {interception, '$1'}),
          if (BlockUser == <<"0">>  orelse BlockUser == <<>>) andalso Interception =:= <<"0">> ->
            case catch fly_mod_utils:update_recent_chat(FServer,SUser,BarePeer,MessageId,SUser,MsgContent,SType,MessageType,Topicid, MetaData, <<"1">>,EditMsgid, FlatTimeStamp) of
              {updated,1} ->
                ok;
              {updated,0}->
                fly_mod_utils:insert_recent_chat(FServer,SUser,BarePeer,MessageId,SUser,MsgContent,SType,MessageType,Topicid,MetaData, <<"">>,<<"1">>,FlatTimeStamp);
              _ ->
                ok
            end;
          true ->
              ok
          end,
  if Topicid =/= <<"">> ->
    update_recent_topic(FServer, BarePeer, SUser, MessageId, MsgContent, SType, MessageType, Topicid, MetaData, BlockUser, FlatTimeStamp);
    true ->
      ok
    end.

update_recent_topic(FServer, BarePeer, SUser, MessageId, MsgContent, SType, MessageType, Topicid, Metadata, BlockUser, FlatTimeStamp)->

if Metadata =:= <<>> ->
    MetaData = <<"{}">>;
  true ->
    MetaData = Metadata
  end,
  case catch fly_mod_utils:update_recent_chat_topic(FServer,BarePeer,SUser,MessageId,SUser,MsgContent,SType,MessageType,Topicid, MetaData, <<"0">>,FlatTimeStamp) of
            {updated,1} ->
              ok;
            {updated,0}->
              fly_mod_utils:insert_recent_chat_topic(FServer,BarePeer,SUser,MessageId,SUser,MsgContent,SType,MessageType,Topicid, MetaData, <<"">>,<<"0">>,FlatTimeStamp );
            _ ->
              ok
          end,
          ClientName = gen_mod:get_module_opt(FServer, fly_mod_user_activities, client_name),
          [[Interception]] = ets:match(ClientName, {interception, '$1'}),
      if (BlockUser == <<"0">>  orelse BlockUser == <<>>) andalso Interception =:= <<"0">> ->
        case catch fly_mod_utils:update_recent_chat_topic(FServer,SUser,BarePeer,MessageId,SUser,MsgContent,SType,MessageType,Topicid, MetaData, <<"1">>,FlatTimeStamp) of
          {updated,1} ->
            ok;
          {updated,0}->
            fly_mod_utils:insert_recent_chat_topic(FServer,SUser,BarePeer,MessageId,SUser,MsgContent,SType,MessageType,Topicid,MetaData, <<"">>,<<"1">>,FlatTimeStamp);
          _ ->
            ok
        end;
        true ->
          ok
      end.

should_acknowledge_on_send(Packet) ->
  if Packet#message.body =:= []  ->
    false ;
    true ->
      message_acknowledge
  end.

should_acknowledge_on_receive(Packet) ->
  Received = xmpp:get_subtag(Packet, #delivered{}),
  if Received =/= false ->
    message_delivered;
    true ->
      Seen = xmpp:get_subtag(Packet, #seen{}),
      if Seen =/= false ->
        message_seen;
        true ->
          Recall = xmpp:get_subtag(Packet, #recall{}),
          if Recall =/= false ->
            message_recall;
            true ->
              ok
          end
      end
  end.

should_acknowledge_on_receipts(Packet) ->
  ElementAcknowledge = xmpp:get_subtag(Packet, #acknowledge{}),
  if ElementAcknowledge == false ->
    ok;
    true ->
      {_,_,Type,_,_} = ElementAcknowledge,
      if Type == <<"delivered">> ->
        received_receipt;
        Type == <<"seen">> ->
          seen_receipt;
        Type == <<"recall">> ->
          recall_receipt;
        true ->
          ok
      end
  end.

now_to_microseconds({Mega, Sec, Micro}) ->
  %%Epoch time in milliseconds from 1 Jan 1970
  (Mega * 1000000 + Sec) * 1000000 + Micro.

send_ack_response(From, To, ReceiptId, Type) ->
  #jid{user = _FUser, lserver = ServerHost} = From,
  SentTo = jid:to_string(To),
  XmlBody = #xmlel{name = <<"acknowledge">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"id">>, ReceiptId}, {<<"sent_to">>, SentTo}, {<<"type">>, Type}],
      children = []},
  Proc = gen_mod:get_module_proc(ServerHost, ?MODULE),
  Msg = #message{from = To, to = From, type = chat, sub_els = [XmlBody]},
  gen_server:cast(Proc, {send_ack,Msg}).

depends(_, _) ->
  [].

mod_options(_) ->
  [].