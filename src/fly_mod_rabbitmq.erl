-module(fly_mod_rabbitmq).

-author('Thangatamil').

-behaviour(gen_mod).
-behaviour(gen_server).

%% gen_mod callbacks %%
-export([start/2, stop/1, reload/3, mod_opt_type/1,
         depends/2, mod_doc/0, mod_options/1]).

%% gen_server callbacks %%
-export([init/1, handle_call/3, handle_cast/2, 
         handle_info/2, terminate/2, code_change/3]).

-export([publish/3, is_channel_alive/2, create_channel/2]).

-define(LISTENER_MOD, mod_amqp_proc).
-define(LISTENER_FUN, proc_listener_payload).

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-define(Q_API_DATA, <<"api_data">>).

-record(state, {host :: binary(),
                connection :: pid(),
                ex :: binary(),
                channels = #{} :: #{atom() => pid()},
                monitor = #{} :: #{pid() => reference()}}).


start(Host, Opts) ->
    gen_mod:start_child(?MODULE, Host, Opts).

stop(Host) ->
    gen_mod:stop_child(?MODULE, Host).

reload(Host, NewOpts, OldOpts) ->
    Proc = gen_mod:get_module_proc(Host, ?MODULE),
    gen_server:cast(Proc, {reload, Host, NewOpts, OldOpts}).

depends(_Host, _Opts) ->
    [].

mod_doc() ->
    #{desc => "RabbitMQ integration module for ejabberd",
      author => "Thangatamil",
      version => "1.0.0"}.

mod_opt_type(rabbitmq_host) -> fun iolist_to_binary/1;
mod_opt_type(rabbitmq_username) -> fun iolist_to_binary/1;
mod_opt_type(rabbitmq_exchange) -> fun iolist_to_binary/1;
mod_opt_type(rabbitmq_password) -> fun iolist_to_binary/1;
mod_opt_type(amqp_listener) -> fun is_boolean/1;

mod_opt_type(_) ->
  [rabbitmq_host, 
   rabbitmq_username, 
   rabbitmq_password, 
   rabbitmq_exchange, 
   amqp_listener].

mod_options(_Host) ->
  [{rabbitmq_host, undefined},
    {rabbitmq_username, undefined},
    {rabbitmq_exchange, undefined},
    {rabbitmq_password, undefined},
    {amqp_listener, false}].


init([Host | _]) ->
    ModOptions = gen_mod:get_module_opts(Host, ?MODULE),
    RabbitMQH = maps:get(rabbitmq_host, ModOptions),
    RabbitMQU = maps:get(rabbitmq_username, ModOptions),
    RabbitMQP = maps:get(rabbitmq_password, ModOptions),
    RabbitMQE = maps:get(rabbitmq_exchange, ModOptions),
    AmqpListner = maps:get(amqp_listener, ModOptions),

    ?LOG_INFO("Initializing RabbitMQ module with host: ~p, 
               username: ~p, exchange: ~p, listener: ~p",
              [RabbitMQH, RabbitMQU, RabbitMQE, AmqpListner]),

    case amqp_connection:start(
        #amqp_params_network{
            host = binary_to_list(RabbitMQH),
            username = RabbitMQU,
            password = RabbitMQP,
            heartbeat = 30
        }) of
        {ok, Connection} ->
             ?LOG_INFO("rabbitMQ connection established: ~p", 
                       [Connection]),
            [Host] = ejabberd_option:hosts(),
            init_state(Connection, RabbitMQE, Host, AmqpListner);
        Error ->
            ?LOG_ERROR("init rabbitMQ connection failure with 
                        error =>: ~p", [Error]),
            {stop, ignore}
    end.

init_state(Connection, RabbitMQE, Host, true) ->
    Channels = create_channel(Connection, [subscription, publication]),
    {Channel, MonitorRef} = listen(?Q_API_DATA),
    {ok, #state{host = Host, 
                       connection = Connection, 
                       ex = RabbitMQE, 
                       channels = Channels, 
                       monitor = #{Channel => MonitorRef}}};
init_state(Connection, RabbitMQE, Host, false) ->
    Channels = create_channel(Connection, publication),
    {ok, #state{host = Host, 
                connection = Connection, 
                ex = RabbitMQE, 
                channels = Channels}}.

listen(Q) -> 
    Key = channel_name(subscription),
    [[Channel]] = ets:match(rabbitmq, {Key, '$1'}),
    MonitorRef = erlang:monitor(process, Channel),
    
    #'basic.consume_ok'{consumer_tag = Tag} =
    amqp_channel:call(Channel, 
                #'basic.consume'{queue = Q, no_ack = true}),

    ?LOG_INFO("subscribed to queue: ~ts 
               with consumer tag: ~ts", [Q, Tag]),
    {Channel, MonitorRef}.

listen(down, OldChannel, Q) -> 

    NewChannel = gen_server:call(?MODULE, 
                    {channel, subscription, OldChannel}),
    MonitorRef = erlang:monitor(process, NewChannel),

    #'basic.consume_ok'{consumer_tag = Tag} =
    amqp_channel:call(NewChannel, 
                #'basic.consume'{queue = Q, no_ack = true}),

    ?LOG_INFO("re-subscribing to queue: ~ts 
               with consumer tag: ~ts", [?Q_API_DATA, Tag]),
    {NewChannel, MonitorRef}.

handle_call({channel, Type, OldChannel}, _From, State) ->
    close_channels(OldChannel),
    ChannelName = channel_name(Type),
    case create_channel(State#state.connection, Type) of 
        #{ChannelName := ChannelVal} -> 
            Channels = maps:put(ChannelName, ChannelVal, 
                                State#state.channels),
            {reply, ChannelVal, State#state{channels = Channels}};
        #{} ->
            {noreply, State}
    end;
handle_call(Key, _From, State) ->
    ChannelKey = channel_name(Key),
    case State#state.channels of 
        #{ChannelKey := ChannelVal} ->
            {reply, ChannelVal, State}
    end.

handle_cast({Type, RoutingKey, PayPac}, State) ->
    Key = channel_name(Type),
    case State#state.channels of
        #{Key := Channel} ->
            publication(RoutingKey, PayPac, Channel, State#state.ex)
    end,
    {noreply, State};
handle_cast(_, State) -> 
    {noreply, State}.

handle_info({#'basic.deliver'{}, #amqp_msg{payload = Payload}}, State) ->
    ?LOG_INFO("consumed:: ~p", [Payload]),
    try
        Map = jiffy:decode(Payload, [return_maps]),
        ?LOG_INFO("decoded Map:: ~p", [Map]),
        Type = maps:get(<<"type">>, Map),

        if Type =:= false -> 
            ok;
        true ->
            subscription(?LISTENER_MOD, ?LISTENER_FUN,
            [Type, Map, State#state.host])
        end,
        {noreply, State}
    catch
        error:{_, invalid_json} = Error ->
            ?LOG_ERROR("invalid json payload => ~p error => ~p",
            [Payload, Error]),
            {noreply, State}
    end;
handle_info({'basic.consume_ok', _Tag}, State) ->
    {noreply, State};

handle_info({'DOWN', _Ref, process, OldChannel, Reason}, State) ->
    ?LOG_ERROR("rabbbit mq channel down => ~p 
                reason => ~p", [OldChannel, Reason]),

    Map = maps:remove(OldChannel, State#state.channels),
    {NewChannel, MonitorRef} = listen(down, OldChannel, ?Q_API_DATA),
    NewMap = maps:put(NewChannel, MonitorRef, Map),
    {noreply, State#state{channels = NewMap}};
handle_info(_, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(Reason, State) ->
    close_connection(State#state.connection),
    ?LOG_INFO("~p mod ~p terminated", [?MODULE, Reason]),
    ok.

% ------------------ %
% Internal functions % 
% ------------------ %
create_channel(Connection, Types) when is_list(Types) ->
    ets:new(rabbitmq, 
            [set, public, 
            named_table, 
            {read_concurrency, true}, 
            {write_concurrency, true}]),

    lists:foldl(
        fun(Type, Acc) ->
            ChannelName = channel_name(Type),
            case amqp_connection:open_channel(Connection) of
                {ok, Channel} ->
                    ets:insert(rabbitmq, {ChannelName, Channel}),
                    Acc#{ChannelName => Channel};
                {error, _} ->
                    Acc
            end
        end, #{}, Types);
create_channel(Connection, Type) when is_atom(Type) ->
    ChannelName = channel_name(Type),
    case amqp_connection:open_channel(Connection) of
        {ok, Channel} ->
            #{ChannelName => Channel};
        {error, _} ->
            #{}
    end;
create_channel(_, _) ->
    #{}.

is_channel_alive(Channel, Type) ->
  case {is_pid(Channel), is_process_alive(Channel)} of
    {true, true} ->
      ?LOG_INFO("channel ~p is alive", [Type]),
      Channel;
    {true, false} -> 
      ?LOG_INFO(
      "channel ~p is down, close existing & create a new one",
      [Type]),
      gen_server:call(?MODULE, {channel, Type, Channel})
  end.


channel_name(Type) when is_atom(Type) ->
    BinType = atom_to_binary(Type),
    binary_to_atom(<<BinType/binary, "_", "channel">>).


close_connection({pid, Pid}) ->
    amqp_connection:close(Pid),
    ok;
close_connection(Pid) when is_pid(Pid) ->
    amqp_connection:close(Pid),
    ok;    
close_connection(_) ->
    bad_return.

close_channels(Channels) when is_list(Channels) -> 
    lists:foreach(
        fun({_Mod, Channel}) -> 
            amqp_channel:close(Channel)
        end, Channels),
    ok;
close_channels(Channel) when is_pid(Channel) -> 
    amqp_channel:close(Channel),
    ok;
close_channels({_Mod, Channel}) when is_pid(Channel) -> 
    amqp_channel:close(Channel),
    ok;
close_channels(_) ->
    bad_return.

publish(Type, RoutingKey, PayPac) -> 
    gen_server:cast(?MODULE, 
        {Type, RoutingKey, PayPac}).

publication(RoutingKey, {Payload, Packet}, Channel, Exchange)  ->
    BinPayload =
    case is_binary(Payload) of
        true -> Payload;
        false -> iolist_to_binary(Payload)
    end,
    logger(Packet, Exchange, RoutingKey, "publishing"),

    ActiveChannel = is_channel_alive(Channel, publication),
    case amqp_channel:cast(ActiveChannel, 
        #'basic.publish'{exchange = Exchange, routing_key = RoutingKey},
        #amqp_msg{payload = BinPayload}) of
        ok ->
            ?LOG_INFO("publication success in routingkey=> ~p",
            [RoutingKey]),
            logger(Packet, Exchange, RoutingKey, "published"),
            
            {ok, <<"success">>};
        Error ->
            logger(Packet, Exchange, RoutingKey, "publish_failed"),
            ?LOG_ERROR("Unable to send push messages to 
                        the rabbitmq: ~p", [Error])
    end.

subscription(Mod, Fun, Args) ->
    apply(Mod, Fun, Args).

logger(Pkt, Exchange, RoutingKey, Msg) ->
    MsgId = Pkt#message.id,
    Type = Pkt#message.type,
    {FUser, _, FRes} = jid:tolower(Pkt#message.from),
    {TUser, _, TRes} = jid:tolower(Pkt#message.to),
        
    ?LOG_INFO(Msg ++ " rabbitmq payload from=~p to=~p ", [Msg]),

    Map = #{
            message_id => MsgId,
            type => Type,
            from_user_id => FUser,
            from_resource => FRes,
            to_user_id => TUser,
            to_resource => TRes,
            exchange => Exchange,
            routing_key => RoutingKey
        },
    
    io:format("~p~n", [Map]).
