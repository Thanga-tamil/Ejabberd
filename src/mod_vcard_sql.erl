%%%-------------------------------------------------------------------
%%% File    : mod_vcard_sql.erl
%%% Author  : Evgeny Khramtsov <ekhramtsov@process-one.net>
%%% Created : 13 Apr 2016 by Evgeny Khramtsov <ekhramtsov@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2024   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License along
%%% with this program; if not, write to the Free Software Foundation, Inc.,
%%% 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
%%%
%%%----------------------------------------------------------------------

-module(mod_vcard_sql).


-behaviour(mod_vcard).

%% API
-export([init/2, stop/1, get_vcard/2, set_vcard/4, search/4, remove_user/2,
	 search_fields/1, search_reported/1, import/3, export/1]).
-export([is_search_supported/1]).
-export([sql_schemas/0]).

-include_lib("xmpp/include/xmpp.hrl").
-include("mod_vcard.hrl").
-include("logger.hrl").
-include("ejabberd_sql_pt.hrl").
-include("translate.hrl").

%%%===================================================================
%%% API
%%%===================================================================
init(Host, _Opts) ->
    ejabberd_sql_schema:update_schema(Host, ?MODULE, sql_schemas()),
    ok.

sql_schemas() ->
    [#sql_schema{
        version = 1,
        tables =
            [#sql_table{
                name = <<"vcard">>,
                columns =
                    [#sql_column{name = <<"username">>, type = text},
                     #sql_column{name = <<"server_host">>, type = text},
                     #sql_column{name = <<"vcard">>, type = {text, big}},
                     #sql_column{name = <<"created_at">>, type = timestamp,
                                 default = true}],
                indices = [#sql_index{
                              columns = [<<"server_host">>, <<"username">>],
                              unique = true}]},
             #sql_table{
                name = <<"vcard_search">>,
                columns =
                    [#sql_column{name = <<"username">>, type = text},
                     #sql_column{name = <<"lusername">>, type = text},
                     #sql_column{name = <<"server_host">>, type = text},
                     #sql_column{name = <<"fn">>, type = text},
                     #sql_column{name = <<"lfn">>, type = text},
                     #sql_column{name = <<"family">>, type = text},
                     #sql_column{name = <<"lfamily">>, type = text},
                     #sql_column{name = <<"given">>, type = text},
                     #sql_column{name = <<"lgiven">>, type = text},
                     #sql_column{name = <<"middle">>, type = text},
                     #sql_column{name = <<"lmiddle">>, type = text},
                     #sql_column{name = <<"nickname">>, type = text},
                     #sql_column{name = <<"lnickname">>, type = text},
                     #sql_column{name = <<"bday">>, type = text},
                     #sql_column{name = <<"lbday">>, type = text},
                     #sql_column{name = <<"ctry">>, type = text},
                     #sql_column{name = <<"lctry">>, type = text},
                     #sql_column{name = <<"locality">>, type = text},
                     #sql_column{name = <<"llocality">>, type = text},
                     #sql_column{name = <<"email">>, type = text},
                     #sql_column{name = <<"lemail">>, type = text},
                     #sql_column{name = <<"orgname">>, type = text},
                     #sql_column{name = <<"lorgname">>, type = text},
                     #sql_column{name = <<"orgunit">>, type = text},
                     #sql_column{name = <<"lorgunit">>, type = text},
                     #sql_column{name = <<"msg_disappear">>, type = text},
                     #sql_column{name = <<"updated_by">>, type = text},
                     #sql_column{name = <<"disp_updated_at">>, type = text},
                     #sql_column{name = <<"description">>, type = text}],
                indices = [#sql_index{
                              columns = [<<"server_host">>, <<"lusername">>],
                              unique = true},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lfn">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lfamily">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lgiven">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lmiddle">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lnickname">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lbday">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lctry">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"llocality">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lemail">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lorgname">>]},
                           #sql_index{
                              columns = [<<"server_host">>, <<"lorgunit">>]}]}]}].

