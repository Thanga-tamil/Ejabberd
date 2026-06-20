
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
        #message{id = Id, 
                 from = From, 
                 to = To, 
                 type = Type,
                 sub_els = SubEls} ->
                    
           {FUser, _, FRes} = jid:tolower(From),
           {TUser, _, TRes} = jid:tolower(To),
           Tags = [Tag || #xmlel{name = Tag} <- SubEls],

           % use -E grep with 'from' and 'to' 
           % to trace the message flow 

            logger:info("[~p:~p:~p] "
                        "from=~p "
                        "to=~p ~s~n ~s~n"
                        "sub_els:: ~p",
                        [Mod, Fun, Line, 
                         binary_to_list(FUser),
                         binary_to_list(TUser), 
                         Msg, 
                         jiffy:encode(
                                #{message_id => Id,
                                  type => Type,
                                  from_userid => FUser,
                                  from_resource => FRes,
                                  to_userid => TUser,
                                  to_resource => TRes}
                            ),
                         Tags
                        ]);
        _ ->
           ok
    end.