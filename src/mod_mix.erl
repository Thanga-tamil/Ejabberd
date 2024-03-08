%%%-------------------------------------------------------------------
%%% File    : mod_mix.erl
%%% Author  : Evgeny Khramtsov <ekhramtsov@process-one.net>
%%% Created :  2 Mar 2016 by Evgeny Khramtsov <ekhramtsov@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2018   ProcessOne
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
-module(mod_mix).
-behaviour(gen_mod).
-behaviour(gen_server).
-protocol({xep, 369, '0.14.1', '16.03', "", ""}).

%% API
-export([route/1]).
%% gen_mod callbacks
-export([start/2, stop/1, reload/3, depends/2, mod_opt_type/1, mod_options/1]).
-export([mod_doc/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
	 terminate/2, code_change/3, format_status/2]).
%% Hooks
-export([process_disco_info/1,
	 process_disco_items/1,
	 process_mix_core/1,
	 process_mam_query/1,
	 process_pubsub_query/1,
	 notify_participant_joined_api/5,
	 notify_participant_left_api/6,
	 process_mix_message/1]).
-export([process_group_msg/8,send_group_push_message/8]).

-include_lib("xmpp/include/xmpp.hrl").
-include("logger.hrl").
-include("translate.hrl").
-include("ejabberd_stacktrace.hrl").

-callback init(binary(), gen_mod:opts()) -> ok | {error, db_failure}.
-callback set_channel(binary(), binary(), binary(),
		      jid:jid(), boolean(), binary()) ->
    ok | {error, db_failure}.
-callback get_channels(binary(), binary()) ->
    {ok, [binary()]} | {error, db_failure}.
-callback get_channel(binary(), binary(), binary()) ->
    {ok, {jid(), boolean(), binary()}} |
    {error, notfound | db_failure}.
-callback set_participant(binary(), binary(), binary(), jid(), binary(), binary()) ->
    ok | {error, db_failure}.
-callback get_participant(binary(), binary(), binary(), jid()) ->
    {ok, {binary(), binary()}} | {error, notfound | db_failure}.

-record(state, {hosts :: [binary()],
		server_host :: binary()}).

%%%===================================================================
%%% API
%%%===================================================================
start(Host, Opts) ->
    gen_mod:start_child(?MODULE, Host, Opts).

stop(Host) ->
    gen_mod:stop_child(?MODULE, Host).

reload(Host, NewOpts, OldOpts) ->
    Proc = gen_mod:get_module_proc(Host, ?MODULE),
    gen_server:cast(Proc, {reload, Host, NewOpts, OldOpts}).

depends(_Host, _Opts) ->
    [{mod_mam, hard}].

mod_opt_type(access_create) ->
    econf:acl();
mod_opt_type(name) ->
    econf:binary();
mod_opt_type(host) ->
    econf:host();
mod_opt_type(hosts) ->
    econf:hosts();
mod_opt_type(db_type) ->
    econf:db_type(?MODULE).

mod_options(Host) ->
    [{access_create, all},
     {host, <<"mix.", Host/binary>>},
     {hosts, []},
     {name, ?T("Channels")},
     {db_type, ejabberd_config:default_db(Host, ?MODULE)}].

mod_doc() ->
    #{desc =>
          [?T("This module is an experimental implementation of "
              "https://xmpp.org/extensions/xep-0369.html"
              "[XEP-0369: Mediated Information eXchange (MIX)]. "
              "MIX support was added in ejabberd 16.03 as an "
              "experimental feature, updated in 19.02, and is not "
              "yet ready to use in production. It's asserted that "
              "the MIX protocol is going to replace the MUC protocol "
              "in the future (see _`mod_muc`_)."), "",
           ?T("To learn more about how to use that feature, you can refer to "
	      "our tutorial: https://docs.ejabberd.im/tutorials/mix-010/"
	      "[Getting started with XEP-0369: Mediated Information "
	      "eXchange (MIX) v0.1]."), "",
           ?T("The module depends on _`mod_mam`_.")],
      opts =>
          [{access_create,
            #{value => ?T("AccessName"),
              desc =>
                  ?T("An access rule to control MIX channels creations. "
                     "The default value is 'all'.")}},
           {host,
            #{desc => ?T("Deprecated. Use 'hosts' instead.")}},
           {hosts,
            #{value => ?T("[Host, ...]"),
              desc =>
                  ?T("This option defines the Jabber IDs of the service. "
                     "If the 'hosts' option is not specified, the only Jabber ID will "
                     "be the hostname of the virtual host with the prefix \"mix.\". "
                     "The keyword '@HOST@' is replaced with the real virtual host name.")}},
           {name,
            #{value => ?T("Name"),
              desc =>
                  ?T("A name of the service in the Service Discovery. "
                     "This will only be displayed by special XMPP clients. "
                     "The default value is 'Channels'.")}},
           {db_type,
            #{value => "mnesia | sql",
              desc =>
                  ?T("Same as top-level _`default_db`_ option, but applied to this module only.")}}]}.

