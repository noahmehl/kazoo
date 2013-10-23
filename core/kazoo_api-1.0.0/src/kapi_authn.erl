%%%-------------------------------------------------------------------
%%% @copyright (C) 2013, 2600Hz
%%% @doc
%%% Handles authentication requests, responses, queue bindings
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(kapi_authn).

-export([req/1, req/2, req_v/1, req_v/2]).

-include("kazoo_api.hrl").

-spec req(api_terms()) ->
                 {'ok', iolist()} |
                 {'error', string()}.
req(API) -> req(API, []).

req(Prop, Options) when is_list(Prop) ->
    req(wh_json:from_list(Prop), Options);
req(JObj, Options) ->
    case req_v(JObj, Options) of
        {'ok', FixedJObj} ->
            lager:debug("end validate"),
            kz_api:build_message(FixedJObj);
        {'error', Errors} -> {'error', Errors};
        'false' -> {'error', "API failed validation for authn_req"}
    end.

-spec req_v(api_terms()) -> boolean().
req_v(API) -> req_v(API, []).

req_v(Prop, Options) when is_list(Prop) ->
    req_v(wh_json:from_list(Prop), Options);
req_v(JObj, Options) ->
    {'ok', Schema} = kz_api:find_schema(<<"authn_req">>),
    lager:debug("start validate"),
    jesse:validate_with_schema(Schema, JObj, [{'allowed_errors', 2} | Options]).
