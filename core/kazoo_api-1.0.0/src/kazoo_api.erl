%%%-------------------------------------------------------------------
%%% @copyright (C) 2013, 2600Hz, INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(kazoo_api).

-export([start_link/0
         ,start/0
        ]).
-export([stop/0]).

-include("kazoo_api.hrl").

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Starts the app for inclusion in a supervisor tree
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> startlink_ret().
start_link() ->
    _ = start_deps(),
    kz_api:init_schemas().

-spec start() -> 'ok' | {'error', _}.
start() ->
    _ = start_deps(),
    application:start('kazoo_api', 'permanent').

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Stop the app
%% @end
%%--------------------------------------------------------------------
-spec stop() -> 'ok'.
stop() ->
    application:stop('kazoo_api').

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Ensures that all dependencies for this app are already running
%% @end
%%--------------------------------------------------------------------
-spec start_deps() -> 'ok'.
start_deps() -> 'ok'.
