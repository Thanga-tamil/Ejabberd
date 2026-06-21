-module(fly_rabbitmq_worker_sup).

-author('Thangatamil').

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    PoolSize = 20,

    Workers =
        [#{id => {worker, N},
           start => {fly_rabbitmq_worker,
                     start_link,
                     []},
           restart => permanent,
           shutdown => 5000,
           type => worker,
           modules => [fly_rabbitmq_worker]}
         || N <- lists:seq(1, PoolSize)],

    {ok, {{one_for_one, 5, 10}, Workers}}.