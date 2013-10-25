-ifndef(KAZOO_API_HRL).
-define(KAZOO_API_HRL, 'true').

-include_lib("whistle/include/wh_types.hrl").
-include_lib("whistle/include/wh_log.hrl").

-define(API_CACHE, 'kazoo_api_cache').

-type api_builder_resp() :: {'ok', iolist()} |
                            {'error', _}.
-type api_validator_resp() :: {'ok', wh_json:object()} |
                              {'error', _}.

-define(DEFAULT_CONTENT_TYPE, <<"application/json">>).

-define(SERVER_ID_SCHEMA, wh_json:from_list([{<<"description">>, <<"AMQP Response Queue on the 'targeted' exchange">>}
                                             ,{<<"type">>, <<"string">>}
                                            ])).
-define(APP_NAME_SCHEMA, wh_json:from_list([{<<"description">>, <<"Application name of the sender">>}
                                            ,{<<"type">>, <<"string">>}
                                            ,{<<"required">>, 'true'}
                                           ])).
-define(APP_VERSION_SCHEMA, wh_json:from_list([{<<"description">>, <<"Application version of the sender">>}
                                               ,{<<"type">>, <<"string">>}
                                               ,{<<"required">>, 'true'}
                                              ])).
-define(NODE_SCHEMA, wh_json:from_list([{<<"description">>, <<"Node of the sender">>}
                                        ,{<<"type">>, <<"string">>}
                                        ,{<<"default">>, wh_util:to_binary(node())}
                                       ])).
-define(EVENT_CATEGORY_SCHEMA, wh_json:from_list([{<<"description">>, <<"Category of the message type">>}
                                                  ,{<<"type">>, <<"string">>}
                                                  ,{<<"required">>, 'true'}
                                                 ])).
-define(EVENT_NAME_SCHEMA, wh_json:from_list([{<<"description">>, <<"Name of the event">>}
                                              ,{<<"type">>, <<"string">>}
                                              ,{<<"required">>, 'true'}
                                             ])).
-define(MSG_ID_SCHEMA, wh_json:from_list([{<<"description">>, <<"Unique ID of the request">>}
                                          ,{<<"type">>, <<"string">>}
                                          ,{<<"default">>, wh_util:rand_hex_binary(16)}
                                         ])).

-define(DEFAULT_HEADERS_SCHEMA
        ,wh_json:from_list([{<<"Server-ID">>, ?SERVER_ID_SCHEMA}
                            ,{<<"App-Name">>, ?APP_NAME_SCHEMA}
                            ,{<<"App-Version">>, ?APP_VERSION_SCHEMA}
                            ,{<<"Node">>, ?NODE_SCHEMA}
                            ,{<<"Event-Name">>, ?EVENT_NAME_SCHEMA}
                            ,{<<"Event-Category">>, ?EVENT_CATEGORY_SCHEMA}
                            ,{<<"Msg-ID">>, ?MSG_ID_SCHEMA}
                           ])).

-endif.
