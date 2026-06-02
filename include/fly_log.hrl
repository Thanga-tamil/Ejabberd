-define(LOGX(Pkt),
        ?LOGX(Pkt, "")).

-define(LOGX(Pkt, Msg),
    fly_log:log(?MODULE, ?FUNCTION_NAME, ?LINE, Pkt, Msg)).
        