stop(_Host) ->
    ok.

is_search_supported(_LServer) ->
    true.

get_vcard(LUser, LServer) ->
    case ejabberd_sql:sql_query(
	   LServer,
	   ?SQL("select @(vcard)s from vcard"
                " where username=%(LUser)s and %(LServer)H")) of
	{selected, [{SVCARD}]} ->
	    case fxml_stream:parse_element(SVCARD) of
		{error, _Reason} -> [];
		VCARD -> {ok, [VCARD]}
	    end;
	{selected, []} -> {ok, []};
	_ -> error
    end.


set_vcard(LUser, LServer, VCARD,
          #vcard_search{
              user = {User, _},
              fn = FN, lfn = LFN,
              family = Family, lfamily = LFamily,
              given = Given, lgiven = LGiven,
              middle = Middle, lmiddle = LMiddle,
              nickname = Nickname, lnickname = LNickname,
              bday = BDay, lbday = LBDay,
              ctry = CTRY, lctry = LCTRY,
              locality = Locality, llocality = LLocality,
              email = EMail, lemail = LEMail,
              orgname = OrgName, lorgname = LOrgName,
              orgunit = OrgUnit, lorgunit = LOrgUnit,
              status = Status, lstatus = LStatus,
              image = Image, limage = LImage,
              thumbimage = ThumbImage, lthumbimage = LThumbImage,
              history = History,
              mobilenumber = MobileNumber, lmobilenumber = LMobileNumber,
              msg_disappear = MsgDisappear,
              updated_by = UpdatedBy,
              disp_updated_at = DispUpdatedAt,
              description = Description
          }) ->

    %% =========================
    %% ENTRY LOG
    %% =========================
    ?INFO_MSG(
        "set_vcard called~nLUser=~p~nLServer=~p~nVCARD=~p",
        [LUser, LServer, fxml:element_to_binary(VCARD)]
    ),

    SVCARD = fxml:element_to_binary(VCARD),

    %% =========================
    %% FETCH EXISTING ROW (OUTSIDE TRANSACTION)
    %% =========================
    
       ExistingRow =
        try
            case ejabberd_sql:sql_query(
                    LServer,
                    [<<"select fn, lfn, family, lfamily, given, lgiven, middle, lmiddle, nickname, lnickname, bday, lbday, ctry, lctry, locality, llocality, email, lemail, orgname, lorgname, orgunit, lorgunit, status, lstatus, image, limage, thumbimage, lthumbimage, history, mobilenumber, lmobilenumber, msg_disappear, updated_by, disp_updated_at, description from vcard_search where lusername= '">>, LUser, <<"' ">>]
                ) of
                {selected, []} -> 
                    ?INFO_MSG("vcard search empty", []),
                    [];
                {selected, _Cols, [Row | _]} -> 
                    ?INFO_MSG("Found existing row with ~p elements", [length(Row)]),
                    Row;
                {selected, _Cols, []} -> 
                    ?INFO_MSG("No existing row found for user ~p", [LUser]),
                    [];
                {error, Reason} ->
                    ?ERROR_MSG("SQL query failed: ~p", [Reason]),
                    [];
                Other ->
                    ?ERROR_MSG("Unexpected SQL result: ~p", [Other]),
                    [];
                _ ->
                    ?ERROR_MSG("Unexpected SQL result: ~p", []),
                    []
            end
        catch
            _:Error ->
                ?ERROR_MSG("Exception during SQL query: ~p", [Error]),
                []
        end,

    ?INFO_MSG("Existing vcard_search row = ~p", [ExistingRow]),
    ?INFO_MSG("Existing active User = ~p", [LUser]),

    ToBin = fun
        (V) when is_binary(V) -> V;
        (V) when is_integer(V) -> integer_to_binary(V);
        (V) when is_list(V) -> list_to_binary(V);
        (V) when is_atom(V) -> 
            case V of
                undefined -> <<>>;
                null -> <<>>;
                'NULL' -> <<>>;
                <<>> -> <<>>;
                _ -> atom_to_binary(V, utf8)
            end;
        ({{Y,M,D},{H,Mi,S,_}}) ->
            list_to_binary(
                io_lib:format("~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B",
                            [Y,M,D,H,Mi,S])
            );
        (_) -> <<>>
    end,

    SafeNth = fun
        (N, Row) when is_list(Row), length(Row) >= N ->
            case lists:nth(N, Row) of
                Value -> ToBin(Value);
                _ -> <<>>
            end;
        (_, _) ->
            <<>>
    end,

    Pick = fun
        (undefined, Idx) -> SafeNth(Idx, ExistingRow);
        (null, Idx) -> SafeNth(Idx, ExistingRow);
        (<<>>, Idx) -> SafeNth(Idx, ExistingRow);
        (Val, _) -> ToBin(Val)
    end,

    %% =========================
    %% FINAL VALUES
    %% =========================

    FN1 = Pick(FN, 1),
    LFN1 = Pick(LFN, 2),
    Family1 = Pick(Family, 3),
    LFamily1 = Pick(LFamily, 4),
    Given1 = Pick(Given, 5),
    LGiven1 = Pick(LGiven, 6),
    Middle1 = Pick(Middle, 7),
    LMiddle1 = Pick(LMiddle, 8),
    Nickname1 = Pick(Nickname, 9),
    LNickname1 = Pick(LNickname, 10),
    BDay1 = Pick(BDay, 11),
    LBDay1 = Pick(LBDay, 12),
    CTRY1 = Pick(CTRY, 13),
    LCTRY1 = Pick(LCTRY, 14),
    Locality1 = Pick(Locality, 15),
    LLocality1 = Pick(LLocality, 16),
    EMail1 = Pick(EMail, 17),
    LEMail1 = Pick(LEMail, 18),
    OrgName1 = Pick(OrgName, 19),
    LOrgName1 = Pick(LOrgName, 20),
    OrgUnit1 = Pick(OrgUnit, 21),
    LOrgUnit1 = Pick(LOrgUnit, 22),
    Status1 = Pick(Status, 23),
    LStatus1 = Pick(LStatus, 24),
    Image1 = Pick(Image, 25),
    LImage1 = Pick(LImage, 26),
    ThumbImage1 = Pick(ThumbImage, 27),
    LThumbImage1 = Pick(LThumbImage, 28),
    History1 = Pick(History, 29),
    MobileNumber1 = Pick(MobileNumber, 30),
    LMobileNumber1 = Pick(LMobileNumber, 31),
    MsgDisappear1 = Pick(MsgDisappear, 32),
    UpdatedBy1 = Pick(UpdatedBy, 33),
    DispUpdatedAt1 = Pick(DispUpdatedAt, 34), 
    Description1 = Pick(Description, 35), 

    ?INFO_MSG(
        "Final picked vcard values:~n"
        "FN=~p LFN=~p~n"
        "Family=~p LFamily=~p~n"
        "Given=~p LGiven=~p~n"
        "Middle=~p LMiddle=~p~n"
        "Nickname=~p LNickname=~p~n"
        "BDay=~p LBDay=~p~n"
        "CTRY=~p LCTRY=~p~n"
        "Locality=~p LLocality=~p~n"
        "EMail=~p LEMail=~p~n"
        "OrgName=~p LOrgName=~p~n"
        "OrgUnit=~p LOrgUnit=~p~n"
        "Status=~p LStatus=~p~n"
        "Image=~p LImage=~p~n"
        "ThumbImage=~p LThumbImage=~p~n"
        "History=~p~n"
        "MobileNumber=~p LMobileNumber=~p~n"
        "MsgDisappear=~p UpdatedBy=~p DispUpdatedAt=~p Description=~p",
        [
            FN1, LFN1,
            Family1, LFamily1,
            Given1, LGiven1,
            Middle1, LMiddle1,
            Nickname1, LNickname1,
            BDay1, LBDay1,
            CTRY1, LCTRY1,
            Locality1, LLocality1,
            EMail1, LEMail1,
            OrgName1, LOrgName1,
            OrgUnit1, LOrgUnit1,
            Status1, LStatus1,
            Image1, LImage1,
            ThumbImage1, LThumbImage1,
            History1,
            MobileNumber1, LMobileNumber1,
            MsgDisappear1, UpdatedBy1, DispUpdatedAt1, Description1
        ]
    ),

    %% =========================
    %% WRITE TRANSACTION (ONLY UPSERTS)
    %% =========================

    IsTimestamp = case catch binary_to_integer(DispUpdatedAt) of
                      IT when is_integer(IT) -> true;
                      _ -> false
                  end,

    ejabberd_sql:sql_transaction(
            LServer,
            fun() ->
                ?SQL_UPSERT(
                    LServer, "vcard",
                    ["!username=%(LUser)s",
                     "!server_host=%(LServer)s",
                     "vcard=%(SVCARD)s",
                     "is_delete=0",
                     "updated_at=NOW()"]),

                if (DispUpdatedAt == <<>>) or (DispUpdatedAt == undefined) ->
                    ?SQL_UPSERT(LServer, "vcard_search",
                                ["username=%(User)s",
                                 "!lusername=%(LUser)s",
                                 "!server_host=%(LServer)s",
                                 "fn=%(FN1)s",
                                 "lfn=%(LFN1)s",
                                 "family=%(Family1)s",
                                 "lfamily=%(LFamily1)s",
                                 "given=%(Given1)s",
                                 "lgiven=%(LGiven1)s",
                                 "middle=%(Middle1)s",
                                 "lmiddle=%(LMiddle1)s",
                                 "nickname=%(Nickname1)s",
                                 "lnickname=%(LNickname1)s",
                                 "bday=%(BDay1)s",
                                 "lbday=%(LBDay1)s",
                                 "ctry=%(CTRY1)s",
                                 "lctry=%(LCTRY1)s",
                                 "locality=%(Locality1)s",
                                 "llocality=%(LLocality1)s",
                                 "email=%(EMail1)s",
                                 "lemail=%(LEMail1)s",
                                 "orgname=%(OrgName1)s",
                                 "lorgname=%(LOrgName1)s",
                                 "orgunit=%(OrgUnit1)s",
                                 "lorgunit=%(LOrgUnit1)s",
                                 "status=%(Status1)s",
                                 "lstatus=%(LStatus1)s",
                                 "image=%(Image1)s",
                                 "limage=%(LImage1)s",
                                 "thumbimage=%(ThumbImage1)s",
                                 "lthumbimage=%(LThumbImage1)s",
                                 "history=%(History1)s",
                                 "mobilenumber=%(MobileNumber1)s",
                                 "lmobilenumber=%(LMobileNumber1)s",
                                 "msg_disappear=%(MsgDisappear1)s",
                                 "updated_by=%(UpdatedBy1)s",
                                 "description=%(Description1)s",
                                 "disp_updated_at=%(DispUpdatedAt1)s"]);
                IsTimestamp ->
                    ?SQL_UPSERT(LServer, "vcard_search",
                                ["username=%(User)s",
                                 "!lusername=%(LUser)s",
                                 "!server_host=%(LServer)s",
                                 "fn=%(FN1)s",
                                 "lfn=%(LFN1)s",
                                 "family=%(Family1)s",
                                 "lfamily=%(LFamily1)s",
                                 "given=%(Given1)s",
                                 "lgiven=%(LGiven1)s",
                                 "middle=%(Middle1)s",
                                 "lmiddle=%(LMiddle1)s",
                                 "nickname=%(Nickname1)s",
                                 "lnickname=%(LNickname1)s",
                                 "bday=%(BDay1)s",
                                 "lbday=%(LBDay1)s",
                                 "ctry=%(CTRY1)s",
                                 "lctry=%(LCTRY1)s",
                                 "locality=%(Locality1)s",
                                 "llocality=%(LLocality1)s",
                                 "email=%(EMail1)s",
                                 "lemail=%(LEMail1)s",
                                 "orgname=%(OrgName1)s",
                                 "lorgname=%(LOrgName1)s",
                                 "orgunit=%(OrgUnit1)s",
                                 "lorgunit=%(LOrgUnit1)s",
                                 "status=%(Status1)s",
                                 "lstatus=%(LStatus1)s",
                                 "image=%(Image1)s",
                                 "limage=%(LImage1)s",
                                 "thumbimage=%(ThumbImage1)s",
                                 "lthumbimage=%(LThumbImage1)s",
                                 "history=%(History1)s",
                                 "mobilenumber=%(MobileNumber1)s",
                                 "lmobilenumber=%(LMobileNumber1)s",
                                 "msg_disappear=%(MsgDisappear1)s",
                                 "updated_by=%(UpdatedBy1)s",
                                 "description=%(Description1)s",
                                 "disp_updated_at=FROM_UNIXTIME(%(DispUpdatedAt)s)"]);
                true ->
                    ?SQL_UPSERT(LServer, "vcard_search",
                                ["username=%(User)s",
                                 "!lusername=%(LUser)s",
                                 "!server_host=%(LServer)s",
                                 "fn=%(FN1)s",
                                 "lfn=%(LFN1)s",
                                 "family=%(Family1)s",
                                 "lfamily=%(LFamily1)s",
                                 "given=%(Given1)s",
                                 "lgiven=%(LGiven1)s",
                                 "middle=%(Middle1)s",
                                 "lmiddle=%(LMiddle1)s",
                                 "nickname=%(Nickname1)s",
                                 "lnickname=%(LNickname1)s",
                                 "bday=%(BDay1)s",
                                 "lbday=%(LBDay1)s",
                                 "ctry=%(CTRY1)s",
                                 "lctry=%(LCTRY1)s",
                                 "locality=%(Locality1)s",
                                 "llocality=%(LLocality1)s",
                                 "email=%(EMail1)s",
                                 "lemail=%(LEMail1)s",
                                 "orgname=%(OrgName1)s",
                                 "lorgname=%(LOrgName1)s",
                                 "orgunit=%(OrgUnit1)s",
                                 "lorgunit=%(LOrgUnit1)s",
                                 "status=%(Status1)s",
                                 "lstatus=%(LStatus1)s",
                                 "image=%(Image1)s",
                                 "limage=%(LImage1)s",
                                 "thumbimage=%(ThumbImage1)s",
                                 "lthumbimage=%(LThumbImage1)s",
                                 "history=%(History1)s",
                                 "mobilenumber=%(MobileNumber1)s",
                                 "lmobilenumber=%(LMobileNumber1)s",
                                 "msg_disappear=%(MsgDisappear1)s",
                                 "updated_by=%(UpdatedBy1)s",
                                 "description=%(Description1)s",
                                 "disp_updated_at=%(DispUpdatedAt1)s"])
                end
   

            end
        ).

