%%%-------------------------------------------------------------------
%%% @copyright (C) 2013, 2600Hz
%%% @doc
%%% Handles authentication requests, responses, queue bindings
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(kapi_authn).

-compile({'no_auto_import', [error/1]}).

-export([req/1, req/2, req_v/1, req_v/2
         ,resp/1, resp/2, resp_v/1, resp_v/2
         ,error/1, error/2, error_v/1, error_v/2

         ,bind_q/2, unbind_q/2
         ,declare_exchanges/0

         ,publish_req/1, publish_req/2
         ,publish_resp/2, publish_resp/3
         ,publish_error/2, publish_error/3
         ,get_auth_user/1, get_auth_realm/1
        ]).

-include("kazoo_api.hrl").

-define(KEY_AUTHN_REQ, <<"authn.req">>).

%%--------------------------------------------------------------------
%% @doc Setup and tear down bindings for authn gen_listeners
%% @end
%%--------------------------------------------------------------------
-spec bind_q(ne_binary(), wh_proplist()) -> 'ok'.
bind_q(Q, Props) ->
    Realm = props:get_value('realm', Props, <<"*">>),
    amqp_util:bind_q_to_callmgr(Q, get_authn_req_routing(Realm)).

-spec unbind_q(ne_binary(), wh_proplist()) -> 'ok'.
unbind_q(Q, Props) ->
    Realm = props:get_value('realm', Props, <<"*">>),
    amqp_util:unbind_q_from_callmgr(Q, get_authn_req_routing(Realm)).

%%--------------------------------------------------------------------
%% @doc
%% declare the exchanges used by this API
%% @end
%%--------------------------------------------------------------------
-spec declare_exchanges() -> 'ok'.
declare_exchanges() ->
    amqp_util:callmgr_exchange().

-spec req(api_terms()) -> api_builder_resp().
-spec req(api_terms(), wh_proplist()) -> api_builder_resp().
req(API) -> req(API, []).

req(Props, Options) when is_list(Props) ->
    req(wh_json:from_list(Props), Options);
req(JObj, Options) ->
    case req_v(JObj, Options) of
        {'ok', FixedJObj} ->
            kz_api:build_message(FixedJObj);
        {'error', Errors} -> {'error', Errors};
        'false' -> {'error', "API failed validation for authn_req"}
    end.

-spec req_v(api_terms()) -> api_validator_resp().
-spec req_v(api_terms(), wh_proplist()) -> api_validator_resp().
req_v(API) -> req_v(API, []).

req_v(Props, Options) when is_list(Props) ->
    req_v(wh_json:from_list(Props), Options);
req_v(JObj, Options) ->
    {'ok', Schema} = kz_api:find_schema(<<"authn_req">>),
    jesse:validate_with_schema(Schema, JObj, [{'allowed_errors', 2} | Options]).

-spec resp(api_terms()) -> api_builder_resp().
-spec resp(api_terms(), wh_proplist()) -> api_builder_resp().
resp(API) -> resp(API, []).

resp(Props, Options) when is_list(Props) ->
    resp(wh_json:from_list(Props), Options);
resp(JObj, Options) ->
    case resp_v(JObj, Options) of
        {'ok', FixedJObj} ->
            kz_api:build_message(FixedJObj);
        {'error', Errors} -> {'error', Errors};
        'false' -> {'error', "API failed validation for authn_resp"}
    end.

-spec resp_v(api_terms()) -> api_validator_resp().
resp_v(API) -> resp_v(API, []).

resp_v(Props, Options) when is_list(Props) ->
    resp_v(wh_json:from_list(Props), Options);
resp_v(JObj, Options) ->
    {'ok', Schema} = kz_api:find_schema(<<"authn_resp">>),
    jesse:validate_with_schema(Schema, JObj, [{'allowed_errors', 2} | Options]).

-spec error(api_terms()) -> api_builder_resp().
error(API) -> error(API, []).

error(Props, Options) when is_list(Props) ->
    error(wh_json:from_list(Props), Options);
