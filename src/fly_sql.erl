-module(fly_sql).

-author('Thangatamil').

-include("logger.hrl").

-export([insert/0, update/0, delete/3]).

-export([construct_insert_q/3, 
         construct_update_q/3, 
         construct_delete_q/2]).

insert() ->
    ok.

update() ->
    ok.

delete(Host, Tables, WhereClauses) when is_list(Tables) ->
   Cmds =
       [construct_delete_q(Table, Where)
        || {Table, Where} <- lists:zip(Tables, WhereClauses)],
   call_transaction(Host, Cmds);

delete(Host, Table, WhereClause) ->
   call_transaction(Host, [construct_delete_q(Table, WhereClause)]).

call_transaction(Host, Arg) ->
    ejabberd_sql:sql_transaction(Host, Arg).


%% Construct query dynamically based on the args %% 
construct_insert_q(Table, Columns, Values) -> 
  [<<"INSERT INTO ">>, Table, <<"( ">>, Columns, <<" )">>, Values].

construct_update_q(Table, Set, WhereClause) -> 
  [<<"UPDATE ">>, Table, <<" SET ">>, Set, <<" WHERE ">>, WhereClause].

construct_delete_q(Table, WhereClause) -> 
  [<<"DELETE FROM ">>, Table, <<" WHERE ">>, WhereClause].