search(LServer, Data, AllowReturnAll, MaxMatch) ->
    MatchSpec = make_matchspec(LServer, Data),
    if (MatchSpec == <<"">>) and not AllowReturnAll -> [];
       true ->
	    Limit = case MaxMatch of
			infinity ->
			    <<"">>;
			Val ->
			    [<<" LIMIT ">>, integer_to_binary(Val)]
		    end,
	   case catch ejabberd_sql:sql_query(
			LServer,
			[<<"select username, fn, family, given, "
			   "middle,        nickname, bday, ctry, "
			   "locality,        email, orgname, orgunit "
			   "from vcard_search ">>,
			 MatchSpec, Limit, <<";">>]) of
	       {selected,
		[<<"username">>, <<"fn">>, <<"family">>, <<"given">>,
		 <<"middle">>, <<"nickname">>, <<"bday">>, <<"ctry">>,
		 <<"locality">>, <<"email">>, <<"orgname">>,
		 <<"orgunit">>], Rs} when is_list(Rs) ->
		   [row_to_item(LServer, R) || R <- Rs];
	       Error ->
		   ?ERROR_MSG("~p", [Error]), []
	   end
    end.

search_fields(_LServer) ->
    [{?T("User"), <<"user">>},
     {?T("Full Name"), <<"fn">>},
     {?T("Name"), <<"first">>},
     {?T("Middle Name"), <<"middle">>},
     {?T("Family Name"), <<"last">>},
     {?T("Nickname"), <<"nick">>},
     {?T("Birthday"), <<"bday">>},
     {?T("Country"), <<"ctry">>},
     {?T("City"), <<"locality">>},
     {?T("Email"), <<"email">>},
     {?T("Organization Name"), <<"orgname">>},
     {?T("Organization Unit"), <<"orgunit">>}].

