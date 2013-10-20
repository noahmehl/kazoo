%%%-------------------------------------------------------------------
%%% @copyright (C) 2013, 2600Hz
%%% @doc
%%% Handles authentication requests, responses, queue bindings
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(kapi_authn).

-export([req/1, req_v/1]).

-include("kazoo_api.hrl").

-spec req(api_terms()) ->
                 {'ok', iolist()} |
                 {'error', string()}.
req(Prop) when is_list(Prop) ->
    req(wh_json:from_list(Prop));
req(JObj) ->
    case req_v(JObj) of
        {'ok', FixedJObj} -> kz_api:build_message(FixedJObj);
        {'error', Errors} -> {'error', Errors};
        'false' -> {'error', "API failed validation for authn_req"}
    end.

-spec req_v(api_terms()) -> boolean().
req_v(Prop) when is_list(Prop) ->
    req_v(wh_json:from_list(Prop));
req_v(JObj) ->
    {'ok', Schema} = kz_api:find_schema(<<"authn_req">>),
    jesse:validate_with_schema(Schema, JObj, [{'allowed_errors', 'infinity'}]).
