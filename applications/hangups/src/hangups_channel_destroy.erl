%%%-------------------------------------------------------------------
%%% @copyright (C) 2010-2013, 2600Hz INC
%%% @doc
%%%
%%% @end
%%%
%%% @contributors
%%%   James Aimonetti
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(hangups_channel_destroy).

-include("hangups.hrl").

-export([handle_req/2]).

-spec handle_req(wh_json:object(), proplist()) -> no_return().
handle_req(JObj, _Props) ->
    'true' = wapi_call:event_v(JObj),
    IgnoreCauses = whapps_config:get(<<"hangups">>, <<"ignore_hangup_causes">>, ?IGNORE),
    HangupCause = wh_json:get_value(<<"Hangup-Cause">>, JObj, <<"unknown">>),
    case lists:member(HangupCause, IgnoreCauses) of
        'true' -> 'ok';
        'false' ->
            AccountId = wh_json:get_value([<<"Custom-Channel-Vars">>, <<"Account-ID">>], JObj),
            lager:debug("abnormal call termination: ~s", [HangupCause]),
            wh_notify:system_alert("~s ~s to ~s (~s) on ~s(~s)"
                                   ,[wh_util:to_lower_binary(HangupCause)
                                     ,find_source(JObj)
                                     ,find_destination(JObj)
                                     ,find_direction(JObj)
                                     ,find_realm(JObj, AccountId)
                                     ,AccountId
                                    ]
                                   ,maybe_add_hangup_specific(HangupCause, JObj)
                                  )
    end.

-spec maybe_add_hangup_specific(ne_binary(), wh_json:object()) -> wh_proplist().
maybe_add_hangup_specific(<<"UNALLOCATED_NUMBER">>, JObj) ->
    maybe_add_number_info(JObj);
maybe_add_hangup_specific(<<"NO_ROUTE_DESTINATION">>, JObj) ->
    maybe_add_number_info(JObj);
maybe_add_hangup_specific(_HangupCause, JObj) ->
    wh_json:to_proplist(JObj).

-spec maybe_add_number_info(wh_json:object()) -> wh_proplist().
maybe_add_number_info(JObj) ->
    Destination = find_destination(JObj),
    try stepswitch_util:lookup_number(Destination) of
        {'ok', AccountId, _Props} ->
            [{<<"Account-Tree">>, build_account_tree(AccountId)}
             | wh_json:to_proplist(JObj)
            ];
        {'error', _} ->
            [{<<"Hangups-Message">>, <<"Destination was not found in numbers DBs">>}
             | wh_json:to_proplist(JObj)
            ]
    catch
        _:_ -> wh_json:to_proplist(JObj)
    end.

-spec build_account_tree(ne_binary()) -> wh_json:object().
build_account_tree(AccountId) ->
    {'ok', AccountDoc} = couch_mgr:open_cache_doc(?WH_ACCOUNTS_DB, AccountId),
    Tree = wh_json:get_value(<<"pvt_tree">>, AccountDoc, []),
    build_account_tree(Tree, []).

-spec build_account_tree(ne_binaries(), wh_proplist()) -> wh_json:object().
build_account_tree([], Map) -> wh_json:from_list(Map);
build_account_tree([AccountId|Tree], Map) ->
    {'ok', AccountDoc} = couch_mgr:open_doc(?WH_ACCOUNTS_DB, AccountId),
    build_account_tree(Tree, [{AccountId, wh_json:get_value(<<"name">>, AccountDoc)} | Map]).

-spec find_realm(wh_json:object(), ne_binary()) -> ne_binary().
find_realm(JObj, AccountId) ->
    case wh_json:get_value([<<"Custom-Channel-Vars">>, <<"Account-ID">>], JObj) of
        'undefined' -> get_account_realm(AccountId);
        Realm -> Realm
    end.

-spec get_account_realm(api_binary()) -> ne_binary().
get_account_realm('undefined') -> <<"unknown">>;
get_account_realm(AccountId) ->
    case couch_mgr:open_cache_doc(?WH_ACCOUNTS_DB, AccountId) of
        {'ok', JObj} -> wh_json:get_value(<<"realm">>, JObj, <<"unknown">>);
        {'error', _} -> <<"unknown">>
    end.

-spec find_destination(wh_json:object()) -> ne_binary().
find_destination(JObj) ->
    case catch binary:split(wh_json:get_value(<<"Request">>, JObj), <<"@">>) of
        [Num|_] -> Num;
        _ -> use_to_as_destination(JObj)
    end.

-spec use_to_as_destination(wh_json:object()) -> ne_binary().
use_to_as_destination(JObj) ->
    case catch binary:split(wh_json:get_value(<<"To-Uri">>, JObj), <<"@">>) of
        [Num|_] -> Num;
        _ -> wh_json:get_value(<<"Callee-ID-Number">>, JObj, <<"unknown">>)
    end.

-spec find_source(wh_json:object()) -> ne_binary().
find_source(JObj) ->
    case catch binary:split(wh_json:get_value(<<"From-Uri">>, JObj), <<"@">>) of
        [Num|_] -> Num;
        _ -> wh_json:get_value(<<"Caller-ID-Number">>, JObj, <<"unknown">>)
    end.

-spec find_direction(wh_json:object()) -> ne_binary().
find_direction(JObj) ->
    wh_json:get_value(<<"Call-Direction">>, JObj, <<"unknown">>).

