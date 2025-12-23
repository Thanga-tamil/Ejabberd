%%%=========================================================
%%% File       : fly_mod_media.erl
%%% Author     : Contus <ejabberd@contus.in>
%%% Purpose    : handle media call
%%% Created At : 02 April 2020
%%%=========================================================
-module(fly_mod_media).
-author("venkatesh@contus.in").
-protocol({xep, 12, '2.0'}).
-behaviour(gen_mod).

%% API
-export([start/2, stop/1, depends/2, process_local_iq/1, filter_packet/1, mod_options/1, mod_opt_type/1]).

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").
-include("translate.hrl").

-type host() :: string().
-type name() :: string().
-type value() :: string().
-type opts() :: [{name(), value()}, ...].

-define(EJABBERD_DEBUG, true).

%===================================================================
% API
%===================================================================
-spec start(host(), opts()) -> ok.
start(Host, Opts) ->
  % IQDisc = gen_mod:get_opt(iqdisc, Opts, fun gen_iq_handler:check_type/1, one_queue),
  % gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_MEDIA_CALL_ACTIVITIES, ?MODULE, process_local_iq, IQDisc),
  gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_MEDIA_CALL_ACTIVITIES, ?MODULE, process_local_iq, Host),
  ejabberd_hooks:add(user_send_packet, Host, ?MODULE, filter_packet, 50),
  ok.

-spec stop(host()) -> ok.
stop(Host) ->
%%  gen_iq_handler:remove_iq_handler(ejabberd_local, Host, ?NS_USER_ACTIVITIES),
  gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_MEDIA_CALL_ACTIVITIES),
  ejabberd_hooks:delete(user_send_packet, Host,
    ?MODULE, filter_packet, 50),
  ok.

%% Handling the IQ

process_local_iq(#iq{from = From, to = To, type = Type, sub_els = [#media_call_activities{status = RequestType}]} = IQ) ->
  case Type of
    set ->
      process_iq_set(From, To, RequestType, xmpp:encode(IQ));
    _ ->
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = <<"error">>, result_type = <<"invalid iq type">>})
  end.

%% Set method for the IQ
process_iq_set(From, To, RequestType, IQ) ->
  SubEl = fxml:get_subtag_with_xmlns(IQ, <<"query">>, <<"jabber:iq:media_call_activities">>),
  case RequestType of
    <<"call_status">> ->
      LServer = To#jid.lserver,
      IsValid = fly_mod_utils:validate_license(LServer, true, <<"call">>),
      if IsValid =:= true ->
        update_call_status(From, RequestType, SubEl,IQ);
      true ->
        fly_mod_utils:generate_subel(IQ, #media_call_activities{type = <<"license">>, result_type = <<"License Expired or Invalid">>})
      end;
    no_such_subtag ->
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});
    empty_value ->
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = <<"empty_value">>, result_type = <<"unknown request">>});
    _Status ->
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = _Status, result_type = <<"unknown request">>})
  end.

%%<iq type="set" id="dasdwq">
%%<query xmlns="jabber:iq:media_call_activities" status="call_status"
%% room_id = "assdfsdfsd" call_status = "ATTENDED/ENDED/ENDED">
%%</query>
%%</iq>

