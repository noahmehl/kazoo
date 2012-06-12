%%%-------------------------------------------------------------------
%%% @copyright (C) 2011-2012, VoIP INC
%%% @doc
%%%
%%% Handle client requests for phone_number documents
%%%
%%% @end
%%% @contributors
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(wh_number_manager).

-export([find/1, find/2]).
-export([lookup_account_by_number/1]).
-export([create_number/3, create_number/4]).
-export([port_in/3, port_in/4]).
-export([reconcile_number/3]).
-export([free_numbers/1]).
-export([reserve_number/3, reserve_number/4]).
-export([assign_number_to_account/3, assign_number_to_account/4]).
-export([release_number/2]).
-export([list_attachments/2]).
-export([fetch_attachment/3]).
-export([put_attachment/5]).
-export([delete_attachment/3]).
-export([get_public_fields/2, set_public_fields/3]).

-include("wh_number_manager.hrl").

-define(SERVER, ?MODULE).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Query the various providers for available numbers.
%% @end
%%--------------------------------------------------------------------
-spec find/1 :: (ne_binary()) -> [] | [ne_binary(),...].
-spec find/2 :: (ne_binary(), ne_binary()) -> [] | [ne_binary(),...].

find(Number) ->
    find(Number, <<"1">>).

find(Number, Quanity) ->
    Num = wnm_util:normalize_number(Number),
    lager:debug("attempting to find ~p numbers with prefix '~s'", [Quanity, Number]),
    Results = [{Module, catch(Module:find_numbers(Num, Quanity))}
               || Module <- wnm_util:list_carrier_modules()],
    prepare_find_results(Results, []).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Attempt to find the number, and if sucessful return the account
%% assignment
%% @end
%%--------------------------------------------------------------------
-spec lookup_account_by_number/1 :: (ne_binary()) -> {'ok', ne_binary(), boolean()} |
                                                     {'error', _}.
lookup_account_by_number(undefined) ->
    {error, not_reconcilable};
