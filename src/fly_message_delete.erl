


%%%-------------------------------------------------------------------
%%% File       : fly_message_delete.erl
%%% Author     : Contus <ejabberd@contus.in>
%%% Purpose    : Receive Vcard Update Iq (an empty iq with specific status)
%%% Created At : 21 Jul 2016
%%%-------------------------------------------------------------------

-module(fly_message_delete).
-author("ejabberd@contus.in").
-protocol({xep, 12, '2.0'}).
-behaviour(gen_mod).
-define(EJABBERD_DEBUG, true).
%% API
-export([start/2, stop/1, depends/2, mod_options/1, mod_opt_type/1, process_local_iq/1]).

-include("logger.hrl").
-include_lib("xmpp/include/xmpp.hrl").




-type host() :: string().
-type name() :: string().
-type value() :: string().
-type opts() :: [{name(), value()}, ...].

%===================================================================
% API
%===================================================================
-spec start(host(), opts()) -> ok.
start(Host, _Opts) ->
  gen_iq_handler:add_iq_handler(ejabberd_sm, Host, ?NS_MESSAGE_ACTIVITIES, ?MODULE, process_local_iq),
  ok.

-spec stop(host()) -> ok.
stop(Host) ->
  gen_iq_handler:remove_iq_handler(ejabberd_sm, Host, ?NS_MESSAGE_ACTIVITIES),
  ok.


depends(_, _) ->
  [].

%% Handling the IQ

process_local_iq(#iq{from = From, to = To, type = Type, sub_els = [#del_message_activities{status = RequestType,delete_type=SubStatus}]} = IQ) ->
  case Type of
    set ->
      process_iq_set(From, To, RequestType,SubStatus, xmpp:encode(IQ));
%%    get ->
%%      process_iq_get(From, To,RequestType, xmpp:encode(IQ));
    _ ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = <<"error">>, result_type = <<"invalid iq type">>})
  end.

%% Set method for the IQ
process_iq_set(From, _To, RequestType,SubStatus, IQ) ->
  SubEl = fxml:get_subtag_with_xmlns(IQ, <<"query">>, ?NS_MESSAGE_ACTIVITIES),
  case RequestType of
    <<"message_delete">> ->
      delete_message_with_media(From, RequestType,SubStatus, SubEl, IQ);
    no_such_subtag ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});
    empty_value ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = <<"empty_value">>, result_type = <<"unknown request">>});
    _Status ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = _Status, result_type = <<"unknown request">>})
  end.



%% delete the users message in db and notify to other resource
%%
%%
%% @param record From
%% @param binary RequestType
%% @param binary IQ
%% @return IQ(Result)
delete_message_with_media(#jid{luser = User, lserver = Server, lresource = Resource}= From , RequestType, DeleteType, SubEl, IQ) ->
  case DeleteType of
    <<"delete_for_me">> ->
      delete_for_me(#jid{luser = User, lserver = Server, lresource = Resource} = From,SubEl,RequestType,IQ);
    <<"delete_all_conversation">> ->
      delete_all_conversation(From, RequestType,SubEl, IQ);
    <<"delete_for_everyone">> ->
      delete_for_everyone(#jid{luser = User, lserver = Server, lresource = Resource} = From,SubEl,RequestType,IQ);
    <<"delete_multiple_conversation">> ->
      delete_multiple_conversation(#jid{luser = User, lserver = Server, lresource = Resource} = From,SubEl,RequestType,IQ);
    no_such_subtag ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = <<"no_such_subtag">>, result_type = <<"unknown request">>});
    empty_value ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = <<"empty_value">>, result_type = <<"unknown request">>});
    _Status ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = _Status, result_type = <<"unknown request">>})
  end.