update_call_status(From, RequestType, SubEl, IQ) ->
  #jid{user = FUser, lserver = FServer} = From,
  RoomId = fxml:get_path_s(SubEl, [{attr, <<"room_id">>}]),
  CallStatus = fxml:get_path_s(SubEl, [{attr, <<"call_status">>}]),
  case CallStatus of
    <<"ATTENDED">> ->
      StartTime = fxml:get_path_s(SubEl, [{attr, <<"start_time">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      %%CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      Timestamp = now_to_microseconds(erlang:now()),
      CallTime = lists:flatten(io_lib:format("~p", [Timestamp])),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
      CallFromJID = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
      FromJid = jid:from_string(CallFromJID),
      #jid{user = CallFrom, lserver = FServer} = FromJid,
      carboncall_message(FromJid,<<"CARBONATTEND">>,RoomId,CallType,CallMode,CallTime, SubEl),
      fly_mod_utils:update_media_call_status(FServer,RoomId,CallFrom,CallStatus,StartTime,<<"start_time">>),
      case fly_mod_utils:get_call_user_list(FServer,RoomId) of
        {selected, _, []} ->
          fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ATTENDED status updated successfully">>});
        {selected, _, Users} ->
          send_call_attend_message(FromJid,Users,CallStatus,CallType,CallTime,CallMode,RoomId, SubEl),
          fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ATTENDED status updated successfully">>})
      end;
    <<"CARBONATTEND">> ->
      CallFrom = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
      CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      FromJid = jid:from_string(CallFrom),
      carboncall_message(FromJid,CallStatus,RoomId,CallType,CallMode,CallTime, SubEl),
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ATTENDED in another resource">>});
    <<"CARBONBUSY">> ->
      CallFrom = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
        CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      FromJid = jid:from_string(CallFrom),
      carboncall_message(FromJid,CallStatus,RoomId,CallType,CallMode,CallTime, SubEl),
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call BUSY in another resource">>});
    <<"CARBONENDED">> ->
      CallFrom = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
        CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      FromJid = jid:from_string(CallFrom),
      carboncall_message(FromJid,CallStatus,RoomId,CallType,CallMode,CallTime, SubEl),
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENDED in another resource">>});
    <<"CARBONENGAGED">> ->
      CallFrom = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
        CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      FromJid = jid:from_string(CallFrom),
      carboncall_message(FromJid,CallStatus,RoomId,CallType,CallMode,CallTime, SubEl),
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENDED in another resource">>});
    <<"ENDED">> ->
      EndTime = fxml:get_path_s(SubEl, [{attr, <<"end_time">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      %%CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      Timestamp = now_to_microseconds(erlang:now()),
      CallTime = lists:flatten(io_lib:format("~p", [Timestamp])),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
      CallFromJID = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
      FromJid = jid:from_string(CallFromJID),
      #jid{user = CallFrom, lserver = FServer} = FromJid,
      fly_mod_utils:update_media_call_status(FServer,RoomId,CallFrom,CallStatus,EndTime,<<"end_time">>),
      carboncall_message(FromJid,<<"CARBONENDED">>,RoomId,CallType,CallMode,CallTime, SubEl),
      if CallMode =:= <<"onetoone">> ->
        case fly_mod_utils:get_call_user_list(FServer,RoomId) of
          {selected, _, []} ->
            fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENDED status updated successfully">>});
          {selected, _, AllUsers} ->

            send_call_end_message(FromJid,AllUsers,CallType,EndTime,CallMode,CallStatus,RoomId,CallTime,<<"closed">>, SubEl),
            fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENDED status updated successfully">>})
        end;
        true ->

        case fly_mod_utils:get_call_initiator(FServer,RoomId) of
        {selected, _, []} ->
          fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call BUSY status updated successfully">>});
        {selected, _, CallIniator} ->

            CallerFrom = list_to_binary(CallIniator),
          if CallerFrom =:= CallFrom ->
              {selected, _, [[CallerEnded]]} = fly_mod_utils:get_call_caller_attended_count(FServer, RoomId,CallFrom),

              if CallerEnded =< <<"1">> ->
              send_call_to_users(FServer,RoomId,<<"closed">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl);
              true ->
              send_call_to_users(FServer,RoomId,<<"exit">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl)
            end;
          true ->
              {selected, _, [[CallingCount]]} = fly_mod_utils:get_call_user_calling_count(FServer, RoomId),
              {selected, _, [[AttendedCount]]} = fly_mod_utils:get_call_user_attended_count(FServer, RoomId),
              if (CallingCount == <<"1">>) and (AttendedCount == <<"1">>) ->
                  send_call_to_users(FServer,RoomId,<<"exit">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl);
                  (CallingCount == <<"0">>) and (AttendedCount =< <<"1">>) ->
                  send_call_to_users(FServer,RoomId,<<"closed">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl);
                  (CallingCount =< <<"1">>) and (AttendedCount == <<"0">>) ->
                  send_call_to_users(FServer,RoomId,<<"closed">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl);
              true ->
                  send_call_to_users(FServer,RoomId,<<"exit">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl)
              end
          end
        end
      end;
    <<"BUSY">> ->
      EndTime = fxml:get_path_s(SubEl, [{attr, <<"end_time">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
      CallFromJID = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
     %% CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      Timestamp = now_to_microseconds(erlang:now()),
      CallTime = lists:flatten(io_lib:format("~p", [Timestamp])),
      FromJid = jid:from_string(CallFromJID),
      carboncall_message(FromJid,<<"CARBONBUSY">>,RoomId,CallType,CallMode,CallTime, SubEl),

      fly_mod_utils:update_media_call_status(FServer,RoomId,FUser,CallStatus),

      if CallMode =:= <<"onetoone">> ->
        case fly_mod_utils:get_call_initiator(FServer,RoomId) of
          {selected, _, []} ->
            fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call BUSY status updated successfully">>});
          {selected, _, AllUsers} ->
            send_call_end_message(FromJid,AllUsers,CallType,EndTime,CallMode,CallStatus,RoomId,CallTime,<<"closed">>, SubEl),
            fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call BUSY status updated successfully">>})
        end;
        true ->
          {selected, _, [[CallingCount]]} = fly_mod_utils:get_call_user_calling_count(FServer, RoomId),
          {selected, _, [[AttendedCount]]} = fly_mod_utils:get_call_user_attended_count(FServer, RoomId),
          if (CallingCount == <<"1">>) and (AttendedCount == <<"1">>) ->
              send_call_to_users(FServer,RoomId,<<"exit">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl);
              (CallingCount == <<"0">>) and (AttendedCount =< <<"1">>) ->
              send_call_to_users(FServer,RoomId,<<"closed">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl);
              (CallingCount =< <<"1">>) and (AttendedCount == <<"0">>) ->
              send_call_to_users(FServer,RoomId,<<"closed">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl);
          true ->
              send_call_to_users(FServer,RoomId,<<"exit">>,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl)
          end
        end;
    <<"CALLING">> ->

      Users  = fxml:get_subtag(SubEl, <<"users">>),
      Ccodes = gen_mod:get_module_opt(FServer, fly_mod_media, restricted_country_code),

      case fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]) of 
        <<"onetomany">> -> 
          UserList = lists:map(fun(U) -> JidBin = fxml:get_tag_cdata(U), [UserId, _] = binary:split(JidBin, <<"@">>), UserId end, Users#xmlel.children),
          ?LOG_INFO("user_list ~p", [UserList]),
          GroupId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
          if GroupId =/= <<"">> -> 
            DevList = fly_mod_utils:get_users_devices_detail(FServer, sql_in(UserList), sql_in(Ccodes)),
            ?LOG_INFO("device_list ~p", [DevList]),
            case DevList of 
              [] -> 
                fly_mod_utils:generate_subel(IQ,#media_call_activities{type = <<"restricted_country">>,result_type = <<"The persons you are trying to reach is in call restricted region.">>});
              _ -> 
                send_payload(CallStatus, SubEl, []),
                fly_mod_utils:generate_subel(IQ,#media_call_activities{type = RequestType,result_type = <<"Media call CALLING status updated successfully">>})
              end;
          false -> 
            ok
          end;

        <<"onetoone">> -> 
          TUserJidEl  = fxml:get_subtag(Users, <<"user">>), ?LOG_INFO("TUserJidEl ~p", [TUserJidEl]),
          JidBin      = fxml:get_tag_cdata(TUserJidEl), ?LOG_INFO("JidBin ~p", [JidBin]),
          [TU,TS]     = binary:split(JidBin, <<"@">>), ?LOG_INFO("TU ~p, TS ~p", [TU,TS]),
          DevList     = fly_mod_utils:get_users_devices_detail(FServer, sql_in([TU]), sql_in(Ccodes)), ?LOG_INFO("DevList ~p", [DevList]),
          URes        = ejabberd_sm:get_user_resources(TU, FServer), ?LOG_INFO("URes ~p", [URes]),
          IsAllowed   = case {DevList, URes} of {[], _} -> false; {_DevList, []} -> true; {_DevList, _URes} -> true end,

          case IsAllowed of
            true ->
              ?LOG_INFO("call allowed"),
              AllowedDevices = [ DeviceType || [_Country, DeviceType] <- DevList ],
              ?LOG_INFO("pick AllowedDevices from devList to make full jid.. found: ~p", [AllowedDevices]),
              TargetJids = [ jid:make(TU, TS, Res) || Res <- URes, lists:member(get_device_type(Res), AllowedDevices) ],
              ?LOG_INFO("TargetJids ~p", [TargetJids]),
              send_payload(CallStatus, SubEl, TargetJids),
              fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call CALLING status updated successfully">>});
            false ->
              ?LOG_INFO("call not allowed"),
              fly_mod_utils:generate_subel(IQ, #media_call_activities{type = <<"restricted_country">>, result_type = <<"The person you are trying to reach is in call restricted region.">>})
          end;
        _ -> 
          ok
        end;

    <<"JOINED">> ->
      RoomId = fxml:get_path_s(SubEl, [{attr, <<"room_id">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      %%CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      Timestamp = now_to_microseconds(erlang:now()),
      CallTime = lists:flatten(io_lib:format("~p", [Timestamp])),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
      GroupId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
      CallFromJID = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
      CallLink = fxml:get_path_s(SubEl, [{attr, <<"call_link">>}]),
      CallerName = fxml:get_path_s(SubEl, [{attr, <<"caller_name">>}]),
      MetaData = fxml:get_path_s(SubEl, [{attr, <<"meta_data">>}]),
      FromJid = jid:from_string(CallFromJID),
      send_call_message(FromJid,SubEl,<<"">>,CallStatus,RoomId,CallType,CallMode,CallTime,GroupId,CallLink,CallerName,MetaData, []),
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call JOINED status updated successfully">>});

    <<"INVITEUSERS">> ->
      send_payload(CallStatus, SubEl, []),
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call CALLING status updated successfully">>});

    <<"RECEIVED">> ->
      RoomId = fxml:get_path_s(SubEl, [{attr, <<"room_id">>}]),
      CallFromJID = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
      %%CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      Timestamp = now_to_microseconds(erlang:now()),
      CallTime = lists:flatten(io_lib:format("~p", [Timestamp])),
      FromJid = jid:from_string(CallFromJID),
      case fly_mod_utils:get_call_initiator(FServer,RoomId) of
        {selected, _, []} ->
          fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call RECEIVED status updated successfully">>});
        {selected, _, AllUsers} ->
          send_call_receive_message(FromJid,RoomId,AllUsers,CallStatus,CallType,CallMode,CallTime, SubEl),
          fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call RECEIVED status updated successfully">>})
      end;
    <<"ENGAGED">> ->
      EndTime = fxml:get_path_s(SubEl, [{attr, <<"end_time">>}]),
      CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
      CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
      CallFromJID = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
     %% CallTime = fxml:get_path_s(SubEl, [{attr, <<"call_time">>}]),
      Timestamp = now_to_microseconds(erlang:now()),
      CallTime = lists:flatten(io_lib:format("~p", [Timestamp])),
      FromJid = jid:from_string(CallFromJID),
      carboncall_message(FromJid,<<"CARBONENGAGED">>,RoomId,CallType,CallMode,CallTime, SubEl),

      fly_mod_utils:update_media_call_status(FServer,RoomId,FUser,CallStatus),

      if CallMode =:= <<"onetoone">> ->
        case fly_mod_utils:get_call_initiator(FServer,RoomId) of
          {selected, _, []} ->
            fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENGAGED status updated successfully">>});
          {selected, _, AllUsers} ->
            send_call_end_message(FromJid,AllUsers,CallType,EndTime,CallMode,CallStatus,RoomId,CallTime,<<"closed">>, SubEl),
            fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENGAGED status updated successfully">>})
        end;
        true ->
          case fly_mod_utils:get_call_user_list(FServer,RoomId) of
            {selected, _, []} ->
              fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENGAGED status updated successfully">>});
            {selected, _, AllUsers} ->
                case fly_mod_utils:get_attend_and_calling_list(FServer,RoomId) of
                  {selected, _, []} ->
                    fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENGAGED status updated successfully">>});
                  {selected, _, [[CallingCount]]} ->
                    if CallingCount =:= <<"1">> ->
                      send_call_end_message(FromJid,AllUsers,CallType,EndTime,CallMode,CallStatus,RoomId,CallTime,<<"closed">>, SubEl);
                      CallingCount =:= <<"0">> ->
                        send_call_end_message(FromJid,AllUsers,CallType,EndTime,CallMode,CallStatus,RoomId,CallTime,<<"closed">>, SubEl);
                      true ->
                        send_call_end_message(FromJid,AllUsers,CallType,EndTime,CallMode,CallStatus,RoomId,CallTime,<<"exit">>, SubEl)
                    end,
                    fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENGAGED status updated successfully">>})
                end
          end
        end;
    _Status ->
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Unknown call status">>})
  end.

get_device_type(<<"Web-", _/binary>>) -> <<"web">>;
get_device_type(<<"Mobile-", _/binary>>) -> <<"mobile">>;
get_device_type(_) -> <<"unknown">>.

normalize(Bin) when is_binary(Bin) -> list_to_binary(string:lowercase(binary_to_list(Bin))).

sql_in(List) when is_list(List), List =/= [] ->
  JoinedIolist = lists:join(<<",">>, [<< "'", V/binary, "'" >> || V <- List]), Joined = iolist_to_binary(JoinedIolist), << "(", Joined/binary, ")" >>;
sql_in([]) -> <<"(NULL)">>.


send_payload(CallStatus, SubEl, TargetJids)->
  RoomId = fxml:get_path_s(SubEl, [{attr, <<"room_id">>}]),
  CallType = fxml:get_path_s(SubEl, [{attr, <<"call_type">>}]),
  Timestamp = now_to_microseconds(erlang:now()),
  CallTime = lists:flatten(io_lib:format("~p", [Timestamp])),
  CallMode = fxml:get_path_s(SubEl, [{attr, <<"call_mode">>}]),
  GroupId = fxml:get_path_s(SubEl, [{attr, <<"group_id">>}]),
  CallFromJID = fxml:get_path_s(SubEl, [{attr, <<"call_from">>}]),
  CallLink = fxml:get_path_s(SubEl, [{attr, <<"call_link">>}]),
  CallerName = fxml:get_path_s(SubEl, [{attr, <<"caller_name">>}]),
  MetaData = fxml:get_path_s(SubEl, [{attr, <<"meta_data">>}]),
  FromJid = jid:from_string(CallFromJID),
  Users = fxml:get_subtag(SubEl, <<"users">>),
  send_call_message(FromJid,SubEl,Users,CallStatus,RoomId,CallType,CallMode,CallTime,GroupId,CallLink,CallerName, MetaData, TargetJids).



filter_packet({#message{from = From,to = To} = XML, State} = _Acc) ->
  #jid{user = FUser, lserver = FServer} = From,
  #jid{user = TUser, lserver = _TServer} = To,
  Type = XML#message.type,
  %% Add timestamp to chat message and where no DataTag exist
  case Type of
    chat ->
      Mediatag = xmpp:get_subtag(XML, #mediacall{}),
      if Mediatag =/= false ->
        IsValid = fly_mod_utils:validate_license(FServer, true, <<"call">>),
        if IsValid =:= true ->
              #mediacall{
                room_id = RoomId,
                call_type = CallType,
                call_time = CallTime,
                call_mode = CallMode,
                group_id = GroupId,
                caller_name = CallerName,
                meta_data = MetaData,
                call_link = CallLink} = Mediatag,
              fly_mod_utils:insert_media_call_status(FServer,FUser,TUser,RoomId,CallType,<<"CALLING">>,CallTime,CallMode,GroupId,CallLink,MetaData),
              XML;
        true ->
          {drop,State}
        end;
      true ->
        XML
      end;
    _ ->
      XML
  end,
  {XML,State};
filter_packet(Acc) ->
  Acc.

send_call_to_users(FServer,RoomId,Status,IQ,RequestType,FromJid,CallType,EndTime,CallMode,CallStatus,CallTime, SubEl) ->
  case fly_mod_utils:get_call_user_list(FServer,RoomId) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENDED status updated successfully">>});
    {selected, _, AllUsers} ->
      send_call_end_message(FromJid,AllUsers,CallType,EndTime,CallMode,CallStatus,RoomId,CallTime,Status, SubEl),
      fly_mod_utils:generate_subel(IQ, #media_call_activities{type = RequestType, result_type = <<"Media call ENDED status updated successfully">>})
  end.

send_call_message(From,SubEl,Users,CallStatus,RoomId,CallType,CallMode,CallTime,GroupId,CallLink, CallerName, MetaData, TargetJids) ->
  #jid{user = FUser, lserver = FServer,lresource = LResource} = From,
  Opts = ejabberd_config:codec_options(),
  if CallStatus =:= <<"CALLING">>  ->
    fly_mod_utils:insert_media_call_status(FServer,FUser,FUser,RoomId,CallType,<<"ATTENDED">>,CallTime,CallMode,GroupId,CallLink,MetaData),
    UserList = lists:map(fun(U) ->
    binary_to_list(fxml:get_tag_cdata(U)) ++ "," end, Users#xmlel.children),
    UserLists = binary_to_list(list_to_binary(UserList)),
    UsersList = lists:sublist(UserLists, 1, length(UserLists) - 1),
    case TargetJids of
      [_ | _] ->
        ?LOG_INFO("proceed at [_ | _] "),
        lists:foreach(fun(Dest) ->
          #jid{user = ToUser, lserver = ToServer, lresource = ToRes} = Dest,
          MessageId = fly_mod_utils:get_iq_message_id(7),
          NoCopy = #xmlel{name = <<"no-copy">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:hints">>}]},
          NewPacket = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)},  {<<"id">>,MessageId}, {<<"type">>, <<"chat">>}, {<<"to">>, jid:to_string(Dest)}],
          children = [ NoCopy,
            #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:call">>}, {<<"room_id">>, RoomId},  {<<"call_link">>, CallLink},{<<"meta_data">>, MetaData}, {<<"caller_name">>, CallerName}, {<<"call_mode">>, CallMode},{<<"call_status">>, CallStatus}, {<<"call_type">>, CallType},  {<<"call_time">>, CallTime},  {<<"group_id">>, GroupId}], children = [Users]},
            fly_mod_utils:get_custom_attributes(SubEl)
          ]},
            ejabberd_router:route(From, Dest, NewPacket),
          case fly_mod_utils:get_mobile_user_message(ToUser, FServer) of
            true ->
              fly_mod_offline_push:send_offline_message({From,xmpp:decode(NewPacket,?NS_CLIENT, Opts)});
            false ->
              ok
          end,
          fly_mod_utils:insert_media_call_status(FServer,FUser,ToUser,RoomId,CallType,CallStatus,CallTime,CallMode,GroupId,CallLink,MetaData),
          fly_mod_utils:insert_call_log_status(FServer,FUser,ToUser,RoomId,CallType,CallStatus,CallTime,CallMode,GroupId,CallLink,list_to_binary(UsersList),LResource,MetaData)
        end, TargetJids);
       [] ->
        ?LOG_INFO("damn son [] "),
        lists:foreach(fun(U) ->
          User = fxml:get_tag_cdata(U),
          [ToUser, _] = binary:split(User, <<"@">>),
          BareToJid = jid:from_string(User),
          MessageId = fly_mod_utils:get_iq_message_id(7),
          NewPacket = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)},  {<<"id">>,MessageId}, {<<"type">>, <<"chat">>}, {<<"to">>, jid:to_string(BareToJid)}],
          children = [
            #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:call">>}, {<<"room_id">>, RoomId},  {<<"call_link">>, CallLink},{<<"meta_data">>, MetaData}, {<<"caller_name">>, CallerName}, {<<"call_mode">>, CallMode},{<<"call_status">>, CallStatus}, {<<"call_type">>, CallType},  {<<"call_time">>, CallTime},  {<<"group_id">>, GroupId}], children = [Users]},
            fly_mod_utils:get_custom_attributes(SubEl)
          ]},
            ejabberd_router:route(From, BareToJid, NewPacket),
          case fly_mod_utils:get_mobile_user_message(ToUser, FServer) of
            true ->
              fly_mod_offline_push:send_offline_message({From,xmpp:decode(NewPacket,?NS_CLIENT, Opts)});
            false ->
              ok
          end,
          fly_mod_utils:insert_media_call_status(FServer,FUser,ToUser,RoomId,CallType,CallStatus,CallTime,CallMode,GroupId,CallLink,MetaData),
          fly_mod_utils:insert_call_log_status(FServer,FUser,ToUser,RoomId,CallType,CallStatus,CallTime,CallMode,GroupId,CallLink,list_to_binary(UsersList),LResource,MetaData)
        end, Users#xmlel.children)
      end;
   

    % lists:foreach(fun(U) ->
    %   User = fxml:get_tag_cdata(U),
    %   [ToUser, _] = binary:split(User, <<"@">>),
    %   case catch fly_mod_utils:check_blockedlist(FServer,ToUser,FUser)
    % of
    %   {selected, _, [[_T]]} ->
    %     ?INFO_MSG("user blocked ~p", [ToUser]);
    %   {error,timeout}  ->
    %     ok;
    %   {selected, _, []} ->
    %   fly_mod_utils:insert_media_call_status(FServer,FUser,ToUser,RoomId,CallType,CallStatus,CallTime,CallMode,GroupId,CallLink,MetaData),
    %   fly_mod_utils:insert_call_log_status(FServer,FUser,ToUser,RoomId,CallType,CallStatus,CallTime,CallMode,GroupId,CallLink,list_to_binary(UserList),LResource,MetaData)
    % end
    % end, Users#xmlel.children);
  CallStatus =:= <<"JOINED">>  ->
    fly_mod_utils:update_media_call_status(FServer,RoomId,FUser,<<"ATTENDED">>);
  true ->
    InviteUsers = fxml:get_subtag(SubEl, <<"invite">>),
    InviteUserList = lists:map(fun(U) ->
    binary_to_list(fxml:get_tag_cdata(U)) ++ ","
    end, InviteUsers#xmlel.children),
    lists:foreach(fun(U) ->
      User = fxml:get_tag_cdata(U),
      [ToUser, _] = binary:split(User, <<"@">>),
      ToJid = jid:from_string(User),
      MessageId = fly_mod_utils:get_iq_message_id(7),
      fly_mod_utils:insert_media_call_status(FServer,FUser,ToUser,RoomId,CallType,<<"CALLING">>,CallTime,CallMode,GroupId,CallLink,MetaData),
      fly_mod_utils:insert_call_log_status(FServer,FUser,ToUser,RoomId,CallType,CallStatus,CallTime,CallMode,GroupId,CallLink,list_to_binary(InviteUserList),LResource,MetaData),
      NewPacket = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)},  {<<"id">>,MessageId}, {<<"type">>, <<"chat">>}, {<<"to">>, User}],
      children = [
        #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:call">>}, {<<"room_id">>, RoomId}, {<<"meta_data">>, MetaData}, {<<"call_link">>, CallLink},{<<"call_mode">>, CallMode},{<<"call_status">>, <<"CALLING">>}, {<<"call_type">>, CallType},  {<<"call_time">>, CallTime},  {<<"group_id">>, GroupId}], children = [Users,InviteUsers]},
        fly_mod_utils:get_custom_attributes(SubEl)
      ]},
      ejabberd_router:route(From, ToJid, NewPacket),
      case fly_mod_utils:get_mobile_user_message(ToUser, FServer) of
        true ->
          fly_mod_offline_push:send_offline_message({ From,xmpp:decode(NewPacket,?NS_CLIENT, Opts)});
        false ->
          ok
      end
    end, InviteUsers#xmlel.children),

    lists:foreach(fun(F) ->
      User = fxml:get_tag_cdata(F),
      [ToUser,Server] = binary:split(User, <<"@">>),
      ToJid = jid:make(ToUser,Server,<<"">>),
      MessageId = fly_mod_utils:get_iq_message_id(7),
      NewPacket = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)},
        {<<"id">>,MessageId}, {<<"type">>, <<"chat">>}, {<<"to">>, User}],
        children = [
          #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:call">>}, {<<"room_id">>, RoomId},{<<"call_link">>, CallLink}, {<<"meta_data">>, MetaData},{<<"call_mode">>, CallMode},{<<"call_status">>, CallStatus}, {<<"call_type">>, CallType},  {<<"call_time">>, CallTime}, {<<"group_id">>, GroupId}], children = [Users,InviteUsers]},
          fly_mod_utils:get_custom_attributes(SubEl)
        ]},
      ejabberd_router:route(From, ToJid, NewPacket),
      case fly_mod_utils:get_mobile_user_message(ToUser, FServer) of
        true ->
          fly_mod_offline_push:send_offline_message({ From,xmpp:decode(NewPacket,?NS_CLIENT, Opts) });
        false ->
          ok
      end
    end, Users#xmlel.children)
  end.

send_call_receive_message(From,RoomId, AllUsers, CallStatus,CallType,CallMode,CallTime, SubEl) ->
  #jid{user = FUser, lserver = FServer} = From,
  lists:foreach(fun([User]) ->
    ToJid = jid:make(User,FServer,<<"">>),
    MessageId = fly_mod_utils:get_iq_message_id(7),
    NewPacket = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)},  {<<"id">>,MessageId}, {<<"type">>, <<"chat">>}, {<<"to">>,  jid:to_string(ToJid)}],
    children = [
      #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:call">>}, {<<"room_id">>, RoomId},{<<"call_status">>, CallStatus}, {<<"call_mode">>, CallMode},{<<"session_status">>, <<"">>}, {<<"call_type">>, CallType}, {<<"call_time">>, CallTime}, {<<"call_from">>, FUser}], children = []},
      fly_mod_utils:get_custom_attributes(SubEl)
    ]},
    ejabberd_router:route(From, ToJid, NewPacket)
  end, AllUsers).

send_call_end_message(From,AllUsers,CallType,EndTime,CallMode,CallStatus,RoomId,CallTime,SessionStatus,SubEl) ->
  #jid{lserver = FServer} = From,
  lists:foreach(fun([User]) ->
    ToJid = jid:make(User,FServer,<<"">>),
    MessageId = fly_mod_utils:get_iq_message_id(7),
    NewPacket = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)},  {<<"id">>,MessageId}, {<<"type">>, <<"chat">>}, {<<"to">>, jid:to_string(ToJid)}],
      children = [
        #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:call">>}, {<<"room_id">>, RoomId},{<<"call_status">>, CallStatus}, {<<"session_status">>, SessionStatus},{<<"call_type">>, CallType},{<<"end_time">>, EndTime},{<<"call_time">>, CallTime},{<<"call_mode">>, CallMode}]},
        fly_mod_utils:get_custom_attributes(SubEl)
      ]},
    ejabberd_router:route(From, ToJid, NewPacket)
  end, AllUsers).

