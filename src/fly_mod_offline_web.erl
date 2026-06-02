%%%=================================================================
%%% File    : mod_offline_web.erl
%%% Author  : Venkatesh <venkatesh@contus.in>
%%% Purpose : Store Offline Messages from web to mobile
%%% Created : 7 July 2017 by Venkatesh <venkatesh@contus.in>
%%%==================================================================
-module(fly_mod_offline_web).

-behaviour(gen_mod).


%% API

-include("logger.hrl").
-include_lib("include/fly_log.hrl").
-include_lib("xmpp/include/xmpp.hrl").

-type host() :: string().
-type name() :: string().
-type value() :: string().
-type opts() :: [{name(), value()}, ...].

-define(EJABBERD_DEBUG, true).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start/2, stop/1,depends/2, mod_options/1]).
-export([on_user_send_packet/1]).

-spec start(host(), opts()) -> ok.

start(Host, _Opts) ->
  ejabberd_hooks:add(user_send_packet, Host, ?MODULE, on_user_send_packet, 70),
  ok.

-spec stop(host()) -> ok.
stop(Host) ->
  ejabberd_hooks:delete(user_send_packet, Host, ?MODULE,
    on_user_send_packet, 70),
  ok.

%% ====================================================================
%% Internal functions
%% ====================================================================

%% Function triggers when receive message packets from sender
on_user_send_packet({#message{from = From,to = To,type = Type, id = MessageId } = Pkt, _C2SState}) ->
    #jid{luser = FUser, lserver = FServer,lresource = FResource} = From,
    Packet = xmpp:encode(Pkt),
  IsValid = fly_mod_utils:validate_license(FServer, true, <<"chat">>),
  if IsValid =:= true ->
  GetTimestamp = xmpp:get_subtag(Pkt, #timestampmsg{}),
  if GetTimestamp =:= false ->
    Timestamp = now_to_microseconds(erlang:now()),
    FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
    XMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>},{<<"time">>, list_to_binary(FlatTimeStamp)}], children = []},
    TimeStampedPacket = fxml:append_subtags(Packet, [XMLTag]);
    true ->
      TimeStampedPacket = Packet
  end,
  Seen = xmpp:get_subtag(Pkt, #seen{}),
      if Seen =/= false ->
        store_offline_user_send(xmpp:decode(TimeStampedPacket), _C2SState,  From, To, MessageId);
      true ->
        ok
      end,
  Recall = xmpp:get_subtag(Pkt, #recall{}),
    if Recall =/= false ->
      store_offline_user_send(xmpp:decode(TimeStampedPacket), _C2SState, From, To, MessageId);
      true ->
      ok
    end,
  Delivered = xmpp:get_subtag(Pkt, #delivered{}),
    if Delivered =/= false ->
      store_offline_user_send(xmpp:decode(TimeStampedPacket), _C2SState, From, To, MessageId);
      true ->
      ok
    end,  
  case xmpp:get_text(Pkt#message.body) of
    <<>> ->
      ok;
    _ ->
      case fxml:get_subtag(Packet, <<"subject">>) of
      false ->
      store_offline_user_send(xmpp:decode(TimeStampedPacket), _C2SState, From, To, MessageId);
      _->
        ok
      end
  end,
  {Pkt,_C2SState};
true ->
    {drop,_C2SState}
end;
on_user_send_packet(Acc) ->
  Acc.

store_offline_user_send(Packet, _C2SState, #jid{luser = FUser, lserver = FServer, lresource = LResource} = From, To, MessageId) ->

  fly_mod_offline_push:send_own_offline_message(From, To, xmpp:encode(Packet)),
  
  case fly_mod_utils:get_mobile_user_message(FUser, FServer) of
    true ->
      {U, S, R} = jid:tolower(From),
      Sender = jid:make({U, S, R}),
      Dest = jid:make({U, S, <<>>}),
      
      case fly_mod_utils:is_carbon_copy(Packet) of 
        false ->
          NewPacket = build_forward_packet(From, Packet, Sender, Dest, sent),
          ContentAcknowledge = xmpp:get_subtag(Packet, #chatcontent{}),
          
          if (ContentAcknowledge =:= false)  -> 
            ok;
          true ->
            
            if ContentAcknowledge == false ->
              MessageType = <<"">>,
              Topicid = <<"">>,
              MetaData = <<"">>,
              MentionList = <<"">>,
              EditMsgid = MessageId;
            true ->
              {_,_,_,_, MessageType,Topicid, MetaData, EditMsgid,MentionList, DisappearAt ,_} = ContentAcknowledge
            end,

            if EditMsgid =/= MessageId ->
              ejabberd_sql:sql_query(FServer, [<<"delete from spool where username = '">>,FUser, <<"' and message_id ='">>,MessageId, <<"';">>]);
              true ->
                ok
            end

          end,
          ?LOGX(Packet, "::store 'sent' carbon copy in offline::"),
          mod_offline:store_packet({_C2SState, NewPacket});
        true ->
          ok
      end;
    false ->
      ok
  end.

% -spec build_forward_packet(jid(), message(), jid(), jid(), direction()) -> message().
build_forward_packet(JID, #message{type = T} = Msg, Sender, Dest, Direction) ->
  Forwarded = #forwarded{sub_els = [complete_packet(JID, Msg, Direction)]},
  Carbon = case Direction of
    sent -> #carbons_sent{forwarded = Forwarded};
    received -> #carbons_received{forwarded = Forwarded}
  end,
  #message{from = Sender, to = Dest, type = T, sub_els = [Carbon],
      meta = #{carbon_copy => true}}.

% -spec complete_packet(jid(), message(), direction()) -> message().
complete_packet(From, #message{from = undefined} = Msg, sent) ->
    %% if this is a packet sent by user on this host, then Packet doesn't
    %% include the 'from' attribute. We must add it.
    Msg#message{from = From};
complete_packet(_From, Msg, _Direction) ->
    Msg.

now_to_microseconds({Mega, Sec, Micro}) ->
  %%Epoch time in milliseconds from 1 Jan 1970
  (Mega * 1000000 + Sec) * 1000000 + Micro.

depends(_, _) ->
  [].

mod_options(_) ->
[].