-module(fly_rabbitmq_worker).

-author('Thangatamil').

-behaviour(gen_server).

-define(Q_DATA, <<"data">>).
-define(Q_API_DATA, <<"api_data">>).
-define(Q_API_CALL, <<"api_call">>).
-define(Q_API_MESSAGE, <<"api_message">>).

-define(LISTENER_MOD, mod_amqp_proc).
-define(LISTENER_PROC_FUN, process_listener_payload).
-define(LISTENER_LICENSE_DATA_FUN, update_license).
-define(LISTENER_PUSH_FUN, process_push).

-export([start_link/0]).

-export([
    init/1,
    handle_cast/2,
    handle_call/3,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-export([process/3]).

start_link() ->
    gen_server:start_link(?MODULE, [], []).

process(Payload, Host, Queue) ->
    Workers = supervisor:which_children(fly_rabbitmq_worker_sup),

    {_, Pid, _, _} = lists:nth(rand:uniform(length(Workers)), Workers),

    gen_server:cast(Pid, {process, Payload, Host, Queue}).

init([]) ->
    {ok, #{}}.

handle_call(_, _, State) ->
    {reply, ok, State}.

handle_cast({process, Payload, Host, Queue}, State) ->
    try
        consumer_info(Payload, Host, Queue)
    catch
        Class:Reason:Stack ->
                logger:error("Worker failed ~p:~p~n~p", 
                                [Class, Reason, Stack])
    end,
    {noreply, State};


handle_cast(_, State) ->
    {noreply, State}.

handle_info(_, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(Reason, _State) ->
    logger:warning("~p terminating with reason: ~p", 
                   [?MODULE, Reason]),
    ok.



%% subscription handlers starts %%

consumer_info(Payload, Host, Q) 
                when Q =:= ?Q_DATA;
                     Q =:= ?Q_API_DATA; 
                     Q =:= ?Q_API_CALL;
                     Q =:= ?Q_API_MESSAGE ->

    logger:debug("Q :: ~p consumed :: ~p", [Q, Payload]),

    Map = jiffy:decode(Payload, [return_maps]),
    logger:debug("decoded Map :: ~p", [Map]),

    case Q of 
        ?Q_DATA -> 
            LicenseData = maps:get(<<"data">>, Map),
            subscription(?LISTENER_MOD, ?LISTENER_LICENSE_DATA_FUN,
                         [LicenseData, Host]);

        ?Q_API_MESSAGE -> 
            IsNotification = maps:get(<<"notification">>, Map),
            if IsNotification -> 
                subscription(?LISTENER_MOD, ?LISTENER_PUSH_FUN,
                             [Map, Host]);
            true ->
                subscription(?LISTENER_MOD, ?LISTENER_PROC_FUN,
                             [<<"message_delivery">>, Map, Host])
            end;
        _ ->
            Type = maps:get(<<"type">>, Map),
            case {Type, Q} of 
                {false, _} -> 
                    ok;
                {T, ?Q_API_CALL} 
                    when 
                    T =/= <<"mediacall">>,
                    T =/= <<"carbonmediacall">> ->
                        
                        subscription(?LISTENER_MOD, ?LISTENER_PROC_FUN,
                                     [<<"call_activity">>, Map, Host]);
                {_, _} ->
                    subscription(?LISTENER_MOD, ?LISTENER_PROC_FUN,
                                 [Type, Map, Host])
            end
    end;

consumer_info(Payload, _, UnknownTag) ->
    logger:info("consumed unknown tag :: ~p payload :: ~p", 
                [UnknownTag, Payload]).

subscription(Mod, Fun, Args) ->
    apply(Mod, Fun, Args).

%% subscription handlers ends %%