-spec route(stanza()) -> ok.
route(#iq{} = IQ) ->
    ejabberd_router:process_iq(IQ);
%% Contus Changed the type from groupchat to normal
route(#message{type = normal, id = ID, lang = Lang,
	       to = #jid{luser = <<_, _/binary>>}} = Msg) ->
    case ID of
	<<>> ->
	    Txt = ?T("Attribute 'id' is mandatory for MIX messages"),
	    Err = xmpp:err_bad_request(Txt, Lang),
	    ejabberd_router:route_error(Msg, Err);
	_ ->
	    process_mix_message(Msg)
    end;
route(Pkt) ->
    ?DEBUG("Dropping packet:~n~ts", [xmpp:pp(Pkt)]).

-spec process_disco_info(iq()) -> iq().
process_disco_info(#iq{type = set, lang = Lang} = IQ) ->
    Txt = ?T("Value 'set' of 'type' attribute is not allowed"),
    xmpp:make_error(IQ, xmpp:err_not_allowed(Txt, Lang));
process_disco_info(#iq{type = get, to = #jid{luser = <<>>} = To,
		       from = _From, lang = Lang,
		       sub_els = [#disco_info{node = <<>>}]} = IQ) ->
    ServerHost = ejabberd_router:host_of_route(To#jid.lserver),
    X = ejabberd_hooks:run_fold(disco_info, ServerHost, [],
				[ServerHost, ?MODULE, <<"">>, Lang]),
    Name = mod_mix_opt:name(ServerHost),
    Identity = #identity{category = <<"conference">>,
			 type = <<"mix">>,
			 name = translate:translate(Lang, Name)},
    Features = [?NS_DISCO_INFO, ?NS_DISCO_ITEMS, ?NS_MIX_CORE_0,
		?NS_MIX_CORE_SEARCHABLE_0, ?NS_MIX_CORE_CREATE_CHANNEL_0,
		?NS_MIX_CORE_1, ?NS_MIX_CORE_SEARCHABLE_1,
		?NS_MIX_CORE_CREATE_CHANNEL_1],
    xmpp:make_iq_result(
      IQ, #disco_info{features = Features,
		      identities = [Identity],
		      xdata = X});
process_disco_info(#iq{type = get, to = #jid{luser = <<_, _/binary>>} = To,
		       sub_els = [#disco_info{node = Node}]} = IQ)
  when Node == <<"mix">>; Node == <<>> ->
    {Chan, Host, _} = jid:tolower(To),
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, _} ->
	    Identity = #identity{category = <<"conference">>,
				 type = <<"mix">>},
	    Features = [?NS_DISCO_INFO, ?NS_DISCO_ITEMS,
			?NS_MIX_CORE_0, ?NS_MIX_CORE_1, ?NS_MAM_2],
	    xmpp:make_iq_result(
	      IQ, #disco_info{node = Node,
			      features = Features,
			      identities = [Identity]});
	{error, notfound} ->
	    xmpp:make_error(IQ, no_channel_error(IQ));
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end;
process_disco_info(#iq{type = get, sub_els = [#disco_info{node = Node}]} = IQ) ->
    xmpp:make_iq_result(IQ, #disco_info{node = Node, features = [?NS_DISCO_INFO]});
process_disco_info(IQ) ->
    xmpp:make_error(IQ, unsupported_error(IQ)).

-spec process_disco_items(iq()) -> iq().
process_disco_items(#iq{type = set, lang = Lang} = IQ) ->
    Txt = ?T("Value 'set' of 'type' attribute is not allowed"),
    xmpp:make_error(IQ, xmpp:err_not_allowed(Txt, Lang));
process_disco_items(#iq{type = get, to = #jid{luser = <<>>} = To,
			sub_els = [#disco_items{node = <<>>}]} = IQ) ->
    Host = To#jid.lserver,
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    case Mod:get_channels(ServerHost, Host) of
	{ok, Channels} ->
	    Items = [#disco_item{jid = jid:make(Channel, Host)}
		     || Channel <- Channels],
	    xmpp:make_iq_result(IQ, #disco_items{items = Items});
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end;
process_disco_items(#iq{type = get, to = #jid{luser = <<_, _/binary>>} = To,
			sub_els = [#disco_items{node = Node}]} = IQ)
  when Node == <<"mix">>; Node == <<>> ->
    {Chan, Host, _} = jid:tolower(To),
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, _} ->
	    BTo = jid:remove_resource(To),
	    Items = [#disco_item{jid = BTo, node = N} || N <- known_nodes()],
	    xmpp:make_iq_result(IQ, #disco_items{node = Node, items = Items});
	{error, notfound} ->
	    xmpp:make_error(IQ, no_channel_error(IQ));
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end;
process_disco_items(#iq{type = get, sub_els = [#disco_items{node = Node}]} = IQ) ->
    xmpp:make_iq_result(IQ, #disco_items{node = Node});
process_disco_items(IQ) ->
    xmpp:make_error(IQ, unsupported_error(IQ)).

-spec process_mix_core(iq()) -> iq().
process_mix_core(#iq{type = set, to = #jid{luser = <<>>},
		     sub_els = [#mix_create{}]} = IQ) ->
    process_mix_create(IQ);
process_mix_core(#iq{type = set, to = #jid{luser = <<>>},
		     sub_els = [#mix_destroy{}]} = IQ) ->
    process_mix_destroy(IQ);
process_mix_core(#iq{type = set, to = #jid{luser = <<_, _/binary>>},
		     sub_els = [#mix_join{}]} = IQ) ->
    process_mix_join(IQ);
process_mix_core(#iq{type = set, to = #jid{luser = <<_, _/binary>>},
		     sub_els = [#mix_leave{}]} = IQ) ->
    process_mix_leave(IQ);
process_mix_core(#iq{type = set, to = #jid{luser = <<_, _/binary>>},
		     sub_els = [#mix_setnick{}]} = IQ) ->
    process_mix_setnick(IQ);
process_mix_core(IQ) ->
    xmpp:make_error(IQ, unsupported_error(IQ)).

process_pubsub_query(#iq{type = get,
			 sub_els = [#pubsub{items = #ps_items{node = Node}}]} = IQ)
  when Node == ?NS_MIX_NODES_PARTICIPANTS ->
    process_participants_list(IQ);
process_pubsub_query(IQ) ->
    xmpp:make_error(IQ, unsupported_error(IQ)).

process_mam_query(#iq{from = From, to = To, type = T,
		      sub_els = [#mam_query{}]} = IQ)
  when T == get; T == set ->
    {Chan, Host, _} = jid:tolower(To),
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, _} ->
	    BFrom = jid:remove_resource(From),
	    case Mod:get_participant(ServerHost, Chan, Host, BFrom) of
		{ok, _} ->
		    mod_mam:process_iq(ServerHost, IQ, mix);
		{error, notfound} ->
		    xmpp:make_error(IQ, not_joined_error(IQ));
		{error, db_failure} ->
		    xmpp:make_error(IQ, db_error(IQ))
	    end;
	{error, notfound} ->
	    xmpp:make_error(IQ, no_channel_error(IQ));
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end;
process_mam_query(IQ) ->
    xmpp:make_error(IQ, unsupported_error(IQ)).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([Host|_]) ->
    process_flag(trap_exit, true),
    Opts = gen_mod:get_module_opts(Host, ?MODULE),
    Mod = gen_mod:db_mod(Opts, ?MODULE),
    MyHosts = gen_mod:get_opt_hosts(Opts),
    case Mod:init(Host, gen_mod:set_opt(hosts, MyHosts, Opts)) of
	ok ->
	    lists:foreach(
	      fun(MyHost) ->
		      ejabberd_router:register_route(
			MyHost, Host, {apply, ?MODULE, route}),
		      register_iq_handlers(MyHost)
	      end, MyHosts),
	    {ok, #state{hosts = MyHosts, server_host = Host}};
	{error, db_failure} ->
	    {stop, db_failure}
    end.

handle_call(Request, From, State) ->
    ?WARNING_MSG("Unexpected call from ~p: ~p", [From, Request]),
    {noreply, State}.

handle_cast(Request, State) ->
    ?WARNING_MSG("Unexpected cast: ~p", [Request]),
    {noreply, State}.

handle_info({route, Packet}, State) ->
    try route(Packet)
    catch ?EX_RULE(Class, Reason, St) ->
	    StackTrace = ?EX_STACK(St),
	    ?ERROR_MSG("Failed to route packet:~n~ts~n** ~ts",
		       [xmpp:pp(Packet),
			misc:format_exception(2, Class, Reason, StackTrace)])
    end,
    {noreply, State};
handle_info(Info, State) ->
    ?WARNING_MSG("Unexpected info: ~p", [Info]),
    {noreply, State}.

terminate(_Reason, State) ->
    lists:foreach(
      fun(MyHost) ->
	      unregister_iq_handlers(MyHost),
	      ejabberd_router:unregister_route(MyHost)
      end, State#state.hosts).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================
-spec process_mix_create(iq()) -> iq().
process_mix_create(#iq{to = To, from = From,
		       sub_els = [#mix_create{channel = Chan, xmlns = XmlNs}]} = IQ) ->
    Host = To#jid.lserver,
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    Creator = jid:remove_resource(From),
    Chan1 = case Chan of
		<<>> -> p1_rand:get_string();
		_ -> Chan
	    end,
    Ret = case Mod:get_channel(ServerHost, Chan1, Host) of
	      {ok, {#jid{luser = U, lserver = S}, _, _}} ->
		  case {From#jid.luser, From#jid.lserver} of
		      {U, S} -> ok;
		      _ -> {error, conflict}
		  end;
	      {error, notfound} ->
		  Key = xmpp_util:hex(p1_rand:bytes(20)),
		  Mod:set_channel(ServerHost, Chan1, Host,
				  Creator, Chan == <<>>, Key);
	      {error, db_failure} = Err ->
		  Err
	  end,
    case Ret of
	ok ->
	    xmpp:make_iq_result(IQ, #mix_create{channel = Chan1, xmlns = XmlNs});
	{error, conflict} ->
	    xmpp:make_error(IQ, channel_exists_error(IQ));
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end.

-spec process_mix_destroy(iq()) -> iq().
process_mix_destroy(#iq{to = To,
			from = #jid{luser = U, lserver = S},
			sub_els = [#mix_destroy{channel = Chan, xmlns = XmlNs}]} = IQ) ->
    Host = To#jid.lserver,
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, {#jid{luser = U, lserver = S}, _, _}} ->
	    case Mod:del_channel(ServerHost, Chan, Host) of
		ok ->
		    xmpp:make_iq_result(IQ, #mix_destroy{channel = Chan, xmlns = XmlNs});
		{error, db_failure} ->
		    xmpp:make_error(IQ, db_error(IQ))
	    end;
	{ok, _} ->
	    xmpp:make_error(IQ, ownership_error(IQ));
	{error, notfound} ->
	    xmpp:make_error(IQ, no_channel_error(IQ));
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end.

-spec process_mix_join(iq()) -> iq().
process_mix_join(#iq{to = To, from = From,
		     sub_els = [#mix_join{owner = Pub, custom_attributes = CustomAttr, message_id = MsgId, group_create = GroupCreate, xmlns = XmlNs} = JoinReq]} = IQ) ->
    Chan = To#jid.luser,
    Host = To#jid.lserver,
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, {_, _, Key}} ->
	    ID = make_id(From, Key),
	    Nick = JoinReq#mix_join.nick,
	    BFrom = jid:remove_resource(From),
	    Nodes = filter_nodes(JoinReq#mix_join.subscribe),
	    if Pub == <<>> ->
		Publisher = fly_mod_utils:jid_to_string(From);
	    true ->
		Publisher = Pub
	   end,
	   PublisherJID = jid:make(fly_mod_utils:get_user_from_string_jid(Publisher),From#jid.lserver,<<"">>),
	   PubID = make_id(PublisherJID, Key),
	    try
		ok = Mod:set_participant(ServerHost, Chan, Host, BFrom, MsgId, Nick),
		ok = Mod:subscribe(ServerHost, Chan, Host, BFrom, Nodes),
		notify_participant_joined(Mod, ServerHost, To, From, MsgId, [Nick, GroupCreate,  Publisher, PubID, CustomAttr], MsgId),
		xmpp:make_iq_result(IQ, #mix_join{id = MsgId,
						  subscribe = Nodes,
						  jid = make_channel_id(To, MsgId),
						  nick = Nick,
						  xmlns = XmlNs})
	    catch _:{badmatch, {error, db_failure}} ->
		    xmpp:make_error(IQ, db_error(IQ))
	    end;
	{error, notfound} ->
	    xmpp:make_error(IQ, no_channel_error(IQ));
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end.

-spec process_mix_leave(iq()) -> iq().
process_mix_leave(#iq{to = To, from = From, id = MsgId,
		      sub_els = [#mix_leave{admin_user = AdminUser, from_jid = FromJid, xmlns = XmlNs}]} = IQ) ->
    {Chan, Host, _} = jid:tolower(To),
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    BFrom = jid:remove_resource(From),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, _} ->
	    case Mod:get_participant(ServerHost, Chan, Host, BFrom) of
		{ok, {ID, _}} ->
		    try
		        notify_participant_left(Mod, ServerHost, To, ID, FromJid, BFrom, AdminUser, MsgId),
			ok = Mod:unsubscribe(ServerHost, Chan, Host, BFrom),
			ok = mod_mix_pam:del_channel(BFrom, To),
			ok = Mod:del_participant(ServerHost, Chan, Host, BFrom),
			xmpp:make_iq_result(IQ, #mix_leave{})
		    catch _:{badmatch, {error, db_failure}} ->
			    xmpp:make_error(IQ, db_error(IQ))
		    end;
		{error, notfound} ->
		    xmpp:make_iq_result(IQ, #mix_leave{xmlns = XmlNs});
		{error, db_failure} ->
		    xmpp:make_error(IQ, db_error(IQ))
	    end;
	{error, notfound} ->
	    xmpp:make_iq_result(IQ, #mix_leave{});
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end.

-spec process_mix_setnick(iq()) -> iq().
process_mix_setnick(#iq{to = To, from = From, id = MsgId,
			sub_els = [#mix_setnick{nick = Nick, xmlns = XmlNs}]} = IQ) ->
    {Chan, Host, _} = jid:tolower(To),
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    BFrom = jid:remove_resource(From),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, _} ->
	    case Mod:get_participant(ServerHost, Chan, Host, BFrom) of
		{ok, {_, Nick}} ->
		    xmpp:make_iq_result(IQ, #mix_setnick{nick = Nick, xmlns = XmlNs});
		{ok, {ID, _}} ->
		    case Mod:set_participant(ServerHost, Chan, Host, BFrom, ID, Nick) of
			ok ->
			    notify_participant_joined(Mod, ServerHost, To, From, ID, [Nick,Nick],MsgId),
			    xmpp:make_iq_result(IQ, #mix_setnick{nick = Nick, xmlns = XmlNs});
			{error, db_failure} ->
			    xmpp:make_error(IQ, db_error(IQ))
		    end;
		{error, notfound} ->
		    xmpp:make_error(IQ, not_joined_error(IQ));
		{error, db_failure} ->
		    xmpp:make_error(IQ, db_error(IQ))
	    end;
	{error, notfound} ->
	    xmpp:make_error(IQ, no_channel_error(IQ));
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end.

-spec process_mix_message(message()) -> ok.
process_mix_message(#message{from = From, to = To, type = normal,
			     id = SubmissionID} = Msg) ->
    {Chan, Host, _} = jid:tolower(To),
    {FUser, FServer, _} = jid:tolower(From),
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, _} ->
	    BFrom = jid:remove_resource(From),
	    case Mod:get_participant(ServerHost, Chan, Host, BFrom) of
		{ok, {StableID, Nick}} ->
		    MamID = mod_mam:make_id(),
		    Msg1 = xmpp:set_subtag(
			     Msg#message{from = jid:replace_resource(To, StableID),
					 to = undefined,
                                         type = normal,
					 id = integer_to_binary(MamID)},
			     #mix{jid = BFrom, nick = Nick}),
		    Msg2 = xmpp:put_meta(Msg1, stanza_id, MamID),
		    case ejabberd_hooks:run_fold(
			   store_mam_message, ServerHost, Msg2,
			   [Chan, Host, BFrom, Nick, groupchat, recv]) of
			#message{} ->
			    multicast(Mod, ServerHost, Chan, Host,
				      ?NS_MIX_NODES_MESSAGES,
				      fun(#jid{luser = U, lserver = S})
					    when U == FUser, S == FServer ->
					      xmpp:set_subtag(
						Msg1, #mix{jid = BFrom,
							   nick = Nick,
							   submission_id = SubmissionID});
					 (_) ->
					      xmpp:set_subtag(
							 Msg1, #mix{jid = BFrom,
								 nick = Nick,
								 submission_id = SubmissionID})
				      end);
			_ ->
			    ok
		    end;
		{error, notfound} ->
		    ejabberd_router:route_error(Msg, not_joined_error(Msg));
		{error, db_failure} ->
		    ejabberd_router:route_error(Msg, db_error(Msg))
	    end;
	{error, notfound} ->
	    ejabberd_router:route_error(Msg, no_channel_error(Msg));
	{error, db_failure} ->
	    ejabberd_router:route_error(Msg, db_error(Msg))
    end.

-spec process_participants_list(iq()) -> iq().
process_participants_list(#iq{from = From, to = To} = IQ) ->
    {Chan, Host, _} = jid:tolower(To),
    ServerHost = ejabberd_router:host_of_route(Host),
    Mod = gen_mod:db_mod(ServerHost, ?MODULE),
    case Mod:get_channel(ServerHost, Chan, Host) of
	{ok, _} ->
	    BFrom = jid:remove_resource(From),
	    case Mod:get_participant(ServerHost, Chan, Host, BFrom) of
		{ok, _} ->
		    case Mod:get_participants(ServerHost, Chan, Host) of
			{ok, Participants} ->
			    Items = items_of_participants(Participants),
			    Pubsub = #pubsub{
					items = #ps_items{
						   node = ?NS_MIX_NODES_PARTICIPANTS,
						   items = Items}},
			    xmpp:make_iq_result(IQ, Pubsub);
			{error, db_failure} ->
			    xmpp:make_error(IQ, db_error(IQ))
		    end;
		{error, notfound} ->
		    xmpp:make_error(IQ, not_joined_error(IQ));
		{error, db_failure} ->
		    xmpp:make_error(IQ, db_error(IQ))
	    end;
	{error, notfound} ->
	    xmpp:make_error(IQ, no_channel_error(IQ));
	{error, db_failure} ->
	    xmpp:make_error(IQ, db_error(IQ))
    end.

-spec items_of_participants([{jid(), binary(), binary()}]) -> [ps_item()].
items_of_participants(Participants) ->
    lists:map(
      fun({JID, ID, Nick}) ->
	      Participant = #mix_participant{jid = JID, nick = Nick},
	      #ps_item{id = ID,
		       sub_els = [xmpp:encode(Participant)]}
      end, Participants).

-spec known_nodes() -> [binary()].
known_nodes() ->
    [?NS_MIX_NODES_MESSAGES,
     ?NS_MIX_NODES_PARTICIPANTS].

-spec filter_nodes([binary()]) -> [binary()].
filter_nodes(Nodes) ->
    KnownNodes = known_nodes(),
    [Node || KnownNode <- KnownNodes, Node <- Nodes, KnownNode == Node].

-spec multicast(module(), binary(), binary(),
		binary(), binary(), fun((jid()) -> message())) -> ok.
% multicast(Mod, LServer, Chan, Service, Node, F) ->
%     case Mod:get_subscribed(LServer, Chan, Service, Node) of
% 	{ok, Subscribers} ->
% 	    lists:foreach(
% 	      fun(To) ->
% 		      Msg = xmpp:set_to(F(To), To),
% 		      ejabberd_router:route(Msg)
% 	      end, Subscribers);
% 	{error, db_failure} ->
% 	    ok
%     end.

multicast(Mod, LServer, Chan, Service, Node, F) ->
	From = jid:make(Chan,Service,<<"">>),
  IsValid = fly_mod_utils:validate_license(LServer, true, <<"chat">>),
  if IsValid =:= true ->
	case Mod:get_subscribed(LServer, Chan, Service, Node) of
		{ok, Subscribers} ->
			Pkt = xmpp:set_type(F(normal), normal),
			Stanza = xmpp:encode(Pkt),
			if Node =:= <<"urn:xmpp:mix:nodes:messages">>  ->
				Content = get_message_content(Stanza , Pkt),
				[_, CMessageId, _, _, _, CEditMsgId ] = Content,
				if (CEditMsgId =:= CMessageId) or (CEditMsgId =:= <<"">>) ->
				spawn(?MODULE, send_group_push_message, [F,Node,Subscribers,LServer,Chan,Service,Stanza,Content]);
				true ->
				 ok
				end;
			true ->
				Content  = ok
			end,
			MsgContent=Content,
			% Bulk Insert Starts
			if Node =:= <<"urn:xmpp:mix:nodes:messages">> ->

				[MessageType, MessageId, MesssageSend, _GroupName, MsgData, EditmsgId] = MsgContent,

				% fly_mod_offline_push:queryexecfunctions(LServer, <<"group_insert">>, From, MsgContent, Subscribers);
				TimestampNew = fly_add_timestamp:now_to_microseconds(erlang:now()),
				FlatTimeStampNew = lists:flatten(io_lib:format("~p", [TimestampNew])),
				#jid{luser = FromUser} = From,
				SUser = fly_mod_utils:get_user_from_string_jid(MesssageSend),
				if EditmsgId =:= <<"">> ->
					EditMsgId = MessageId;
				true ->
					EditMsgId = EditmsgId
				end,
				if (EditMsgId =:= MessageId) or (EditMsgId =:= <<"">>) ->
				InsertStatement = <<"insert into message_status (from_user,to_user,status, recent,message_id, edit_message_id, message_type,txt,chat_type,from_notification, message_time,to_notification,message_notification,received_at,seen_at, meta_data) values ">>,
			   RecentInsert = <<"insert into chat_recent (from_user, to_user,  message_id, message_from, txt, chat_type, message_type,  notification_to, unread, message_time,meta_data) values ">>,
				ValueStatement = lists:map(fun(Part) ->
					#jid{luser = ToUser} = Part,
					string:concat("", ", ('" ++ binary_to_list(FromUser) ++ "', '" ++ binary_to_list(ToUser) ++ "', 0,1, '" ++ binary_to_list(MessageId) ++ "', '" ++ binary_to_list(EditMsgId) ++ "','" ++ binary_to_list(MessageType) ++ "', '" ++ binary_to_list(MsgData) ++"', 'normal', '" ++ binary_to_list(MesssageSend) ++ "', '" ++ FlatTimeStampNew ++ "','',0,'0000-00-00 00:00:00','0000-00-00 00:00:00','{}')")
				end, Subscribers),

				RecentValueStatement = lists:map(fun(Part) ->
					#jid{luser = ToUser} = Part,

					if ToUser =:= SUser ->
						Unread = <<"0">>;
					true ->
						Unread = <<"1">>
					end,
					string:concat("", ", ('" ++ binary_to_list(FromUser) ++ "', '" ++ binary_to_list(ToUser) ++ "', '" ++ binary_to_list(MessageId) ++ "', '"  ++ binary_to_list(SUser) ++ "', '"  ++ binary_to_list(MsgData) ++ "', 'normal', '" ++ binary_to_list(MessageType) ++ "', '', '" ++ binary_to_list(Unread) ++ "', '" ++ FlatTimeStampNew ++ "','{}')")
				end, Subscribers),

				DuplicateStatement = "ON DUPLICATE KEY UPDATE to_user = values(to_user), message_id = '" ++ binary_to_list(MessageId) ++"' ;",
				RecentDuplicateStatement = " ON DUPLICATE KEY UPDATE message_id = values(message_id), message_from = values(message_from), txt = values(txt), chat_type = values(chat_type), message_type = values(message_type),  notification_to = values(notification_to), unread = unread + values(unread), status = 0, recall_status = 0, favourite_status = 0, message_time= values(message_time), created_at = NOW();",
				[_|NewVal] = re:replace(ValueStatement, ",", ""),
				[_|RecentNewVal] = re:replace(RecentValueStatement, ",", ""),

				FinalQuery = binary_to_list(InsertStatement) ++ binary_to_list(NewVal) ++ DuplicateStatement,
				RecentFinalQuery = binary_to_list(RecentInsert) ++ binary_to_list(RecentNewVal) ++ RecentDuplicateStatement,
				ejabberd_sql:sql_query(LServer, [FinalQuery]),
				ejabberd_sql:sql_query(LServer, [RecentFinalQuery]);
				true ->
				ejabberd_sql:sql_query(LServer, [<<"update  message_status set status = 0, edit_status = 1, received_at = '0000-00-00 00:00:00' ,seen_at = '0000-00-00 00:00:00',  edit_message_id = '">>, EditMsgId, <<"', txt  = '">>, MsgData , <<"' where message_id = '">>, MessageId, <<"' ;">>]),
				ejabberd_sql:sql_query(LServer, [<<"update chat_recent set status = 0,  txt  = '">>, MsgData , <<"'where message_id = '">>, MessageId, <<"';">>])
				end,
				ejabberd_sql:sql_query( LServer, [<<"insert into chat_message_edit_history (from_user,to_user, message_id, edit_message_id, chat_type, msg) values ('">>, SUser, <<"', '">>, FromUser,  <<"', '">>, MessageId, <<"', '">>, EditMsgId, <<"', 'normal', '">>, MsgData, <<"');">>]);
			true ->
				ok
			end,
			% Bulk Insert Ends

		spawn(?MODULE, process_group_msg, [Subscribers, MsgContent, From, F, Node, Stanza, Pkt, Chan]);

	{error, db_failure} ->
	  ok
    end;
true ->
    ok
end.

%% Contus Added send_group_push_message
send_group_push_message(_F,Node,Members,LServer,Chan,Service,Stanza,MessageContent) ->
	From = jid:make(Chan,Service,<<"">>),
	if Members =/= []  ->

		fly_mod_offline_push:send_bulk_group_push(From,LServer,MessageContent,Members,Node,Stanza, <<"message">>);
		true ->

			ok
	end.

%% Contus Added get_message_content
get_message_content(Stanza, Pkt) ->
	ContentAcknowledge = xmpp:get_subtag(Pkt, #chatcontent{}),

	MessageContent = case fxml:get_subtag(Stanza, <<"mix">>) of
						false -> ok;
						Mix ->
							case fxml:get_subtag(Stanza, <<"body">>) of

								false -> ok;
								Body ->
								case fxml:get_subtag(Mix, <<"submission-id">>) of

									false -> ok;
									SubmissionID ->
									case fxml:get_subtag(Mix, <<"nick">>) of

										false ->  ok;
										Nick ->
										case fxml:get_subtag(Stanza, <<"subject">>) of

											false ->  ok;
											MsgType ->
											case fxml:get_subtag(Mix, <<"jid">>) of

												false -> ok;
												JidTag ->
													Id = fxml:get_tag_cdata(SubmissionID),
													SentFrom = fxml:get_tag_cdata(JidTag),
													MSG = fxml:get_tag_cdata(Body),
													Type = fxml:get_tag_cdata(MsgType),
													GroupName = fxml:get_tag_cdata(Nick),
													if ContentAcknowledge == false ->
													EditMsgid = Id;
													true ->
													{_,_,_,_,_,_, _,EditMsgid,_} = ContentAcknowledge
												    end,
													[Type, Id, SentFrom, GroupName, MSG, EditMsgid]
											end

										end
									end
								end
							end
					end,
	MessageContent.

%% Contus Added save_message
save_message(From,TServer,MessageContent,To,Node,Stanza, _MsgTime) ->
	#jid{luser = TUser} = To,
	if Node == <<"urn:xmpp:mix:nodes:messages">>  ->
			if MessageContent /= ok ->
				NewPacket = xmpp:set_from_to(xmpp:decode(Stanza),From,To),
				GetTimestamp = fxml:get_subtag_with_xmlns(Stanza, <<"timestamp">>, <<"urn:xmpp:messagetime">>),
				if GetTimestamp =:= false ->
					Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),
					FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
					XMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
						children = []},
					Packtes = fxml:append_subtags(xmpp:encode(NewPacket), [XMLTag]),
					TimeStampedPacket = xmpp:decode(Packtes);
				true ->
						TimeStampedPacket = xmpp:decode(NewPacket)
				end,
				mod_offline:store_packet({TimeStampedPacket,TimeStampedPacket});
			true ->
				ok
			end;
	true ->
      case fly_mod_utils:get_mobile_user_message(TUser, TServer) of
        true ->
					NewPacket = xmpp:set_from_to(xmpp:decode(Stanza),From,To),
					GetTimestamp = fxml:get_subtag_with_xmlns(Stanza, <<"timestamp">>, <<"urn:xmpp:messagetime">>),
					if GetTimestamp =:= false ->
						Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),
						FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
						XMLTag = #xmlel{name = <<"timestamp">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:messagetime">>}, {<<"time">>, list_to_binary(FlatTimeStamp)}],
							children = []},
						TimeStampedPacketS = fxml:append_subtags(xmpp:encode(NewPacket), [XMLTag]),
						TimeStampedPacket = xmpp:decode(TimeStampedPacketS);
					true ->
						TimeStampedPacket = xmpp:decode(NewPacket)
					end,
          mod_offline:store_packet({TimeStampedPacket,TimeStampedPacket});
				false ->
					ok
		end
	end.

	process_group_msg(Subscribers, MsgContent, From, F, Node, Stanza, Pkt, Chan) ->
		lists:foreach(
			fun(To) ->
				Msg1 = xmpp:set_to(F(To), To),
				Msg = xmpp:set_type(Msg1, normal),
				Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),
				FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
				Msg2 = xmpp:set_subtag(Msg, #timestampmsg{time= list_to_binary(FlatTimeStamp)}),
				#jid{luser = TUser, lserver = LServer, lresource = _LResource} = To,

				if Node =:= <<"urn:xmpp:mix:nodes:participants">>  ->
					MessageContent = participants,
					case fxml:get_subtag(Stanza, <<"event">>) of
						false -> ok;
						Event ->
							case fxml:get_subtag(Event, <<"items">>) of
								false -> ok;
								Items ->
								case fxml:get_subtag(Items, <<"item">>) of
									false -> ok;
									Item ->
									case fxml:get_tag_attr_s(<<"publisher">>, Item) of
										false -> ok;
										Publisher ->
										case fxml:get_subtag(Item, <<"participant">>) of
											false ->
												case fxml:get_subtag(Item, <<"jid">>) of
											    false ->
													ok;
												RetractId ->
							 RemovedUser = fxml:get_tag_cdata(RetractId),

													NodeId =  fxml:get_tag_attr_s(<<"id">>, Item),
													IdValue = xmpp:get_id(Pkt),
													Content1 = [Chan,Publisher,RemovedUser,NodeId,<<"">>,IdValue],

													Resources = ejabberd_sm:get_user_resources(TUser, LServer),
							if LServer =/= <<"vezbi-xmpp.mirrorfly.com">> ->
														fly_mod_offline_push:send_bulk_group_push(From,LServer,Content1,TUser,Node,Stanza,<<"remove">>);
													true ->
														ok
							end


												end,
												fly_mix_group_chat:carboncall_message(TUser ,LServer, Msg2, From),
												ok;
											Participant ->
											case fxml:get_tag_attr_s(<<"jid">>, Participant) of
												false -> ok;
											Jid ->
												NodeId =  fxml:get_tag_attr_s(<<"id">>, Item),
												GroupName = fxml:get_tag_attr_s(<<"nick">>, Participant),
												IdValue = xmpp:get_id(Pkt),
												Content1 = [Chan,Publisher,Jid,NodeId,GroupName,IdValue],
												[U,_] = binary:split(Jid, <<"@">>),
						    Resources = ejabberd_sm:get_user_resources(TUser, LServer),
												if LServer =/= <<"vezbi-xmpp.mirrorfly.com">> ->
												fly_mod_offline_push:send_bulk_group_push(From,LServer,Content1,TUser,Node,Stanza,<<"added">>);
												true ->
												ok
											    end,

												fly_mix_group_chat:carboncall_message(TUser ,LServer, Msg2, From)
											end
										end
									end
								end
							end
					end;
					Node =:= <<"urn:xmpp:mix:nodes:messages">> ->
						MessageContent = MsgContent;
					true ->
						MessageContent = ok
				end,
				ejabberd_router:route(Msg2),
				save_message(From,LServer,MessageContent,To,Node,Stanza, list_to_binary(FlatTimeStamp))
		end, Subscribers).

-spec notify_participant_joined(module(), binary(),
	jid(), jid(), binary(), binary(), binary()) -> ok.
notify_participant_joined(Mod, LServer, To, From, ID, [Nick, GroupCreate, Publisher, PubID, CustomAttr],MsgId) ->
    {Chan, Host, _} = jid:tolower(To),
    #jid{user = FUser, lserver = FServer} = From,
    PublisherJID = jid:make(fly_mod_utils:get_user_from_string_jid(Publisher),FServer,<<"">>),
    #jid{user = PUser, lserver = PServer} = PublisherJID,
    Vcard = case catch fly_mod_utils:get_vcard(FServer, FUser) of
      {selected, [{GVCARD, _GrpCreatedAt}]} ->
        xmpp:encode(fxml_stream:parse_element(GVCARD));
      {selected, []} ->
        #xmlel{name = <<"vCard">>};
      _ ->
        #xmlel{name = <<"vCard">>}
      end,

      PublisherVcard = case catch fly_mod_utils:get_vcard(PServer, PUser) of
      {selected, [{VCARD, _CreatedAt}]} ->
        xmpp:encode(fxml_stream:parse_element(VCARD));
      {selected, []} ->
        #xmlel{name = <<"vCard">>};
      _ ->
        #xmlel{name = <<"vCard">>}
      end,

    Participant = #mix_participant{jid = jid:remove_resource(From),
				   nick = Nick, sub_els=[Vcard]},
    Item = #ps_item{id = ID, publisher = Publisher, group_create = GroupCreate,
				   sub_els = [xmpp:encode(Participant), #xmlel{name = <<"publisher">>, attrs = [{<<"item_id">>, PubID}, {<<"jid">>, jid:to_string(PublisherJID)}], children = [PublisherVcard]}, CustomAttr]},
    Items = #ps_items{node = ?NS_MIX_NODES_PARTICIPANTS,
		      items = [Item]},
    Event = #ps_event{items = Items},
    Msg = #message{from = jid:remove_resource(To),
		   id = MsgId,
		   sub_els = [Event]},
    multicast(Mod, LServer, Chan, Host,
	      ?NS_MIX_NODES_PARTICIPANTS,
	      fun(_) -> Msg end).


	      -spec notify_participant_left(module(), binary(), jid(), binary(), jid(), jid(), binary(), binary()) -> ok.

	      notify_participant_joined_api(LServer, To, From, [Nick, Publisher, RouteToJid, JIDs ],MsgId) ->
		      {Chan, Host, _} = jid:tolower(To),
		      ServerHost = ejabberd_router:host_of_route(Host),
                      Mod = gen_mod:db_mod(ServerHost, ?MODULE),
		      #jid{user = FUser, lserver = FServer} = From,
		      PublisherJID = jid:make(fly_mod_utils:get_user_from_string_jid(Publisher),FServer),
		      #jid{user = PUser, lserver = PServer} = PublisherJID,
                      ?INFO_MSG("From ~p",[From]),
		      Vcard = case catch fly_mod_utils:get_vcard(FServer, FUser) of
			      {selected, [{GVCARD, _GrpCreatedAt}]} ->
			      xmpp:encode(fxml_stream:parse_element(GVCARD));
			      {selected, []} ->
			      #xmlel{name = <<"vCard">>};
			      _ ->
			      #xmlel{name = <<"vCard">>}
			      end,

			      PublisherVcard = case catch fly_mod_utils:get_vcard(PServer, PUser) of
			      {selected, [{VCARD, _CreatedAt}]} ->
			      xmpp:encode(fxml_stream:parse_element(VCARD));
			      {selected, []} ->
			      #xmlel{name = <<"vCard">>};
			      _ ->
			      #xmlel{name = <<"vCard">>}
			      end,
                      ItemId = p1_rand:get_string(),
		      Participant = #mix_participant{jid = jid:remove_resource(From),
						      nick = Nick, sub_els=[Vcard]},
		      Item = #ps_item{id = ItemId, publisher = Publisher,
					      sub_els = [xmpp:encode(Participant), #xmlel{name = <<"publisher">>, attrs = [{<<"item_id">>, p1_rand:get_string()}, {<<"jid">>, jid:to_string(PublisherJID)}], children = [PublisherVcard]},#xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, ""}]}]},
		      Items = #ps_items{node = ?NS_MIX_NODES_PARTICIPANTS,
					      items = [Item]},
		      Event = #ps_event{items = Items},
		      %%MsgId = p1_rand:get_string(),
		      Msg = #message{from = jid:remove_resource(To),
			      to = jid:remove_resource(RouteToJid),
				      id = MsgId,
				      type = normal,
					      sub_els = [Event]},
		      Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),
		      FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
		      Msg2 = xmpp:set_subtag(Msg, #timestampmsg{time= list_to_binary(FlatTimeStamp)}),
		      #jid{user = TUser, lserver = TServer} = RouteToJid,
		      lists:foreach(fun(ToJid) ->
			RouteJid = jid:make(ToJid, TServer, <<>>),
			ejabberd_router:route(To, RouteJid, Msg2),
			mod_offline:store_packet({RouteJid,xmpp:decode(Msg2)}),
			Stanza = xmpp:encode(Msg2),
			Node = ?NS_MIX_NODES_PARTICIPANTS,
			Content1 = [Chan,Publisher,jid:to_string(From),ItemId,Nick,MsgId],
			if TServer =/= <<"vezbi-xmpp.mirrorfly.com">> ->
			fly_mod_offline_push:send_bulk_group_push(To,TServer,Content1,ToJid,Node,Stanza,<<"added">>);
			true ->
			ok
                        end,
			fly_mix_group_chat:carboncall_message(ToJid ,TServer, Msg2, To)
		      end, JIDs).

	      notify_participant_left_api( _LServer, To, FromJid, BFromJid, RouteToJid, JIDs) ->
		  {Chan, Host, _} = jid:tolower(To),
		  {From, Server, _} = jid:tolower(FromJid),
		  {BFrom, BServer, _} = jid:tolower(BFromJid),
		  ServerHost = ejabberd_router:host_of_route(Host),
                  Mod = gen_mod:db_mod(ServerHost, ?MODULE),
		  ItemId = p1_rand:get_string(),
		  RetractId = p1_rand:get_string(),
		  RemovedUser = [{xmlcdata, <<BFrom/binary, <<"@">>/binary, BServer/binary>>}],
		  Publisher = <<From/binary,$@, Server/binary>>,
			Item = #ps_item{id = ItemId, publisher = Publisher, sub_els=[#xmlel{name = <<"jid">>, attrs = [], children = RemovedUser}]},
			      Items = #ps_items{node = ?NS_MIX_NODES_PARTICIPANTS,
				    retract = RetractId, items = [Item]},
		  Event = #ps_event{items = Items},
		  MsgId = p1_rand:get_string(),
		  Msg = #message{from = jid:remove_resource(To),
				 id = MsgId,
				 sub_els = [Event]},
		      Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),
		      FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),
		      Msg2 = xmpp:set_subtag(Msg, #timestampmsg{time= list_to_binary(FlatTimeStamp)}),
		      ejabberd_router:route(To, RouteToJid, Msg2),
		      #jid{user = TUser, lserver = TServer} = RouteToJid,
		      lists:foreach(fun(ToJid) ->
			RouteJid = jid:make(ToJid, TServer, <<>>),
			ejabberd_router:route(To, RouteJid, Msg2),
			  mod_offline:store_packet({RouteJid,xmpp:decode(Msg2)}),
			  Stanza = xmpp:encode(Msg2),
			  Node = ?NS_MIX_NODES_PARTICIPANTS,
			  Content1 = [Chan,Publisher,RemovedUser,ItemId,<<"">>,MsgId],
			  if TServer =/= <<"vezbi-xmpp.mirrorfly.com">> ->
			  fly_mod_offline_push:send_bulk_group_push(To,TServer,Content1,ToJid,Node,Stanza,<<"remove">>);
			  true ->
			  ok
              end,
		  fly_mix_group_chat:carboncall_message(ToJid ,TServer, Msg2, To)
			end, JIDs).



notify_participant_left(Mod, LServer, To, ID, FromJid, BFromJid, AdminUser, MsgId) ->
    {Chan, Host, _} = jid:tolower(To),
    {From, Server, _} = jid:tolower(FromJid),
    {BFrom, BServer, _} = jid:tolower(BFromJid),
    Item = #ps_item{id = ID, publisher = <<From/binary,$@, Server/binary>>, admin_user = AdminUser, sub_els=[#xmlel{name = <<"jid">>, attrs = [], children = [{xmlcdata, <<BFrom/binary, <<"@">>/binary, BServer/binary>>}]}]},
    Items = #ps_items{node = ?NS_MIX_NODES_PARTICIPANTS,
		      retract = ID, items = [Item]},
    Event = #ps_event{items = Items},
    Msg = #message{from = jid:remove_resource(To),
		   id = MsgId,
		   sub_els = [Event]},
    multicast(Mod, LServer, Chan, Host, ?NS_MIX_NODES_PARTICIPANTS,
	     fun(_) -> Msg end).

-spec make_id(jid(), binary()) -> binary().
make_id(JID, Key) ->
    Data = jid:encode(jid:tolower(jid:remove_resource(JID))),
    xmpp_util:hex(misc:crypto_hmac(sha256, Data, Key, 10)).

-spec make_channel_id(jid(), binary()) -> jid().
make_channel_id(JID, ID) ->
	{U, S, R} = jid:split(JID),
	jid:make(<<ID/binary, $#, U/binary>>, S, R).

%%%===================================================================
%%% Error generators
%%%===================================================================
-spec db_error(stanza()) -> stanza_error().
db_error(Pkt) ->
    Txt = ?T("Database failure"),
    xmpp:err_internal_server_error(Txt, xmpp:get_lang(Pkt)).

-spec channel_exists_error(stanza()) -> stanza_error().
channel_exists_error(Pkt) ->
    Txt = ?T("Channel already exists"),
    xmpp:err_conflict(Txt, xmpp:get_lang(Pkt)).

-spec no_channel_error(stanza()) -> stanza_error().
no_channel_error(Pkt) ->
    Txt = ?T("Channel does not exist"),
    xmpp:err_item_not_found(Txt, xmpp:get_lang(Pkt)).

-spec not_joined_error(stanza()) -> stanza_error().
not_joined_error(Pkt) ->
    Txt = ?T("You are not joined to the channel"),
    xmpp:err_forbidden(Txt, xmpp:get_lang(Pkt)).

-spec unsupported_error(stanza()) -> stanza_error().
unsupported_error(Pkt) ->
    Txt = ?T("No module is handling this query"),
    xmpp:err_service_unavailable(Txt, xmpp:get_lang(Pkt)).

-spec ownership_error(stanza()) -> stanza_error().
ownership_error(Pkt) ->
    Txt = ?T("Owner privileges required"),
    xmpp:err_forbidden(Txt, xmpp:get_lang(Pkt)).

%%%===================================================================
%%% IQ handlers
%%%===================================================================
-spec register_iq_handlers(binary()) -> ok.
register_iq_handlers(Host) ->
    gen_iq_handler:add_iq_handler(ejabberd_local, Host, ?NS_DISCO_INFO,
				  ?MODULE, process_disco_info),
    gen_iq_handler:add_iq_handler(ejabberd_local, Host, ?NS_DISCO_ITEMS,
				  ?MODULE, process_disco_items),
    gen_iq_handler:add_iq_handler(ejabberd_local, Host, ?NS_MIX_CORE_0,
				  ?MODULE, process_mix_core),
    gen_iq_handler:add_iq_handler(ejabberd_local, Host, ?NS_MIX_CORE_1,
				  ?MODULE, process_mix_core),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_DISCO_INFO,
				  ?MODULE, process_disco_info),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_DISCO_ITEMS,
				  ?MODULE, process_disco_items),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_MIX_CORE_0,
				  ?MODULE, process_mix_core),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_MIX_CORE_1,
				  ?MODULE, process_mix_core),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_PUBSUB,
				  ?MODULE, process_pubsub_query),
    gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_MAM_2,
				  ?MODULE, process_mam_query).

-spec unregister_iq_handlers(binary()) -> ok.
unregister_iq_handlers(Host) ->
    gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?NS_DISCO_INFO),
    gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?NS_DISCO_ITEMS),
    gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?NS_MIX_CORE_0),
    gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?NS_MIX_CORE_1),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_DISCO_INFO),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_DISCO_ITEMS),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_MIX_CORE_0),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_MIX_CORE_1),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_PUBSUB),
    gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_MAM_2).
