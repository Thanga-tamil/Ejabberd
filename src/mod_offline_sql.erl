%%%-------------------------------------------------------------------
%%% File    : mod_offline_sql.erl
%%% Author  : Evgeny Khramtsov <ekhramtsov@process-one.net>
%%% Created : 15 Apr 2016 by Evgeny Khramtsov <ekhramtsov@process-one.net>
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

-module(mod_offline_sql).


-behaviour(mod_offline).

-export([init/2, store_message/1, pop_messages/3, remove_expired_messages/1,
	 remove_old_messages/2, remove_user/2, read_message_headers/2,
	 read_message/3, remove_message/3, read_all_messages/2,
	 remove_all_messages/2, count_messages/2, import/1, export/1, remove_old_messages_batch/3]).
-export([sql_schemas/0]).

-include_lib("xmpp/include/xmpp.hrl").
-include("mod_offline.hrl").
-include("logger.hrl").
-include("ejabberd_sql_pt.hrl").

%%%===================================================================
%%% API
%%%===================================================================
init(Host, _Opts) ->
    ejabberd_sql_schema:update_schema(Host, ?MODULE, sql_schemas()),
    ok.

sql_schemas() ->
    [#sql_schema{
        version = 1,
        tables =
            [#sql_table{
                name = <<"spool">>,
                columns =
                    [#sql_column{name = <<"username">>, type = text},
                     #sql_column{name = <<"server_host">>, type = text},
		     #sql_column{name = <<"device_id">>, type = text},
                     #sql_column{name = <<"xml">>, type = {text, big}},
                     #sql_column{name = <<"seq">>, type = bigserial},
                     #sql_column{name = <<"created_at">>, type = timestamp,
                                 default = true}],
                indices = [#sql_index{
                              columns = [<<"server_host">>, <<"username">>, <<"device_id">>]},
                           #sql_index{
                              columns = [<<"created_at">>]}]}]}].

