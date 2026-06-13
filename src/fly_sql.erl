-module(fly_sql).

-author('Thangatamil').

-include("logger.hrl").

-export([insert/0, update/0, delete/3]).

insert() ->
    ok.

update() ->
    ok.

delete(Host, Tables, WhereClauses) when is_list(Tables) ->
   Cmds =
       [construct(Table, 0, Where, delete)
        || {Table, Where} <- lists:zip(Tables, WhereClauses)],
   call_transaction(Host, Cmds);

delete(Host, Table, WhereClause) ->
   call_transaction(Host, 
        [construct(Table, 0, WhereClause, delete)]).

call_transaction(Host, Arg) ->
    ejabberd_sql:sql_transaction(Host, Arg).


%% Construct query dynamically based on the args %% 
construct(Table, Columns, Values, insert) -> 
  [<<"INSERT INTO ">>, Table, <<"( ">>, Columns, <<" )">>, Values];

construct(Table, Set, WhereClause, update) -> 
  [<<"UPDATE ">>, Table, <<" SET ">>, Set, <<" WHERE ">>, WhereClause];

construct(Table, _, WhereClause, delete) -> 
  [<<"DELETE FROM ">>, Table, <<" WHERE ">>, WhereClause].