search_reported(_LServer) ->
    [{?T("Jabber ID"), <<"jid">>},
     {?T("Full Name"), <<"fn">>},
     {?T("Name"), <<"first">>},
     {?T("Middle Name"), <<"middle">>},
     {?T("Family Name"), <<"last">>},
     {?T("Nickname"), <<"nick">>},
     {?T("Birthday"), <<"bday">>},
     {?T("Country"), <<"ctry">>},
     {?T("City"), <<"locality">>},
     {?T("Email"), <<"email">>},
     {?T("Organization Name"), <<"orgname">>},
     {?T("Organization Unit"), <<"orgunit">>}].

remove_user(LUser, LServer) ->
    ejabberd_sql:sql_transaction(
      LServer,
      fun() ->
              ejabberd_sql:sql_query_t(
                ?SQL("delete from vcard"
                     " where username=%(LUser)s and %(LServer)H")),
              ejabberd_sql:sql_query_t(
                ?SQL("delete from vcard_search"
                     " where lusername=%(LUser)s and %(LServer)H"))
      end).

export(_Server) ->
    [{vcard,
      fun(Host, #vcard{us = {LUser, LServer}, vcard = VCARD})
            when LServer == Host ->
              SVCARD = fxml:element_to_binary(VCARD),
              [?SQL("delete from vcard"
                    " where username=%(LUser)s and %(LServer)H;"),
               ?SQL_INSERT("vcard",
                           ["username=%(LUser)s",
                            "server_host=%(LServer)s",
                            "vcard=%(SVCARD)s"])];
         (_Host, _R) ->
              []
      end},
     {vcard_search,
      fun(Host, #vcard_search{user = {User, LServer}, luser = LUser,
                              fn = FN, lfn = LFN, family = Family,
                              lfamily = LFamily, given = Given,
                              lgiven = LGiven, middle = Middle,
                              lmiddle = LMiddle, nickname = Nickname,
                              lnickname = LNickname, bday = BDay,
                              lbday = LBDay, ctry = CTRY, lctry = LCTRY,
                              locality = Locality, llocality = LLocality,
                              email = EMail, lemail = LEMail,
                              orgname = OrgName, lorgname = LOrgName,
                              orgunit = OrgUnit, lorgunit = LOrgUnit})
            when LServer == Host ->
              [?SQL("delete from vcard_search"
                    " where lusername=%(LUser)s and %(LServer)H;"),
               ?SQL_INSERT("vcard_search",
                           ["username=%(User)s",
                            "lusername=%(LUser)s",
                            "server_host=%(LServer)s",
                            "fn=%(FN)s",
                            "lfn=%(LFN)s",
                            "family=%(Family)s",
                            "lfamily=%(LFamily)s",
                            "given=%(Given)s",
                            "lgiven=%(LGiven)s",
                            "middle=%(Middle)s",
                            "lmiddle=%(LMiddle)s",
                            "nickname=%(Nickname)s",
                            "lnickname=%(LNickname)s",
                            "bday=%(BDay)s",
                            "lbday=%(LBDay)s",
                            "ctry=%(CTRY)s",
                            "lctry=%(LCTRY)s",
                            "locality=%(Locality)s",
                            "llocality=%(LLocality)s",
                            "email=%(EMail)s",
                            "lemail=%(LEMail)s",
                            "orgname=%(OrgName)s",
                            "lorgname=%(LOrgName)s",
                            "orgunit=%(OrgUnit)s",
                            "lorgunit=%(LOrgUnit)s"])];
         (_Host, _R) ->
              []
      end}].