lookup_account_by_number(Number) ->
    try wnm_number:get(Number) of
        #number{assigned_to=undefined} -> 
            lager:debug("number ~s not assigned to an account", [Number]),
            {error, unassigned};            
        #number{assigned_to=AssignedTo, state = <<"port_in">>} -> 
            lager:debug("number ~s is assigned to ~s in state port_in", [Number, AssignedTo]),
            {ok, AssignedTo, true};
        #number{assigned_to=AssignedTo, state = <<"in_service">>, number_doc=JObj} -> 
            case wh_json:is_true(<<"force_outbound">>, JObj, false) of
                true -> 
                    lager:debug("number ~s is assigned to ~s in state in_serivce and is forced outbound", [Number, AssignedTo]),
                    {ok, AssignedTo, true};
                false -> 
                    lager:debug("number ~s is assigned to ~s in state in_serivce", [Number, AssignedTo]),
                    {ok, AssignedTo, false}
            end;
        #number{assigned_to=AssignedTo, state = <<"port_out">>} -> 
            lager:debug("number ~s is assigned to ~s in state port_in", [Number, AssignedTo]),
            {ok, AssignedTo, true};
        #number{assigned_to=AssignedTo, state=State} -> 
            lager:debug("number ~s assigned to acccount id ~s but in state ~s", [Number, AssignedTo, State]),
            {error, {not_in_service, AssignedTo}}
    catch
        throw:{Error, #number{}} ->
            {error, Error}
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Add and reserve a number for an account
%% @end
%%--------------------------------------------------------------------
-spec create_number/3 :: (ne_binary(), ne_binary(), ne_binary()) -> transition_return().
-spec create_number/4 :: (ne_binary(), ne_binary(), ne_binary(), wh_json:json_object()) -> transition_return().

create_number(Number, AssignTo, AuthBy) ->
    create_number(Number, AssignTo, AuthBy, wh_json:new()).

create_number(Number, AssignTo, AuthBy, PublicFields) ->
    lager:debug("attempting to create number ~s for account ~s", [Number, AssignTo]),    
    Routines = [fun(_) -> wnm_number:get(Number, PublicFields) end
                ,fun({not_found, #number{}=N}) -> 
                         AccountId = wh_util:format_account_id(AuthBy, raw),
                         AccountDb = wh_util:format_account_id(AuthBy, encoded),
                         try
                             {ok, JObj} = couch_mgr:open_cache_doc(AccountDb, AccountId),
                             true = wh_json:is_true(<<"pvt_wnm_allow_additions">>, JObj),
                             lager:debug("number doesnt exist but account ~s is authorized to create it", [AuthBy]),
                             NewNumber = N#number{number=Number
                                                  ,assign_to=AssignTo
                                                  ,auth_by=AuthBy
                                                  ,number_doc=PublicFields
                                                 },
                             wnm_number:create_available(NewNumber)
                         catch
                             error:{badmatch, Error} ->
                                 lager:debug("account is not authorized to create a new number: ~p", [Error]),
                                 wnm_number:error_unauthorized(N)
                         end;
                    ({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:error_number_exists(N)
                 end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:reserved(N#number{assign_to=AssignTo, auth_by=AuthBy})
                 end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:save(N)
                 end
                ,fun({E, #number{}}) -> 
                         lager:debug("create number prematurely ended: ~p", [E]),
                         {error, E};
                    (#number{number_doc=JObj}) -> 
                         lager:debug("create number successfully completed", []),
                         {ok, wh_json:public_fields(JObj)}
                 end
               ], 
    lists:foldl(fun(F, J) -> catch F(J) end, ok, Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Add a port in number for an account
%% @end
%%--------------------------------------------------------------------
-spec port_in/3 :: (ne_binary(), ne_binary(), ne_binary()) -> transition_return().
-spec port_in/4 :: (ne_binary(), ne_binary(), ne_binary(), wh_json:json_object()) -> transition_return().

port_in(Number, AssignTo, AuthBy) ->
    port_in(Number, AssignTo, AuthBy, wh_json:new()).

port_in(Number, AssignTo, AuthBy, PublicFields) ->
    lager:debug("attempting to port_in number ~s for account ~s", [Number, AssignTo]),    
    Routines = [fun(_) -> wnm_number:get(Number, PublicFields) end
                ,fun({not_found, #number{}=N}) ->
                         NewNumber = N#number{number=Number
                                              ,assign_to=AssignTo
                                              ,auth_by=AuthBy
                                              ,number_doc=PublicFields
                                             },
                         wnm_number:create_port_in(NewNumber);
                    ({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:error_number_exists(N)
                 end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:save(N)
                 end
                ,fun({E, #number{}}) -> 
                         lager:debug("port in number prematurely ended: ~p", [E]),
                         {error, E};
                    (#number{number_doc=JObj}) -> 
                         lager:debug("port in number successfully completed", []),
                         {ok, wh_json:public_fields(JObj)}
                 end
               ], 
    lists:foldl(fun(F, J) -> catch F(J) end, ok, Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Assign a number to an account, creating it as a local number if
%% missing
%% @end
%%--------------------------------------------------------------------
-spec reconcile_number/3 :: (ne_binary(), ne_binary(), ne_binary()) -> transition_return().
reconcile_number(Number, AssignTo, AuthBy) ->
    Routines = [fun(_) -> wnm_number:get(Number) end
                ,fun({not_found, #number{}=N}) -> 
                         NewNumber = N#number{number=Number
                                              ,assign_to=AssignTo
                                              ,auth_by=AuthBy
                                             },
                         wnm_number:create_available(NewNumber);
                    ({_, #number{}}=E) -> E;
                    (#number{}=N) -> N#number{assign_to=AssignTo
                                              ,auth_by=AuthBy
                                             }
                 end
                ,fun({_, #number{}}=E) -> E;
                    (#number{assign_to=Assign}=N) ->
                         lager:debug("attempting to reconcile number ~s with account ~s", [Number, Assign]),
                         wnm_number:in_service(N)
                 end
                ,fun({no_change_required, #number{}=N}) ->
                         wnm_number:save_phone_number_docs(N);
                    ({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:save(N)
                 end
                ,fun({E, #number{}}) -> 
                         lager:debug("reconcile number prematurely ended: ~p", [E]),
                         {error, E};
                    (#number{number_doc=JObj}) -> 
                         lager:debug("reconcile number successfully completed", []),
                         {ok, wh_json:public_fields(JObj)}
                 end
               ], 
    lists:foldl(fun(F, J) -> catch F(J) end, ok, Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Release all numbers currently assigned to an account
%% @end
%%--------------------------------------------------------------------
-spec free_numbers/1 :: (ne_binary()) -> ok.
free_numbers(AccountId) ->
    lager:debug("attempting to free all numbers assigned to account ~s", [AccountId]),
    AccountDb = wh_util:format_account_id(AccountId, encoded),
    case couch_mgr:open_doc(AccountDb, ?WNM_PHONE_NUMBER_DOC) of
        {ok, JObj} ->
            _ = [release_number(Key, AccountId)
                 || Key <- wh_json:get_keys(JObj)
                        ,wnm_util:is_reconcilable(Key)
                ],
            ok;
        {error, _R} -> 
            lager:debug("failed to open account ~s ~s document: ~p", [AccountId, ?WNM_PHONE_NUMBER_DOC, _R]),
            ok
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Add and reserve a number for an account
%% @end
%%--------------------------------------------------------------------
-spec reserve_number/3 :: (ne_binary(), ne_binary(), ne_binary()) -> transition_return().
-spec reserve_number/4 :: (ne_binary(), ne_binary(), ne_binary(), wh_json:json_object()) -> transition_return().

reserve_number(Number, AssignTo, AuthBy) ->
    reserve_number(Number, AssignTo, AuthBy, undefined).

reserve_number(Number, AssignTo, AuthBy, PublicFields) ->
    lager:debug("attempting to reserve ~s for account ~s", [Number, AssignTo]),    
    Routines = [fun(_) -> wnm_number:get(Number, PublicFields) end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:reserved(N#number{assign_to=AssignTo, auth_by=AuthBy})
                 end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:save(N)
                 end
                ,fun({E, #number{}}) -> 
                         lager:debug("reserve prematurely ended: ~p", [E]),
                         {error, E};
                    (#number{number_doc=JObj}) -> 
                         lager:debug("reserve successfully completed", []),
                         {ok, wh_json:public_fields(JObj)}
                 end
               ], 
    lists:foldl(fun(F, J) -> catch F(J) end, ok, Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Assign a number to an account, aquiring the number from the provider
%% if necessary
%% @end
%%--------------------------------------------------------------------
-spec assign_number_to_account/3 :: (ne_binary(), ne_binary(), ne_binary()) -> transition_return().
-spec assign_number_to_account/4 :: (ne_binary(), ne_binary(), ne_binary(), wh_json:json_object()) -> transition_return().

assign_number_to_account(Number, AssignTo, AuthBy) ->
    assign_number_to_account(Number, AssignTo, AuthBy, undefined).

assign_number_to_account(Number, AssignTo, AuthBy, PublicFields) ->
    lager:debug("attempting to assign ~s to account ~s", [Number, AssignTo]),
    Routines = [fun(_) -> wnm_number:get(Number, PublicFields) end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:in_service(N#number{assign_to=AssignTo, auth_by=AuthBy})
                 end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:save(N)
                 end
                ,fun({E, #number{}}) -> 
                         lager:debug("assign number to account prematurely ended: ~p", [E]),
                         {error, E};
                    (#number{number_doc=JObj}) -> 
                         lager:debug("assign number to account successfully completed", []),
                         {ok, wh_json:public_fields(JObj)}
                 end
               ],
    lists:foldl(fun(F, J) -> catch F(J) end, ok, Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% move an in service number to the released state were it will be
%% recycled or cancled after a buffer period
%% @end
%%--------------------------------------------------------------------
-spec release_number/2 :: (ne_binary(), ne_binary()) -> {ok, wh_json:json_object()} | {error, _}.
release_number(Number, AuthBy) ->    
    lager:debug("attempting to release ~s", [Number]),
    Routines = [fun(_) -> wnm_number:get(Number) end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:released(N#number{auth_by=AuthBy})
                 end
                ,fun({no_change_required, #number{}=N}) ->
                         wnm_number:save_phone_number_docs(N);
                    ({invalid_state_transition, #number{}=N}) ->
                         wnm_number:save_phone_number_docs(N);
                    ({_, #number{}}=E) -> E;
                    (#number{hard_delete=false}=N) -> wnm_number:save(N);
                    (#number{hard_delete=true}=N) -> wnm_number:delete(N)
                 end
                ,fun({E, #number{}}) -> 
                         lager:debug("release prematurely ended: ~p", [E]),
                         {error, E};
                    (#number{number_doc=JObj}) -> 
                         lager:debug("release successfully completed", []),
                         {ok, wh_json:public_fields(JObj)}
                 end
               ],
    lists:foldl(fun(F, J) -> catch F(J) end, ok, Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Lists attachments on a number
%% @end
%%--------------------------------------------------------------------
-spec list_attachments/2 :: (ne_binary(), ne_binary()) -> {'ok', wh_json:json_object()} | {'error', atom()}.
list_attachments(Number, AuthBy) ->
    lager:debug("attempting to list attachements on ~s", [Number]),
    Routines = [fun(_) -> wnm_number:get(Number) end
                ,fun({error, _}=E) -> E;
                    ({ok, J}) -> 
                         case wh_json:get_value(<<"pvt_number_state">>, J) of
                             <<"port_in">> -> {ok, J};
                             _Else -> {error, unauthorized}
                         end
                 end
                ,fun({error, _}=E) -> E;
                    ({ok, J}) ->
                        AssignedTo = wh_json:get_ne_value(<<"pvt_assigned_to">>, J),
                        case wh_util:is_in_account_hierarchy(AuthBy, AssignedTo, true) of
                            false -> {error, unauthorized};
                            true -> {ok, J}
                        end
                 end
                ,fun({error, _R}=E) -> 
                         lager:debug("list attachments prematurely ended: ~p", [_R]),
                         E;
                    ({ok, J}) -> 
                         {ok, wh_json:get_value(<<"_attachments">>, J, wh_json:new())}
                 end
               ], 
    lists:foldl(fun(F, J) -> F(J) end, undefined, Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Fetch an attachment on a number
%% @end
%%--------------------------------------------------------------------
-spec fetch_attachment/3 :: (ne_binary(), ne_binary(), ne_binary()) -> {'ok', wh_json:json_object()} | {'error', atom()}.
fetch_attachment(Number, Name, AuthBy) ->
    lager:debug("attempting to fetch attachement ~s on ~s for account ~s", [Name, Number]),
    Routines = [fun({error, _}=E) -> E;
                   ({ok, J}) -> 
                        case wh_json:get_value(<<"pvt_number_state">>, J) of
                            <<"port_in">> -> {ok, J};
                            _Else -> {error, unauthorized}
                        end
                end
                ,fun({error, _}=E) -> E;
                    ({ok, J}) ->
                         AssignedTo = wh_json:get_ne_value(<<"pvt_assigned_to">>, J),
                         case wh_util:is_in_account_hierarchy(AuthBy, AssignedTo, true) of
                             false -> {error, unauthorized};
                             true -> {ok, J}
                         end
                 end
                ,fun({error, _R}=E) -> 
                         lager:debug("fetch attachments prematurely ended: ~p", [_R]),
                         E;
                    ({ok, J}) -> 
                         Num = wh_json:get_value(<<"_id">>, J),
                         Db = wnm_util:number_to_db_name(Num),
                         couch_mgr:fetch_attachment(Db, Num, Name)
                 end
               ], 
    lists:foldl(fun(F, J) -> F(J) end, wnm_number:get(Number), Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Add an attachment to a number
%% @end
%%--------------------------------------------------------------------
-spec put_attachment/5 :: (ne_binary(), ne_binary(), ne_binary(), proplist(), ne_binary()) -> {'ok', wh_json:json_object()} | {'error', atom}.
put_attachment(Number, Name, Content, Options, AuthBy) ->
    lager:debug("attempting to add an attachement to ~s", [Number]),
    Routines = [fun({error, _}=E) -> E;
                   ({ok, J}) -> 
                        case wh_json:get_value(<<"pvt_number_state">>, J) of
                            <<"port_in">> -> {ok, J};
                            _Else -> {error, unauthorized}
                        end
                end
                ,fun({error, _}=E) -> E;
                    ({ok, J}) ->
                         AssignedTo = wh_json:get_ne_value(<<"pvt_assigned_to">>, J),
                         case wh_util:is_in_account_hierarchy(AuthBy, AssignedTo, true) of
                             false -> {error, unauthorized};
                             true -> {ok, J}
                         end
                 end
                ,fun({error, _R}=E) -> 
                         lager:debug("put attachments prematurely ended: ~p", [_R]),
                         E;
                    ({ok, J}) -> 
                         Rev = wh_json:get_value(<<"_rev">>, J),
                         Num = wh_json:get_value(<<"_id">>, J),
                         Db = wnm_util:number_to_db_name(Num),
                         couch_mgr:put_attachment(Db, Num, Name, Content, [{rev, Rev}|Options])
                 end
               ], 
    lists:foldl(fun(F, J) -> F(J) end, wnm_number:get(Number), Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Add an attachment to a number
%% @end
%%--------------------------------------------------------------------
-spec delete_attachment/3 :: (ne_binary(), ne_binary(), ne_binary()) -> {'ok', wh_json:json_object()} | {'error', atom()}.
delete_attachment(Number, Name, AuthBy) ->
    lager:debug("attempting to delete attachement ~s from ~s", [Name, Number]),
    Routines = [fun({error, _}=E) -> E;
                   ({ok, J}) -> 
                        case wh_json:get_value(<<"pvt_number_state">>, J) of
                            <<"port_in">> -> {ok, J};
                            _Else -> {error, unauthorized}
                        end
                end
                ,fun({error, _}=E) -> E;
                    ({ok, J}) ->
                        AssignedTo = wh_json:get_ne_value(<<"pvt_assigned_to">>, J),
                        case wh_util:is_in_account_hierarchy(AuthBy, AssignedTo, true) of
                            false -> {error, unauthorized};
                            true -> {ok, J}
                        end
                 end
                ,fun({error, _R}=E) -> 
                         lager:debug("delete attachment prematurely ended: ~p", [_R]),
                         E;
                    ({ok, J}) ->
                         Num = wh_json:get_value(<<"_id">>, J),
                         Db = wnm_util:number_to_db_name(Num),
                         couch_mgr:delete_attachment(Db, Num, Name)
                 end
               ], 
    lists:foldl(fun(F, J) -> F(J) end, wnm_number:get(Number), Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Update the user configurable fields
%% @end
%%--------------------------------------------------------------------
-spec get_public_fields/2 :: (ne_binary(), ne_binary()) -> {ok, wh_json:json_object()} |
                                                           {error, atom()}.
get_public_fields(Number, AuthBy) ->
    lager:debug("attempting to get public fields for number ~s", [Number]),
    Routines = [fun(_) -> wnm_number:get(Number) end
                ,fun({_, #number{}}=E) -> E;
                    (#number{assigned_to=AssignedTo}=N) ->
                         case wh_util:is_in_account_hierarchy(AuthBy, AssignedTo, true) of
                             false -> wnm_number:error_unauthorized(N);
                             true -> N
                         end
                 end
                ,fun({E, #number{}}) -> 
                         lager:debug("fetch public fields prematurely ended: ~p", [E]),
                         {error, E};
                    (#number{number_doc=JObj}) -> 
                         lager:debug("fetch public fields successfully completed", []),
                         {ok, wh_json:public_fields(JObj)}
                 end
               ], 
    lists:foldl(fun(F, J) -> catch F(J) end, ok, Routines).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Update the user configurable fields
%% @end
%%--------------------------------------------------------------------
-spec set_public_fields/3 :: (ne_binary(), wh_json:json_object(), ne_binary()) -> {ok, wh_json:json_object()} |
                                                                                  {error, atom()}.
set_public_fields(Number, PublicFields, AuthBy) ->
    lager:debug("attempting to set public fields for number ~s", [Number]),
    Routines = [fun(_) -> wnm_number:get(Number, PublicFields) end
                ,fun({_, #number{}}=E) -> E;
                    (#number{assigned_to=AssignedTo}=N) ->
                         case wh_util:is_in_account_hierarchy(AuthBy, AssignedTo, true) of
                             false -> wnm_number:error_unauthorized(N);
                             true -> N
                         end
                 end
                ,fun({_, #number{}}=E) -> E;
                    (#number{}=N) -> wnm_number:save(N)
                 end
                ,fun({E, #number{}}) -> 
                         lager:debug("set public fields prematurely ended: ~p", [E]),
                         {error, E};
                    (#number{number_doc=JObj}) -> 
                         lager:debug("set public fields successfully completed", []),
                         {ok, wh_json:public_fields(JObj)}
                 end
               ], 
    lists:foldl(fun(F, J) -> catch F(J) end, ok, Routines).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Loop over all the discovered numbers during a find operation and
%% ensure the modules data is stored for later acquisition.
%% @end
%%--------------------------------------------------------------------
-spec prepare_find_results/2 :: (proplist(), [] | [ne_binary(),...]) -> [] | [ne_binary(),...].
-spec prepare_find_results/4 :: ([] | [ne_binary(),...], ne_binary(), wh_json:json_object(), [] | [ne_binary(),...])
                                -> [] | [ne_binary(),...].

prepare_find_results([], Found) ->
    Results = lists:flatten(Found),
    lager:debug("discovered ~p available numbers", [length(Results)]),
    Results;
prepare_find_results([{Module, {ok, ModuleResults}}|T], Found) ->
    case wh_json:get_keys(ModuleResults) of
        [] -> prepare_find_results(T, Found);
        Numbers ->
            Results = prepare_find_results(Numbers, wh_util:to_binary(Module)
                                           ,ModuleResults, Found),
            prepare_find_results(T, [Results|Found])
    end;
prepare_find_results([_|T], Found) ->
    prepare_find_results(T, Found).

prepare_find_results([], _, _, Found) ->
    Found;
prepare_find_results([Number|Numbers], ModuleName, ModuleResults, Found) ->
    case wnm_number:get(Number) of
        {#number{state=State}} ->
            case lists:member(State, ?WNM_AVALIABLE_STATES) of
                true ->
                    prepare_find_results(Numbers, ModuleName, ModuleResults, [Number|Found]);
                false ->
                    lager:debug("the discovery '~s' is not available: ~s", [Number, State]),
                    prepare_find_results(Numbers, ModuleName, ModuleResults, Found)
            end;
        {not_found, #number{}=N} ->
            NewNumber = N#number{number=Number
                                 ,module_name=ModuleName
                                 ,module_data=wh_json:get_value(Number, ModuleResults)
                                },
            case wnm_number:save(wnm_number:create_discovery(NewNumber)) of
                {#number{}} -> 
                    prepare_find_results(Numbers, ModuleName, ModuleResults, [Number|Found]);
                {_R, #number{}} ->
                    lager:debug("failed to store discovery ~s: ~p", [Number, _R]),
                    prepare_find_results(Numbers, ModuleName, ModuleResults, Found)
            end;
        {_R, #number{}} ->
            lager:debug("failed to determine state of discovery ~s: ~p", [Number, _R]),
            prepare_find_results(Numbers, ModuleName, ModuleResults, Found)    
    end.
