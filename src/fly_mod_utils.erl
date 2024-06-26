
%%%=============================================================================
%%% File       : mod_utils.erl
%%% Author     : Contus <ejabberd@contus.in>
%%% Purpose    : Common methods which used for all modules and obdc queries also.
%%% Created At : 01. Jul 2016 1:18 PM
%%%==============================================================================
-module(fly_mod_utils).

-compile([{parse_transform, ejabberd_sql_pt}]).

-author("Contus").

-export([check_user_exists/2,
  check_users_exists/2,
  check_roster_exists/3,
  add_sync_roster/4,
  check_empty_roster_exists/3,
  update_sync_roster/4,
  del_sync_roster/3,
  update_delete_roster/2,
  get_roster_delete/2,
  update_roster_avail/3,
  get_vcard/2,
  get_vcard_from_search/2,
  get_user_device/2,
  get_user_device/4,
  get_user_for_ios_group_device/3,
  get_group_participants/2,
  get_roster_and_recent_jid/1,
  get_roster_from_recent_jid/1,
  get_users_from_group/1,
  get_email_contacts/1,
  get_roster_and_recent/1,
  generate_subel/3,
  get_participants_update/3,
  get_admin_update/3,
  admin_user/3,
  update_group_removed_user/3,
  make_admin_ifadminexit/3,
  create_broadcast/4,
  insert_broadcast_users/3,
  check_broadcast_id_exists/2,
  remove_broadcast_users/3,
  get_broadcast_users/2,
  update_broadcast_name/4,
  delete_broadcast_id_from_broadcast/2,
  delete_broadcast_users_from_broadcast_users/2,
  get_my_all_broadcast_details/2,
  get_broadcast_details/3,
  get_group_users/2,
  get_group_users/3,
  get_group_users_list/3,
  generate_subel/4,
  get_roster_jid/1,
  generate_subel/2,
  get_my_all_group_ids/2,
  get_my_all_group_id_rosters/2,
  get_my_all_group_id/2,
  get_group_profile/3,
  set_last_t/2,
  set_last_o/3,
  clear_message/5,
  clear_message/4,
  get_userbusy_message/3,
  delete_group_user/3,
  delete_group/2,
  updategroup_clear/2,
  clear_broadcast_message/3,
  delete_broadcast_message/2,
  clear_all/2,
  delete_message/2,
  remove_offline/2,
  remove_offline/3,
  update_offline/3,
  update_seen/4,
  update_delivery/4,
  update_delivery_offline/2,
  update_recall/2,
  insert_status/12,
  insert_status/2,
  set_favourite_message/3,
  get_favourite_message/3,
  update_favourite_message/3,
  get_user_resource/1,
  get_user_resource/3,
  get_message/2,
  get_message_from/2,
  get_offline_msg/2,
  update_offline_status/3,
  mute_user_notification/3,
  update_to_normal_user/3,
  create_user_ifuserexit/7,
  get_recent_chat_web/1,
  get_recent_chat_topic/4,
  get_single_chat_messages/8,
  get_broadcast_chat_media_messages/3,
  get_bot_chat_messages/4,
  get_group_chat_messages/7,
  get_broadcast_chat_messages/5,
  get_broadcast_message/3,
  get_message_status/2,
  get_groupmessage_status/2,
  group_notify_message/7,
  get_blockedlist/2,
  check_group_exists/2,
  set_web_password/2,
  update_last_recent_message/2,
  get_last_message_id/2,
  get_group_message_status/2,
  get_single_chat_media_messages/4,
  get_group_chat_media_messages/4,
  get_broadcast_chat_fullmedia_messages/4,
  get_single_chat_fullmedia_messages/4,
  get_group_chat_fullmedia_messages/5,
  get_roster_nick/3,
  get_callstatus/2,
  get_group_vcard/2,
  msg_exit/2,
  get_offline_message/3,
  insert_group_count/2,
  update_group_count/2,
  update_media_call_status/4,
  update_media_call_status/6,
  insert_media_call_status/11,
  insert_call_log_status/13,
  get_call_user_list/2,
  get_call_initiator/2,
  get_call_calling_status/2,
  get_attend_and_calling_list/2,
  get_call_user_status/2,
  get_call_user_count/2,
  get_call_user_calling_count/2,
  get_call_user_attended_count/2,
  get_call_caller_attended_count/3,
  get_call_get_call_initiator/2,
  get_calling_user_status/2,
  get_group_update_count/2,
  get_single_message/3,
  get_group_message/3,
  check_blockedlist/3,
  get_reply_message/2,
  get_reply_messages/2,
  delete_spool/2,
  get_busy_status/1,
  update_user_busy/3,
  get_not_delivered_message/2,
  update_delivered_status/2,
  delete_favourite_message/2,
  get_bulk_user_device/6,
  get_bulk_user_device/5,
  get_bulk_voip_user_device/5,
  get_bulk_group_create_android_user_device/2,
  delete_recentchat/2,
  delete_message_recentchat/3,
  insert_recent_chat/13,
  insert_recent_chat_topic/13,
  update_recent_groupchat/11,
  get_last_messages/3,
  update_recent_chat/13,
  update_recent_chat_topic/12,
  update_recent_chat_broadcast/11,
  update_deleted_recent_chat/16,
  update_deleted_grouprecent_chat/16,
  clear_particular_call_log/2,
  clear_call_log/2,
  get_message/3,
  get_nickname/2,
  get_team_jid/3,
  recent_exist/3,
  get_iq_message_id/1,
  get_user_from_string_jid/1,
  get_device_from_resource/1,
  check_blockeduser/3,
  get_messagestatus/2,
  getuserBlockedList/1,
  jid_to_string/1,
  get_host/1,
  get_nick/2,
  get_recent_profile/3,
  get_all_media_conversation/2,empty_from_user_to_chat_media/2,update_tousers_to_chat_media/3,
  revoke_media_permission/3, get_chat_media_by_messageid/2,
  get_all_media_conversation_with_filetoken/2,
  create_profile_chat_media_files/3,get_all_media_conversation_with_single_chat/4,empty_from_user_to_chat_media_everyone/2,
  get_all_media_conversation_with_group/4,get_all_media_conversation_with_broadcast/4,
  get_chat_media_profile/2,update_chat_media_profile/3,
  get_remove_user/2,get_caller_busy/2,
  get_last/2, get_custom_attributes/1,is_carbon_copy/1,
  update_license_lookup/1, validate_license/3,message_status/3,message_status_new/3,
  decrypt_license_data/2,get_participants/3,update_mute_chat/3,update_archive_chat/3,get_user_settings/1,
  set_user_settings/2, get_archived_chats/1,update_recent_unread_chat/2,update_recent_group_unread_chat/3,
  update_block_status_user/3,update_block_status_group/3,get_contact_permission/1,update_vcard_date/2,get_user_resources/2,
  get_user_resources/3,get_mobile_user_message/2,get_mobile_user_resource/2,get_push_type/1,get_meta_chat_web/4,poll_vote_update/8,
  remove_poll_offline/3]).

-include("logger.hrl").

-include_lib("xmpp/include/xmpp.hrl").

-include("ejabberd_sql_pt.hrl").

%%%=============================================================================
%%% Here we can implement all our custom query methods for the custom modules
%%% Method  : check_user_exists
%%% Params  : LServer,User,Contact
%%% Author  : Contus <ejabberd@contus.in>
%%% Purpose : Check whether the user is exist or not in the particular server
%%%================================================================================

-spec is_carbon_copy(stanza()) -> boolean().
is_carbon_copy(#message{meta = #{carbon_copy := true}}) ->
    true;
is_carbon_copy(_) ->
    false.

check_user_exists(LServer, Contact) ->
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT username FROM users WHERE username = '">>, Contact, <<"';">>]).

check_users_exists(LServer, Contact) ->
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT username FROM users WHERE username IN(">>, Contact, <<");">>]).

check_roster_exists(LServer,Username,Contact)->
  Jid = make_jid_s(Contact,LServer),
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT username FROM rosterusers WHERE username='">>,Username,<<"' AND jid='">>,Jid,<<"';">>]).

check_empty_roster_exists(LServer,Username,Contact)->
  Jid = make_jid_s(Contact,LServer),
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT username FROM rosterusers WHERE username='">>,Username,<<"' AND jid='">>,Jid,<<"' AND subscription='F';">>]).

add_sync_roster(LServer, Username, Contact,Subscription) ->
  Jid = make_jid_s(Contact,LServer),
  ejabberd_sql:sql_query(LServer,[<<"INSERT INTO rosterusers(username,jid,nick,subscription,ask,server,type) "
  "values ('">>,Username, <<"','">>, Jid,<<"','">>,Contact,<<"','">>,Subscription,<<"','N','N','item');">>]).

update_sync_roster(LServer, Username, Contact, Subscription) ->
  Jid = make_jid_s(Contact,LServer),
  sql_queries:update(LServer, <<"rosterusers">>,
    [<<"subscription">>,<<"ask">>],
    [Subscription,<<"N">>],
    [<<"username='">>, Username, <<"' AND jid='">>,Jid,<<"'">>]).

del_sync_roster(LServer, Username, Contact) ->
  Jid = make_jid_s(Contact,LServer),
  ejabberd_sql:sql_query(LServer,[<<"DELETE FROM rosterusers WHERE username='">>,Username,<<"' AND jid='">>,Jid,<<"';">>]).

update_delete_roster(LServer, Username) ->

  ejabberd_sql:sql_query(LServer,[<<"UPDATE rosterusers SET ask='O' WHERE username='">>, Username,<<"';">>]).

get_roster_delete(LServer, Username) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select username, jid, subscription, ask FROM rosterusers WHERE username='">>,Username,<<"' AND ask = 'O' AND subscription !='F';">>]).

update_roster_avail(LServer, Username, Contact) ->
  Jid = make_jid_s(Contact,LServer),
  sql_queries:update(LServer, <<"rosterusers">>,
    [<<"ask">>],
    [<<"N">>],
    [<<"username='">>, Username, <<"' AND jid='">>,Jid,<<"'">>]).

make_jid_s(UserName, Server) ->
  ejabberd_sql:escape(jid:to_string(jid:tolower(jid:make(UserName,
    Server,
    <<"">>)))).

get_vcard(LServer, LUser) ->
  ejabberd_sql:sql_query(
    LServer,
    ?SQL("select @(vcard)s, @(created_at)s from vcard"
    " where username=%(LUser)s")).

get_vcard_from_search(LServer, LUser) ->
  ejabberd_sql:sql_query(
    LServer,
    ?SQL("select @(nickname)s,@(image)s,@(email)s,@(mobilenumber)s,@(status)s,@(designation)s,@(coverimg)s from vcard_search"
    " where username=%(LUser)s")).

get_nickname(LServer, LUser) ->
  ejabberd_sql:sql_query(
    LServer,
    ?SQL("select @(nickname)s from vcard_search"
    " where username=%(LUser)s")).

get_user_device(LServer, LUser) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT IFNULL(device_type,'') as device_type, IFNULL(device_token,'')as device_token,IFNULL(voip_device_token,'')as voip_device_token ,  mode, device_os_version,device_id ,user_type  FROM chat_users_details WHERE  username = '">>, LUser, <<"' and (device_type !='Web' and device_type !='') and  device_token != '' and device_token != 'null';">>]).

% get_user_device(LServer, LUser, LResource) ->
%   Substring = string:str((LResource), binary_to_list(<<"Web">>)),
%   if Substring =:= 1 ->
%       ejabberd_sql:sql_query(LServer,
%       [<<"SELECT IFNULL(device_type,'') as device_type, IFNULL(device_token,'')as device_token,IFNULL(voip_device_token,'')as voip_device_token ,mode, device_os_version, device_id  FROM chat_users_details WHERE (device_type !='Web' and device_type !='') and device_id != ''and username = '">>, LUser, <<"';">>]);
%   true ->
%       Resource = get_device_from_resource(LResource),
%       ejabberd_sql:sql_query(LServer,
%       [<<"SELECT IFNULL(device_type,'') as device_type, IFNULL(device_token,'')as device_token,IFNULL(voip_device_token,'')as voip_device_token , mode, device_os_version, device_id  FROM chat_users_details WHERE (device_type !='Web' and device_type !='') and device_id != '' and device_id != '">>, Resource, <<"' and username = '">>, LUser, <<"';">>])
%   end.

get_user_device(LServer, LUser, LResource, ChatType) ->
  % if ChatType == <<"mediacall">> ->
  %    ejabberd_sql:sql_query(LServer,
  %     [<<"SELECT IFNULL(device_type,'') as device_type, IFNULL(device_token,'')as device_token,IFNULL(voip_device_token,'')as voip_device_token , mode, device_os_version, device_id  FROM chat_users_details WHERE (device_type !='Web' and device_type !='') and device_id != ''  and username = '">>, LUser, <<"';">>]);
  % true ->
    if LResource =:= "" ->
      ejabberd_sql:sql_query(LServer,
      [<<"SELECT  device_type, device_token, voip_device_token , mode, device_os_version, device_id ,user_type, push_server_type  FROM chat_users_details WHERE username = '">>, LUser, <<"' and ( device_token != '' and device_token != 'null'  and device_type !='') and device_id != ''  ;">>]);
      true ->
      ejabberd_sql:sql_query(LServer,
      [<<"SELECT  device_type,device_token, voip_device_token , mode, device_os_version, device_id ,user_type, push_server_type  FROM chat_users_details WHERE  username = '">>, LUser, <<"'  and ( device_token != '' and device_token != 'null'  and device_type !='') and device_id != ''  and device_id not in  ('">>, LResource, <<"' );">>])
      % end
  end.

get_user_for_ios_group_device(LServer, LUser, LResource) ->
  if LResource =:= "" ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT  device_type,  device_token,voip_device_token ,  mode, device_os_version ,user_type, push_server_type  FROM chat_users_details WHERE  username = '">>, LUser, <<"' and device_token != '' and device_token != 'null' and device_type ='ios'  ;">>]);
  true ->
      ejabberd_sql:sql_query(LServer,
      [<<"SELECT  device_type, device_token, voip_device_token ,  mode, device_os_version, user_type,push_server_type FROM chat_users_details WHERE  username = '">>, LUser, <<"' and  device_token != '' and device_token != 'null' and device_type ='ios'   and device_id not in  ('">>, LResource, <<"' );">>])
      end.

get_bulk_user_device(LServer, Members, Resources, Type,Fromuser) ->
  FromUser = get_user_from_string_jid(Fromuser),
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT device_token ,user_type, push_server_type  FROM chat_users_details WHERE  username  in ('">>, Members, <<"') and  device_token != '' and device_token != 'null' and (device_type = 'android' or device_type = 'flutter-android' or  device_type = 'flutter-ios') and username != '">>, FromUser, <<"' and device_id not in  ('">>, Resources, <<"' );">>]).

get_bulk_user_device(LServer, Members, Resources, Type,Mode,Fromuser) ->
  FromUser = get_user_from_string_jid(Fromuser),
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT  device_token ,user_type, push_server_type From chat_users_details WHERE  username  in ('">>, Members, <<"') and  device_token != '' and device_token != 'null' and device_type = '">>, Type, <<"'and mode = '">>, Mode, <<"' and device_os_version >= 13 and username != '">>, FromUser, <<"' and device_id not in  ('">>, Resources, <<"' );">>]).

get_bulk_voip_user_device(LServer, Members,Type,Mode,Fromuser) ->
  FromUser = get_user_from_string_jid(Fromuser),
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT  voip_device_token ,user_type, push_server_type From chat_users_details WHERE  username  in ('">>, Members, <<"') and voip_device_token != '' and voip_device_token != 'null' and device_type = '">>, Type, <<"'and mode = '">>, Mode, <<"' and device_os_version < 13 and username != '">>, FromUser, <<"';">> ]).

get_bulk_group_create_android_user_device(LServer, Member) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT  device_token ,user_type, push_server_type From chat_users_details WHERE  username  ='">>, Member, <<"' and  device_token != '' and device_token != 'null' and device_type = 'android';">> ]).

%% get roaster usg user jabber id
%%
%%
%% @param  record jid
%% @return List
get_roster_jid(#jid{luser = User,lserver = Server})->
  Value = list_to_binary(binary_to_list(User) ++ "@" ++ binary_to_list(Server)),
  ejabberd_sql:sql_query(Server,[<<"select distinct(jid_username) as username from rosterusers  where username = '">>,User,<<"' or jid = '">>,Value, <<"' ;">>]).

get_group_update_count(LServer, LUser) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT update_count  FROM group_update WHERE groupid = '">>, LUser, <<"' LIMIT 1;">>]).

update_vcard_date(LServer, LUser) ->
    ejabberd_sql:sql_query(
      LServer,
      [<<"update vcard set updated_at = NOW() WHERE username = '">>, LUser, <<"';">>]).

update_group_count(LServer, LUser) ->
  update_vcard_date(LServer, LUser),
  ejabberd_sql:sql_query(
    LServer,
    [<<"update group_update set  update_count = update_count + 1   WHERE groupid = '">>, LUser, <<"';">>]).

update_media_call_status(LServer,RoomId,LUser,CallStatus) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"update media_call_logs set call_status='">>, CallStatus, <<"'   WHERE room_id = '">>, RoomId, <<"' and to_user = '">>, LUser, <<"' ;">>]).

