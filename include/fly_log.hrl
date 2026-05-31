-define(MSG_LOGX(Pkt),
        ?MSG_LOGX(Pkt, "")).

-define(MSG_LOGX(Pkt, Msg),
    fly_log:log(?MODULE, ?FUNCTION_NAME, ?LINE, Pkt, Msg)).
        