error(JObj, Options) ->
    case error_v(JObj, Options) of
        {'ok', FixedJObj} ->
            kz_api:build_message(FixedJObj);
        {'error', Errors} -> {'error', Errors};
        'false' -> {'error', "API failed validation for authn_err"}
    end.

-spec error_v(api_terms()) -> api_validator_resp().
error_v(API) -> error_v(API, []).

error_v(Props, Options) when is_list(Props) ->
    error_v(wh_json:from_list(Props), Options);
error_v(JObj, Options) ->
    {'ok', Schema} = kz_api:find_schema(<<"authn_err">>),
    jesse:validate_with_schema(Schema, JObj, [{'allowed_errors', 2} | Options]).

%%--------------------------------------------------------------------
%% @doc Publish the JSON iolist() to the proper Exchange
%% @end
%%--------------------------------------------------------------------
-spec publish_req(api_terms()) -> 'ok'.
-spec publish_req(api_terms(), binary()) -> 'ok'.
publish_req(JObj) ->
    publish_req(JObj, ?DEFAULT_CONTENT_TYPE).
publish_req(Req, ContentType) ->
    {'ok', Payload} = ?MODULE:req(Req),
    amqp_util:callmgr_publish(Payload, ContentType, get_authn_req_routing(Req)).

-spec publish_resp(ne_binary(), api_terms()) -> 'ok'.
-spec publish_resp(ne_binary(), api_terms(), binary()) -> 'ok'.
publish_resp(Queue, JObj) ->
    publish_resp(Queue, JObj, ?DEFAULT_CONTENT_TYPE).
publish_resp(Queue, Resp, ContentType) ->
    {'ok', Payload} = ?MODULE:resp(Resp),
    amqp_util:targeted_publish(Queue, Payload, ContentType).

-spec publish_error(ne_binary(), api_terms()) -> 'ok'.
-spec publish_error(ne_binary(), api_terms(), binary()) -> 'ok'.
publish_error(Queue, JObj) ->
    publish_error(Queue, JObj, ?DEFAULT_CONTENT_TYPE).
publish_error(Queue, Resp, ContentType) ->
    {'ok', Payload} = ?MODULE:error(Resp),
    amqp_util:targeted_publish(Queue, Payload, ContentType).

%%-----------------------------------------------------------------------------
%% @private
%% @doc
%% creating the routing key for either binding queues or publishing messages
%% @end
%%-----------------------------------------------------------------------------
-spec get_authn_req_routing(ne_binary() | api_terms()) -> ne_binary().
get_authn_req_routing(Realm) when is_binary(Realm) ->
    list_to_binary([?KEY_AUTHN_REQ, ".", amqp_util:encode(Realm)]);
get_authn_req_routing(Req) ->
    get_authn_req_routing(get_auth_realm(Req)).

%%-----------------------------------------------------------------------------
%% @private
%% @doc
%% extract the auth user from the API request
%% @end
%%-----------------------------------------------------------------------------
-spec get_auth_user(wh_json:object()) -> api_binary().
get_auth_user(ApiJObj) ->
    case wh_json:get_value(<<"Auth-User">>, ApiJObj) of
        'undefined' -> 'undefined';
         Username -> wh_util:to_lower_binary(Username)
    end.

%%-----------------------------------------------------------------------------
%% @private
%% @doc
%% extract the auth realm from the API request, using the requests to domain
%% when provided with an IP
%% @end
%%-----------------------------------------------------------------------------
-spec get_auth_realm(api_terms()) -> ne_binary().
get_auth_realm(Props) when is_list(Props) ->
    AuthRealm = props:get_value(<<"Auth-Realm">>, Props, <<"missing.realm">>),
    case wh_network_utils:is_ipv4(AuthRealm)
        orelse wh_network_utils:is_ipv6(AuthRealm)
    of
        'false' -> wh_util:to_lower_binary(AuthRealm);
        'true' ->
            [_ToUser, ToDomain] = binary:split(props:get_value(<<"To">>, Props), <<"@">>),
            wh_util:to_lower_binary(ToDomain)
    end;
get_auth_realm(JObj) -> get_auth_realm(wh_json:to_proplist(JObj)).