import(_, _, _) ->
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================
make_matchspec(LServer, Data) ->
    filter_fields(Data, <<"">>, LServer).

filter_fields([], Match, LServer) ->
    case ejabberd_sql:use_new_schema() of
        true ->
            SQLType = ejabberd_option:sql_type(LServer),
            SServer = ejabberd_sql:to_string_literal(SQLType, LServer),
            case Match of
                <<"">> -> [<<"where server_host=">>, SServer];
                _ -> [<<" where server_host=">>, SServer, <<" and ">>, Match]
            end;
        false ->
            case Match of
                <<"">> -> <<"">>;
                _ -> [<<" where ">>, Match]
            end
    end;
filter_fields([{SVar, [Val]} | Ds], Match, LServer)
  when is_binary(Val) and (Val /= <<"">>) ->
    LVal = mod_vcard:string2lower(Val),
    NewMatch = case SVar of
		   <<"user">> -> make_val(LServer, Match, <<"lusername">>, LVal);
		   <<"fn">> -> make_val(LServer, Match, <<"lfn">>, LVal);
		   <<"last">> -> make_val(LServer, Match, <<"lfamily">>, LVal);
		   <<"first">> -> make_val(LServer, Match, <<"lgiven">>, LVal);
		   <<"middle">> -> make_val(LServer, Match, <<"lmiddle">>, LVal);
		   <<"nick">> -> make_val(LServer, Match, <<"lnickname">>, LVal);
		   <<"bday">> -> make_val(LServer, Match, <<"lbday">>, LVal);
		   <<"ctry">> -> make_val(LServer, Match, <<"lctry">>, LVal);
		   <<"locality">> ->
		       make_val(LServer, Match, <<"llocality">>, LVal);
		   <<"email">> -> make_val(LServer, Match, <<"lemail">>, LVal);
		   <<"orgname">> -> make_val(LServer, Match, <<"lorgname">>, LVal);
		   <<"orgunit">> -> make_val(LServer, Match, <<"lorgunit">>, LVal);
		   _ -> Match
	       end,
    filter_fields(Ds, NewMatch, LServer);
