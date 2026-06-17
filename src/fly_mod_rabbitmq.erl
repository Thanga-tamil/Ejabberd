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

-export([publish/3, is_channel_alive/3, create_channel/2]).

-define(Q_DATA, <<"data">>).
-define(Q_API_DATA, <<"api_data">>).
-define(Q_API_CALL, <<"api_call">>).
-define(Q_API_MESSAGE, <<"api_message">>).

-define(LISTENER_MOD, mod_amqp_proc).
-define(LISTENER_PROC_FUN, process_listener_payload).
-define(LISTENER_LICENSE_DATA_FUN, update_license).
-define(LISTENER_PUSH_FUN, process_push).

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").

-record(state, {host :: binary(),
                connection :: pid(),
                ex :: binary(),
                tag = #{} :: #{any() => atom()},
                channels = #{} :: #{atom() => pid()},
                monitor = #{} :: #{pid() => reference()}}).

%% gen_mod callbacks %%

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

mod_opt_type(rabbitmq_host) ->
    fun iolist_to_binary/1;
mod_opt_type(rabbitmq_username) ->
    fun iolist_to_binary/1;
mod_opt_type(rabbitmq_exchange) ->
    fun iolist_to_binary/1;
mod_opt_type(rabbitmq_password) ->
    fun iolist_to_binary/1;
mod_opt_type(amqp_listener) ->
    fun(B) when is_boolean(B) -> B end;
mod_opt_type(queues) ->
    econf:list(econf:binary()).

mod_options(_Host) ->
    [{rabbitmq_host, undefined},
     {rabbitmq_username, undefined},
     {rabbitmq_exchange, undefined},
     {rabbitmq_password, undefined},
     {amqp_listener, false},
     {queues, []}].

%% gen_serve callbacks %%

init([Host | _]) ->
    ModOptions = gen_mod:get_module_opts(Host, ?MODULE),
    RabbitMQH = maps:get(rabbitmq_host, ModOptions),
    RabbitMQU = maps:get(rabbitmq_username, ModOptions),
    RabbitMQP = maps:get(rabbitmq_password, ModOptions),
    RabbitMQE = maps:get(rabbitmq_exchange, ModOptions),
    AmqpListner = maps:get(amqp_listener, ModOptions),
    Queues = maps:get(queues, ModOptions),

    logger:info("Initializing RabbitMQ module with host: ~p, 
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
             logger:info("rabbitMQ connection established: ~p", 
                       [Connection]),
            init_state(Connection, RabbitMQE, 
                    Host, AmqpListner, Queues);
        Error ->
            logger:error("init rabbitMQ connection failure " 
                         "with error =>: ~p", [Error]),
            {stop, ignore}
    end.

init_state(Connection, RabbitMQE, Host, true, Qs) ->
    Channels = create_channel(Connection, [subscription, publication]),
    {Channel, MonitorRef, Tags} = listen(Qs),
    {ok, #state{host = Host,
                connection = Connection,
                ex = RabbitMQE,
                tag = Tags,
                channels = Channels,
                monitor = #{Channel => MonitorRef}}};
init_state(Connection, RabbitMQE, Host, false, _) ->
    Channels = create_channel(Connection, publication),
    {ok, #state{host = Host, 
                connection = Connection, 
                ex = RabbitMQE, 
                channels = Channels}}.

listen(Qs) when is_list(Qs) -> 
    Key = channel_name(subscription),
    [[Channel]] = ets:match(rabbitmq, {Key, '$1'}),
    MonitorRef = erlang:monitor(process, Channel),
    
    Tags =
    lists:foldl(
        fun(Q, Acc) ->
            #'basic.consume_ok'{consumer_tag = Tag} =
            amqp_channel:call(
                Channel,
                #'basic.consume'{queue = Q, no_ack = true}
            ),
            logger:info("subscribed to queue: ~ts", [Q]),

            Acc#{Tag => Q}
        end, 
      #{}, Qs),
    
    {Channel, MonitorRef, Tags};

listen(Q) -> 
    Key = channel_name(subscription),
    [[Channel]] = ets:match(rabbitmq, {Key, '$1'}),
    MonitorRef = erlang:monitor(process, Channel),
    
    #'basic.consume_ok'{consumer_tag = Tag} =
    amqp_channel:call(Channel, 
                #'basic.consume'{queue = Q, no_ack = true}),

    logger:info("subscribed to queue: ~ts 
               with consumer tag: ~ts", [Q, Tag]),
    {Channel, MonitorRef, Tag}.

listen(down, Host, OldChannel) -> 

    Proc = gen_mod:get_module_proc(Host, ?MODULE),
    NewChannel = gen_server:call(Proc, 
                    {channel, subscription, OldChannel}),
    MonitorRef = erlang:monitor(process, NewChannel),

    ModOptions = gen_mod:get_module_opts(Host, ?MODULE),
    Queues = maps:get(queues, ModOptions),

    Tags =
    lists:foldl(
        fun(Q, Acc) ->
            #'basic.consume_ok'{consumer_tag = Tag} =
            amqp_channel:call(
                NewChannel,
                #'basic.consume'{queue = Q, no_ack = true}
            ),
            logger:info("re-subscribed to queue: ~ts", [Q]),

            Acc#{Tag => Q}
        end, 
      #{}, Queues),

    {NewChannel, MonitorRef, Tags}.

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

handle_cast({Type, Arg, PayPac}, State) ->
    Key = channel_name(Type),
    case State#state.channels of
        #{Key := Channel} ->
            publication(Arg, PayPac, Channel, State#state.ex)
    end,
    {noreply, State};
handle_cast(_, State) -> 
    {noreply, State}.

handle_info({#'basic.deliver'{consumer_tag = Tag},
            #amqp_msg{payload = Payload}}, State) ->

    try
        Tags = State#state.tag,
        Host = State#state.host,
        consumer_info(Payload, Host, maps:get(Tag, Tags)),
        {noreply, State}
    catch
        error:{_, invalid_json} = Error ->
            logger:error("invalid json payload => ~p " 
                         "error => ~p", [Payload, Error]),
        {noreply, State}
    end;
handle_info({'basic.consume_ok', _Tag}, State) ->
    {noreply, State};

handle_info({'DOWN', _Ref, process, OldChannel, Reason}, State) ->
    logger:error("rabbbit mq channel down => ~p "
                 "reason => ~p", [OldChannel, Reason]),

    Map = maps:remove(OldChannel, State#state.channels),
    {NewChannel, MonitorRef, Tags} = listen(down,
                                        State#state.host, 
                                        OldChannel),
    NewMap = maps:put(NewChannel, MonitorRef, Map),
    {noreply, State#state{channels = NewMap, tag = Tags}};
handle_info(_, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(Reason, State) ->
    close_connection(State#state.connection),
    logger:warning("~p mod ~p terminated", [?MODULE, Reason]),
    ok.

% ------------------------------------------------------------ %
% Functions to create | check alive | close rabbit-mq channels % 
% ------------------------------------------------------------ %
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

is_channel_alive(Host, Channel, Type) ->
  case {is_pid(Channel), is_process_alive(Channel)} of
    {true, true} ->
      logger:info("channel ~p is alive", [Type]),
      Channel;
    {true, false} -> 
      logger:info(
      "channel ~p is down, close existing & create a new one",
      [Type]),
      Proc = gen_mod:get_module_proc(Host, ?MODULE),
      gen_server:call(Proc, {channel, Type, Channel})
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

%% publication handlers starts %%

publish(Type, Arg, PayPac) -> 
    {Host, _} = Arg,
    Proc = gen_mod:get_module_proc(Host, ?MODULE),
    gen_server:cast(Proc, {Type, Arg, PayPac}).

publication({Host, RoutingKey}, 
            {Payload, Packet}, 
            Channel, Exchange)  ->
    BinPayload =
    case is_binary(Payload) of
        true -> Payload;
        false -> iolist_to_binary(Payload)
    end,
    logger(Packet, Exchange, RoutingKey, "publishing"),

    ActiveChannel = is_channel_alive(Host, Channel, publication),
    case amqp_channel:cast(ActiveChannel, 
        #'basic.publish'{exchange = Exchange, routing_key = RoutingKey},
        #amqp_msg{payload = BinPayload}) of
        ok ->
            logger:info("publication success in routingkey=> ~p",
            [RoutingKey]),
            logger(Packet, Exchange, RoutingKey, "published"),
            
            {ok, <<"success">>};
        Error ->
            logger(Packet, Exchange, RoutingKey, "publish_failed"),
            logger:info("Unable to send push messages to 
                        the rabbitmq: ~p", [Error])
    end.

%% publication handlers ends %%


%% subscription handlers starts %%

consumer_info(Payload, Host, Q) when Q =:= ?Q_API_DATA ->
    logger:info("Q :: ~p consumed :: ~p", [Q, Payload]),

    Map = jiffy:decode(Payload, [return_maps]),
    logger:info("decoded Map :: ~p", [Map]),
    Type = maps:get(<<"type">>, Map),

    if Type =:= false -> 
        ok;
    true ->
        subscription(?LISTENER_MOD, ?LISTENER_PROC_FUN,
            [Type, Map, Host])
    end;
consumer_info(Payload, Host, Q) when Q =:= ?Q_DATA ->
    logger:info("Q :: ~p consumed :: ~p", [Q, Payload]),

    Map = jiffy:decode(Payload, [return_maps]),
    logger:info("decoded Map :: ~p", [Map]),
    LicenseData = maps:get(<<"data">>, Map),

    subscription(?LISTENER_MOD, ?LISTENER_LICENSE_DATA_FUN,
        [LicenseData, Host]);

consumer_info(Payload, Host, Q) when Q =:= ?Q_API_MESSAGE ->
    logger:info("Q :: ~p consumed :: ~p", [Q, Payload]),

    Map = jiffy:decode(Payload, [return_maps]),
    logger:info("decoded Map :: ~p", [Map]),
    IsNotification = maps:get(<<"notification">>, Map),

    if IsNotification -> 
        subscription(?LISTENER_MOD, ?LISTENER_PUSH_FUN,
            [Map, Host]);
    true ->
        subscription(?LISTENER_MOD, ?LISTENER_PROC_FUN,
            [<<"message_delivery">>, Map, Host])
    end;

consumer_info(Payload, Host, Q) when Q =:= ?Q_API_CALL ->
    logger:info("Q :: ~p consumed :: ~p", [Q, Payload]),

    Map = jiffy:decode(Payload, [return_maps]),
    logger:info("decoded Map :: ~p", [Map]),
    Type = maps:get(<<"type">>, Map),

    case Type of 
        T when 
        T =:= <<"mediacall">>; 
        T =:= <<"carbonmediacall">> ->

            subscription(?LISTENER_MOD, ?LISTENER_PROC_FUN,
                            [Type, Map, Host]);
        _ ->
            
            subscription(?LISTENER_MOD, ?LISTENER_PROC_FUN,
                            [<<"call_activity">>, Map, Host])
    end;

consumer_info(Payload, _, UnknownTag) ->
    logger:info("consumed unknown tag :: ~p "
           "payload :: ~p", [UnknownTag, Payload]),
    ok.

subscription(Mod, Fun, Args) ->
    apply(Mod, Fun, Args).

%% subscription handlers ends %%
logger(false, _, _, _) ->
    ok;
logger(Pkt, Exchange, RoutingKey, Msg) ->
    Packet = xmpp:decode(Pkt),
    case Packet of
        #message{id = Id, 
                 from = #jid{user = FUser, lresource = FRes}, 
                 to = #jid{user = TUser, lresource = TRes}, 
                 type = Type} ->

        logger:info(Msg ++ 
                    " rabbitmq payload"
                    " from=~p"
                    " to=~p~n ~s",
                [FUser, TUser, 
                    jiffy:encode(#{
                        message_id => Id,
                        type => Type,
                        from_userid => FUser,
                        from_resource => FRes,
                        to_userid => TUser,
                        to_resource => TRes,
                        exchange => Exchange,
                        routing_key => RoutingKey
                    })]);
    _ ->
        ok
    end.
