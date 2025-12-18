%% name of module must match file name
-module(fly_add_timestamp).

-author("Johan Vorster").

%% Every ejabberd module implements the gen_mod behavior
%% The gen_mod behavior requires two functions: start/2 and stop/1
-behaviour(gen_mod).
-define(EJABBERD_DEBUG, true).
%% public methods for this module
-export([start/2, stop/1, depends/2,mod_options/1, mod_opt_type/1, filter_packet/1, filter_packet_receive/1, now_to_microseconds/1]).

%% included for writing to ejabberd log file
-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").

start(Host, _Opt) ->
  ejabberd_hooks:add(user_send_packet, Host,
    ?MODULE, filter_packet, 25),
  ejabberd_hooks:add(user_receive_packet, Host,
    ?MODULE, filter_packet_receive, 25),
ok.

stop(Host) ->
  ejabberd_hooks:delete(user_send_packet, Host,
    ?MODULE, filter_packet, 25),
  ejabberd_hooks:delete(user_receive_packet, Host,
    ?MODULE, filter_packet_receive, 25),
  ok.

filter_packet({#message{from = From,to = To} = XML, State} = _Acc) ->
  #jid{user = TUser, lserver = LServer} = To,
  #jid{user = FUser, lserver = _FServer} = From,
    Type = XML#message.type,
    %% Add timestamp to chat message and where no DataTag exist
    case Type of
      chat ->
        case fly_mod_utils:is_carbon_copy(XML) of
          false ->
                case fxml:get_subtag(xmpp:encode(XML),<<"composing">>) of
                  false ->
                    case fxml:get_subtag(xmpp:encode(XML),<<"gone">>) of
                      false ->
                        Delivered = xmpp:get_subtag(XML, #delivered{}),
                      if Delivered =:= false ->
                          Seen = xmpp:get_subtag(XML, #seen{}),
                            if Seen =:= false ->
                            NewXMl = XML;
                            true ->
                            {seen,Id,_,_Time,_,GroupId} = Seen,
                            ?LOG_INFO("update seen"),
                            case catch fly_mod_utils:update_seen(From, TUser, Id, GroupId) of
                              {updated,_} ->
                            case catch fly_mod_utils:message_status(LServer, Id, TUser) of
                                    {selected, _, []} ->
                                      GStatus = <<"0">>;
                                    {selected, _, [[GroupStatus]]} ->
                                      GStatus = GroupStatus;
                                    _ ->
                                      GStatus = <<"0">>
                                  end;
                          _ ->
                          GStatus = <<"0">>
                          end,
                          XMLNewTag = #xmlel{name = <<"seen">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:receipts">>}, {<<"id">>, Id},{<<"message_status">>, GStatus}, {<<"group_id">>, GroupId}],
                            children = []},
                          NewSeenXMl = fxml:replace_subtag( xmpp:encode(XMLNewTag),xmpp:encode(XML)),
                          NewXMl = xmpp:decode(NewSeenXMl)
                          end;
                          true ->
                          {delivered,Id,_,_Time,GroupId} = Delivered,
                          case catch  fly_mod_utils:update_delivery(From, TUser, Id, GroupId) of
                            {updated,_} ->
                                    case catch fly_mod_utils:message_status_new(LServer, Id, TUser) of
                                    {selected, _, []} ->
                                      DGStatus = <<"0">>;
                                    {selected, _, [[DGroupStatus, _RowId]]} ->
                                      DGStatus = DGroupStatus;
                                    _ ->
                                      DGStatus = <<"0">>
                                    end;
                            _ ->
                          DGStatus = <<"0">>
                          end,
                          XMLNewTag = #xmlel{name = <<"delivered">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:receipts">>}, {<<"id">>, Id},{<<"message_status">>, DGStatus}, {<<"group_id">>, GroupId}],
                            children = []},
                          NewDeliveyXMl = fxml:replace_subtag( xmpp:encode(XMLNewTag),xmpp:encode(XML)),
                          NewXMl = xmpp:decode(NewDeliveyXMl)
                        end,
                        Return = add_timestamp(NewXMl);
                      _ ->
                        Return = XML
                    end;
              _ ->
                Return = XML
            end;
          _ ->
            Return = XML
        end;
      receipts->
        Return = add_timestamp(XML);
      normal ->
        Return = add_timestamp(XML);
      _ ->
        Return = XML
    end,
    {Return,State};
filter_packet(Acc) ->
  Acc.

filter_packet_receive({#message{from = _From,to = To} = XML, State} = _Acc) ->
Type = XML#message.type,
#jid{user = TUser, lserver = LServer} = To,
  case Type of
      normal ->
        if To =:= <<"">> ->
          Return = XML;
          To =:= <<>> ->
          Return = XML;
        true ->
          Return = add_timestamp(XML)
      end;
    _ ->
    %   Seen = fxml:get_subtag(xmpp:encode(XML),<<"seen">>),
    %   if Seen =/= false andalso  LServer =:= <<"weiilla-xmpp.mirrorfly.com">> ->
    %   ?INFO_MSG("Seen log ~p",[XML]);
    % true ->
    %   ok
    % end,
      Return = XML
end,
  {Return,State};
filter_packet_receive(Acc) ->
  Acc.

add_timestamp(XML) ->
  GetTimestamp = xmpp:get_subtag(XML, #timestampmsg{}),
        if GetTimestamp =:= false ->
          Timestamp = now_to_microseconds(erlang:now()),
          FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
          XMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
            children = []},
          TimeStampedPacket = fxml:append_subtags(xmpp:encode(XML), [XMLTag]),
          Return = xmpp:decode(TimeStampedPacket);
          true ->
            Return = XML
        end.

now_to_microseconds({Mega, Sec, Micro}) ->
  %%Epoch time in milliseconds from 1 Jan 1970
  (Mega * 1000000 + Sec) * 1000000 + Micro.

depends(_, _) ->
  [].

mod_options(_Host) ->
[].

mod_opt_type(iqdisc) -> fun gen_iq_handler:check_type/1;
mod_opt_type(db_type) -> fun(T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(_) -> [db_type, iqdisc].