send_call_attend_message(From,Users,CallStatus,CallType,CallTime,CallMode,RoomId, SubEl) ->
  #jid{user = FUser, lserver = FServer} = From,
  lists:foreach(fun([User]) ->
    ToJid = jid:make(User,FServer,<<"">>),
    if(User =/= FUser) ->
      MessageId = fly_mod_utils:get_iq_message_id(7),
      NewPacket = #xmlel{name = <<"message">>, attrs = [{<<"from">>, jid:to_string(From)},  {<<"id">>,MessageId}, {<<"type">>, <<"chat">>}, {<<"to">>, jid:to_string(ToJid)}],
        children = [
          #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>, <<"urn:xmpp:call">>}, {<<"room_id">>, RoomId},{<<"call_status">>, CallStatus},{<<"call_type">>, CallType},{<<"call_time">>, CallTime},{<<"call_mode">>, CallMode}]},
          fly_mod_utils:get_custom_attributes(SubEl)
        ]},
      ejabberd_router:route(From, ToJid, NewPacket);
    true ->
      ok
    end
  end, Users).

carboncall_message(From, CallStatus, RoomId,CallType,CallMode,CallTime, SubEl) ->
  #jid{luser = LUser, lserver = LServer, lresource = LResource} = From,
  WebResource = string:str(binary_to_list(LResource), binary_to_list(<<"Web">>)),
  MessageId = fly_mod_utils:get_iq_message_id(7),
  lists:foldl(fun(SResource,_Acc) ->
    MobileResource = string:str(binary_to_list(SResource), binary_to_list(<<"Mobile">>)),
    if WebResource =:= 1 ->
      if MobileResource =:= 1 ->
        ToJid = jid:make(LUser, LServer, SResource),
        XmlBody = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(ToJid)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
          children = [
            #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>,<<"urn:xmpp:call">>},{<<"session_status">>, <<"closed">>}, {<<"call_status">>,CallStatus}, {<<"room_id">>, RoomId},{<<"call_type">>, CallType},{<<"call_time">>, CallTime},{<<"call_mode">>, CallMode}], children = []},
            fly_mod_utils:get_custom_attributes(SubEl)
          ]},
        ejabberd_router:route(From, ToJid, XmlBody);
        true ->
          ok
      end;
      true ->
        if MobileResource =:= 0 ->
          ToJid = jid:make(LUser, LServer, SResource),
          XmlBody = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(ToJid)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
          children = [
            #xmlel{name = <<"mediacall">>, attrs = [{<<"xmlns">>,<<"urn:xmpp:call">>}, {<<"call_status">>,CallStatus}, {<<"session_status">>, <<"closed">>},{<<"room_id">>, RoomId},{<<"call_type">>, CallType},{<<"call_time">>, <<"">>},{<<"call_mode">>, CallMode}], children = []},
            fly_mod_utils:get_custom_attributes(SubEl)
          ]},
          ejabberd_router:route(From, ToJid, XmlBody);

          true ->
            ok
        end
    end
  end,[],ejabberd_sm:get_user_resources(LUser, LServer)).

now_to_microseconds({Mega, Sec, Micro}) ->
  %%Epoch time in milliseconds from 1 Jan 1970
  (Mega * 1000000 + Sec) * 1000000 + Micro.

depends(_, _) ->
    [].

mod_options(_) ->
    [{restricted_country_code, []}].

mod_opt_type(restricted_country_code) ->
    econf:list(econf:binary());
mod_opt_type(_) ->
    [].