delete_multiple_conversation(#jid{luser = User, lserver = Server, lresource = Resource} = From,SubEl,RequestType,IQ) ->
  MessageTag = fxml:get_subtag(SubEl, <<"delete_messages">>),
  lists:foreach(fun(U) ->
    ToUser = fxml:get_attr_s(<<"to_user">>,
      U#xmlel.attrs),
    Type = fxml:get_attr_s(<<"type">>,
      U#xmlel.attrs),
    if
      Type =:= <<"chat">> ->
        delete_single_chat_conversation(#jid{luser = User, lserver = Server, lresource = Resource} = From,RequestType,IQ,ToUser,Type);
      Type =:= <<"groupchat">> ->
        delete_group_chat_conversation(#jid{luser = User, lserver = Server} = From,RequestType,IQ,ToUser,Type);
      Type =:= <<"broadcast">> ->
        delete_broadcast_conversation(#jid{luser = User, lserver = Server} = From,RequestType,IQ,ToUser,Type)
    end  end, MessageTag#xmlel.children),
  fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"Multiple message conversations deleted for you successfully">>}).

delete_single_chat_conversation(#jid{luser = User, lserver = Server} = From,RequestType,IQ,ToUser,Type) ->
  case catch fly_mod_utils:get_all_media_conversation_with_single_chat(Server,Type,ToUser,User)  of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"No media messages">>});
    {selected, _,   Result} ->
      update_chat_media_files(Server,User,Result,RequestType,From)

  end.

delete_group_chat_conversation(#jid{luser = User, lserver = Server} = From,RequestType,IQ,ToUser,Type) ->
  case catch fly_mod_utils:get_all_media_conversation_with_group(Server,Type,ToUser,User)  of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"No media messages">>});
    {selected, _,   Result} ->
      update_chat_media_files(Server,User,Result,RequestType,From)

  end.

delete_broadcast_conversation(#jid{luser = User, lserver = Server} = From,RequestType,IQ,ToUser,Type) ->
  case catch fly_mod_utils:get_all_media_conversation_with_broadcast(Server,Type,ToUser,User)  of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"No media messages">>});
    {selected, _,   Result} ->
      update_chat_media_files(Server,User,Result,RequestType,From)
  end.

delete_for_me(#jid{luser = User, lserver = Server, lresource = Resource} = From,SubEl,RequestType,IQ) ->
  MessageTag = fxml:get_subtag(SubEl, <<"delete_messages">>),
  lists:foreach(fun(U) ->
    Token = fxml:get_attr_s(<<"file_token">>,
      U#xmlel.attrs),
    MessageId = fxml:get_attr_s(<<"id">>,
      U#xmlel.attrs),
    if
      Token /= <<>> ->
        delete_for_me_chat(#jid{luser = User, lserver = Server, lresource = Resource} = From,RequestType,IQ,Token);
      true ->
        ToUser = fxml:get_attr_s(<<"to_user">>,
          SubEl#xmlel.attrs),
        message_delete_for_web_chat(#jid{luser = User, lserver = Server} = From,RequestType,MessageId,ToUser)
    end  end, MessageTag#xmlel.children),
  fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"Message deleted for you successfully">>}).


delete_for_everyone(#jid{luser = User, lserver = Server, lresource = Resource} = From,SubEl,RequestType,IQ) ->
  MessageTag = fxml:get_subtag(SubEl, <<"delete_messages">>),
  lists:foreach(fun(U) ->
    Token = fxml:get_attr_s(<<"file_token">>,
      U#xmlel.attrs),
    MessageId = fxml:get_attr_s(<<"id">>,
      U#xmlel.attrs),
    if
      Token /= <<>> ->
        delete_for_everyone_chat(#jid{luser = User, lserver = Server, lresource = Resource} = From,RequestType,IQ,Token);
      true ->
        ToUser = fxml:get_attr_s(<<"to_user">>, SubEl#xmlel.attrs),
        message_delete_for_web_chat(#jid{luser = User, lserver = Server} = From,RequestType,MessageId,ToUser)
    end  end, MessageTag#xmlel.children),
  fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"Message deleted  successfully">>}).

delete_for_everyone_chat(#jid{luser = User, lserver = Server} = From,RequestType,IQ,FileToken) ->
  case catch fly_mod_utils:get_all_media_conversation_with_filetoken(Server, FileToken) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"No media messages">>});
    {selected, _,   Result} ->
      update_chat_media_files_everyone(Server,User,Result,RequestType,From)
  end.


delete_for_me_chat(#jid{luser = User, lserver = Server} = From,RequestType,IQ,FileToken) ->
  case catch fly_mod_utils:get_all_media_conversation_with_filetoken(Server, FileToken) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"No media messages">>});
    {selected, _,   Result} ->
      update_chat_media_files(Server,User,Result,RequestType,From)
  end.


delete_all_conversation(#jid{luser = User, lserver = Server} = From,RequestType,_SubEl,IQ) ->
  case catch fly_mod_utils:get_all_media_conversation(Server, User) of
    {selected, _, []} ->
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"No media messages">>});
    {selected, _,  Result} ->
      update_chat_media_files(Server,User,Result,RequestType,From),
      fly_mod_utils:generate_subel(IQ, #del_message_activities{type = RequestType, result_type = <<"All conversations deleted successfully">>})
  end.

message_delete_for_web_chat(#jid{luser = User, lserver = Server, lresource = Resource} = From,RequestType,MessageId,TUser) ->
  To = jid:make({User, Server, <<>>}),
  ToUser = jid:make({TUser, Server, <<>>}),
  XmlBody = #xmlel{name = <<"message">>,
    attrs = [{<<"from">>, jid:to_string(From)}, {<<"to">>, jid:to_string(To)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
    children = [#xmlel{name = <<"messageclear">>,
      attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"message_ids">>, MessageId}, {<<"type">>, RequestType}],
      children = []}]},
  ejabberd_router:route(From, To, XmlBody),

    case fly_mod_utils:get_mobile_user_message(User, Server) of
      true ->
        NewPacket = #xmlel{name = <<"message">>,
          attrs = [{<<"from">>, jid:to_string(To)}, {<<"to">>, jid:to_string(From)}, {<<"type">>, <<"chat">>}, {<<"id">>, MessageId}],
          children = [#xmlel{name = <<"messageclear">>,
            attrs = [{<<"xmlns">>, ?NS_RECEIPTS}, {<<"message_ids">>, MessageId}, {<<"type">>, RequestType}],
            children = []}]},
        mod_offline:store_packet({From,  xmpp:decode(NewPacket)});
      false ->
        ok
  end,
  fly_mod_utils:delete_message(From, MessageId),
  case catch fly_mod_utils:recent_exist(Server, User, MessageId) of

    {selected, _, []} ->
      ok;
    {selected, _, [[Id,_FromUser,_FromMessage]]} ->
      case catch fly_mod_utils:get_last_messages(From, ToUser, TUser) of
        {selected, _, []} ->
          fly_mod_utils:delete_message_recentchat(Server,Id,<<"">>);
        {selected, _, [[MessageFrom,MessageTo, Message_id, Message_type, ChatType, Status, Recall_status, From_notification, To_notification, Message_notification, Created_at,Topic_id,Meta_Data]]} ->

          if Message_type =:= <<"text">> ->

            case catch
              fly_mod_utils:get_message(Server, ChatType, Message_id)
            of
              {selected, _, []} ->
                MsgContent = <<"">>;
              {selected, _, [[Txt]]} ->
               
                  MsgContent = Txt
      
            end;
            Message_type =:= <<"auto_text">> ->
              case catch
                fly_mod_utils:get_message(Server, ChatType, Message_id)
              of
                {selected, _, []} ->
                  MsgContent = <<"">>;
                {selected, _, [[Txt]]} ->
                
                MsgContent = Txt
  
              end;
            Message_type =:= <<"notification">> ->

              MsgContent = Message_notification;
            true ->
              MsgContent = Message_type
          end,
          if(MessageFrom =:= User) ->
            fly_mod_utils:update_deleted_recent_chat(Server,MessageTo,User,Message_id,From_notification,MsgContent,ChatType,Message_type,To_notification,Status, Recall_status,Created_at);
            true ->
              fly_mod_utils:update_deleted_recent_chat(Server,MessageFrom,User,Message_id,From_notification,MsgContent,ChatType,Message_type,To_notification,Status, Recall_status,Created_at)
          end


      end

  end.

update_chat_media_files(Server,User,Result,RequestType,From) ->
  lists:map(fun(G) ->
    [Id, FromUser, ToUsers,MessageId] = G,
    if
      FromUser =:= User ->
        message_delete_for_web_chat(#jid{luser = User, lserver = Server} = From,RequestType,MessageId,ToUsers),
        fly_mod_utils:empty_from_user_to_chat_media(Server,Id);
      true ->
        ToUserList = binary_to_list(ToUsers),
        RemoveUser1 = <<User / binary, <<",">> / binary>>,
        RemoveUser2 = <<<<",">> / binary,User / binary>>,
        UsersList1 = re:replace(ToUserList,binary_to_list(RemoveUser1), ""),
        UsersList2 = re:replace(UsersList1,binary_to_list(RemoveUser2), ""),
        UsersList3 = re:replace(UsersList2,binary_to_list(User), ""),
        UpdatedToUserList = iolist_to_binary(UsersList3),
        fly_mod_utils:update_tousers_to_chat_media(Server,UpdatedToUserList,Id),
        Range = binary:split(ToUsers, <<",">>, [global]),
        lists:foreach(fun(TUser) ->
          message_delete_for_web_chat(#jid{luser = User, lserver = Server} = From,RequestType,MessageId,TUser)
                      end, Range)
    end

            end,
    Result).

update_chat_media_files_everyone(Server,User,Result,RequestType,From) ->
  lists:map(fun(G) ->
    [Id, FromUser, ToUsers,MessageId] = G,
    if
      FromUser =:= User ->
        message_delete_for_web_chat(#jid{luser = User, lserver = Server} = From,RequestType,MessageId,ToUsers),
        fly_mod_utils:empty_from_user_to_chat_media_everyone(Server,Id);
      true ->
        fly_mod_utils:empty_from_user_to_chat_media_everyone(Server,Id),
        Range = binary:split(ToUsers, <<",">>, [global]),
        lists:foreach(fun(TUser) ->
          message_delete_for_web_chat(#jid{luser = User, lserver = Server} = From,RequestType,MessageId,TUser)
                      end, Range)
    end

            end,
    Result).


mod_options(_Host) ->
[].
mod_opt_type(iqdisc) -> fun gen_iq_handler:check_type/1;
mod_opt_type(db_type) -> fun(T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(_) -> [db_type, iqdisc].