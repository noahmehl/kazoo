%%%-------------------------------------------------------------------
%%% @copyright (C) 2013, 2600Hz INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(kapi_resource).

-include("kazoo_api.hrl").

-define(KEY_EAVESDROP_REQ, <<"eavesdrop.resource.req">>). %% corresponds to eavesdrop_req/1 api call
-define(KEY_RESOURCE_REQ, <<"originate.resource.req">>).

-export([originate_req/1, originate_req/2, originate_req_v/1, originate_req_v/2
         %% ,originate_resp/1, originate_resp/2, originate_resp_v/1, originate_resp_v/2
         %% ,originate_ready/1, originate_ready/2, originate_ready_v/1, originate_ready_v/2
         %% ,originate_execute/1, originate_execute/2, originate_execute_v/1, originate_execute_v/2
         %% ,originate_started/1, originate_started/2, originate_started_v/1, originate_started_v/2
         %% ,originate_uuid/1, originate_uuid/2, originate_uuid_v/1, originate_uuid_v/2
         %% ,eavesdrop_req/1, eavesdrop_req/2, eavesdrop_req_v/1, eavesdrop_req_v/2
         %% ,eavesdrop_resp/1, eavesdrop_resp/2, eavesdrop_resp_v/1, eavesdrop_resp_v/2
        ]).
%% -export([is_valid_mode/1]).

-export([bind_q/2, unbind_q/2]).
-export([declare_exchanges/0]).

-export([publish_originate_req/1, publish_originate_req/2
         %% ,publish_originate_resp/2, publish_originate_resp/3
         %% ,publish_originate_started/2, publish_originate_started/3
         %% ,publish_originate_uuid/2, publish_originate_uuid/3
         %% ,publish_eavesdrop_req/1, publish_eavesdrop_req/2
         %% ,publish_eavesdrop_resp/2, publish_eavesdrop_resp/3
        ]).

-spec bind_q(ne_binary(), wh_proplist()) -> 'ok'.
-spec bind_q(ne_binary(), wh_proplist(), atoms() | 'undefined') -> 'ok'.
bind_q(Queue, Prop) ->
    bind_q(Queue, Prop, props:get_value('restrict_to', Prop)).

bind_q(Queue, _Prop, 'undefined') ->
    'ok' = amqp_util:bind_q_to_callmgr(Queue, ?KEY_RESOURCE_REQ),
    amqp_util:bind_q_to_callmgr(Queue, ?KEY_EAVESDROP_REQ);
bind_q(Queue, Prop, ['originate'|T]) ->
    'ok' = amqp_util:bind_q_to_callmgr(Queue, ?KEY_RESOURCE_REQ),
    bind_q(Queue, Prop, T);
bind_q(Queue, Prop, ['eavesdrop'|T]) ->
    'ok' = amqp_util:bind_q_to_callmgr(Queue, ?KEY_EAVESDROP_REQ),
    bind_q(Queue, Prop, T);
bind_q(Queue, Prop, [_|T]) ->
    bind_q(Queue, Prop, T);
bind_q(_, _, []) ->
    'ok'.

-spec unbind_q(ne_binary(), wh_proplist()) -> 'ok'.
-spec unbind_q(ne_binary(), wh_proplist(), atoms() | 'undefined') -> 'ok'.
unbind_q(Queue, Prop) ->
    unbind_q(Queue, Prop, props:get_value('restrict_to', Prop)).

unbind_q(Queue, _Prop, 'undefined') ->
    'ok' = amqp_util:unbind_q_from_callmgr(Queue, ?KEY_RESOURCE_REQ),
    amqp_util:unbind_q_from_callmgr(Queue, ?KEY_EAVESDROP_REQ);
unbind_q(Queue, Prop, ['originate'|T]) ->
    'ok' = amqp_util:unbind_q_from_callmgr(Queue, ?KEY_RESOURCE_REQ),
    unbind_q(Queue, Prop, T);
unbind_q(Queue, Prop, ['eavesdrop'|T]) ->
    'ok' = amqp_util:unbind_q_from_callmgr(Queue, ?KEY_EAVESDROP_REQ),
    unbind_q(Queue, Prop, T);
unbind_q(Queue, Prop, [_|T]) ->
    unbind_q(Queue, Prop, T);
unbind_q(_, _, []) ->
    'ok'.

%%--------------------------------------------------------------------
%% @doc
%% declare the exchanges used by this API
%% @end
%%--------------------------------------------------------------------
-spec declare_exchanges() -> 'ok'.
declare_exchanges() ->
    amqp_util:callmgr_exchange().

-spec originate_req(api_terms()) -> api_builder_resp().
-spec originate_req(api_terms(), wh_proplist()) -> api_builder_resp().
originate_req(API) -> originate_req(API, []).

originate_req(Props, Options) when is_list(Props) ->
    originate_req(wh_json:from_list(Props), Options);
originate_req(JObj, Options) ->
    case originate_req_v(JObj, Options) of
        {'ok', FixedJObj} ->
            kz_api:build_message(FixedJObj);
        {'error', Errors} -> {'error', Errors};
        'false' -> {'error', "API failed validation for originate_req"}
    end.

-spec originate_req_v(api_terms()) -> api_validator_resp().
-spec originate_req_v(api_terms(), wh_proplist()) -> api_validator_resp().
originate_req_v(API) -> originate_req_v(API, []).

originate_req_v(Props, Options) when is_list(Props) ->
    originate_req_v(wh_json:from_list(Props), Options);
originate_req_v(JObj, Options) ->
    {'ok', Schema} = kz_api:find_schema(<<"originate_req">>),
    jesse:validate_with_schema(Schema, JObj, [{'allowed_errors', 2} | Options]).

%%--------------------------------------------------------------------
%% @doc Publish the JSON iolist() to the proper Exchange
%% @end
%%--------------------------------------------------------------------
-spec publish_originate_req(api_terms()) -> 'ok'.
-spec publish_originate_req(api_terms(), binary()) -> 'ok'.
publish_originate_req(JObj) ->
    publish_originate_req(JObj, ?DEFAULT_CONTENT_TYPE).
publish_originate_req(Req, ContentType) ->
    {'ok', Payload} = ?MODULE:originate_req(Req),
    amqp_util:callmgr_publish(Payload, ContentType, ?KEY_RESOURCE_REQ).
