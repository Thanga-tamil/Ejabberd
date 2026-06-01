
%%--------------------------------------------------------------------
%% @doc
%%  This module provides logging functionality for message packets in the ejabberd server.
%%  It logs the details of message packets, including their ID, type, sender, and recipient.
%%--------------------------------------------------------------------

-module(fly_log).

-author('Thangatamil').

-include("logger.hrl").

-include_lib("xmpp/include/xmpp.hrl").

-export([log/5]).

log(Mod, Fun, Line, Pkt, Msg) ->
    case Pkt of
        #message{id = Id, from = From, to = To, type = Type} ->
           {FUserId, _, FResource} = jid:tolower(From),
           {TUserId, _, TResource} = jid:tolower(To),

           % use -E grep with 'from' and 'to' 
           % to trace the message flow 

           ?LOG_INFO("[~p:~p:~p] from=~p to=~p ~s",
                [Mod, Fun, Line, binary_to_list(FUserId), 
                binary_to_list(TUserId), Msg]),

            Map = #{message_id => Id,
                    type => Type,
                    from_user_id => FUserId,
                    from_resource => FResource,
                    to_user_id => TUserId,
                    to_resource => TResource},

            io:format("~p~n", [Map]);
        _ ->
           ok
    end.