insert_media_call_status(FServer,FUser,TUser,RoomId,CallType,CallStatus,_CallTime,CallMode,GroupId,CallLink,Meta_data) ->
  if Meta_data =:= <<>> ->
      MetaData = <<"{}">>;
    Meta_data =:= <<"">> ->
      MetaData = <<"{}">>;
    true ->
      MetaData = Meta_data
  end,
  ejabberd_sql:sql_query(FServer, [<<"insert into media_call_logs (from_user,to_user,room_id,called_type,call_status,call_mode,group_id,room_link, metadata) values ('">>,FUser, <<"','">>,TUser, <<"','">>,RoomId, <<"','">>,CallType, <<"','">>,CallStatus, <<"','">>,CallMode, <<"','">>,GroupId, <<"','">>,CallLink, <<"','">>,MetaData, <<"')
  ON DUPLICATE KEY UPDATE from_user = '">>, FUser, <<"',to_user = '">>, TUser, <<"',room_id = '">>,RoomId , <<"';">> ]).

insert_call_log_status(FServer,FUser,TUser,RoomId,CallType,CallStatus,_CallTime,CallMode,GroupId,CallLink,UserList,CallerDevice,Meta_data) ->
  Substring = string:str(binary_to_list(CallerDevice),binary_to_list(<<"Web-">>)),
  Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),
  if Meta_data =:= <<>> ->
      MetaData = <<"{}">>;
    Meta_data =:= <<"">> ->
      MetaData = <<"{}">>;
    true ->
      MetaData = Meta_data
  end,
  FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),

  Currenttime = list_to_binary(FlatTimeStamp),
    if Substring =:= 1 ->
      U = <<"WEB">>;
      true ->
      U = <<"Mobile">>
    end,
  Value = list_to_binary(binary_to_list(FUser) ++ "@" ++ binary_to_list(FServer)),
  ejabberd_sql:sql_query(FServer, [<<"insert into client_call_logs (from_user,to_user,room_id,call_type,call_mode,group_id,call_time,created_user,caller_device,user_list,metadata)" "values
  ('">>,Value, <<"','">>,UserList, <<"','">>,RoomId, <<"','">>,CallType, <<"','">>,CallMode, <<"','">>,GroupId, <<"','">>,Currenttime, <<"','">>,TUser, <<"','">>,U, <<"','">>,UserList, <<"','">>,MetaData, <<"')
  ON DUPLICATE KEY UPDATE from_user = '">>, Value, <<"',to_user = '">>, UserList, <<"',room_id = '">>,RoomId , <<"';">> ]).

get_call_user_list(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT to_user  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' and  (call_status = 'CALLING' or call_status = 'ATTENDED');">>]).

get_caller_busy(LServer, FUser) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT to_user  FROM media_call_logs WHERE from_user = '">>, FUser , <<"' and  (call_status = 'CALLING' or call_status = 'ATTENDED');">>]).

get_call_initiator(LServer, RoomId) ->
ejabberd_sql:sql_query(
LServer,
[<<"SELECT from_user  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' limit 1;">>]).

get_call_calling_status(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT count(*)  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' and  call_status = 'CALLING' ;">>]).

get_attend_and_calling_list(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT count(*)  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' and  (call_status = 'CALLING' or call_status = 'ATTENDED');">>]).

get_call_user_status(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT to_user  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' and  call_status = 'ATTENDED';">>]).

get_call_user_calling_count(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT count(*)  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' and  call_status = 'CALLING' ;">>]).

get_call_user_attended_count(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT count(*)  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' and  call_status = 'ATTENDED' ;">>]).

get_call_caller_attended_count(LServer, RoomId, Caller) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT count(*)  FROM media_call_logs WHERE from_user = '">>, Caller , <<"' and room_id = '">>, RoomId , <<"' and  call_status = 'ATTENDED' ;">>]).

get_call_user_count(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT count(*)  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' and  (call_status = 'CALLING' or call_status = 'ATTENDED');">>]).

get_call_get_call_initiator(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT from_user, call_status  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' order by id ASC LIMIT 1;">>]).

get_calling_user_status(LServer, RoomId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"SELECT to_user  FROM media_call_logs WHERE room_id = '">>, RoomId , <<"' and  call_status = 'CALLING';">>]).

update_media_call_status(LServer,RoomId,LUser,CallStatus,_Time,TimeType) ->
if TimeType =:= <<"start_time">> ->
      ejabberd_sql:sql_query(
        LServer,
        [<<"update media_call_logs set call_status='">>, CallStatus, <<"' , start_time= NOW()  WHERE room_id = '">>, RoomId, <<"' and to_user = '">>, LUser, <<"' ;">>]);
    true ->
      ejabberd_sql:sql_query(
        LServer,
        [<<"update media_call_logs set call_status='">>, CallStatus, <<"' , end_time= NOW() WHERE room_id = '">>, RoomId, <<"' and to_user = '">>, LUser, <<"' ;">>])
  end.

insert_group_count(LServer, LUser) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"insert into group_update (update_count,groupid) " "values ('1','">>,LUser, <<"') ;">>]).

get_group_participants(LServer, NodeHost) ->
  ejabberd_sql:sql_query(
    LServer, [<<"select mix_pam.id, mix_pam.username, mix_pam.affiliation, mix_pam.created_at, vcard_search.is_block, vcard.vcard from mix_pam inner join mix_participant on mix_pam.channel = mix_participant.channel and mix_pam.username = mix_participant.username join vcard_search on mix_pam.username = vcard_search.username join vcard on vcard.username = vcard_search.username where mix_pam.channel='">>,NodeHost,<<"';">>]).

generate_subel(Type, Message, MacroNameSpace)->

  #xmlel{name = <<"query">>, attrs = [{<<"xmlns">>, MacroNameSpace}, {<<"type">>, Type}],children = [{xmlcdata,Message}]}.

generate_subel(Type,Status, Message, MacroNameSpace)->

  #xmlel{name = <<"query">>, attrs = [{<<"xmlns">>, MacroNameSpace}, {<<"type">>, Type},{<<"mute">>, Status}],children = [{xmlcdata,Message}]}.

generate_subel(IQ, Record)->
  xmpp:make_iq_result(xmpp:decode(IQ), Record ).

get_roster_and_recent_jid(#jid{luser = User,lserver = Server})->
  ejabberd_sql:sql_query(Server,[<<" select from_user as jid from chat_recent where to_user = '">>,User,<<"' and chat_type = 'chat';" >>]).

get_roster_from_recent_jid(#jid{luser = User,lserver = Server})->
  ejabberd_sql:sql_query(Server,[<<"select to_user as jid from chat_recent where from_user = '">>,User,<<"' and chat_type = 'chat' union select username from rosterusers  where jid_username = '">>,User,<<"';" >>]).

get_email_contacts(#jid{luser = User, lserver = Server})->
  ejabberd_sql:sql_query(Server,[<<"select username as jid from contus_chat_users contus_chat_users where username not in (select jid from rosterusers  where username = '">>,User,<<"' union select CONCAT(from_user,'@','">>,Server,<<"') as jid from chat_recent where to_user = '">>,User,<<"' and chat_type = 'chat') GROUP BY jid;" >>]).

get_roster_and_recent(#jid{luser = User,lserver = Server})->
  ejabberd_sql:sql_query(Server,[<<" select from_user as jid from chat_recent where to_user = '">>,User,<<"' and chat_type = 'chat' union select to_user as jid from chat_recent where to_user = '">>,User,<<"' and chat_type = 'chat';" >>]).

get_users_from_group(#jid{luser = User,lserver = Server})->
  ejabberd_sql:sql_query(Server,[<<"select distinct(mp.username) as jid from mix_participant mp join ( select distinct channel from mix_participant where username = '">>,User,<<"' ) mpa on mpa.channel = mp.channel;">>]).

%% get roaster usg user jabber id
%%
%%
%% @param  record jid
%% @return List
getuserBlockedList(#jid{luser = User,lserver = Server})->
  ejabberd_sql:sql_query(Server,[<<"SELECT pl.value FROM privacy_list_data AS pl, privacy_list AS pv WHERE pv.username = '">>,User,<<"' AND pv.id = pl.id and pl.action = d;">>]).

%% get all users jabber id
%%
%%
%% @param  record jid
%% @return List
% get_allusers(#jid{luser = User,lserver = Server})->
%   ejabberd_sql:sql_query(Server,[<<"select CONCAT(u.username,'@','">>,Server,<<"') as jid from users as u inner join vcard as v on v.username=u.username where u.username != '">>,User,<<"';">>]).

%% get the participants from the group using group node id
%%
%%
%% &param Node id
%% @return List
get_participants_update(LServer, NodeHost, ParticipantData) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"update mix_pam  SET affiliation='o'  where channel = '">>,NodeHost,<<"' and username = '">>,ParticipantData,<<"';">>]).

get_admin_update(LServer, NodeHost, ParticipantData) ->

ejabberd_sql:sql_query(
    LServer,
    [<<"update mix_pam  SET affiliation='n'  where channel = '">>,NodeHost,<<"' and  username = '">>,ParticipantData,<<"';">>]),

  case admin_exit(LServer, NodeHost) of
{selected,[<<"username">>],Admins} ->
  if length(Admins) == 0 ->
    case get_jid_update_admin(LServer, NodeHost, ParticipantData) of
      {selected,[<<"username">>],[[Jid]]} ->
        ejabberd_sql:sql_query(
          LServer,
          [<<"update mix_pam SET affiliation='o'  where channel ='">>,NodeHost,<<"' and username='">>,Jid,<<"';">>]),
          Jid;
      {selected,[<<"username">>],[]} ->
        % ejabberd_sql:sql_query(
        %   LServer,
        %   [<<"delete  from mix_pam  where channel ='">>,GroupTo,<<"' and username='">>,From,<<"';">>]),
          ok
    end;
    true ->
      ok
  end;
{selected,_} ->
  ok
end.


%% get the participants from the group using group node id
%%
%%
%% &param Node id
%% @return List
get_participants(LServer, NodeHost, From) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"select username from mix_participant  where  channel='">>,NodeHost,<<"' and username='">>,From,<<"';">>]).

%% Update admin of the group using Jid
%%
%%
%% &param Jid
%% @return Update the admin in the group
update_group_removed_user(LServer, From, GroupTo) ->
  ejabberd_sql:sql_query(LServer,
    [<<"update mix_pam SET affiliation='' where  channel ='">>,GroupTo,<<"' and username='">>,From,<<"';">>]).

make_admin_ifadminexit(LServer, From, GroupTo) ->
  ejabberd_sql:sql_query(
              LServer,
              [<<"update mix_pam SET affiliation=''  where channel ='">>,GroupTo,<<"' and username='">>,From,<<"'  ;">>]),
  case admin_exit(LServer, GroupTo) of
    {selected,[<<"username">>],Admins} ->
      if length(Admins) == 0 ->
        case get_jid_update_admin(LServer, GroupTo) of
          {selected,[<<"username">>],[[Jid]]} ->
            ejabberd_sql:sql_query(
              LServer,
              [<<"update mix_pam SET affiliation='o'  where channel ='">>,GroupTo,<<"' and username='">>,Jid,<<"' ;">>]),
              Jid;
          {selected,[<<"username">>],[]} ->
            % ejabberd_sql:sql_query(
            %   LServer,
            %   [<<"delete  from mix_pam  where channel ='">>,GroupTo,<<"' and username='">>,From,<<"';">>]),
              ok
        end;
        true ->
          ok
      end;
    {selected,_} ->
      ok
  end.
%% Check admin if the group as admin
%%
%%
%% &param Jid
%% @return List
admin_exit(LServer,  GroupTo) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"select username from mix_pam  where  channel='">>,GroupTo,<<"' and affiliation = 'o' ;">>]).

admin_user(LServer,  GroupTo, Fuser) ->
      ejabberd_sql:sql_query(
        LServer,
        [<<"select username from mix_pam  where  channel='">>,GroupTo,<<"' and username='">>,Fuser,<<"' and  affiliation = 'o';">>]).

get_userbusy_message(LServer, FUser) ->
ejabberd_sql:sql_query(
        LServer,
        [<<"SELECT busy_message from users where username ='">>,FUser,<<"' and busy_status = 1 ;">>]).

check_busy_msg(LServer, TUser, FUser) ->
ejabberd_sql:sql_query(
LServer,
[<<"SELECT message_id from  message_status   where  from_user ='">>,FUser,<<"' and to_user = '">>,TUser,<<"' and message_type = 'auto_text' and DATE(created_at) = CURDATE() limit 1;">>]).

get_userbusy_message(LServer, TUser, FUser) ->
        case catch get_userbusy_message(LServer, FUser) of
          {selected, _, []} ->
            Msg = <<"">>;
          {selected, _, [[BusyMsg]]} ->
            case catch check_busy_msg(LServer, TUser, FUser) of
              {selected, _, []} ->
                Msg = BusyMsg;
              {selected, _, [[MessageId]]} ->
                Msg = <<"">>;
              _ ->
                Msg = <<"">>
            end;
          _ ->
            Msg = <<"">>
        end,
Msg.

update_user_busy(#jid{luser = FUser, lserver = FServer}, BusyStatus, BusyMsg)->
  ejabberd_sql:sql_query(FServer,
        [<<"update  users set busy_message = '">>,BusyMsg,<<"' , busy_status =  '">>,BusyStatus,<<"' where username = '">>,FUser, <<"';">>]).

get_busy_status(#jid{luser = FUser, lserver = FServer})->
  ejabberd_sql:sql_query(FServer,
        [<<"select busy_message, busy_status from users  where  username='">>,FUser,<<"';">>]).

%% get admin details from group using Jid
%%
%%
%% &param Jid
%% @return Update the admin in the group
get_jid_update_admin(LServer, GroupTo) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"select  mix_pam.username from mix_pam inner join mix_participant on mix_pam.channel = mix_participant.channel and mix_pam.username = mix_participant.username where  mix_pam.channel='">>,GroupTo,<<"' and mix_pam.affiliation != '' order by participant_id ASC LIMIT 1">>]).

get_jid_update_admin(LServer, GroupTo, UserName) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"select  mix_pam.username from mix_pam inner join mix_participant on mix_pam.channel = mix_participant.channel and mix_pam.username = mix_participant.username where  mix_pam.channel='">>,GroupTo,<<"'  and mix_pam.username !='">>,UserName,<<"' and mix_pam.affiliation != ''  order by participant_id ASC LIMIT 1">>]).

%% Update admin of the group using Jid
%%
%%
%% &param Jid
%% @return Update the admin in the group
get_group_users(LServer, GroupId) ->
  ejabberd_sql:sql_query(LServer, [<<"select mix_pam.username from mix_pam  inner join mix_participant on mix_pam.channel = mix_participant.channel and mix_pam.username = mix_participant.username where  mix_pam.channel ='">>,GroupId,<<"'  and mix_pam.affiliation != '' order by mix_pam.pam_id asc;">>]).

%% Update admin of the group using Jid
%%
%%
%% &param Jid
%% @return Update the admin in the group
get_group_users_list(LServer, GroupId, UserType) ->
  ejabberd_sql:sql_query(LServer, [<<"select mix_pam.username from mix_pam  inner join mix_participant on mix_pam.channel = mix_participant.channel and mix_pam.username = mix_participant.username where  mix_pam.channel ='">>,GroupId,<<"'  and mix_pam.affiliation = '">>,UserType,<<"';">>]).

get_group_users(LServer, GroupId, Participant) ->
    ejabberd_sql:sql_query(LServer, [<<"select mix_pam.username from mix_pam  inner join mix_participant on mix_pam.channel = mix_participant.channel and mix_pam.username = mix_participant.username where   mix_pam.channel ='">>,GroupId,<<"' and mix_pam.username  ='">>,Participant,<<"' and mix_pam.affiliation != '';">>]).

%% Create broadcast
%%
%%
%% &param BroadcastName, User, BroadcastId
%% @return

create_broadcast(LServer, BroadcastName, User, BroadcastId) ->
  ejabberd_sql:sql_query(
    LServer,
    [<<"insert into chat_broadcast (broadcast_name,broadcast_admin,broadcast_id) " "values ('">>,BroadcastName, <<"','">>,User, <<"','">>,BroadcastId, <<"') ;">>]).

%% Add users to broadcast
%%
%%
%% &param Users , broadcastid
%% @return

insert_broadcast_users(LServer, User, BroadcastId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"insert into chat_broadcast_users (users,broadcast_id) " "values ('">>,User, <<"','">>,BroadcastId, <<"') ;">>]).
%% get broadcast id
%%
%%
%% &param Broadcastid
%% @return list
check_broadcast_id_exists(LServer,  BroadcastId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select broadcast_id from chat_broadcast where broadcast_id = '">>,BroadcastId, <<"';">>]).

%% remove users from chat_broadcast_user table
%%
%%
%% &param Users and BroadcastId
%% @return update the broadcast users
remove_broadcast_users(LServer, User, BroadcastId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"Delete From chat_broadcast_users  WHERE broadcast_id = '">>, BroadcastId, <<"' and users = '">>, User, <<"' ;">>]).

%% get broadcast users from chat_broadcast_user table
%%
%%
%% &param  Broadcastid
%% @return list
get_broadcast_users(LServer,BroadcastId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select users from chat_broadcast_users where broadcast_id = '">>,BroadcastId, <<"';">>]).

%% get offline messages from spool table
%%
%%
%% &param  LUser
%% @return list
get_offline_msg(LServer,LUser) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select  chat_type, xml, message_id from spool where username = '">>,LUser, <<"' and (chat_type = 'chat' or chat_type = 'normal') and status = 0 ;">>]).

%% update offline messages status from spool table
%%
%% &param MessageID
%% &param  LUser
%% @return list
update_offline_status(LServer,MsgId,LUser) ->
  ejabberd_sql:sql_query(LServer,
    [<<"update  spool set status =1  where username = '">>,LUser, <<"' and message_id = '">>,MsgId, <<"';">>]).

%% get who are all blocked me
%%
%%
%% &param  userid
%% @return list
get_blockedlist(LServer,User) ->
  Value = list_to_binary(binary_to_list(User) ++ "@" ++ binary_to_list(LServer)),
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT E.username  as users from privacy_list E JOIN privacy_list_data S ON E.id = S.id and S.value = '">>,Value, <<"';">>]).

%% get broadcast details from chat_broadcast_user and broadcast tables
%%
%%
%% &param  LUser
%% @return list
get_my_all_broadcast_details(LServer,LUser) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select A.broadcast_name,A.broadcast_id, A.created_at ,IFNULL(GROUP_CONCAT( B.users ),'')  from chat_broadcast as A ,chat_broadcast_users as B where A.broadcast_admin = '">>,LUser, <<"' and A.broadcast_id = B.broadcast_id GROUP BY A.id ORDER BY A.id;">>]).

%% check the user blocked or not
%%
%%
%% &param  userid
%% @return list

check_blockedlist(LServer,FUser, TUser) ->
  Value = list_to_binary(binary_to_list(TUser) ++ "@" ++ binary_to_list(LServer)),
  ejabberd_sql:sql_query(LServer,
  [<<"SELECT E.t from privacy_list_data E JOIN privacy_list S ON E.id = S.id and E.value = '">>,Value, <<"' and  S.username = '">>,FUser, <<"';">>]).

%% check the user blocked or not
%%
%%
%% &param  userid
%% @return list
delete_spool(LServer,User) ->
  ejabberd_sql:sql_query(LServer,
    [<<"delete from spool where username ='">>,User, <<"';">>]).

%% update broadcast name when admin updates
%%
%%
%% &param  BroadcastId BroadcastName
%% @return list

update_broadcast_name(LServer, User, BroadcastId, BroadcastName) ->
  ejabberd_sql:sql_query(LServer,
    [<<"UPDATE  chat_broadcast SET  broadcast_name =  '">>,BroadcastName, <<"' WHERE  broadcast_id ='">>,BroadcastId, <<"' and broadcast_admin ='">>,User, <<"';">>]).

%% Delete broadcast id from chat_broadcast table
%%
%% &param Users , BroadcastId
%% @return

delete_broadcast_id_from_broadcast(LServer, BroadcastId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"delete from chat_broadcast where broadcast_id= '">>,BroadcastId, <<"';">>]).

%% Delete broadcast users from chat_broadcast_users table
%%
%% &param Users , BroadcastId
%% @return

delete_broadcast_users_from_broadcast_users(LServer, BroadcastId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"delete from chat_broadcast_users where broadcast_id= '">>,BroadcastId, <<"';">>]).

%% get all group id of user
%%
%%
%% &param  LUser
%% @return list

%%get_my_all_group_ids(LServer,LUser) ->
%%  ejabberd_sql:sql_query(LServer,
%%    [<<"select DISTINCT node.host,node.created_at from pubsub_node as node, pubsub_state as state where state.jid = '">>,LUser, <<"' and state.nodeid=node.nodeid and state.subscriptions != ''">>]).

get_my_all_group_ids(LServer,LUser) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select channel,created_at,affiliation from mix_pam where username = '">>,LUser, <<"'">>]).

%%get_my_all_group_ids(LServer,LUser) ->
%%  ejabberd_sql:sql_query(LServer,
%%    [<<"select DISTINCT node.host,node.created_at from pubsub_node as node, pubsub_state as state where state.jid = '">>,LUser, <<"' and state.nodeid=node.nodeid and state.subscriptions != ''">>]).

get_my_all_group_id_rosters(LServer,LUser) ->
  ejabberd_sql:sql_query(LServer,
[<<"SELECT DISTINCT E.username FROM mix_pam E JOIN mix_pam S ON E.channel = S.channel where S.username = '">>,LUser, <<"';">>]).

%% get group profile details
%%
%%
%% &param  LUser
%% @return list

get_group_profile(LServer,LUser,GroupId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select DISTINCT  mp.channel,mp.created_at,vcard.vcard, mp.affiliation, mp.id from mix_pam as mp join  vcard as vcard on vcard.username =  mp.channel where mp.channel = '">>,GroupId,<<"'  and mp.username = '">>,LUser, <<"'">>]).

%% get all group id of user
%%
%%
%% &param  LUser
%% @return list

get_my_all_group_id(LServer,LUser) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select DISTINCT mp.channel,mp.created_at,vcard.vcard,mp.affiliation, mp.id, mp.is_block  from mix_pam as mp join vcard as vcard on vcard.username =  mp.channel  where mp.username = '">>,LUser, <<"'">>]).

%% get all group id of user
%%
%%
%% &param  LUser
%% @return list

get_last_message_id(#jid{luser = FUser,lserver = FServer},#jid{luser = ToUser,lserver = _TServer}) ->
  ejabberd_sql:sql_query(FServer,
    [<<"select message_id from chat_recent WHERE from_user = '">>, FUser, <<"' AND to_user = '">>, ToUser, <<"');">>]).


%% Update user profile using Jid
%%
%%
%% &param Jid & profile details
%% @return Update

create_user_ifuserexit(LServer, From, Nickname, Image, MobileNumber, Status, Email) ->
  case user_exit(LServer, From) of
    {selected,[<<"username">>],[]} ->
      ejabberd_sql:sql_query(
        LServer,
        [<<"insert into chat_users (username,name,image,mobile_number,status_msg,email) values ('">>,From, <<"','">>,ejabberd_sql:escape(Nickname), <<"','">>,Image, <<"','">>,MobileNumber, <<"','">>,ejabberd_sql:escape(Status), <<"','">>,Email, <<"') ;">>]);
    {selected,[<<"username">>],[_]} ->
      ejabberd_sql:sql_query(
        LServer,
        [<<"update chat_users set name = '">>,ejabberd_sql:escape(Nickname), <<"', image = '">>,Image, <<"', mobile_number = '">>,MobileNumber, <<"', status_msg = '">>,ejabberd_sql:escape(Status), <<"', email = '">>,Email, <<"' where username='">>,From,<<"';">>])
    end.

%% Check user is exist or not
%%
%%
%% &param Jid
%% @return List

user_exit(LServer, From) ->

  ejabberd_sql:sql_query(
    LServer,
    [<<"select username from chat_users where username='">>,From,<<"';">>]).
%% Mute user notification
%%
%%
%% &param  LUser
%% @return list

mute_user_notification(LServer,LUser,Status) ->
  ejabberd_sql:sql_query(LServer,
    [<<"UPDATE  chat_users SET  notification =  '">>,Status, <<"' WHERE  username ='">>,LUser, <<"' ;">>]).

update_to_normal_user(LServer,GroupId,ParticipantJid) ->
  ejabberd_sql:sql_query(LServer,
    [<<"UPDATE  mix_pam  SET  affiliation =  'n' WHERE channel = '">>,GroupId, <<"' and username = '">>,ParticipantJid, <<"' ;">>]).

delete_group_user(LServer,GroupId,User) ->
  ejabberd_sql:sql_query(
              LServer,
              [<<"delete  from mix_pam  where  channel ='">>,GroupId,<<"' and username='">>,User,<<"';">>]),
ejabberd_sql:sql_query(LServer,
    [<<"Delete from chat_recent WHERE  from_user = '">>,GroupId, <<"' and to_user = '">>,User, <<"' ;">>]).

delete_group(LServer,GroupId) ->
  ejabberd_sql:sql_query(
            LServer,[<<"delete  from mix_pam  where channel ='">>,GroupId,<<"' and is_delete= '0';">>]),
  ejabberd_sql:sql_query(
            LServer,[<<"Delete from chat_recent WHERE  from_user = '">>,GroupId, <<"';">>]).

%% Update last seen activities hide or not
%%
%%
%% &param Jid
%% @return List

set_last_t(#jid{luser = User,lserver = Server}, Seenstatus) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"update last set status =  '">>,Seenstatus, <<"' where username='">>,User,<<"';">>]).

%% Update online activities
%%
%%
%% &param Jid
%% @return List

set_last_o( User,Server, Onlinestatus) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"update last set presence =  '">>,Onlinestatus, <<"' where username='">>,User,<<"';">>]).

%% Update web password
%%
%%
%% &param Jid
%% @return List

set_web_password(#jid{luser = User,lserver = Server}, Password) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"update users set ws_password =  '">>,Password, <<"' where username='">>,User,<<"';">>]).
%% clear the messages between users
%%
%%
%% &param Jid
%% @return List

%% clear the messages between users
%%
%%
%% &param Jid
%% @return List

clear_message(#jid{luser = User,lserver = Server}, ToUser, Favourite, Delete_Type, MsgId) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"delete from spool WHERE to_user = '">>, ToUser, <<"' and username = '">>, User, <<"' ;">>]),
  if Delete_Type =:= <<"1">> ->
    if Favourite =:= <<"0">> ->
      ejabberd_sql:sql_query(Server,
        [<<"update chat_recent set  txt = '', message_type = '', status  = 4, unread =  0 WHERE from_user ='">>, ToUser, <<"' and to_user = '">>, User, <<"' and message_id = '">>, MsgId, <<"';">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 2, deleted_by = '' where   ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and deleted_status = 1 and deleted_by != '">>, User, <<"' ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"DELETE f FROM message_favourite as f join message_status on message_status.message_id = f.message_id  WHERE (from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"') ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 1, deleted_by = '">>, User, <<"' where  ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and message_notification != 1 and deleted_status = 0 ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"UPDATE chat_media_files SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (from_user ='">>, ToUser, <<"' and to_users like '">>,<<"%">>,User,<<"%">>, <<"' ) ;">>]);
    true ->
      ejabberd_sql:sql_query(Server,
        [<<"update chat_recent set  txt = '', message_type = '', status  = 4,unread =  0 WHERE favourite_status = 0 and from_user ='">>, ToUser, <<"' and to_user = '">>, User, <<"' and message_id = '">>, MsgId, <<"';">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 2, deleted_by = '' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and favourite_status = 0 and deleted_status =1 and deleted_by != '">>, User, <<"' ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 1, deleted_by = '">>, User, <<"' where  ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and favourite_status = 0  and message_notification != 1 and deleted_status = 0 ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"UPDATE chat_media_files cm LEFT JOIN message_status ms ON cm.message_id = ms.message_id SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (cm.from_user ='">>, ToUser, <<"' and cm.to_users like '">>,<<"%">>,User,<<"%">>, <<"' and ms.favourite_status = 0) ;">>])
    end;
  true ->
    if Favourite =:= <<"0">> ->
      ejabberd_sql:sql_query(Server,
        [<<"delete from chat_recent  WHERE from_user ='">>, ToUser, <<"' and to_user = '">>, User, <<"' and message_id = '">>, MsgId, <<"';">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 2, deleted_by = '' where  ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and deleted_status =1 and deleted_by != '">>, User, <<"' ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"DELETE f FROM message_favourite as f join message_status on message_status.message_id = f.message_id  WHERE (from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"');">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 1, deleted_by = '">>, User, <<"' where  ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and message_notification != 1 and deleted_status = 0 ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"UPDATE chat_media_files SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (from_user ='">>, ToUser, <<"' and to_users like '">>,<<"%">>,User,<<"%">>, <<"' ) ;">>]);
    true ->
      ejabberd_sql:sql_query(Server,
        [<<"delete from chat_recent  WHERE favourite_status = 0 and from_user ='">>, ToUser, <<"' and to_user = '">>, User, <<"' and message_id = '">>, MsgId, <<"';">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 2, deleted_by = '' where  ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and favourite_status =0 and deleted_status =1 and deleted_by != '">>, User, <<"' ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set  deleted_status = 1, deleted_by = '">>, User, <<"' where  ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and favourite_status =0  and message_notification != 1 and deleted_status =0 ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"UPDATE chat_media_files cm LEFT JOIN message_status ms ON cm.message_id = ms.message_id SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (cm.from_user ='">>, ToUser, <<"' and cm.to_users like '">>,<<"%">>,User,<<"%">>, <<"' and ms.favourite_status = 0) ;">>])
    end
  end.

clear_message(#jid{luser = User,lserver = Server}, ToUser, Favourite, Delete_Type) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"delete from spool WHERE to_user = '">>, ToUser, <<"' and username = '">>, User, <<"' ;">>]),
  if Delete_Type =:= <<"1">> ->
    if Favourite =:= <<"0">> ->
      ejabberd_sql:sql_query(Server,
        [<<"update chat_recent set created_at = NOW(), txt = '', message_type = '', status  = 4, unread =  0 WHERE from_user ='">>, ToUser, <<"' and to_user = '">>, User, <<"';">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 2, deleted_by = '' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and deleted_status = 1 and deleted_by != '">>, User, <<"' ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"DELETE f FROM message_favourite as f join message_status on message_status.message_id = f.message_id  WHERE (from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"');">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 1, deleted_by = '">>, User, <<"' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and message_notification != 1 and deleted_status = 0 ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"UPDATE chat_media_files SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (from_user ='">>, ToUser, <<"' and to_users like '">>,<<"%">>,User,<<"%">>, <<"' ) ;">>]);
    true ->
      ejabberd_sql:sql_query(Server,
        [<<"update chat_recent set created_at = NOW(), txt = '', message_type = '', status  = 4,unread =  0 WHERE favourite_status = 0 and from_user ='">>, ToUser, <<"' and to_user = '">>, User, <<"';">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 2, deleted_by = '' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and favourite_status = 0 and deleted_status =1 and deleted_by != '">>, User, <<"' ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 1, deleted_by = '">>, User, <<"' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and favourite_status = 0  and message_notification != 1 and deleted_status = 0 ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"UPDATE chat_media_files cm LEFT JOIN message_status ms ON cm.message_id = ms.message_id SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (cm.from_user ='">>, ToUser, <<"' and cm.to_users like '">>,<<"%">>,User,<<"%">>, <<"' and ms.favourite_status = 0) ;">>])
    end;
  true ->
    if Favourite =:= <<"0">> ->
      ejabberd_sql:sql_query(Server,
        [<<"delete from chat_recent  WHERE from_user ='">>, ToUser, <<"' and to_user = '">>, User, <<"';">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 2, deleted_by = '' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and deleted_status =1 and deleted_by != '">>, User, <<"' ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"DELETE f FROM message_favourite as f join message_status on message_status.message_id = f.message_id  WHERE (from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"');">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 1, deleted_by = '">>, User, <<"' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and message_notification != 1 and deleted_status = 0 ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"UPDATE chat_media_files SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (from_user ='">>, ToUser, <<"' and to_users like '">>,<<"%">>,User,<<"%">>, <<"' ) ;">>]);
    true ->
      ejabberd_sql:sql_query(Server,
        [<<"delete from chat_recent  WHERE favourite_status = 0 and from_user ='">>, ToUser, <<"' and to_user = '">>, User, <<"';">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set deleted_status = 2, deleted_by = '' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and favourite_status =0 and deleted_status =1 and deleted_by != '">>, User, <<"' ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"update message_status set  deleted_status = 1, deleted_by = '">>, User, <<"' where ((from_user ='">>, ToUser, <<"' and  to_user='">>, User, <<"') or  (to_user ='">>, ToUser, <<"' and  from_user='">>, User, <<"')) and favourite_status =0  and message_notification != 1 and deleted_status =0 ;">>]),
      ejabberd_sql:sql_query(Server,
        [<<"UPDATE chat_media_files cm LEFT JOIN message_status ms ON cm.message_id = ms.message_id SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (cm.from_user ='">>, ToUser, <<"' and cm.to_users like '">>,<<"%">>,User,<<"%">>, <<"' and ms.favourite_status = 0) ;">>])
    end
  end.

updategroup_clear(#jid{luser = User,lserver = Server}, ToUser)->
  ejabberd_sql:sql_query(
    Server,
    [<<"update message_status set deleted_status =0, deleted_by='0' where id = (select * from (select min(id) as id from message_status WHERE from_user = '">>, ToUser, <<"' AND to_user = '">>, User, <<"'  and message_type='0' and chat_type='normal')tmp);">>]).

%% clear the messages between users
%%
%%
%% &param Jid
%% @return List

clear_broadcast_message(#jid{lserver = Server}, ToUser, _Favourite) ->
  ejabberd_sql:sql_query(Server,
    [<<"update chat_recent set created_at = NOW(), txt = '', status  = 4 WHERE from_user ='">>, ToUser, <<"';">>]),

  ejabberd_sql:sql_query(
    Server,
    [<<"update message_status set broadcast_msg_id = '', broadcast_id = '' where broadcast_id = '">>, ToUser, <<"';">>]).
%% delete broadcast
delete_broadcast_message(Server,ToUser) ->
  ejabberd_sql:sql_query(Server,
    [<<"delete from chat_recent  WHERE from_user ='">>, ToUser, <<"';">>]),

  ejabberd_sql:sql_query(
    Server,
    [<<"delete from message_status where broadcast_id = '">>, ToUser, <<"' and  message_id = 0;">>]).

%% clear all the messages between users
%%
%%
%% &param Jid
%% @return List

get_message_rowid(User, Server, MsgId)->
  ejabberd_sql:sql_query(
    Server,
    [<<"select max(id) as id from message_status where (from_user ='">>, User, <<"' or  to_user='">>, User, <<"') and  message_id = '">>, MsgId, <<"' ;">>]).

get_message_rowid(User, Server)->
  ejabberd_sql:sql_query(
    Server,
    [<<"select max(id) as id from message_status where (from_user ='">>, User, <<"' or  to_user='">>, User, <<"');">>]).

clear_all(#jid{luser = User,lserver = Server},Delete_Type) ->

  if Delete_Type =:= <<"1">> ->
    ejabberd_sql:sql_query(Server,
      [<<"update chat_recent set created_at = NOW(), txt = '', status  = 4, unread = 0 WHERE to_user = '">>, User, <<"';">>]),
    ejabberd_sql:sql_query(Server,
      [<<"update message_status set  deleted_by = '',deleted_status = 2 where (from_user ='">>, User, <<"' or  to_user='">>, User, <<"')  and deleted_by != '">>, User, <<"' and deleted_status =1 and chat_type = 'chat';">>]),
    ejabberd_sql:sql_query(Server,
      [<<"update message_status set  deleted_by = '">>, User, <<"',deleted_status = 1 where (from_user ='">>, User, <<"' or  to_user='">>, User, <<"')  and deleted_status =0 AND message_notification != '1'  ;">>]),
    ejabberd_sql:sql_query(Server,
      [<<"delete from spool WHERE username = '">>, User, <<"';">>]),
    ejabberd_sql:sql_query(Server,
      [<<"DELETE FROM message_favourite WHERE favourite_user='">>,User,<<"';">>]),
    ejabberd_sql:sql_query(Server,
      [<<"UPDATE chat_media_files SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (to_users like '">>,<<"%">>,User,<<"%">>, <<"' ) ;">>]);
  true ->
    ejabberd_sql:sql_query(Server,
      [<<"delete from chat_recent WHERE to_user = '">>, User, <<"' and chat_type='chat';">>]),
    ejabberd_sql:sql_query(Server,
      [<<"update chat_recent set txt = '', status  = 4, unread = 0 WHERE to_user = '">>, User, <<"';">>]),
    ejabberd_sql:sql_query(Server,
      [<<"update message_status set  deleted_by = '',deleted_status = 2 where (from_user ='">>, User, <<"' or  to_user='">>, User, <<"')  and deleted_by != '">>, User, <<"'  and deleted_status =1 and chat_type = 'chat';">>]),
    ejabberd_sql:sql_query(Server,
      [<<"update message_status set  deleted_by = '">>, User, <<"', deleted_status = 1 where (from_user ='">>, User, <<"' or  to_user='">>, User, <<"') and deleted_status =0 AND message_notification != '1' ;">>]),
    ejabberd_sql:sql_query(Server,
      [<<"delete from spool WHERE username = '">>, User, <<"';">>]),
    ejabberd_sql:sql_query(Server,
      [<<"UPDATE chat_media_files SET to_users = TRIM(BOTH ',' FROM REPLACE(CONCAT(',', to_users), ',">>, User, <<"', '')) where (to_users like '">>,<<"%">>,User,<<"%">>, <<"' ) ;">>])
  end.

%% Delete Particular messages
%%
%%
%% &param Jid
%% @return List

delete_message(#jid{luser = User,lserver = Server}, MessageId) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"delete from spool WHERE username = '">>, User, <<"' and  message_id = '">>, MessageId, <<"';">>]),

  ejabberd_sql:sql_query(
    Server,
    [<<"update message_status set  deleted_by = '', deleted_status = 2 where message_id = '">>, MessageId, <<"' and deleted_by != '">>, User, <<"' and deleted_status =1 and chat_type = 'chat' ;">>]),

  ejabberd_sql:sql_query(
    Server,
    [<<"update message_status set  deleted_by = '">>, User, <<"', deleted_status = 1  where message_id = '">>, MessageId, <<"' and deleted_status =0 and chat_type = 'chat';">>]),

  ejabberd_sql:sql_query(
    Server,
    [<<"update message_status set  deleted_by = '">>, User, <<"', deleted_status = 1  where to_user='">>, User, <<"' and message_id = '">>, MessageId, <<"'  and deleted_status =0 and chat_type = 'normal' ;">>]),

  ejabberd_sql:sql_query(
    Server,
    [<<"DELETE FROM message_favourite WHERE favourite_user='">>,User,<<"' AND message_id='">>,MessageId,<<"';">>]).

%% get recent messages for user
%%
%%
%% &param Jid
%% @return List

recent_exist(Server,User, MessageId) ->

  ejabberd_sql:sql_query(
    Server,
    [<<"select id, from_user,message_from from chat_recent where  to_user='">>, User, <<"' and message_id = '">>, MessageId, <<"';">>]).

delete_recentchat(#jid{luser = FUser,lserver = FServer},#jid{luser = ToUser} ) ->
  ejabberd_sql:sql_query(
    FServer,
    [<<"update chat_recent set status  = 4, txt = ''  WHERE from_user = '">>, FUser, <<"' AND to_user = '">>, ToUser, <<"';">>]).

delete_message_recentchat(FServer, User, ToUser) ->
  ejabberd_sql:sql_query(
    FServer,
    [<<"update chat_recent set message_type = '', status  = 4, txt = ''  WHERE  from_user ='">>,User, <<"' and to_user ='">>,ToUser, <<"';">>]).

%% Delete Particular messages
%%
%%
%% &param Jid
%% @return List

update_last_recent_message(#jid{luser = FUser,lserver = FServer},#jid{luser = ToUser} ) ->
  ejabberd_sql:sql_query(
    FServer,
    [<<"update chat_recent set message_id = (select message_id from message_status WHERE ((from_user = '">>, FUser, <<"' AND to_user = '">>, ToUser, <<"') OR (from_user = '">>, ToUser, <<"' AND to_user = '">>, FUser, <<"')) and deleted_status!=2 and deleted_by!='">>, FUser, <<"' order by created_at DESC LIMIT 1) WHERE from_user = '">>, FUser, <<"' AND to_user = '">>, ToUser, <<"';">>]).

get_last_messages(#jid{luser = FUser,lserver = FServer},#jid{luser = ToUser}, _BroadcastId) ->
  ejabberd_sql:sql_query(
    FServer,
    [<<"select from_user, to_user, message_id,message_type,chat_type,status, recall_status, message_time, from_notification,to_notification,message_notification,created_at,topic_id,IFNULL(json_unquote(meta_data),'') as meta from message_status USE INDEX (from_user,to_user) WHERE ((from_user = '">>, FUser, <<"' AND to_user = '">>, ToUser, <<"') OR (from_user = '">>, ToUser, <<"' AND to_user = '">>, FUser, <<"'))  and deleted_by!='">>, FUser, <<"' and deleted_status!=2 order by id DESC LIMIT 1;">>]).

%% Get user alternate resource
%%
%%
%% &param Jid
%% @return List

get_user_resource(#jid{luser = User,lserver = Server, lresource = Resource}) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"select resource from chat_users where  username='">>,User,<<"' and resource != '">>,Resource,<<"';">>]).


%% Get user alternate resource
%%
%%
%% &param Jid
%% @return List

get_group_message_status(#jid{luser = FUser,lserver = Server, lresource = _Resource}, MessageID) ->
  ejabberd_sql:sql_query(Server,
    [<<"select to_user, status ,received_at, seen_at from message_status where to_user != '">>,FUser,<<"' and message_id = '">>,MessageID,<<"';">>]).


%% remove offline temp storage
%%
%%
%% &param Jid
%% &param MessageId
%% @return List

remove_offline(Server,  MessageId) ->

  ejabberd_sql:sql_query(
    Server,
    [<<"DELETE from spool where message_id='">>,MessageId,<<"';">>]).

remove_offline(Server, MessageId, LResource) ->

  ejabberd_sql:sql_query(
    Server,
    [<<"DELETE from spool where message_id='">>,MessageId,<<"' and (device_id = '">>,LResource,<<"' or device_id = '') ;">>]).

update_offline(Server, MessageId, LResource) ->

  ejabberd_sql:sql_query(
  Server,
  [<<"update spool set admin_delivered = 1 where message_id='">>,MessageId,<<"' and (device_id = '">>,LResource,<<"' or device_id = '') ;">>]).


%% Update message seen status
%%
%%
%% &param Jid
%% &param MessageId
%% &param SeenStatus
%% @return List

update_seen(#jid{luser = User,lserver = Server},TUser, MessageId, GroupId) ->

  % ejabberd_sql:sql_query(
  %   Server,
  %   [<<"update message_status set status = 2, seen_at = NOW() where  to_user='">>,User,<<"' and from_user = (SELECT from_user FROM (select from_user from message_status where message_id='">>,MessageId,<<"' limit 1) s);">>]),

  ejabberd_sql:sql_query(
    Server,
    [<<"update message_status set status =  2, seen_at = NOW() where  to_user='">>,User,<<"' and message_id='">>,MessageId,<<"' and  status != 2 ;">>]),

  % ejabberd_sql:sql_query(
  %   Server,
  %   [<<"update chat_recent set unread =  0 where message_id='">>,MessageId,<<"' and to_user ='">>,User,<<"';">>]),

  if GroupId =/= <<"">> ->
    ToJid = jid:make(TUser, Server, <<>>),
    case catch get_groupmessage_status(ToJid, MessageId) of
        {selected, _, []} ->
          Status = <<"2">>;
        {selected, _, [[GroupStatus]]} ->
          Status = GroupStatus;
        _ ->
          Status = <<"2">>
      end;
  true ->
    Status = <<"2">>
  end,

  ejabberd_sql:sql_query(
    Server,
    [<<"update chat_recent set status = '">>,Status,<<"', unread =  0 where  to_user ='">>,TUser,<<"' and message_id='">>,MessageId,<<"' and status < 2 ;">>]).

%% Update message delivery status
%%
%%
%% &param Jid
%% &param MessageId
%% &param SeenStatus
%% @return List

update_delivery(#jid{luser = User,lserver = Server}, TUser,  MessageId, GroupId) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"update message_status set status =  1, received_at = NOW() where   to_user='">>,User,<<"' and message_id='">>,MessageId,<<"' and status = 0;">>]),

  if GroupId =/= <<"">> ->
    ToJid = jid:make(TUser, Server, <<>>),
    case catch get_groupmessage_status(ToJid, MessageId) of
        {selected, _, []} ->
          Status = <<"1">>;
        {selected, _, [[GroupStatus]]} ->
          Status = GroupStatus;
        _ ->
          Status = <<"1">>
      end;
  true ->
    Status = <<"1">>
  end,

  ejabberd_sql:sql_query(
    Server,
    [<<"update chat_recent set status = '">>,Status,<<"' where  (from_user = '">>,TUser,<<"' or  to_user ='">>,TUser,<<"') and message_id='">>,MessageId,<<"' and status = 0;">>]).

update_delivery_offline(Server, User) ->

  FromNotification = list_to_binary(binary_to_list(User) ++ "@" ++ binary_to_list(Server)),
  ejabberd_sql:sql_query(
    Server,
    [<<"update message_status set status =  1, received_at = NOW() where  to_user='">>,User,<<"' and status = 0;">>]).
% ejabberd_sql:sql_query(
%     Server,
%     [<<"update message_status set status =  1, received_at = NOW() where status = 0 and chat_type = 'normal' and from_notification != '">>,FromNotification,<<"' and to_user='">>,User,<<"';">>]).

clear_call_log(#jid{luser = User,lserver = Server},RoomId) ->
  if RoomId =:= <<"">> ->
    ejabberd_sql:sql_query(
    Server,
    [<<"update client_call_logs  set deleted_at = now() where created_user='">>,User,<<"';">>]);
    true ->
  ejabberd_sql:sql_query(
    Server,
    [<<"update client_call_logs  set deleted_at = now() where created_user='">>,User,<<"' and id <= (select id from ( (select id from client_call_logs where  created_user='">>,User,<<"' and room_id = '">>, RoomId , <<"' order by id DESC LIMIT 1)) as c); ;">>])
  end.

clear_particular_call_log(#jid{luser = User,lserver = Server},RoomId) ->
  ejabberd_sql:sql_query(
    Server,
    [<<"update client_call_logs  set deleted_at = now() where room_id = '">>, RoomId , <<"' and created_user='">>,User,<<"';">>]).

%% Update message recall status
%%
%%
%% &param Jid
%% &param MessageId
%% &param RecallStatus
%% @return List

update_recall(#jid{luser = _User,lserver = Server}, MessageId) ->
  Range = binary:split(MessageId, <<",">>, [global]),
  lists:foreach(fun(N) ->
  ejabberd_sql:sql_query(
      Server,
      [<<"delete FROM spool  where message_id='">>,N,<<"';">>]),
    ejabberd_sql:sql_query(
      Server,
      [<<"update message_status set recall_status =  1 where message_id='">>,N,<<"';">>]),
    ejabberd_sql:sql_query(
      Server,
    [<<"DELETE FROM message_favourite WHERE message_id = '">>,N,<<"';">>]),
    ejabberd_sql:sql_query(
      Server,
      [<<"update chat_recent set recall_status  =  1 where message_id='">>,N,<<"';">>])
  end, Range).

%% insert message status
%%
%%
%% &param Jid
%% &param MessageId
%% &param ToJid
%% @return List

insert_status(#jid{luser = User}, #jid{luser = ToUser,lserver = ToServer}, MessageId,MessageType, Topicid, MetaData, ChatType,SentFrom,BlockUser, Msg, MsgTime, EditmsgId) ->
  if EditmsgId =:= <<"">> ->
    EditMsgId = MessageId;
  true ->
    EditMsgId = EditmsgId
end,
  if EditMsgId =:= MessageId ->
    if Topicid =:= <<"">> ->
      ejabberd_sql:sql_query( ToServer, [<<"insert into message_status (from_user,to_user,status, recent,message_id, edit_message_id, message_type,  topic_id, meta_data, txt,chat_type,from_notification,blocked,message_time,to_notification,message_notification,received_at,seen_at) values
        ('">>, User, <<"', '">>, ToUser, <<"', 0,1, '">>, MessageId, <<"',  '">>, EditMsgId, <<"', '">>, MessageType, <<"', '">>, Topicid, <<"', '">>, MetaData, <<"', '">>, Msg, <<"', '">>, ChatType, <<"','">>, SentFrom, <<"', '">>, BlockUser, <<"', '">>, MsgTime, <<"',
        '',0,'0000-00-00 00:00:00','0000-00-00 00:00:00') ON DUPLICATE KEY UPDATE to_user = '">>, ToUser, <<"',message_id = '">>, MessageId, <<"' ;">>]);
      true ->
      ejabberd_sql:sql_query( ToServer, [<<"insert into message_status (from_user,to_user,status, recent,message_id, edit_message_id, message_type, topic_id, meta_data, txt,chat_type,from_notification,blocked,message_time,to_notification,message_notification,received_at,seen_at) values
      ('">>, User, <<"', '">>, ToUser, <<"', 0,1, '">>, MessageId, <<"',  '">>, EditMsgId, <<"', '">>, MessageType, <<"', '">>, Topicid, <<"', '">>, MetaData, <<"', '">>, Msg, <<"', '">>, ChatType, <<"','">>, SentFrom, <<"', '">>, BlockUser, <<"', '">>, MsgTime, <<"',
      '',0,'0000-00-00 00:00:00','0000-00-00 00:00:00') ON DUPLICATE KEY UPDATE to_user = '">>, ToUser, <<"',message_id = '">>, MessageId, <<"' ;">>])
      end;
    true ->
  ejabberd_sql:sql_query(ToServer, [<<"delete from spool where username = '">>,ToUser, <<"' and message_id ='">>,MessageId, <<"';">>]),
  ejabberd_sql:sql_query( ToServer, [<<"update  message_status set edit_status = 1, status = 0,  edit_message_id = '">>, EditMsgId , <<"', txt = '">>, Msg , <<"' where message_id = '">>, MessageId, <<"' ;">>])
  end,
  ejabberd_sql:sql_query( ToServer, [<<"insert into chat_message_edit_history (from_user,to_user, message_id, edit_message_id, chat_type, msg) values ('">>, User, <<"', '">>, ToUser,  <<"', '">>, MessageId, <<"', '">>, EditMsgId, <<"', 'chat', '">>, Msg, <<"');">>]).

msg_exit(LServer,MsgId)->
  ejabberd_sql:sql_query(
    LServer,
    [<<"select txt from message_status where message_id='">>,MsgId,<<"' limit 1;">>]).

insert_status(#jid{luser = User,lserver = Server}, ToUser ) ->
  ejabberd_sql:sql_query(
  Server, [<<"insert into message_status (from_user,to_user,status,recent,message_id, edit_message_id, chat_type,to_notification,message_notification,received_at,seen_at,meta_data) values
  ('">>, ToUser, <<"','">>, User, <<"',0,">>,<<"1,">>,<<"0,'">>,<<"0,'">>,<<"chat">>, <<"','',0,'0000-00-00 00:00:00','0000-00-00 00:00:00'),'{}';">>]),
  ejabberd_sql:sql_query(
  Server, [<<"insert into chat_recent (from_user, to_user,  message_id, edit_message_id, message_from, txt, chat_type, message_type,  notification_to,message_time,meta_data) values
  ('">>, ToUser, <<"','">>, User, <<"','0','">>,<<"','0','">>, User, <<"','0','broadcast','notification','">>,  User, <<"',0),'{}';">>]).

insert_recent_chat_topic(LServer,SUser,BarePeer,MessageId,MessageFrom,Body,SType,MessageType, Topicid, MetaData, Notification_to,Unread,FlatTimeStamp) ->
if Topicid =:= <<"">> ->
ejabberd_sql:sql_query(
LServer, [<<"insert into chat_recent_topic (from_user, to_user,  message_id, message_from, txt, chat_type, message_type,  unread, notification_to,message_time) values
('">>, SUser, <<"','">>, BarePeer, <<"','">>,  MessageId, <<"','">>, MessageFrom, <<"','">>, Body, <<"','">>,  SType, <<"','">>,  MessageType, <<"','">>,  Unread, <<"','">>,  Notification_to, <<"','">>,  FlatTimeStamp, <<"');">>]);
true ->
ejabberd_sql:sql_query(
LServer, [<<"insert into chat_recent_topic (from_user, to_user,  message_id, message_from, txt, chat_type, message_type, topic_id, meta_data, unread, notification_to,message_time) values
('">>, SUser, <<"','">>, BarePeer, <<"','">>,  MessageId, <<"','">>, MessageFrom, <<"','">>, Body, <<"','">>,  SType, <<"','">>,  MessageType, <<"', '">>,  Topicid, <<"', '">>,  MetaData, <<"','">>,  Unread, <<"','">>,  Notification_to, <<"','">>,  FlatTimeStamp, <<"');">>])
end.

update_recent_chat_topic(LServer,SUser,BarePeer,MessageId,MessageFrom,Body,SType,MessageType, Topicid, MetaData, Unread,FlatTimeStamp) ->

  if Unread =:= <<"1">> ->
    ejabberd_sql:sql_query(LServer,
      [<<"UPDATE  chat_recent_topic SET meta_data =  '">>,MetaData, <<"', message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',chat_type =  '">>,SType, <<"',message_type =  '">>,MessageType,  <<"',meta_data =  '">>,MetaData,  <<"', unread =  unread + 1 ,status =  '0', recall_status = '0', message_time =  '">>,FlatTimeStamp,  <<"', created_at = NOW() WHERE  from_user ='">>,SUser, <<"' and to_user ='">>,BarePeer, <<"' and topic_id ='">>,Topicid, <<"';">>]);
    true ->
      ejabberd_sql:sql_query(LServer,
      [<<"UPDATE  chat_recent_topic SET  meta_data =  '">>,MetaData, <<"', message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',chat_type =  '">>,SType, <<"',message_type =  '">>,MessageType, <<"',meta_data =  '">>,MetaData,  <<"',unread =  '">>,Unread, <<"'  ,status =  '0', recall_status = '0', created_at = NOW(),  message_time =  '">>,FlatTimeStamp,  <<"' WHERE  from_user ='">>,SUser, <<"' and to_user ='">>,BarePeer, <<"' and topic_id ='">>,Topicid, <<"';">>])
end.

insert_recent_chat(LServer,SUser,BarePeer,MessageId,MessageFrom,Body,SType,MessageType, Topicid, MetaData, Notification_to,Unread,FlatTimeStamp) ->

ejabberd_sql:sql_query(
LServer, [<<"insert into chat_recent (from_user, to_user,  message_id, message_from, txt, chat_type, message_type, topic_id, meta_data, unread, notification_to,message_time) values
('">>, SUser, <<"','">>, BarePeer, <<"','">>,  MessageId, <<"','">>, MessageFrom, <<"','">>, Body, <<"','">>,  SType, <<"','">>,  MessageType, <<"', '">>,  Topicid, <<"', '">>,  MetaData, <<"','">>,  Unread, <<"','">>,  Notification_to, <<"','">>,  FlatTimeStamp, <<"');">>]).

update_recent_chat(LServer,SUser,BarePeer,MessageId,MessageFrom,Body,SType,MessageType, Topicid, MetaData, Unread, EditmsgId , FlatTimeStamp) ->
  if EditmsgId =:= <<"">> ->
    EditMsgId = MessageId;
  true ->
    EditMsgId = EditmsgId
end,
  if EditMsgId =:= MessageId ->
    if Unread =:= <<"1">> ->
      ejabberd_sql:sql_query(LServer,
        [<<"UPDATE  chat_recent SET  topic_id =  '">>,Topicid, <<"', meta_data =  '">>,MetaData, <<"', message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',chat_type =  '">>,SType, <<"',message_type =  '">>,MessageType,  <<"', unread =  unread + 1 ,status =  '0', recall_status = '0', message_time =  '">>,FlatTimeStamp,  <<"', created_at = NOW() WHERE  from_user ='">>,SUser, <<"' and to_user ='">>,BarePeer, <<"';">>]);
      true ->
        ejabberd_sql:sql_query(LServer,
        [<<"UPDATE  chat_recent SET  topic_id =  '">>,Topicid, <<"',meta_data =  '">>,MetaData, <<"',message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',chat_type =  '">>,SType, <<"',message_type =  '">>,MessageType, <<"', unread =  '">>,Unread, <<"'  ,status =  '0', recall_status = '0', created_at = NOW(),  message_time =  '">>,FlatTimeStamp,  <<"' WHERE  from_user ='">>,SUser, <<"' and to_user ='">>,BarePeer, <<"';">>])
end;
true ->

        ejabberd_sql:sql_query(LServer,
        [<<"UPDATE  chat_recent SET  message_id =  '">>,MessageId, <<"', status = 0, txt =  '">>,Body, <<"' WHERE  message_id ='">>,MessageId, <<"';">>])

end.

update_recent_chat_broadcast(LServer,Fromuser,_Touser,MessageId,MessageFrom,Body,SType,MessageType,BroadcastId,BroadcastmsgId,Unread) ->
ejabberd_sql:sql_query(LServer,
    [<<"UPDATE  chat_recent SET  message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',chat_type =  '">>,SType, <<"',message_type =  '">>,MessageType, <<"',unread =  '">>,Unread, <<"',status =  '0', recall_status = '0', created_at = NOW() WHERE  from_user ='">>,Fromuser, <<"' and broadcast_msg_id !='">>,BroadcastmsgId, <<"';">>]).

update_deleted_recent_chat(LServer,SUser,BarePeer,MessageId,_MessageFrom,Body,SType,MessageType,Notification_to,Status, Recall_status,Created_at,MessageFrom,Topicid, MetaData, MessageTime) ->
  ejabberd_sql:sql_query(LServer,
    [<<"UPDATE  chat_recent SET  topic_id =  '">>,Topicid, <<"', meta_data =  '">>,MetaData, <<"', message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',message_time =  '">>,MessageTime, <<"',chat_type =  '">>,SType, <<"',status =  '">>,Status, <<"',recall_status ='">>,Recall_status, <<"',message_type =  '">>,MessageType, <<"',notification_to =  '">>,Notification_to, <<"',created_at =  '">>,Created_at, <<"' WHERE  from_user ='">>,SUser, <<"' and to_user ='">>,BarePeer, <<"';">>]).

update_deleted_grouprecent_chat(LServer,SUser,BarePeer,MessageId,_MessageFrom,Body,SType,MessageType,Notification_to,Status, Recall_status,Created_at, ToUser,Topicid, MetaData, MessageTime) ->
  User = get_user_from_string_jid(SUser),
  ejabberd_sql:sql_query(LServer,
    [<<"UPDATE  chat_recent SET  topic_id =  '">>,Topicid, <<"', meta_data =  '">>,MetaData, <<"', message_id =  '">>,MessageId, <<"',message_from =  '">>,User, <<"',txt =  '">>,Body, <<"',message_time =  '">>,MessageTime, <<"',chat_type =  '">>,SType, <<"',status =  '">>,Status, <<"',recall_status ='">>,Recall_status, <<"',message_type =  '">>,MessageType,  <<"',notification_to =  '">>,Notification_to, <<"',created_at =  '">>,Created_at, <<"' WHERE  from_user ='">>,BarePeer, <<"' and to_user ='">>,ToUser, <<"';">>]).

update_recent_groupchat(LServer,SUser,BarePeer,MessageId,MessageFrom,Body,SType,MessageType,NotifyUser,Unread,Currenttime) ->
  if Unread =:= <<"1">> ->
    ejabberd_sql:sql_query(LServer,
      [<<"UPDATE  chat_recent SET message_time =  '">>,Currenttime, <<"', message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',chat_type =  '">>,SType, <<"',message_type =  '">>,MessageType, <<"', notification_to =  '">>,NotifyUser, <<"', unread = unread + 1 ,status =  '0', recall_status = '0', created_at = NOW() WHERE from_user = '">>,SUser, <<"' and to_user ='">>,BarePeer, <<"' ;">>]);
  Unread =:= <<"2">> ->
    ejabberd_sql:sql_query(LServer,
      [<<"UPDATE  chat_recent SET  message_time =  '">>,Currenttime, <<"',message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',chat_type =  '">>,SType, <<"',message_type =  '">>,MessageType, <<"', notification_to =  '">>,NotifyUser, <<"' , status =  '0', recall_status = '0', created_at = NOW() WHERE from_user = '">>,SUser, <<"' and to_user ='">>,BarePeer, <<"' ;">>]);
  true ->
    ejabberd_sql:sql_query(LServer,
      [<<"UPDATE  chat_recent SET  message_time =  '">>,Currenttime, <<"',message_id =  '">>,MessageId, <<"',message_from =  '">>,MessageFrom, <<"',txt =  '">>,Body, <<"',chat_type =  '">>,SType, <<"',message_type =  '">>,MessageType, <<"', notification_to =  '">>,NotifyUser, <<"' , unread =  '">>,Unread, <<"' ,status =  '0', recall_status = '0', created_at = NOW()  WHERE from_user = '">>,SUser, <<"' and to_user ='">>,BarePeer, <<"';">>])

  end.

get_recent_chat_web(#jid{luser = FUser, lserver = FServer}) ->

  ejabberd_sql:sql_query(
    FServer,
    [<<"SELECT topic_id, from_user, to_user,  message_id, message_from, txt, chat_type, message_type, IFNULL(json_unquote(meta_data),'') as meta, notification_to, status, recall_status, message_time, created_at, unread, mute_status, archive_status, updated_at from chat_recent where to_user = '">>, FUser, <<"' order by created_at asc ;">>]).

get_recent_chat_topic(#jid{luser = FUser, lserver = FServer},  TopicTime, Topicid, Limit) ->
  if Topicid =:= <<"">> ->
  if TopicTime =:= <<"">> ->
    ejabberd_sql:sql_query(
    FServer,
    [<<"SELECT topic_id, from_user, to_user,  message_id, message_from, txt, chat_type, message_type, IFNULL(json_unquote(meta_data),'') as meta, notification_to, status, recall_status, message_time, created_at, unread, mute_status, archive_status, updated_at from chat_recent_topic where to_user = '">>, FUser, <<"' order by message_time desc LIMIT 0,">>,Limit,<<";">>]);
  true->

        ejabberd_sql:sql_query(FServer,
          [<<"SELECT topic_id, from_user, to_user,  message_id, message_from, txt, chat_type, message_type, IFNULL(json_unquote(meta_data),'') as meta, notification_to, status, recall_status, message_time, created_at, unread, mute_status, archive_status, updated_at from chat_recent_topic WHERE   to_user = '">>, FUser, <<"' and message_time < ">>, TopicTime, <<" ORDER BY message_time DESC LIMIT 0,">>,Limit,<<";">>])

  end;
  true ->
  if TopicTime =:= <<"">> ->
    ejabberd_sql:sql_query(
  FServer,
  [<<"SELECT topic_id, from_user, to_user,  message_id, message_from, txt, chat_type, message_type, IFNULL(json_unquote(meta_data),'') as meta, notification_to, status, recall_status, message_time, created_at, unread, mute_status, archive_status, updated_at from chat_recent_topic where to_user = '">>, FUser, <<"' and topic_id = '">>, Topicid, <<"' order by message_time desc LIMIT 0,">>,Limit,<<";">>]);
true->

      ejabberd_sql:sql_query(FServer,
        [<<"SELECT topic_id, from_user, to_user,  message_id, message_from, txt, chat_type, message_type, IFNULL(json_unquote(meta_data),'') as meta, notification_to, status, recall_status, message_time, created_at, unread, mute_status, archive_status, updated_at from chat_recent_topic  WHERE  to_user = '">>, FUser, <<"' and topic_id = '">>, Topicid, <<"' and message_time < ">>, TopicTime, <<" ORDER BY message_time DESC LIMIT 0,">>,Limit,<<";">>])

end
  end.

poll_vote_update(LServer,PollId,VoterUserId,Status,PollOptionId,ToUser,FlatTimeStamp,VoteId) ->
VoterId = get_user_from_string_jid(VoterUserId),
if Status =:= <<"poll_add">> ->
  ejabberd_sql:sql_query(
  LServer, [<<"insert into chat_poll_votes (poll_id, answer_id,  username, voted_time, vote_id) values ('">>, PollId, <<"','">>, PollOptionId, <<"','">>,  VoterId, <<"','">>, FlatTimeStamp, <<"','">>, VoteId, <<"');">>]);
  true ->
    ejabberd_sql:sql_query(
  LServer,
    [<<"update chat_poll_votes SET is_deleted = 1 WHERE poll_id='">>,PollId,<<"' AND answer_id='">>,PollOptionId,<<"' AND username='">>,VoterId,<<"'AND vote_id='">>,VoteId,<<"';">>])
end.

get_meta_chat_web(#jid{luser = FUser, lserver = FServer}, Topicid, RowId, Limit) ->
  if RowId =:= <<"">> ->
  ejabberd_sql:sql_query(
    FServer,
    [<<"SELECT * FROM (SELECT id, from_user, to_user, message_type, txt, message_id, edit_message_id, status, recall_status, message_time, IFNULL(json_unquote(meta_data),'') as meta  from message_status USE INDEX (id, from_user, to_user) where (from_user = '">>, FUser, <<"' or to_user = '">>, FUser, <<"') and deleted_status != '2' AND blocked != '">>, FUser, <<"' and topic_id = '">>, Topicid, <<"' group by from_user,to_user order by id desc) tmp limit 0,">>,Limit,<<";">>]);
  true ->
    ejabberd_sql:sql_query(
  FServer,
  [<<"SELECT * FROM (SELECT id, from_user, to_user, message_type, txt,  message_id, edit_message_id, status, recall_status, message_time, IFNULL(json_unquote(meta_data),'') as meta  from message_status USE INDEX (id, from_user, to_user) where  id >= ">>, RowId, <<"  and  (from_user = '">>, FUser, <<"' or  to_user = '">>, FUser, <<"')  and deleted_status != '2' AND blocked != '">>, FUser, <<"'  and topic_id = '">>, Topicid, <<"' group by from_user,to_user order by id desc) tmp limit 0,">>,Limit,<<";">>])
end.

get_single_chat_messages(#jid{luser = FUser, lserver = FServer}, TUser, Position, _MsgId, Limit, RowId, SendSeen, Topicid) ->

  if SendSeen =:= <<"1">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"UPDATE  chat_recent SET unread = 0 where from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"';">>]);
  true ->
    ok
  end,
  if Topicid =:= <<"">> ->
  if RowId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT id, from_user, message_type, txt, created_at, message_id, edit_message_id,  status, recall_status, favourite_status, favourite_by, message_time, topic_id, edit_status,  IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (from_user,to_user) WHERE (((from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) and ( deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND blocked != '">>, FUser, <<"') ) ORDER BY id DESC LIMIT 0,">>,Limit,<<";">>]);
    true->
      if Position =:= <<"up">> ->
        ejabberd_sql:sql_query(FServer,
          [<<" SELECT id, from_user, message_type, txt, created_at, message_id, edit_message_id, status, recall_status, favourite_status, favourite_by, message_time,  topic_id, edit_status, IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE  id < ">>, RowId, <<" AND ((from_user= '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"'))  AND deleted_by != '">>, FUser, <<"' and deleted_status != '2'  AND blocked != '">>, FUser, <<"' ORDER BY id DESC LIMIT 0,">>,Limit,<<";">>]);
        Position =:= <<"down">> ->
          ejabberd_sql:sql_query(FServer,
            [<<" SELECT id, from_user,message_type, txt, created_at, message_id,  edit_message_id, status, recall_status, favourite_status, favourite_by,  message_time, topic_id, edit_status,  IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE id >= ">>, RowId, <<"  AND ((from_user= '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"'))  AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND blocked != '">>, FUser, <<"' ORDER BY id ASC LIMIT 0,">>,Limit,<<";">>]);
        true->
          ejabberd_sql:sql_query(FServer,
            [<<" SELECT id, from_user,  message_type, txt, created_at, message_id, edit_message_id, status, recall_status, favourite_status, favourite_by,  message_time, topic_id, edit_status, IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE id >= ">>, RowId, <<"  AND ((from_user= '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"'))  AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND blocked != '">>, FUser, <<"' ORDER BY id ASC LIMIT 0,">>,Limit,<<";">>])
      end
  end;
  true ->
  if RowId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT id, from_user, message_type, txt, created_at, message_id, edit_message_id, status, recall_status, favourite_status, favourite_by, message_time,  topic_id,edit_status,  IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (from_user,to_user) WHERE (((from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) and (deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND blocked != '">>, FUser, <<"' and topic_id = '">>, Topicid, <<"')) ORDER BY id DESC LIMIT 0,">>,Limit,<<";">>]);
    true->
      if Position =:= <<"up">> ->
        ejabberd_sql:sql_query(FServer,
          [<<" SELECT id, from_user, message_type,  txt, created_at, message_id, edit_message_id, status, recall_status, favourite_status, favourite_by, message_time, topic_id, edit_status, IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE  id < ">>, RowId, <<"  AND ((from_user= '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"'))  AND deleted_by != '">>, FUser, <<"'  and deleted_status != '2' AND blocked != '">>, FUser, <<"' and topic_id = '">>, Topicid, <<"' ORDER BY id DESC LIMIT 0,">>,Limit,<<";">>]);
        Position =:= <<"down">> ->
          ejabberd_sql:sql_query(FServer,
            [<<" SELECT id, from_user, message_type, txt, created_at, message_id, edit_message_id, status, recall_status, favourite_status, favourite_by,  message_time,  topic_id, edit_status, IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE id >= ">>, RowId, <<" AND ((from_user= '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"'))  AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND blocked != '">>, FUser, <<"'  and topic_id = '">>, Topicid, <<"' ORDER BY id ASC LIMIT 0,">>,Limit,<<";">>]);
        true->
          ejabberd_sql:sql_query(FServer,
            [<<" SELECT id, from_user, message_type, txt, created_at, message_id, edit_message_id, status, recall_status, favourite_status, favourite_by,  message_time,  topic_id, edit_status, IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE id >= ">>, RowId, <<"  AND ((from_user= '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND blocked != '">>, FUser, <<"' and topic_id = '">>, Topicid, <<"' ORDER BY id ASC LIMIT 0,">>,Limit,<<";">>])
      end
  end
end.

get_single_chat_media_messages(#jid{luser = FUser, lserver = FServer}, TUser, MsgId, Topicid) ->
if Topicid =:= <<"">> ->
  if MsgId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT txt, message_id, edit_message_id, message_time,  topic_id,IFNULL(json_unquote(meta_data),'') as meta  FROM  message_status USE INDEX (from_user,to_user)  WHERE ((from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) and message_type !='text' AND chat_type = 'chat' AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND recall_status =0 AND blocked != '">>, FUser, <<"' GROUP BY message_id ORDER BY created_at DESC LIMIT 0,3;">>]);
    true->
      case catch get_id(FServer, MsgId) of
        {selected, _, []} ->
          ok;
        {selected, _, [[Id]]} ->
          ejabberd_sql:sql_query(FServer,
        [<<"SELECT txt, message_id, edit_message_id,  message_time, topic_id, IFNULL(json_unquote(meta_data),'') as meta  FROM  message_status  USE INDEX (from_user,to_user) WHERE  id < '">>, Id, <<"' and ((from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) AND message_type !='text' AND chat_type = 'chat' AND deleted_by != '">>, FUser, <<"' and deleted_status != '2'  AND recall_status =0 AND blocked != '">>, FUser, <<"'   GROUP BY message_id ORDER BY created_at DESC LIMIT 0,10;">>]);
        _ ->
        ok
      end
      end;
true ->
  if MsgId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT txt, message_id, edit_message_id, message_time,  topic_id,IFNULL(json_unquote(meta_data),'') as meta  FROM  message_status USE INDEX (from_user,to_user)  WHERE ((from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) and message_type !='text' AND chat_type = 'chat' AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND recall_status =0 AND blocked != '">>, FUser, <<"' and topic_id = '">>, Topicid, <<"' GROUP BY message_id ORDER BY created_at DESC LIMIT 0,3;">>]);
    true->
      case catch get_id(FServer, MsgId) of
        {selected, _, []} ->
          ok;
        {selected, _, [[Id]]} ->
          ejabberd_sql:sql_query(FServer,
        [<<"SELECT txt, message_id, edit_message_id,  message_time, topic_id, IFNULL(json_unquote(meta_data),'') as meta  FROM  message_status  USE INDEX (from_user,to_user) WHERE id < '">>, Id, <<"' and ((from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) AND message_type !='text' AND chat_type = 'chat' AND deleted_by != '">>, FUser, <<"' and deleted_status != '2'  AND recall_status =0 AND blocked != '">>, FUser, <<"'and topic_id = '">>, Topicid, <<"'  GROUP BY message_id ORDER BY created_at DESC LIMIT 0,10;">>]);
        _ ->
        ok
      end
      end
end.

get_id(FServer,MsgId)->
  ejabberd_sql:sql_query(FServer,
  [<<"select id from message_status where message_id ='">>, MsgId, <<"' limit 1;">>]).

get_broadcast_chat_media_messages(#jid{luser = FUser, lserver = FServer}, TUser, MsgId) ->
  if MsgId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT txt, message_id, message_time FROM  message_status WHERE ((message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND recall_status =0 ) and  (from_user = '">>, FUser, <<"' AND broadcast_id = '">>, TUser, <<"')  GROUP BY broadcast_msg_id ORDER BY id DESC LIMIT 0,3;">>]);
    true->
      ejabberd_sql:sql_query(FServer,
        [<<"SELECT txt, message_id, message_time FROM  message_status WHERE ((message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND recall_status =0 ) and (from_user = '">>, FUser, <<"' AND broadcast_id = '">>, TUser, <<"') and id < (select id from message_status where message_id ='">>, MsgId, <<"' limit 1)  GROUP BY broadcast_msg_id ORDER BY id DESC LIMIT 0,10;">>])
  end.

get_group_chat_messages(#jid{luser = FUser, lserver = FServer}, TUser,  Position, _MsgId, Limit, RowId, SendSeen) ->
  if SendSeen =:= <<"1">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"UPDATE chat_recent SET unread = 0 where from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"';">>]);
  true ->
    ok
  end,

  if RowId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT id, from_user, txt, created_at as time, message_id, edit_message_id, status, from_notification, message_type, recall_status, favourite_status, favourite_by, to_notification, message_notification, message_time, edit_status, IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (from_user,to_user) WHERE from_user = '">>, TUser, <<"' and to_user='">>, FUser, <<"' AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' ORDER BY id DESC  LIMIT 0, ">>,Limit,<<";">>]);
    true->
      if Position =:= <<"up">> ->
        % Old Query
        % [<<"SELECT id, from_user, txt, created_at as time, message_id, status, from_notification,message_type,recall_status,favourite_status,to_notification,message_notification, message_time FROM message_status  WHERE from_user = '">>, TUser, <<"' and to_user='">>, FUser, <<"' and deleted_status != '2' AND deleted_by != '">>, FUser, <<"'  AND id < (select id from message_status where to_user = '">>,FUser,<<"' and message_id='">>, MsgId, <<"') GROUP BY message_id ORDER BY id DESC  LIMIT 0, ">>,Limit,<<";">>]);
        ejabberd_sql:sql_query(FServer,
          [<<"SELECT id, from_user, txt, created_at as time, message_id,edit_message_id,  status, from_notification, message_type, recall_status, favourite_status, favourite_by, to_notification, message_notification, message_time,edit_status,  IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE  id < ">>, RowId, <<"  and from_user = '">>, TUser, <<"' and to_user='">>, FUser, <<"'  AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' ORDER BY id DESC  LIMIT 0, ">>,Limit,<<";">>]);
        Position =:= <<"down">> ->
          ejabberd_sql:sql_query(FServer,
            [<<"SELECT id, from_user, txt, created_at as time, message_id, edit_message_id, status, from_notification, message_type, recall_status, favourite_status, favourite_by, to_notification, message_notification, message_time, edit_status, IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE id >= ">>, RowId, <<" and from_user = '">>, TUser, <<"' and to_user='">>, FUser, <<"'  AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' ORDER BY id ASC LIMIT 0,">>,Limit,<<";">>]);
        true->
          ejabberd_sql:sql_query(FServer,
            [<<"SELECT id, from_user, txt, created_at as time, message_id, edit_message_id, status, from_notification, message_type, recall_status, favourite_status, favourite_by, to_notification, message_notification, message_time , edit_status, IFNULL(json_unquote(meta_data),'') as meta FROM message_status USE INDEX (id) WHERE id >= ">>, RowId, <<" and from_user = '">>, TUser, <<"' and to_user='">>, FUser, <<"'  AND deleted_by != '">>, FUser, <<"'  and deleted_status != '2' ORDER BY id ASC LIMIT 0,">>,Limit,<<";">>])
      end
  end.

get_group_chat_media_messages(#jid{luser = FUser, lserver = FServer},_GroupJidFull, GroupJid, MsgId) ->
  if MsgId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT  txt, message_id, edit_message_id, message_time FROM  message_status USE INDEX (from_user,to_user) WHERE from_user='">>, GroupJid, <<"' and to_user = '">>, FUser, <<"' AND (message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND deleted_by != '">>, FUser, <<"'  and deleted_status != '2' AND recall_status=0 GROUP BY message_id   ORDER BY created_at DESC  LIMIT 0,3;">>]);
    true->
      ejabberd_sql:sql_query(FServer,
        [<<"SELECT  txt, message_id,edit_message_id,  message_time FROM  message_status USE INDEX (id) WHERE  from_user='">>, GroupJid, <<"' and to_user = '">>, FUser, <<"' AND (message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio')  AND deleted_by != '">>, FUser, <<"'  and deleted_status != '2'  AND recall_status=0 AND id < (select id from message_status where to_user = '">>,FUser,<<"' and  message_id='">>, MsgId, <<"') GROUP BY message_id   ORDER BY created_at DESC  LIMIT 0,10;">>])

  end.

get_single_chat_fullmedia_messages(#jid{luser = FUser, lserver = FServer}, TUser, MsgId, Position) ->
  if Position =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT txt, message_id, edit_message_id, message_time FROM  message_status USE INDEX (from_user,to_user) WHERE ((from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) and (message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND  recall_status =0 AND blocked != '">>, FUser, <<"'  and id >= (select id from message_status where message_id ='">>, MsgId, <<"')) GROUP BY message_id ORDER BY created_at ASC LIMIT 0,10;">>]);
    true->
      ejabberd_sql:sql_query(FServer,
      [<<"SELECT txt, message_id, edit_message_id, message_time FROM  message_status USE INDEX (id) WHERE ((from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"') OR (from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"')) and (message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND deleted_by != '">>, FUser, <<"' and deleted_status != '2' AND  recall_status =0 AND blocked != '">>, FUser, <<"'  and id <= (select id from message_status where message_id ='">>, MsgId, <<"')) GROUP BY message_id ORDER BY created_at ASC LIMIT 0,10;">>])
  end.

get_group_chat_fullmedia_messages(#jid{luser = FUser, lserver = FServer},_GroupJidFull, GroupJid, MsgId,Position) ->
  if Position =:= <<"">> ->
      ejabberd_sql:sql_query(FServer,
        [<<"SELECT  txt, message_id, edit_message_id, message_time FROM  message_status USE INDEX (id) WHERE from_user='">>, GroupJid, <<"' and to_user = '">>, FUser, <<"'  AND (message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND deleted_by != '">>, FUser, <<"' and deleted_status != '2'  AND recall_status=0  AND id >= (select id from message_status where to_user = '">>,FUser,<<"' and  message_id='">>, MsgId, <<"') GROUP BY message_id   ORDER BY time ASC  LIMIT 0,10;">>]);
    true->
      ejabberd_sql:sql_query(FServer,
        [<<"SELECT  txt, message_id, edit_message_id, message_time FROM  message_status USE INDEX (id) WHERE from_user='">>, GroupJid, <<"' and to_user = '">>, FUser, <<"'  AND (message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND deleted_by != '">>, FUser, <<"' and deleted_status != '2'  AND recall_status=0  AND id <= (select id from message_status where to_user = '">>,FUser,<<"' and  message_id='">>, MsgId, <<"') GROUP BY message_id   ORDER BY time ASC  LIMIT 0,10;">>])

  end.

get_broadcast_chat_fullmedia_messages(#jid{luser = FUser, lserver = FServer}, TUser, MsgId,Position) ->
  if Position =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
        [<<"SELECT txt,message_id, message_time FROM  message_status WHERE ((message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND recall_status =0 ) and (from_user = '">>, FUser, <<"' AND broadcast_id = '">>, TUser, <<"') and id >= (select id from message_status where message_id ='">>, MsgId, <<"')  GROUP BY broadcast_msg_id ORDER BY id ASC LIMIT 0,10;">>]);
    true->
      ejabberd_sql:sql_query(FServer,
        [<<"SELECT txt,message_id, message_time FROM  message_status WHERE ((message_type ='image' OR message_type ='video' OR message_type ='file' OR message_type ='audio') AND recall_status =0 ) and (from_user = '">>, FUser, <<"' AND broadcast_id = '">>, TUser, <<"') and id <= (select id from message_status where message_id ='">>, MsgId, <<"')  GROUP BY broadcast_msg_id ORDER BY id ASC LIMIT 0,10;">>])
  end.

get_message_status(#jid{lserver = FServer}, Msgid) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT message_id, status, to_user,updated_at, recall_status FROM message_status WHERE message_id ='">>,Msgid,<<"';">>]).

get_groupmessage_status(#jid{luser = FUser, lserver = FServer}, Msgid) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT MIN(status) as status FROM message_status WHERE to_user !='">>,FUser,<<"' and  message_id ='">>,Msgid,<<"' group by message_id;">>]).

message_status(FServer, Msgid, Fuser) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT MIN(status) as status FROM message_status WHERE to_user != '">>,Fuser,<<"' and  message_id ='">>,Msgid,<<"' group by message_id;">>]).

message_status_new(FServer, Msgid, Fuser) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT status, id FROM message_status WHERE to_user != '">>,Fuser,<<"' and  message_id ='">>,Msgid,<<"' order by status asc limit 1;">>]).

get_broadcast_chat_messages(#jid{luser = FUser, lserver = FServer}, TUser,  Position, MsgId, Limit) ->
  ejabberd_sql:sql_query(FServer,
    [<<"UPDATE  chat_recent SET unread = 0 where from_user = '">>, TUser, <<"' AND to_user = '">>, FUser, <<"';">>]),

  if MsgId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT from_user, txt, created_at, message_id, status,recall_status, favourite_status, favourite_by,  message_time  FROM message_status  WHERE ((deleted_status != '2' AND deleted_by != '">>, FUser, <<"') and (from_user = '">>, FUser, <<"' AND broadcast_id = '">>, TUser, <<"'))  GROUP BY broadcast_msg_id ORDER BY id DESC LIMIT 0, ">>,Limit,<<";">>]);
    true->
      if Position =:= <<"up">> ->
        ejabberd_sql:sql_query(FServer,
          [<<"SELECT from_user, txt, created_at, message_id, status,recall_status, favourite_status, favourite_by,  message_time FROM  message_status  WHERE ((deleted_status != '2' AND deleted_by != '">>, FUser, <<"') and (from_user = '">>, FUser, <<"' AND broadcast_id = '">>, TUser, <<"')   and id < (select min(id) from message_status where broadcast_msg_id='">>, MsgId, <<"' )) GROUP BY broadcast_msg_id ORDER BY  id DESC LIMIT 0, ">>,Limit,<<";">>]);
        Position =:= <<"down">> ->
          ejabberd_sql:sql_query(FServer,
            [<<"SELECT from_user, txt, created_at, message_id, status,recall_status, favourite_status, favourite_by,  message_time FROM  message_status  WHERE ((deleted_status != '2' AND deleted_by != '">>, FUser, <<"') and (from_user = '">>, FUser, <<"' AND broadcast_id = '">>, TUser, <<"')  and id >= (select max(id) from message_status where broadcast_msg_id='">>, MsgId, <<"'))  GROUP BY broadcast_msg_id ORDER BY  id DESC LIMIT 0,">>,Limit,<<";">>]);

        true->
          ejabberd_sql:sql_query(FServer,
            [<<"SELECT from_user, txt, created_at, message_id, status,recall_status, favourite_status, favourite_by,  message_time FROM  message_status  WHERE ((deleted_status != '2' AND deleted_by != '">>, FUser, <<"') and (from_user = '">>, FUser, <<"' AND broadcast_id = '">>, TUser, <<"')  and id >= (select max(id) from message_status where broadcast_msg_id='">>, MsgId, <<"')) GROUP BY broadcast_msg_id ORDER BY id ASC LIMIT 0, ">>,Limit,<<";">>])
      end
  end.

check_group_exists(FServer, GroupId) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT from_user FROM message_status WHERE from_user  = '">>,GroupId,<<"';">>]).

group_notify_message(#jid{luser = AUser, lserver = AServer},#jid{luser = FUser}, TUser, Groupid,NotifyId, RequestType, Msgid)->
  % MsgId = get_iq_message_id(8),

  Timestamp = fly_add_timestamp:now_to_microseconds(erlang:now()),

  FlatTimeStamp = lists:flatten(io_lib:format("~p", [Timestamp])),

  Currenttime = list_to_binary(FlatTimeStamp),

  FromNotification = list_to_binary(binary_to_list(AUser) ++ "@" ++ binary_to_list(AServer)),

  ejabberd_sql:sql_query(
    AServer,
    [<<"insert into message_status (from_notification,to_notification,from_user,to_user,message_id, edit_message_id, message_notification,chat_type, message_time,txt,received_at,seen_at,meta_data) values
     ('">>,FromNotification, <<"','">>,TUser, <<"','">>,Groupid, <<"','">>,FUser,  <<"','">>,Msgid, <<"','">>,Msgid, <<"','">>,NotifyId, <<"','normal','">>,Currenttime, <<"','','0000-00-00 00:00:00','0000-00-00 00:00:00','{}') ON DUPLICATE KEY UPDATE to_user = '">>, FUser, <<"',message_id = '">>, Msgid, <<"' ;">>]),

  case catch update_recent_groupchat(AServer,Groupid,FUser,Msgid,AUser,NotifyId,<<"normal">>,<<"notification">>,TUser,<<"2">>,Currenttime) of
    {updated,1} ->
      ok;
    {updated,0}->
      insert_recent_chat(AServer,Groupid,FUser,Msgid,AUser,NotifyId,<<"normal">>,<<"notification">>,<<"">>, <<"{}">>,TUser,<<"0">>,Currenttime);
    _ ->
      ok
  end.

set_favourite_message(#jid{luser = FUser, lserver = FServer},  MessageId, Chat_Type)->

  ejabberd_sql:sql_query(
    FServer,
    [<<"insert into message_favourite (favourite_user,message_id) values ( '">>, FUser, <<"' , '">>, MessageId, <<"');">>]),

  if Chat_Type == <<"normal">> ->
  ejabberd_sql:sql_query(
    FServer,
    [<<"update message_status set   favourite_status = 1, favourite_by = '">>, FUser, <<"'  where message_id = '">>, MessageId, <<"'  and chat_type = 'normal' and to_user='">>, FUser, <<"' and favourite_status =0;">>]);
    true ->
    ejabberd_sql:sql_query(
    FServer,
    [<<"update message_status set  favourite_status = 2, favourite_by = '' where  message_id = '">>, MessageId, <<"' and favourite_status =1 and chat_type = 'chat'  and favourite_by != '">>, FUser, <<"' ;">>]),
    ejabberd_sql:sql_query(
    FServer,
    [<<"update message_status set  favourite_status = 1, favourite_by = '">>, FUser, <<"'  where message_id = '">>, MessageId, <<"'  and chat_type = 'chat' and favourite_status =0;">>])
  end.

update_favourite_message(#jid{luser = FUser, lserver = FServer}, MessageId, Chat_Type)->
  ejabberd_sql:sql_query(
    FServer,
    [<<"DELETE FROM message_favourite WHERE favourite_user='">>,FUser,<<"' AND message_id='">>,MessageId,<<"';">>]),

    if Chat_Type == <<"normal">> ->
    ejabberd_sql:sql_query(
      FServer,
      [<<"update message_status set  favourite_status = 0, favourite_by = 0 where message_id = '">>, MessageId, <<"' and favourite_status =1 and favourite_by = '">>, FUser, <<"' ;">>]);

    true ->

    case catch update_favorite(FServer,MessageId,FUser) of
      {updated,1} ->
        ok;
      {updated,0}->
        ejabberd_sql:sql_query(
          FServer,
          [<<"update message_status set  favourite_status = 1, favourite_by = to_user where message_id = '">>, MessageId, <<"'  and favourite_status =2 and chat_type = 'chat'  and from_user = '">>, FUser, <<"' ;">>]),
        ejabberd_sql:sql_query(
          FServer,
          [<<"update message_status set  favourite_status = 1, favourite_by = from_user where message_id = '">>, MessageId, <<"' and favourite_status =2 and chat_type = 'chat'  and from_user != '">>, FUser, <<"' ;">>]);
      _ ->
        ok
    end
  end.

  update_favorite(FServer,MessageId,FUser) ->
    ejabberd_sql:sql_query(
      FServer,
      [<<"update message_status set  favourite_status = 0, favourite_by = 0 where message_id = '">>, MessageId, <<"'  and favourite_status =1 and chat_type = 'chat'  and favourite_by = '">>, FUser, <<"' ;">>]).

get_favourite_message(#jid{luser = FUser, lserver = FServer}, _TUser, ChatType)->
  if ChatType =:= <<"chat">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT from_user, txt, t3.created_at as time, t3.message_id, status,t3.from_notification, to_user,chat_type,t4.created_at as favourite_date,t4.message_id, t3.message_time, t3.id as row_id, t3.edit_status FROM  message_status AS t3 JOIN message_favourite AS t4 ON (t3.message_id = t4.message_id ) WHERE t4.favourite_user = '">>, FUser, <<"' GROUP BY t3.message_id ORDER BY favourite_date ASC;">>]);
    ChatType =:= <<"normal">> ->

      ejabberd_sql:sql_query(FServer,
        [<<"SELECT from_user, txt, t3.created_at as time, t3.message_id, t3.status, t3.from_notification,to_user,t3.chat_type,t5.created_at as favourite_date,t5.message_id, t3.message_time, t3.id as row_id, t3.edit_status  FROM message_status AS t3 JOIN message_favourite AS t5 ON (t3.message_id = t5.message_id) WHERE t3.to_user='">>, FUser, <<"' AND t3.message_type != '0' and t5.favourite_user  = '">>, FUser, <<"' GROUP BY t3.message_id  ORDER BY favourite_date ASC">>]);
    true ->
      ejabberd_sql:sql_query(FServer,
        [<<"SELECT from_user, txt, t3.created_at as time, t3.message_id, status,t3.from_notification, to_user,chat_type,t4.created_at as favourite_date,t4.message_id, t3.message_time, t3.id as row_id, t3.edit_status FROM message_status AS t3 JOIN message_favourite AS t4 ON (t3.message_id = t4.message_id  ) WHERE  t4.favourite_user = '">>, FUser, <<"' GROUP BY t3.message_id  ORDER BY favourite_date ASC;">>])
  end.

get_bot_chat_messages(#jid{luser = FUser, lserver = FServer}, TUser, Position, MsgId) ->
  if MsgId =:= <<"">> ->
    ejabberd_sql:sql_query(FServer,
      [<<"SELECT id, from_user, txt, 'chat' as bot, created_at, message_id, status, recall_status, favourite_status, favourite_by FROM  message_status WHERE ((deleted_status != '2' AND blocked != '">>, FUser, <<"' AND deleted_by != '">>, FUser, <<"') and (from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"')) GROUP BY message_id  ORDER BY id DESC LIMIT 0,20;">>]);
    true->
      if Position =:= <<"up">> ->
        ejabberd_sql:sql_query(FServer,
          [<<"SELECT id, from_user, txt, 'chat' as bot, created_at, message_id, status, recall_status, favourite_status, favourite_by FROM message_status WHERE ((deleted_status != '2' AND blocked != '">>, FUser, <<"' AND deleted_by != '">>, FUser, <<"') and (from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"')) and t3.id < (select id from message_status where message_id='">>, MsgId, <<"') ) GROUP BY message_id  ORDER BY id DESC LIMIT 0,20;">>]);

        Position =:= <<"up">> ->
          ejabberd_sql:sql_query(FServer,
            [<<"SELECT id, from_user, txt, 'chat' as bot, created_at, message_id, status, recall_status, favourite_status, favourite_by FROM message_status WHERE ((deleted_status != '2' AND blocked != '">>, FUser, <<"' AND deleted_by != '">>, FUser, <<"') and (from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"')) and t3.id < (select id from message_status where message_id='">>, MsgId, <<"') ) GROUP BY message_id  ORDER BY id DESC LIMIT 0,20;">>]);

        true->
          ejabberd_sql:sql_query(FServer,
            [<<"SELECT id, from_user, txt, 'chat' as bot, created_at, message_id, status, recall_status, favourite_status, favourite_by FROM message_status WHERE ((deleted_status != '2' AND blocked != '">>, FUser, <<"' AND deleted_by != '">>, FUser, <<"') and (from_user = '">>, FUser, <<"' AND to_user = '">>, TUser, <<"')) and t3.id < (select id from message_status where message_id='">>, MsgId, <<"') ) GROUP BY message_id  ORDER BY id DESC LIMIT 0,20;">>])
      end
  end.

get_message(FServer,MessageId)->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT txt as message FROM message_status WHERE message_id IN ('">>, MessageId, <<"') GROUP BY message_id;">>]).

get_message_from(FServer,MessageId)->
      ejabberd_sql:sql_query(FServer,
        [<<"SELECT IF(from_notification =  '', from_user,from_notification) as fromuse FROM fly_mf_prod.message_status where message_id = '">>, MessageId, <<"' limit 1 ;">>]).

get_roster_nick(LServer,Username,Contact)->
  Jid = make_jid_s(Contact,LServer),
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT nick FROM rosterusers WHERE username='">>,Username,<<"' AND jid='">>,Jid,<<"';">>]).

get_remove_user(LServer,ItemId)->
ejabberd_sql:sql_query(LServer,
    [<<"SELECT username FROM mix_pam WHERE id='">>,ItemId,<<"';">>]).

get_callstatus(LServer,SocketId)->
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT status FROM chat_calls WHERE socket_id='">>,SocketId,<<"';">>]).

get_group_vcard(LServer,LUser) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select vcard, created_at from vcard where username= '">>,LUser,<<"';">>]).

get_offline_message(LServer, LUser, LResource) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select chat_type, xml from spool where username= '">>,LUser,<<"' and device_id = '">>,LResource,<<"' and message_id  != '' and status = 0 and (chat_type = 'chat' or chat_type = 'normal')  order by seq;">>]).

get_single_message(FServer,  MsgId ,_OldMsgId) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT txt, message_id, edit_message_id,  from_user, chat_type, deleted_by, deleted_status, status, from_notification, to_notification, to_user, message_time, message_notification, recall_status, created_at, topic_id,  edit_status, updated_at, IFNULL(json_unquote(meta_data),'') as meta FROM message_status WHERE message_id = '">>, MsgId, <<"' limit 1">>]).

get_reply_message(FServer,  MsgId) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT msg, message_id, edit_message_id, from_user, chat_type, 0 as deleted_by, 0 as deleted_status, 0 as status, '' as from_notification, '' as to_notification, to_user, created_at, '' as message_notification, 0 as recall_status, created_at, '' as topic_id,  0 as edit_status, created_at,  '{}' as meta FROM chat_message_edit_history WHERE edit_message_id = '">>, MsgId, <<"' limit 1">>]).

get_reply_messages(FServer,  MsgId) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT txt, message_id, from_user, chat_type,  to_user, created_at FROM message_status WHERE message_id = '">>, MsgId, <<"' limit 1">>]).

get_broadcast_message(FServer, MsgId ,_OldMsgId) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT txt, broadcast_msg_id, from_user FROM message_status WHERE broadcast_msg_id = '">>, MsgId, <<"' group by broadcast_msg_id">>]).

get_group_message(FServer, MsgId, _OldMsgId) ->
  ejabberd_sql:sql_query(FServer,
    [<<"SELECT  txt, message_id,from_notification,deleted_by,deleted_status, status FROM message_status  WHERE message_id = '">>, MsgId, <<"' limit 1">>]).

delete_favourite_message(FServer, FUser) ->
  ejabberd_sql:sql_query(
    FServer,
    [<<"DELETE FROM message_favourite WHERE favourite_user='">>,FUser,<<"';">>]),
  ejabberd_sql:sql_query(
    FServer,
    [<<"update message_status set favourite_status = 0, favourite_by = 0  where favourite_by ='">>, FUser, <<"';">>]),
  ejabberd_sql:sql_query(
    FServer,
    [<<"update message_status set  favourite_status = 1, favourite_by = to_user where  from_user = '">>, FUser, <<"' and favourite_status =2 and chat_type = 'chat' ;">>]),

  ejabberd_sql:sql_query(
    FServer,
    [<<"update message_status set  favourite_status = 1, favourite_by = from_user where from_user != '">>, FUser, <<"' and favourite_status =2 and chat_type = 'chat';">>]).

get_message(FServer, ChatType ,MsgId) ->

    ejabberd_sql:sql_query(FServer,
      [<<"SELECT txt from message_status WHERE message_id = '">>, MsgId,  <<"' limit 1 ">>]).

%% get team member user jabber id
%%
%%
%% @param  record jid
%% @return List
get_team_jid(#jid{lserver = Server},TeamId,Domain)->
  if(TeamId =/= <<"0">>)->
    ejabberd_sql:sql_query(Server,[<<"select distinct users.username from users inner join vcard_search on users.username = vcard_search.lusername inner join admin_team_members on users.username = admin_team_members.users where vcard_search.lemail LIKE CONCAT('%','">>,Domain,<<"'  ,'%') and admin_team_members.team_id IN(">>, TeamId, <<") ;">>]);
    true ->
      ejabberd_sql:sql_query(Server,[<<"select distinct users.username from users inner join vcard_search on users.username = vcard_search.lusername where vcard_search.lemail LIKE CONCAT('%','">>,Domain,<<"'  ,'%');">>])
  end.

get_user_from_string_jid(Jid) ->
[U | _] = binary:split(Jid,<<"@">>,[global]),
U.

get_device_from_resource(Jid) ->
[_,U] = binary:split(Jid,<<"-">>,[global]),
U.

get_host(Host)->
% Find the position of the first dot
DotIndex = string:str(Host, "."),
% Extract the substring starting from the position after the first dot
NewString = string:substr(Host, DotIndex + 1),
NewString.

jid_to_string(Jid) ->
  #jid{user = User, lserver = Server} = Jid,
  <<User / binary, $@,Server / binary>>.

get_messagestatus(LServer,MessageId)->
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT min(status) as status FROM message_status WHERE message_id='">>,MessageId,<<"';">>]).

get_nick(LServer, Channel) ->
  ejabberd_sql:sql_query(
    LServer,
    ?SQL("select @(nick)s from mix_participant"
    " where channel=%(Channel)s")).

check_blockeduser(LServer,User, Tuser) ->
  Value = list_to_binary(binary_to_list(User) ++ "@" ++ binary_to_list(LServer)),
  ejabberd_sql:sql_query(LServer,
    [<<"SELECT l.username as users from privacy_list_data as d join privacy_list as l on d.id = l.id where  l.username  =  '">>,Tuser, <<"' and d.value =  '">>,Value, <<"';">>]).
%% get broadcast details from chat_broadcast_user and broadcast tables
%%
%%
%% &param  LUser
%% @return list

get_broadcast_details(LServer,LUser,BroadcastId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select A.broadcast_name,A.broadcast_id, A.created_at ,IFNULL(GROUP_CONCAT( B.users ),'')  from chat_broadcast as A ,chat_broadcast_users as B where A.broadcast_admin = '">>,LUser, <<"' and A.broadcast_id = '">>,BroadcastId, <<"' and A.broadcast_id = B.broadcast_id GROUP BY A.id ORDER BY A.id;">>]).

update_chat_media_profile(LServer,Image,Id) ->
  ejabberd_sql:sql_query(LServer,
    [<<"update chat_media_files set file_token = '">>,Image, <<"' where id ='">>,Id, <<"' ;">>]).

get_chat_media_profile(LServer, LUser) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select id from chat_media_files where from_user ='">>,LUser, <<"' and type = 'profile' limit 1;">>]).

get_chat_media_by_messageid(LServer, MessageId) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select to_users from chat_media_files where message_id='">>,MessageId,<<"' limit 1;">>]).

create_profile_chat_media_files(LServer, LUser, Image) ->
  ejabberd_sql:sql_query(LServer,
    [<<"insert into chat_media_files (file_token,from_user,type) values ('">>,Image, <<"','">>,LUser, <<"','profile')  ;">>]).

get_iq_message_id(Len) ->
  Chrs = list_to_tuple("abcdefghijklmnopqrstuvwxyz0123456789"),
  ChrsSize = size(Chrs),
  F = fun(_, R) -> [element(random:uniform(ChrsSize), Chrs) | R] end,
  list_to_binary(lists:foldl(F, "", lists:seq(1, Len))).

get_all_media_conversation(LServer,User) ->
  ejabberd_sql:sql_query(LServer,
    [<<"select id,from_user,to_users,message_id from chat_media_files where  type != 'profile' and (from_user ='">>,User, <<"' or to_users like '">>,<<"%">>,User,<<"%">>, <<"' ) ;">>]).

empty_from_user_to_chat_media(Server,Id) ->
  ejabberd_sql:sql_query(Server,[<<"UPDATE chat_media_files SET from_user='' WHERE id='">>, Id,<<"';">>]).

update_tousers_to_chat_media(Server,ToUsers,Id) ->
  ejabberd_sql:sql_query(Server,[<<"UPDATE chat_media_files SET to_users= '">>, ToUsers,<<"' WHERE id='">>, Id,<<"';">>]).

revoke_media_permission(Server, ToUsers, MessageId) ->
  ejabberd_sql:sql_query(Server,[<<"UPDATE chat_media_files SET to_users= '">>, ToUsers,<<"' WHERE message_id='">>, MessageId,<<"';">>]).

get_all_media_conversation_with_filetoken(Server,FileToken) ->
  ejabberd_sql:sql_query(Server,
    [<<"select id,from_user,to_users,message_id from chat_media_files where file_token = '">>,FileToken, <<"' and message_id != 'null' limit 1 ;">>]).

empty_from_user_to_chat_media_everyone(Server,Id) ->
  ejabberd_sql:sql_query(Server,[<<"UPDATE chat_media_files SET from_user='' , to_users= '' WHERE id='">>, Id,<<"';">>]).

get_all_media_conversation_with_single_chat(Server,Type,ToUser,LUser) ->

  ejabberd_sql:sql_query(Server,
    [<<"select id,from_user,to_users,message_id from chat_media_files where type = '">>,Type, <<"' and message_id != 'null'and to_users  != 'null' and (from_user= '">>,LUser, <<"' and  to_users = '">>,ToUser, <<"') or (from_user= '">>,ToUser, <<"' and  to_users = '">>,LUser, <<"')  ;">>]).

get_all_media_conversation_with_group(Server,Type,GroupId,LUser) ->

  ejabberd_sql:sql_query(Server,
    [<<"select id,from_user,to_users,message_id from chat_media_files where type = '">>,Type, <<"' and group_id= '">>,GroupId, <<"' and (from_user= '">>,LUser, <<"' or  to_users like '">>,<<"%">>,LUser,<<"%">>, <<"') ;">>]).

get_all_media_conversation_with_broadcast(Server,Type,BroadCastId,LUser) ->

  ejabberd_sql:sql_query(Server,
    [<<"select id,from_user,to_users,message_id from chat_media_files where type = '">>,Type, <<"' and broadcast_id= '">>,BroadCastId, <<"' and (from_user= '">>,LUser, <<"' or to_users like '">>,<<"%">>,LUser,<<"%">>, <<"')  ;">>]).

get_not_delivered_message(Server,LUser) ->
  FromNotification = list_to_binary(binary_to_list(LUser) ++ "@" ++ binary_to_list(Server)),
  ejabberd_sql:sql_query(Server,
    [<<"SELECT from_user,message_id,chat_type,from_notification FROM message_status where to_user = '">>,LUser, <<"' and from_notification != '">>,FromNotification, <<"'  and status = 0 and recall_status =0 and message_notification = 0 and blocked = 0 ;">>]).

update_delivered_status(Server,LUser) ->
ejabberd_sql:sql_query(
    Server,
    [<<"update chat_recent set status =  1 where from_user ='">>,LUser,<<"' and status = 0 ;">>]).

get_last(LUser, LServer) ->
  case ejabberd_sql:sql_query(
    LServer,
    ?SQL("select @(seconds)d from last"
    " where username=%(LUser)s and status=0 and %(LServer)H")) of
    {selected, []} ->
      error;
    {selected, [{TimeStamp}]} ->
      {ok, {TimeStamp}};
    _Reason ->
      {error, db_failure}
  end.

% Gets custom_attributes tag from the request stanza and returns the equivalent xml element
get_custom_attributes(Packet) ->
  CustAtr = fxml:get_subtag_with_xmlns(xmpp:encode(Packet), <<"custom_attributes">>, <<"ocp:json">>),
  if  CustAtr =:= false ->
    CustomAttributes = "";
  true ->
    CustomAttributes = fxml:get_tag_cdata(CustAtr)
  end,
  #xmlel{name = <<"custom_attributes">>, children = [{xmlcdata, CustomAttributes}]}.

decrypt_license_data(FServer, LicenseData) ->

  ClientKey = gen_mod:get_module_opt(FServer, fly_mod_user_activities, client_key),
  ClientKeyValue = binary_to_list(ClientKey),
  DecryptedMessage = fly_mod_security:aes_decrpyt_license(list_to_binary(ClientKeyValue++ClientKeyValue++ClientKeyValue), <<"k%$/@B[jqAx}>8H@">>, binary_to_list(LicenseData)),
  {ParsedMessageJson} = jiffy:decode(http_uri:decode(binary_to_list(DecryptedMessage))),
  ParsedMessageJson.

update_license_lookup(LServer) ->

  ClientName = gen_mod:get_module_opt(LServer, fly_mod_user_activities, client_name),
  ClientKey = gen_mod:get_module_opt(LServer, fly_mod_user_activities, client_key),

  ClientKeyValue = binary_to_list(ClientKey),

  case ejabberd_sql:sql_query(LServer, [<<"select lkey from license_lookup;">>]) of

    {selected, _, []} ->
      ets:insert(ClientName, {module, []}),
      ets:insert(ClientName, {expiry, 0});

    {selected, _, [[Lkey]]} ->
      DecryptedMessage = fly_mod_security:aes_decrpyt_license(list_to_binary(ClientKeyValue++ClientKeyValue++ClientKeyValue), <<"k%$/@B[jqAx}>8H@">>, binary_to_list(Lkey)),
      {ParsedMessageJson} = jiffy:decode(http_uri:decode(binary_to_list(DecryptedMessage))),
      AvailableModules = proplists:get_value(<<"modulesPurchased">>, ParsedMessageJson),
      Expiry = proplists:get_value(<<"expiresAt">>, ParsedMessageJson),
      Domains = proplists:get_value(<<"domains">>, ParsedMessageJson),
      ?INFO_MSG("AvailableModules: ~p , Expire: ~p, Domain: ~p", [AvailableModules, Expiry, Domains]),
      ets:insert(ClientName, {module, AvailableModules}),
      ets:insert(ClientName, {expiry, Expiry})
  end.

validate_license(LServer, Init, Type) ->
  ClientName = gen_mod:get_module_opt(LServer, fly_mod_user_activities, client_name),
  [[Modules]] = ets:match(ClientName, {module, '$1'}),
  [[Expiry]] = ets:match(ClientName, {expiry, '$1'}),
  IsChatEnabled = lists:any(fun(X) -> X == <<"chat">> end, Modules),
  IsCallEnabled = lists:any(fun(X) -> X == <<"call">> end, Modules),

  { MegaSecs, Secs, _} = erlang:timestamp(),
  Now = (MegaSecs * 1000000 + Secs) * 1000,

  if Type =:= <<"chat">> ->
    IsAllowed = IsChatEnabled;
  true ->
    IsAllowed = IsCallEnabled
  end,
  if Expiry > Now ->
    if IsAllowed =:= true ->
      true;
    true ->
      false
    end;
  true ->
    ?INFO_MSG("license expired:  Expire: ~p, Domain: ~p", [Expiry, LServer]),
    if Init =:= true ->
      fly_mod_utils:update_license_lookup(LServer),
      validate_license(LServer, false, Type);
    true ->
      false
    end
  end.

update_mute_chat(#jid{luser = FUser, lserver = FServer}, ToUser, MuteStatus)->
  ejabberd_sql:sql_query(FServer,
    [<<"update chat_recent set mute_status = '">>, binary_to_list(MuteStatus), <<"' where from_user = '">>, ToUser, <<"' and to_user = '">>, FUser, <<"' ;">>]).

update_archive_chat(#jid{luser = FUser, lserver = FServer}, ToUser, ArchiveStatus)->
  ejabberd_sql:sql_query(FServer,
    [<<"update chat_recent set archive_status = '">>, ArchiveStatus, <<"' where from_user = '">>, ToUser, <<"' and to_user = '">>, FUser, <<"';">>]).

get_user_settings(#jid{luser = FUser, lserver = LServer}) ->
  ejabberd_sql:sql_query( LServer,
    [<<"select archive from chat_users where username='">>,FUser,<<"';">>]).

set_user_settings(#jid{luser = FUser, lserver = LServer}, Archive) ->
  ejabberd_sql:sql_query( LServer,
    [<<"update chat_users set archive = ">>, binary_to_list(Archive), <<" where username='">>,FUser,<<"';">>]).

get_archived_chats(#jid{luser = FUser, lserver = LServer}) ->
  ejabberd_sql:sql_query( LServer,
    [<<"select from_user, chat_type from chat_recent where to_user = '">>, FUser, <<"' and archive_status = 1 ;">>]).

update_recent_unread_chat(#jid{luser = FUser, lserver = FServer}, ToUser)->
  ejabberd_sql:sql_query(FServer,
    [<<"update chat_recent set unread = 0 where from_user = '">>, ToUser, <<"' and to_user = '">>, FUser, <<"' ;">>]).

update_recent_group_unread_chat(MessageId, ToUser, FServer )->
  ejabberd_sql:sql_query(FServer,
    [<<"update chat_recent set unread = 0 where  to_user = '">>, ToUser, <<"' and message_id = '">>, MessageId, <<"';">>]).

update_block_status_user(TServer, #jid{luser = TUser, lserver = _TServer},Status) ->
  ejabberd_sql:sql_query(TServer,
    [<<"update vcard_search set is_block = ">>, binary_to_list(Status), <<" where username='">>,TUser,<<"';">>]).

update_block_status_group(TServer, #jid{luser = TUser, lserver = _TServer},Status) ->
  ejabberd_sql:sql_query(TServer,
    [<<"UPDATE mix_pam SET is_block = '">>,Status, <<"' WHERE channel ='">>,TUser, <<"' ;">>]).

get_contact_permission(#jid{luser = TUser, lserver = TServer}) ->
  ejabberd_sql:sql_query(
    TServer,
    [<<"select contact_permission from chat_users where username='">>,TUser,<<"';">>]).

get_push_type(#jid{luser = TUser, lserver = TServer}) ->
  ejabberd_sql:sql_query(
    TServer,
    [<<"select push_server_type from chat_users_details where username='">>,TUser,<<"';">>]).

get_user_resources(TUser,  TServer) ->
  ejabberd_sql:sql_query(
    TServer,
    [<<"select device_id from chat_users_details where username='">>,TUser,<<"' and device_id !='' and (device_type != 'web' and device_type != '');">>]).

get_user_resource(TUser,  TServer, LResource) ->
      ejabberd_sql:sql_query(
        TServer,
        [<<"select device_id from chat_users_details where username='">>,TUser,<<"' and device_id !='' and device_id != '">>,LResource,<<"' and (device_type != 'web' and device_type != '');">>]).

get_user_resources(TUser, TServer, LResource) ->
  ejabberd_sql:sql_query(
    TServer,
    [<<"select device_id from chat_users_details where username='">>,TUser,<<"' and device_id = '">>,LResource,<<"' and (device_type != 'web' and device_type != '');">>]).

get_recent_profile(FServer, FUser, Updatedat) ->
  if Updatedat == <<"">> ->
    ejabberd_sql:sql_query(
    FServer,
    [<<"SELECT E.username , E.vcard  from vcard E JOIN chat_recent S ON E.username = S.from_user and S.to_user = '">>, FUser, <<"' order by S.created_at asc;">>]);
    true ->
  ejabberd_sql:sql_query(
    FServer,
    [<<"SELECT E.username, E.vcard from vcard E JOIN chat_recent S ON E.username = S.from_user and E.updated_at > '">>,Updatedat, <<"' and S.to_user = '">>, FUser, <<"' order by S.created_at asc;">>])
end.

remove_poll_offline(FServer, FResource, PollMsgId)->
  ejabberd_sql:sql_query(FServer,[<<"DELETE FROM spool WHERE message_id='">>,PollMsgId,<<"' AND device_id='">>,FResource,<<"';">>]).

get_mobile_user_message(TUser, TServer) ->
  Resources = ejabberd_sm:get_user_resources(TUser,
    TServer),
  if length(Resources) =:= 1 -> true;
    length(Resources) =:= 0 -> false;
    length(Resources) =:= 2 -> true;
    length(Resources) =:= 3 -> true;
    length(Resources) > 3 -> false
  end.

get_mobile_user_resource(TUser, TServer) ->
  Resources = ejabberd_sm:get_user_resources(TUser,
    TServer),
  if length(Resources) =:= 1 ->
    Substring = string:str(binary_to_list(list_to_binary(Resources)), binary_to_list(<<"Web">>)),
    if Substring =:= 1 -> true;
      true -> false
    end;
    length(Resources) =:= 0 -> false;
    length(Resources) =:= 2 -> false;
    length(Resources) > 2 -> false
  end.