store_message(#offline_msg{us = {LUser, LServer}} = M) ->
	From = M#offline_msg.from,
	To = M#offline_msg.to,

	ChatType = erlang:atom_to_binary(xmpp:get_type(M#offline_msg.packet), utf8),
	Packet = xmpp:set_from_to(M#offline_msg.packet, From, To),
	NewPacket = misc:add_delay_info(
		Packet, jid:make(LServer),
		M#offline_msg.timestamp,
		<<"Offline Storage">>),
	XML = fxml:element_to_binary(xmpp:encode(NewPacket)),
if ChatType =:= <<"normal">> ->
		Stanza = xmpp:encode(NewPacket),
		#jid{user = TUser, lserver = _TServer, lresource = FResource} =  From,
		Mid = xmpp:get_id(M#offline_msg.packet),
		case fxml:get_subtag(Stanza, <<"mix">>) of
			false -> MessageId = Mid;
			Mix ->
				case fxml:get_subtag(Stanza, <<"body">>) of
					false -> MessageId = Mid;
					_Body ->
						case fxml:get_subtag(Mix, <<"submission-id">>) of
							false -> MessageId = Mid;
							SubmissionID ->
								GroupMsgId = fxml:get_tag_cdata(SubmissionID),
							MessageId = GroupMsgId
						end
				end
		end;
	true ->
		#jid{user = _FUser, lserver = _FServer, lresource = FResource} =  From,
	  case mod_carboncopy:is_carbon_copy(Packet) of
			false ->
				#jid{user = TUser, lserver = _TServer} =  To,
				MessageId = xmpp:get_id(M#offline_msg.packet);

			true->
				CarbonPacket =  misc:unwrap_carbon(xmpp:encode(NewPacket)),
				case fxml:get_subtag(CarbonPacket, <<"sent">>) of
					false ->
						#jid{user = TUser, lserver = _TServer} =  To,
						MessageId = <<"">>;
					Sentpacket ->
						case fxml:get_subtag(Sentpacket, <<"forwarded">>) of
							false ->
								#jid{user = TUser, lserver = _TServer} =  To,
								MessageId = <<"">>;
							Forwardedpacket->
								case fxml:get_subtag(Forwardedpacket, <<"message">>) of
									false ->
										#jid{user = TUser, lserver = _TServer} =  To,
										MessageId = <<"">>;
									Messagepacket->
										Mtype = fxml:get_attr_s(<<"type">>,Messagepacket#xmlel.attrs),
												if Mtype =:=  <<"normal">> ->
													case fxml:get_subtag(Messagepacket, <<"mix">>) of
													false -> MessageId = fxml:get_attr_s(<<"id">>,Messagepacket#xmlel.attrs);
													Mix ->

													case fxml:get_subtag(Mix, <<"submission-id">>) of
														false -> MessageId = fxml:get_attr_s(<<"id">>,Messagepacket#xmlel.attrs);
														SubmissionID ->
															MessageId = fxml:get_tag_cdata(SubmissionID)

													end

												end,
												FromUser =  #jid{} = jid:from_string(fxml:get_attr_s(<<"from">>,Messagepacket#xmlel.attrs)),
												#jid{user = TUser, lserver = _TServer} =  FromUser;
												true ->
												MessageId = fxml:get_attr_s(<<"id">>,Messagepacket#xmlel.attrs),
												FromUser = #jid{} = jid:from_string(fxml:get_attr_s(<<"to">>,Messagepacket#xmlel.attrs)),
												#jid{user = TUser, lserver = _TServer} =  FromUser
												end

								end
					    end
			    end

			    end


	 end,
	Message = fxml:element_to_binary(
		xmpp:encode(M#offline_msg.packet)),
if FResource =:= <<"">> ->
case catch fly_mod_utils:get_user_resources(LUser, LServer) of
        {selected, _, []} ->
        ok;
        {selected, _, Result} ->
			lists:map(fun(G) ->
              [UResources] = G,
				ejabberd_sql:sql_query(
				LServer,
				?SQL_INSERT(
					"spool",
					["username=%(LUser)s",
						"server_host=%(LServer)s",
						"message_id=%(MessageId)s",
						"chat_type=%(ChatType)s",
						"to_user=%(TUser)s",
						"device_id=%(UResources)s",
						% "message=%(Message)s",
						"xml=%(XML)s"]))

			  end, Result),
			  ok;
         _ ->
        ok
 end;
true ->
	Substring = string:str(binary_to_list(FResource), "Mobile"),
    if Substring =:= 1  ->
	Resource = re:replace(binary_to_list(FResource),"Mobile-", ""),
	UResource = iolist_to_binary(Resource);
    true ->
	UResource = FResource
    end,
	case catch fly_mod_utils:get_user_resource(LUser, LServer, UResource) of
        {selected, _, []} ->
        ok;
        {selected, _, Result} ->
			lists:map(fun(G) ->
              [UResources] = G,
				ejabberd_sql:sql_query(
				LServer,
				?SQL_INSERT(
					"spool",
					["username=%(LUser)s",
						"server_host=%(LServer)s",
						"message_id=%(MessageId)s",
						"chat_type=%(ChatType)s",
						"to_user=%(TUser)s",
						"device_id=%(UResources)s",
						% "message=%(Message)s",
						"xml=%(XML)s"]))

			  end, Result),
			  ok;
         _ ->
        ok
 end
end.

pop_messages(LUser, LServer,LResource) ->
case get_and_del_spool_msg_t(LServer, LUser,LResource) of
	{atomic, {selected, Rs}} ->
	    ?LOG_INFO("Popped ~p offline messages for user ~ts@~ts/~ts", [length(Rs), LUser, LServer, LResource]),
	    {ok, lists:flatmap(
		   fun({_, XML}) ->
			   case xml_to_offline_msg(XML) of
			       {ok, Msg} ->
				   [Msg];
			       _Err ->
				   []
			   end
		   end, Rs)};
	Err ->
	    {error, Err}
    end.

remove_expired_messages(_LServer) ->
    %% TODO
    {atomic, ok}.

remove_old_messages(Days, LServer) ->
    case ejabberd_sql:sql_query(
	   LServer,
           fun(pgsql, _) ->
                   ejabberd_sql:sql_query_t(
                     ?SQL("DELETE FROM spool"
                          " WHERE created_at <"
                          " NOW() - %(Days)d * INTERVAL '1 DAY'"));
	      (sqlite, _) ->
		  ejabberd_sql:sql_query_t(
		      ?SQL("DELETE FROM spool"
			   " WHERE created_at <"
			   " DATETIME('now', '-%(Days)d days')"));
              (_, _) ->
                   ejabberd_sql:sql_query_t(
                     ?SQL("DELETE FROM spool"
                          " WHERE created_at < NOW() - INTERVAL %(Days)d DAY"))
              end)
        of
	{updated, N} ->
	    ?INFO_MSG("~p message(s) deleted from offline spool", [N]);
	_Error ->
	    ?ERROR_MSG("Cannot delete message in offline spool: ~p", [_Error])
    end,
    {atomic, ok}.

remove_old_messages_batch(LServer, Days, Batch) ->
    case ejabberd_sql:sql_query(
	LServer,
	fun(pgsql, _) ->
	    ejabberd_sql:sql_query_t(
		?SQL("DELETE FROM spool"
		     " WHERE created_at <"
		     " NOW() - %(Days)d * INTERVAL '1 DAY' LIMIT %(Batch)d"));
	   (sqlite, _) ->
	       ejabberd_sql:sql_query_t(
		   ?SQL("DELETE FROM spool"
			" WHERE created_at <"
			" DATETIME('now', '-%(Days)d days') LIMIT %(Batch)d"));
	   (_, _) ->
	       ejabberd_sql:sql_query_t(
		   ?SQL("DELETE FROM spool"
			" WHERE created_at < NOW() - INTERVAL %(Days)d DAY LIMIT %(Batch)d"))
	end)
    of
	{updated, N} ->
	    {ok, N};
	Error ->
	    {error, Error}
    end.

remove_user(LUser, LServer) ->
    ejabberd_sql:sql_query(
      LServer,
      ?SQL("delete from spool where username=%(LUser)s and %(LServer)H")).

read_message_headers(LUser, LServer) ->
    case ejabberd_sql:sql_query(
	   LServer,
	   ?SQL("select @(xml)s, @(seq)d from spool"
		" where username=%(LUser)s and %(LServer)H order by seq")) of
	{selected, Rows} ->
	    lists:flatmap(
	      fun({XML, Seq}) ->
		      case xml_to_offline_msg(XML) of
			  {ok, #offline_msg{from = From,
					    to = To,
					    timestamp = TS,
					    packet = El}} ->
			      [{Seq, From, To, TS, El}];
			  _ ->
			      []
		      end
	      end, Rows);
	_Err ->
	    error
    end.

read_message(LUser, LServer, Seq) ->
    case ejabberd_sql:sql_query(
	   LServer,
	   ?SQL("select @(xml)s from spool where username=%(LUser)s"
                " and %(LServer)H"
                " and seq=%(Seq)d")) of
	{selected, [{RawXML}|_]} ->
	    case xml_to_offline_msg(RawXML) of
		{ok, Msg} ->
		    {ok, Msg};
		_ ->
		    error
	    end;
	_ ->
	    error
    end.

remove_message(LUser, LServer, Seq) ->
    ejabberd_sql:sql_query(
      LServer,
      ?SQL("delete from spool where username=%(LUser)s and %(LServer)H"
           " and seq=%(Seq)d")),
    ok.

read_all_messages(LUser, LServer) ->
    case ejabberd_sql:sql_query(
	   LServer,
	   ?SQL("select @(xml)s from spool where "
		"username=%(LUser)s and %(LServer)H order by seq")) of
        {selected, Rs} ->
            lists:flatmap(
              fun({XML}) ->
		      case xml_to_offline_msg(XML) of
			  {ok, Msg} -> [Msg];
			  _ -> []
		      end
              end, Rs);
        _ ->
	    []
    end.

remove_all_messages(LUser, LServer) ->
    remove_user(LUser, LServer),
    {atomic, ok}.

count_messages(LUser, LServer) ->
    case catch ejabberd_sql:sql_query(
                 LServer,
                 ?SQL("select @(count(*))d from spool "
                      "where username=%(LUser)s and %(LServer)H")) of
        {selected, [{Res}]} ->
            {cache, Res};
	{selected, []} ->
	    {cache, 0};
        _ ->
	    {nocache, 0}
    end.

export(_Server) ->
    [{offline_msg,
      fun(Host, #offline_msg{us = {LUser, LServer}})
            when LServer == Host ->
		      [?SQL("delete from spool where username=%(LUser)s"
                            " and %(LServer)H;")];
         (_Host, _R) ->
              []
      end},
     {offline_msg,
      fun(Host, #offline_msg{us = {LUser, LServer},
                             timestamp = TimeStamp, from = From, to = To,
                             packet = El})
            when LServer == Host ->
	      try xmpp:decode(El, ?NS_CLIENT, [ignore_els]) of
		  Packet ->
		      Packet1 = xmpp:set_from_to(Packet, From, To),
		      Packet2 = misc:add_delay_info(
				  Packet1, jid:make(LServer),
				  TimeStamp, <<"Offline Storage">>),
		      XML = fxml:element_to_binary(xmpp:encode(Packet2)),
		      [?SQL_INSERT(
                          "spool",
                          ["username=%(LUser)s",
                           "server_host=%(LServer)s",
                           "xml=%(XML)s"])]
	      catch _:{xmpp_codec, Why} ->
		      ?ERROR_MSG("Failed to decode packet ~p of user ~ts@~ts: ~ts",
				 [El, LUser, LServer, xmpp:format_error(Why)]),
		      []
	      end;
         (_Host, _R) ->
              []
      end}].

import(_) ->
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
xml_to_offline_msg(XML) ->
    case fxml_stream:parse_element(XML) of
	#xmlel{} = El ->
	    el_to_offline_msg(El);
	Err ->
	    ?ERROR_MSG("Got ~p when parsing XML packet ~ts",
		       [Err, XML]),
	    Err
    end.

el_to_offline_msg(El) ->
    To_s = fxml:get_tag_attr_s(<<"to">>, El),
    From_s = fxml:get_tag_attr_s(<<"from">>, El),
    try
	To = jid:decode(To_s),
	From = jid:decode(From_s),
	{ok, #offline_msg{us = {To#jid.luser, To#jid.lserver},
			  from = From,
			  to = To,
			  packet = El}}
    catch _:{bad_jid, To_s} ->
	    ?ERROR_MSG("Failed to get 'to' JID from offline XML ~p", [El]),
	    {error, bad_jid_to};
	  _:{bad_jid, From_s} ->
	    ?ERROR_MSG("Failed to get 'from' JID from offline XML ~p", [El]),
	    {error, bad_jid_from}
    end.

get_and_del_spool_msg_t(LServer, LUser, LResource) ->
    CleanResource = re:replace(binary_to_list(LResource), "Mobile-", "", [{return, list}]),
    UResource = iolist_to_binary(CleanResource),
    DeviceID = <<"MF-01-mobile">>,

    F = fun() ->
	ExistQ = ?SQL("select @(count(username))s from spool where username=%(LUser)s and device_id=%(UResource)s and %(LServer)H ;"),
	ExistResult = ejabberd_sql:sql_query_t(ExistQ),
 
        DeviceToUse =
	case ExistResult of
		{selected, [[CountBin]]} when is_binary(CountBin) ->
		case binary_to_integer(CountBin) > 0 of
			true -> UResource;
			false -> DeviceID
		end;

		{selected, [[CountInt]]} when is_integer(CountInt) ->
		case CountInt > 0 of
			true -> UResource;
			false -> DeviceID
		end;

		{selected, [{CountInt}]} when is_integer(CountInt) ->
		case CountInt > 0 of
			true -> UResource;
			false -> DeviceID
		end;

		_ ->
		DeviceID
	end,

        FetchQ = ?SQL("select @(username)s, @(xml)s from spool where username=%(LUser)s and device_id=%(DeviceToUse)s and %(LServer)H order by seq limit 100;"),
        DeleteQ = ?SQL("delete from spool where username=%(LUser)s and device_id=%(DeviceToUse)s and %(LServer)H order by seq limit 100;"),

        Result = ejabberd_sql:sql_query_t(FetchQ),
        DResult = ejabberd_sql:sql_query_t(DeleteQ),

        case {Result, DResult} of
            {{selected, Rs}, {updated, DC}} when length(Rs) =/= DC ->
                ejabberd_sql:restart(concurent_insert);
            _ ->
                Result
        end
    end,

    ejabberd_sql:sql_transaction(LServer, F).