filter_fields([_ | Ds], Match, LServer) ->
    filter_fields(Ds, Match, LServer).

make_val(LServer, Match, Field, Val) ->
    Condition = case str:suffix(<<"*">>, Val) of
		  true ->
		      Val1 = str:substr(Val, 1, byte_size(Val) - 1),
		      SVal = <<(ejabberd_sql:escape(
                                  ejabberd_sql:escape_like_arg_circumflex(
                                    Val1)))/binary,
			       "%">>,
		      [Field, <<" LIKE '">>, SVal, <<"' ESCAPE '^'">>];
		  _ ->
                      SQLType = ejabberd_option:sql_type(LServer),
		      SVal = ejabberd_sql:to_string_literal(SQLType, Val),
		      [Field, <<" = ">>, SVal]
		end,
    case Match of
      <<"">> -> Condition;
      _ -> [Match, <<" and ">>, Condition]
    end.

row_to_item(LServer, [Username, FN, Family, Given, Middle, Nickname, BDay,
		      CTRY, Locality, EMail, OrgName, OrgUnit]) ->
    [{<<"jid">>, <<Username/binary, $@, LServer/binary>>},
     {<<"fn">>, FN},
     {<<"last">>, Family},
     {<<"first">>, Given},
     {<<"middle">>, Middle},
     {<<"nick">>, Nickname},
     {<<"bday">>, BDay},
     {<<"ctry">>, CTRY},
     {<<"locality">>, Locality},
     {<<"email">>, EMail},
     {<<"orgname">>, OrgName},
     {<<"orgunit">>, OrgUnit}].
