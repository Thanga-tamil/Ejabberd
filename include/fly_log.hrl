-define(MSG_LOG(Pkt),
        ?MSG_LOG(Pkt, "")).

-define(MSG_LOG(Pkt, Msg),
    fly_log:msg_log(?MODULE, ?FUNCTION_NAME, ?LINE, Pkt, Msg)).
        