%%%======================================================
%%% File       : user_fav.erl
%%% Author     : Contus <ejabberd@contus.in>
%%% Purpose    : Save the user favourite message for web.
%%% Created At : 29 Aug 2017
%%%========================================================

-module(fly_mod_user_fav).
-author("ejabberd@contus.in").
-protocol({xep, 12, '2.0'}).
-behaviour(gen_mod).
-define(EJABBERD_DEBUG, true).
%% API
-export([start/2, stop/1, depends/2, mod_options/1, process_local_iq/1, mod_opt_type/1]).

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").

%%%===================================================================
%%% API
%%%===================================================================
start(Host, _Opts) ->

  gen_iq_handler:add_iq_handler(ejabberd_sm, Host,?NS_USER_FAV, ?MODULE, process_local_iq).

stop(Host) ->

  gen_iq_handler:remove_iq_handler(ejabberd_sm, Host,?NS_USER_FAV).

depends(_Host, _Opts) ->
  [].

%% Handling the IQ
process_local_iq(#iq{from = From, to = To, type = Type} = IQ) ->
  SubEl = fxml:get_subtag_with_xmlns(xmpp:encode(IQ), <<"query">>, <<"jabber:iq:user_fav">>),
  case Type of
    set ->
      process_iq_set(From, To,SubEl, xmpp:encode(IQ));
    get ->
      process_iq_get(From, To, SubEl, xmpp:encode(IQ));
    _   ->
      fly_mod_utils:generate_subel(IQ, #user_fav{type = <<"error">>, result_type = <<"invalid iq type">>})
  end.

%% Set method for the IQ
process_iq_set(From, _To, SubEl,  IQ) ->
  RequestType = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),
  case RequestType of
    <<"set_favourite_message">> ->
      set_favourite_message(From,RequestType,SubEl,IQ);
    <<"update_favourite_message">> ->
      update_favourite_message(From,RequestType,SubEl,IQ);
    <<"clearall_favourite_message">>->
      clearall_favourite_message(From,RequestType,SubEl,IQ);
    no_such_subtag ->
      fly_mod_utils:generate_subel(IQ, #user_fav{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});
    empty_value ->
      fly_mod_utils:generate_subel(IQ, #user_fav{type = <<"empty_value">>, result_type = <<"unknown request">>});
    _Status ->
      fly_mod_utils:generate_subel(IQ, #user_fav{type = <<"error">>, result_type = <<"unknown request">>})
  end.

%% Get method for the IQ
process_iq_get(From, _, SubEl, IQ) ->
  Type = fxml:get_path_s(SubEl, [{attr, <<"status">>}]),
  case Type of
    <<"get_favourite_message">> ->
      get_favourite_message(From, Type,SubEl, IQ);
    no_such_subtag ->
      fly_mod_utils:generate_subel(IQ, #user_fav{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});
    empty_value ->
      fly_mod_utils:generate_subel(IQ, #user_fav{type = <<"empty_value">>, result_type = <<"unknown request">>});
    _Status ->
      fly_mod_utils:generate_subel(IQ, #user_fav{type = <<"error">>, result_type = <<"unknown request">>})
  end.

%% Set as favourte message
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
set_favourite_message(#jid{luser = User,lserver = Server, lresource = Resource} = From, RequestType, SubEl, IQ) ->

  MessageId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  ToUser = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  NewSubstring = string:str(binary_to_list(ToUser), binary_to_list(<<"@mix.">>)),
  if NewSubstring =:= 0 ->
    Chat_Type = <<"chat">>;
    true ->
    Chat_Type = <<"normal">>
  end,
  fly_mod_utils:set_favourite_message(From, MessageId,Chat_Type),
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  To = jid:make(User, Server),
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"favourite">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, <<"set_favourite_message">>}, {<<"message_id">>,MessageId}, {<<"to_user">>,ToUser}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),
  mod_offline:store_packet({From, xmpp:decode(XmlBody)}),
  fly_mod_utils:generate_subel(IQ, #user_fav{status = RequestType ,message_id = MessageId, result_type = <<"Favourite the message successfully">>}).


%% remove the favourte message
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
update_favourite_message(#jid{luser = User,lserver = Server, lresource = Resource} = From, RequestType, SubEl, IQ) ->
  MessageId = fxml:get_path_s(SubEl, [{attr, <<"message_id">>}]),
  ToUser = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]),
  NewSubstring = string:str(binary_to_list(ToUser), binary_to_list(<<"@mix.">>)),
  if NewSubstring =:= 0 ->
    Chat_Type = <<"chat">>;
    true ->
    Chat_Type = <<"normal">>
  end,
  fly_mod_utils:update_favourite_message(From,  MessageId,Chat_Type),
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  To = jid:make(User, Server),
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"favourite">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, <<"update_favourite_message">>}, {<<"message_id">>,MessageId}, {<<"to_user">>,ToUser}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),
  mod_offline:store_packet({From, xmpp:decode(XmlBody)}),
  fly_mod_utils:generate_subel(IQ, #user_fav{status = RequestType,message_id = MessageId, result_type = <<"Favourite the message successfully">>}).

clearall_favourite_message(#jid{luser = User,lserver = Server, lresource = Resource} = From, RequestType, _SubEl, IQ) ->
  fly_mod_utils:delete_favourite_message(Server,  User),
  NewMessageId = fly_mod_utils:get_iq_message_id(20),
  To = jid:make({User, Server, <<>>}),
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, NewMessageId}],
    children = [#xmlel{name = <<"favourite">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"type">>, <<"delete_favourite_message">>}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),
  mod_offline:store_packet({From, xmpp:decode(XmlBody)}),
  fly_mod_utils:generate_subel(IQ, #user_fav{status = RequestType, result_type = <<"Remove all the favourite message successfully">>}).

%% get favourite message from db for web
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
get_favourite_message(#jid{luser = _User, lserver = _Server, lresource = _Resource} = From, RequestType, SubEl, IQ) ->
  Chattype = fxml:get_path_s(SubEl, [{attr, <<"chat_type">>}]),
  if Chattype =:= <<"">> ->
    UserJid = fxml:get_path_s(SubEl, [{attr, <<"to_user">>}]);
    true ->
      [ToUser | _S] = string:tokens(binary_to_list(fxml:get_path_s(SubEl, [{attr, <<"to_user">>}])), "@"),
      UserJid = list_to_binary(ToUser)
  end,
  case catch  fly_mod_utils:get_favourite_message(From,UserJid,Chattype) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #user_fav{type = RequestType, result_type = <<"No chats available">>});
    {selected, _, Result} ->
      SubEls1 = lists:map(fun(G) ->
        [MessageUser, MessageTag, Time,MsgId, Status, NotifyUser, MessageFrom,  ChatTypes, FavouriteDate,FavMsgId,MessageTime,RowId, EditStatus, MessageContentTag] = G,
        UserElements = #xmlel{name = <<"user">>, attrs = [],
          children = [{xmlcdata, MessageUser}]},
        StatusElements = #xmlel{name = <<"status">>, attrs = [],
          children = [{xmlcdata, Status}]},
        TimeElements = #xmlel{name = <<"time">>, attrs = [],
          children = [{xmlcdata, Time}]},
        MsgidElement = #xmlel{name = <<"msgid">>, attrs = [],
          children = [{xmlcdata, MsgId}]},
        ChattypeElement = #xmlel{name = <<"chat_type">>, attrs = [],
          children = [{xmlcdata, ChatTypes}]},
        FavouriteDateElement = #xmlel{name = <<"favourite_date">>, attrs = [],
          children = [{xmlcdata, FavouriteDate}]},
        FromNotificationElement = #xmlel{name = <<"from_notification">>, attrs = [],
          children = [{xmlcdata, NotifyUser}]},
        MsgToElement = #xmlel{name = <<"messageto">>, attrs = [],
          children = [{xmlcdata, MessageFrom}]},
        if MessageTag =:=  <<"">> ->
          MessageElement = #xmlel{name = <<"message ">>, attrs = [],
          children = [{xmlcdata, MessageContentTag}]};
        true ->
          MessageElement = #xmlel{name = <<"message ">>, attrs = [],
          children = [{xmlcdata, MessageTag}]}
        end,
        FavMsgIdElement = #xmlel{name = <<"favmsgid ">>, attrs = [],
          children = [{xmlcdata, FavMsgId}]},
        MessageTimeElement = #xmlel{name = <<"message_time">>, attrs = [],
          children = [{xmlcdata, MessageTime}]},
        EditStatusElement = #xmlel{name = <<"edit_msg_status ">>, attrs = [],
          children = [{xmlcdata, EditStatus}]},
        RowIdElement = #xmlel{name = <<"row_id">>, attrs = [],
          children = [{xmlcdata, RowId}]},
        #xmlel{name = <<"chat">>, attrs = [],
          children = [UserElements,MsgToElement, EditStatusElement, FavMsgIdElement, StatusElements, TimeElements, MessageElement ,MsgidElement, ChattypeElement, FromNotificationElement,FavouriteDateElement, MessageTimeElement, RowIdElement]}
                          end,
        Result),
      GroupXml = [#xmlel{name = <<"history">>, attrs = [], children = SubEls1}],
      fly_mod_utils:generate_subel(IQ, #user_fav{type = RequestType ,sub_els = GroupXml })
  end.

mod_opt_type(iqdisc) -> fun gen_iq_handler:check_type/1;
mod_opt_type(db_type) -> fun(T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(_) -> [db_type, iqdisc].

mod_options(_Host) ->
[].