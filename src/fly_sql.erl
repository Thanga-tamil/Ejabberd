-module(fly_sql).

-author('Thangatamil').

-include("logger.hrl").

-export([insert/0, get_map/4, 
         update/0, delete/3]).

insert() ->
    ok.

get_map(Host, Table, Selects, Where) ->
    case get(Host, Table, Selects, Where) of
        {atomic, {selected, Columns, [Row]}} ->
            maps:from_list(lists:zip(Columns, Row));

        {atomic, {selected, _Columns, []}} ->
            #{};

        Error ->
            Error
    end.

get(Host, Table, Selects, Where) -> 
  Cmd = fun() ->
          ejabberd_sql:sql_query_t(
            construct(Table, Selects, Where, get))
        end,
  transaction(Host, Cmd).

update() ->
    ok.

delete(Host, Tables, WhereClauses) when is_list(Tables) ->
   Cmds =
       [construct(Table, 0, Where, delete)
        || {Table, Where} <- lists:zip(Tables, WhereClauses)],
   transaction(Host, Cmds);

delete(Host, Table, WhereClause) ->
   transaction(Host, 
        [construct(Table, 0, WhereClause, delete)]).

transaction(Host, Arg) ->
    Start = erlang:monotonic_time(millisecond),

    Result = ejabberd_sql:sql_transaction(Host, Arg),

    End = erlang:monotonic_time(millisecond),

    logger:info("?mod: ~p " 
                "SQL transaction took ~p ms", 
                [?MODULE, End - Start]),

    Result.


%% Construct query dynamically based on the args %% 
construct(Table, Columns, Values, insert) -> 
  [<<"INSERT INTO ">>, Table, <<"( ">>, Columns, <<" )">>, Values];

construct(Table, Selects, Where, get) -> 
  [<<"SELECT ">>, Selects, <<" From ">>, Table, <<" WHERE ">>, Where, <<";">>];

construct(Table, Set, WhereClause, update) -> 
  [<<"UPDATE ">>, Table, <<" SET ">>, Set, <<" WHERE ">>, WhereClause];

construct(Table, _, WhereClause, delete) -> 
  [<<"DELETE FROM ">>, Table, <<" WHERE ">>, WhereClause].